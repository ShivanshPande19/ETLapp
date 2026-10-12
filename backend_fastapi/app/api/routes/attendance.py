# app/api/routes/attendance.py

from datetime import date, datetime, timezone
from typing import Optional

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    UploadFile,
    File,
    Form,
    HTTPException,
    status,
)
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
import httpx
import json
import os
import uuid

from app.database import get_db, SessionLocal
from app.models.attendance import Attendance
from app.models.staff import Staff
from app.models.sale import Court, Outlet
from app.schemas.attendance import AttendanceStatusOut
from app.core.config import settings
from app.core.query_utils import (
    day_range,
    now_ist,
    current_business_date,
    business_date_for,
    to_ist,
    scheduled_shift_end_utc,
    scheduled_shift_start_utc,
)
from app.core.geo import (
    distance_meters,
    MAX_ACCURACY_BUFFER_M,
    MAX_TRUSTED_ACCURACY_M,
    DEFAULT_GEOFENCE_RADIUS_M,
)
from app.services.notice_service import create_notice
from app.services.push_targeting import manager_scope_for_staff
from app.services.attendance_service import build_staff_calendar, build_court_calendars, build_outlet_calendars
from app.api.deps import get_current_user, CurrentUser

router = APIRouter()

# ─── Photo upload constraints ────────────────────────────────────────────────
_ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}
_EXT_BY_TYPE = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}
_MAX_PHOTO_BYTES = 5 * 1024 * 1024  # 5 MB

# How early (minutes) before their shift start a staff may check in.
_EARLY_CHECKIN_WINDOW_MIN = 60


def _reject_if_mocked(is_mocked: Optional[bool]) -> None:
    """Block attendance marked with a mock/spoofed GPS location (Android can
    report this; iOS always returns false)."""
    if is_mocked:
        raise HTTPException(
            status_code=403,
            detail="Mock location detected. Turn off any fake-GPS app and try again.",
        )


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _coords_label(lat: float, lng: float) -> str:
    """The address we can produce instantly, with no network call."""
    return f"Lat: {lat}, Lng: {lng}"


async def get_address_from_coords(lat: float, lng: float) -> str:
    """Free reverse geocoding (OpenStreetMap Nominatim). Falls back to raw
    coords if the service is unavailable/rate-limited.

    NOTE: never call this inside a check-in/check-out request — see
    `_fill_address_later` for why.
    """
    url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lng}&format=json"
    headers = {"User-Agent": "ETL_Manager_App/1.0"}
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get(url, headers=headers)
            if response.status_code == 200:
                data = response.json()
                return data.get("display_name", _coords_label(lat, lng))
    except Exception:
        pass
    return _coords_label(lat, lng)


async def _fill_address_later(
    attendance_id: int, lat: float, lng: float, column: str
) -> None:
    """Resolve the human-readable address AFTER the response has been sent.

    This used to run INLINE: every check-in and check-out waited on a call to
    nominatim.openstreetmap.org (up to 8 s, a public service with a rate limit
    and no uptime promise) before the staff member's phone heard back. That was
    the single biggest chunk of the "photo click karne ke baad bahut der lagti
    hai" wait, and it delayed a punch that was already safely stored.

    The row is written with coordinates immediately; this backfills the street
    address a moment later. A failure here costs a nicer label, nothing more.
    """
    address = await get_address_from_coords(lat, lng)
    if address == _coords_label(lat, lng):
        return  # lookup failed — the placeholder already says this
    db = SessionLocal()
    try:
        rec = db.query(Attendance).filter(Attendance.id == attendance_id).first()
        if rec is None:
            return
        setattr(rec, column, address)
        db.commit()
    except Exception:
        db.rollback()
    finally:
        db.close()


async def _save_selfie(photo: UploadFile, prefix: str) -> str:
    """Validate (type + size) and persist a selfie, returning its stored path."""
    if photo.content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail="Invalid image. Please upload a JPEG, PNG or WebP photo.",
        )
    data = await photo.read()
    if len(data) > _MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Image too large (max 5 MB).")
    if not data:
        raise HTTPException(status_code=400, detail="Empty image upload.")

    os.makedirs(os.path.join(settings.UPLOAD_DIR, "attendance"), exist_ok=True)
    ext = _EXT_BY_TYPE.get(photo.content_type, "jpg")
    filename = f"{prefix}_{uuid.uuid4()}.{ext}"
    with open(os.path.join(settings.UPLOAD_DIR, "attendance", filename), "wb") as buffer:
        buffer.write(data)
    # Return the URL path (served by the /uploads mount), NOT the disk path —
    # so it resolves correctly even when UPLOAD_DIR points at a volume.
    return f"uploads/attendance/{filename}"


def _resolve_staff(user: CurrentUser, db: Session) -> Staff:
    """Identify the staff from the authenticated token (never from a
    client-supplied email). Only staff accounts can mark attendance."""
    staff = db.query(Staff).filter(
        Staff.email == user.email, Staff.is_active == True
    ).first()
    if not staff:
        raise HTTPException(
            status_code=403,
            detail="Only staff accounts can mark attendance.",
        )
    return staff


# Staff roles whose attendance geofence spans MULTIPLE zones — driven by the
# `zone_court_ids` JSON list rather than a single `court_id`:
#   • crownest_maintenance_head — roams across every zone it's assigned to.
#   • crownest_zone_manager     — marks its OWN attendance for its assigned
#                                 zone(s); may check in from within ANY of them.
_MULTI_ZONE_STAFF_ROLES = {"crownest_maintenance_head", "crownest_zone_manager"}


def _covers_multiple_zones(staff: Staff) -> bool:
    """True for staff roles assigned to a SET of zones (via `zone_court_ids`)
    instead of a single court — the Crownest Maintenance Head and the Crownest
    Zone Manager."""
    return staff.role in _MULTI_ZONE_STAFF_ROLES


def _assigned_courts(db: Session, staff: Staff) -> list[Court]:
    """Every zone a staff covers. A multi-zone role (Crownest Maintenance Head /
    Crownest Zone Manager) may be assigned to several (zone_court_ids); everyone
    else has their single court (via _staff_court, which also resolves an outlet
    staff's outlet → court).

    The list is returned in the SAME ORDER as `zone_court_ids`, so element 0 is
    the staff's primary zone — callers rely on that for the single-zone
    geofence payload and the `courts[0]` fallback.
    """
    if _covers_multiple_zones(staff):
        ids: list[int] = []
        raw = getattr(staff, "zone_court_ids", None)
        if raw:
            try:
                v = json.loads(raw)
                if isinstance(v, list):
                    # dict.fromkeys dedupes while preserving order.
                    ids = list(dict.fromkeys(int(x) for x in v))
            except Exception:
                ids = []
        if not ids and staff.court_id:
            ids = [staff.court_id]
        if not ids:
            return []
        rows = db.query(Court).filter(Court.id.in_(ids)).all()
        by_id = {c.id: c for c in rows}
        ordered = [by_id[i] for i in ids if i in by_id]
        # Every assigned zone has since been deleted → fall back to the primary
        # court column so the staff isn't left with no zone at all.
        if not ordered and staff.court_id:
            c = db.query(Court).filter(Court.id == staff.court_id).first()
            return [c] if c else []
        return ordered
    c = _staff_court(db, staff)
    return [c] if c else []


def _enforce_geofence(
    db: Session, staff: Staff, lat: float, lng: float, accuracy: Optional[float]
) -> Optional[Court]:
    """Ensure the check-in is inside the geofence of at least ONE of the staff's
    assigned zones, and return the zone it's credited to. A Crownest Maintenance
    Head may cover several zones — being within ANY of them is enough.

    Returns the primary zone (or None) without a check when no assigned zone has
    a location set (legacy courts) — geofencing simply doesn't apply yet.

    A small buffer (capped) based on the device-reported GPS accuracy is added
    to the allowed radius so a poor fix doesn't reject a genuine staff member.
    """
    courts = _assigned_courts(db, staff)
    configured = [c for c in courts if c.latitude is not None and c.longitude is not None]
    if not configured:
        return courts[0] if courts else None  # no geofence set → allow

    buffer = min(accuracy or 0.0, MAX_ACCURACY_BUFFER_M)
    for c in configured:
        radius = c.geofence_radius or DEFAULT_GEOFENCE_RADIUS_M
        if distance_meters(lat, lng, c.latitude, c.longitude) <= radius + buffer:
            return c  # inside this zone → credit the check-in here

    # Outside every configured zone — reject, pointing at the nearest one.
    nearest = min(
        configured,
        key=lambda c: distance_meters(lat, lng, c.latitude, c.longitude),
    )
    dist = distance_meters(lat, lng, nearest.latitude, nearest.longitude)

    # A fix with a kilometre-wide error bar cannot place anyone inside a ~150 m
    # circle, so saying "you are outside your zone" is simply false — it was
    # the daily false rejection for staff standing INSIDE their court (an
    # Android 12+ "Approximate location" grant reports accuracy in km, and the
    # first fused fix is often 100s of metres). Name the real problem instead,
    # so the message tells them something they can act on.
    # `accuracy <= 0` is how some devices say "I don't know how good this is",
    # which is no more trustworthy than a kilometre-wide fix.
    if accuracy is None or accuracy <= 0 or accuracy > MAX_TRUSTED_ACCURACY_M:
        measured = (
            f" (your phone reported ±{int(round(accuracy))} m)"
            if accuracy and accuracy > 0
            else ""
        )
        raise HTTPException(
            status_code=403,
            detail=(
                f"Your location isn't accurate enough to confirm you're in your "
                f"zone{measured}. Turn on Precise location / high-accuracy GPS, "
                f"switch off battery saver, step near a window or outside, then "
                f"try again."
            ),
        )

    zone_names = ", ".join(c.name for c in configured)
    raise HTTPException(
        status_code=403,
        detail=(
            f"You are about {int(round(dist))} m from {nearest.name} "
            f"(±{int(round(accuracy))} m). You must be within one of your zones "
            f"({zone_names}) to mark attendance."
        ),
    )


def _staff_court(db: Session, staff: Staff) -> Optional[Court]:
    """The court a staff belongs to.

    • ETL staff are linked directly via `court_id`.
    • Outlet staff are linked via their outlet → that outlet's court, so they
      automatically inherit the court's geofence + business-day cutoff (no
      separate geofence needed for outlets).
    """
    if staff.court_id:
        return db.query(Court).filter(Court.id == staff.court_id).first()
    if staff.outlet_id:
        outlet = db.query(Outlet).filter(Outlet.id == staff.outlet_id).first()
        if outlet and outlet.court_id:
            return db.query(Court).filter(Court.id == outlet.court_id).first()
    return None


def _staff_business_date(db: Session, staff: Staff):
    """Current business date for this staff, honouring the court's overnight
    cutoff hour (0 = normal calendar day)."""
    court = _staff_court(db, staff)
    cutoff = (court.day_cutoff_hour or 0) if court else 0
    return current_business_date(cutoff)


def _todays_record(db: Session, staff_id: int, biz_date) -> Optional[Attendance]:
    """The staff's attendance row for the given business date.

    Falls back to a legacy calendar-day match for rows created before the
    business_date column existed (those were backfilled, but be defensive)."""
    rec = (
        db.query(Attendance)
        .filter(
            Attendance.staff_id == staff_id,
            Attendance.business_date == biz_date,
        )
        .order_by(Attendance.check_in_time.desc())
        .first()
    )
    if rec:
        return rec
    # Legacy fallback: rows with no business_date — match by calendar day.
    _start, _end = day_range(biz_date)
    return (
        db.query(Attendance)
        .filter(
            Attendance.staff_id == staff_id,
            Attendance.business_date.is_(None),
            Attendance.check_in_time >= _start,
            Attendance.check_in_time < _end,
        )
        .order_by(Attendance.check_in_time.desc())
        .first()
    )


def _status_from_record(rec: Optional[Attendance]) -> AttendanceStatusOut:
    if rec is None:
        return AttendanceStatusOut(checked_in=False)

    duration = None
    if rec.check_in_time and rec.check_out_time:
        # `check_in_time` comes from the DB's own `now()` while `check_out_time`
        # is written as a naive UTC value, and the columns are
        # DateTime(timezone=True). On Postgres both read back aware, on SQLite
        # both read back naive — but a mixed pair would raise TypeError and 500
        # the whole status call. Normalise to aware UTC first (naive == UTC
        # everywhere in this codebase) so the subtraction can never blow up.
        def _aware(dt: datetime) -> datetime:
            return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)

        delta = _aware(rec.check_out_time) - _aware(rec.check_in_time)
        duration = max(0, int(delta.total_seconds() // 60))

    return AttendanceStatusOut(
        attendance_id=rec.id,
        checked_in=True,
        check_in_time=rec.check_in_time,
        check_in_address=rec.check_in_address,
        check_in_photo_url=rec.check_in_photo_url,
        checked_out=rec.check_out_time is not None,
        check_out_time=rec.check_out_time,
        check_out_address=rec.check_out_address,
        early_checkout=bool(rec.early_checkout),
        auto_closed=bool(rec.auto_closed),
        work_duration_minutes=duration,
    )


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/today", response_model=AttendanceStatusOut)
def attendance_today(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Logged-in staff's attendance status for today (used by the home screen
    to persist state across app restarts)."""
    staff = _resolve_staff(user, db)
    biz_date = _staff_business_date(db, staff)
    return _status_from_record(_todays_record(db, staff.id, biz_date))


@router.get("/geofence")
def my_geofence(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Return the logged-in staff's court geofence so the client can pre-check
    location before opening the camera. `has_geofence=false` means no
    restriction applies (legacy court / no location set)."""
    staff = _resolve_staff(user, db)

    courts = _assigned_courts(db, staff)
    configured = [c for c in courts if c.latitude is not None and c.longitude is not None]
    if not configured:
        return {"has_geofence": False}

    # `zones` is ALWAYS sent, even for a single-zone staff member, so the client
    # has exactly one shape to parse. It used to appear only when a staff had
    # 2+ located zones, which meant the multi-zone roles (Maintenance Head,
    # Zone Manager) silently switched payload shape depending on how many of
    # their courts happened to have a location set. The flat primary-zone
    # fields below are kept for older app builds.
    primary = configured[0]
    return {
        "has_geofence": True,
        "accuracy_buffer": MAX_ACCURACY_BUFFER_M,
        # Past this accuracy neither side will judge inside/outside.
        "max_trusted_accuracy": MAX_TRUSTED_ACCURACY_M,
        "zones": [
            {
                "court_id": c.id,
                "court_name": c.name,
                "latitude": c.latitude,
                "longitude": c.longitude,
                "geofence_radius": c.geofence_radius or DEFAULT_GEOFENCE_RADIUS_M,
            }
            for c in configured
        ],
        # ── Back-compat (primary zone) ──
        "court_id": primary.id,
        "court_name": primary.name,
        "latitude": primary.latitude,
        "longitude": primary.longitude,
        "geofence_radius": primary.geofence_radius or DEFAULT_GEOFENCE_RADIUS_M,
    }


def _parse_month(month: Optional[str]) -> tuple[int, int]:
    """Parse 'YYYY-MM'; default to the current IST month."""
    if month:
        try:
            y, m = month.split("-")
            yi, mi = int(y), int(m)
            if 1 <= mi <= 12:
                return yi, mi
        except (ValueError, AttributeError):
            pass
    today = now_ist().date()
    return today.year, today.month


@router.get("/calendar")
def my_calendar(
    month: Optional[str] = None,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Logged-in staff's own month calendar (present/early/auto/absent)."""
    staff = _resolve_staff(user, db)
    y, m = _parse_month(month)
    return build_staff_calendar(db, staff, y, m)


@router.get("/calendar/court")
def court_calendar(
    month: Optional[str] = None,
    court_id: Optional[int] = None,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """ETL manager: court-wise calendar for every ETL staff."""
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")
    y, m = _parse_month(month)
    return build_court_calendars(db, y, m, court_id=court_id)


@router.get("/calendar/outlet")
def outlet_calendar(
    month: Optional[str] = None,
    outlet_id: Optional[int] = None,  # ✅ MULTI-OUTLET: which of my outlets
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Outlet manager: month calendar for staff in one of their outlets.

    A single-outlet manager may omit outlet_id; a multi-outlet owner passes the
    selected outlet. The target is always validated against their membership.
    """
    if user.role != "outlet_manager" or not user.outlet_ids:
        raise HTTPException(status_code=403, detail="Outlet manager access required.")
    target_outlet_id = outlet_id
    if target_outlet_id is None:
        if len(user.outlet_ids) == 1:
            target_outlet_id = user.outlet_ids[0]
        else:
            raise HTTPException(
                status_code=400,
                detail="outlet_id is required — you manage multiple outlets.",
            )
    if target_outlet_id not in user.outlet_ids:
        raise HTTPException(status_code=403, detail="You cannot access that outlet.")
    y, m = _parse_month(month)
    return build_outlet_calendars(db, y, m, target_outlet_id)


@router.post(
    "/check-in",
    response_model=AttendanceStatusOut,
    status_code=status.HTTP_201_CREATED,
)
async def mark_attendance(
    background: BackgroundTasks,
    lat: float = Form(...),
    lng: float = Form(...),
    accuracy: Optional[float] = Form(None),
    is_mocked: Optional[bool] = Form(None),
    photo: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    staff = _resolve_staff(user, db)

    # ✅ Shift is mandatory — staff can't mark attendance until a manager has
    # assigned their shift timings. A Maintenance Head's shift can be set at
    # creation or later from Manage Accounts (exactly like ETL staff).
    if not staff.shift_start or not staff.shift_end:
        raise HTTPException(
            status_code=403,
            detail="Your shift timings haven't been set yet. Please ask your manager.",
        )

    biz_date = _staff_business_date(db, staff)

    # ✅ One check-in per business day — block duplicates.
    existing = _todays_record(db, staff.id, biz_date)
    if existing:
        raise HTTPException(
            status_code=409,
            detail="You have already checked in today.",
        )

    # 🚫 Mock/spoofed GPS.
    _reject_if_mocked(is_mocked)

    # ⏰ Can't check in too early (more than the early window before shift start).
    start_utc = scheduled_shift_start_utc(biz_date, staff.shift_start)
    if start_utc is not None:
        from datetime import timedelta

        earliest = start_utc - timedelta(minutes=_EARLY_CHECKIN_WINDOW_MIN)
        if datetime.utcnow() < earliest:
            earliest_local = to_ist(earliest).strftime("%I:%M %p").lstrip("0")
            raise HTTPException(
                status_code=403,
                detail=(
                    f"Too early to check in. Your shift starts at "
                    f"{staff.shift_start} — you can check in from {earliest_local}."
                ),
            )

    # ✅ Geofence: must be within ONE of the staff's assigned zones (a
    #    Maintenance Head can cover several). Returns the credited zone.
    matched_court = _enforce_geofence(db, staff, lat, lng, accuracy)

    file_path = await _save_selfie(photo, "in")
    # Coordinates now, street address in the background — see
    # `_fill_address_later`. The punch must not wait on a public geocoder.
    new_record = Attendance(
        staff_id=staff.id,
        outlet_id=staff.outlet_id,
        court_id=(matched_court.id if matched_court else staff.court_id),
        business_date=biz_date,
        check_in_lat=lat,
        check_in_lng=lng,
        check_in_address=_coords_label(lat, lng),
        check_in_photo_url=file_path,
    )
    db.add(new_record)
    try:
        db.commit()
    except IntegrityError:
        # Unique (staff_id, business_date) tripped by a concurrent check-in.
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="You have already checked in today.",
        )
    db.refresh(new_record)

    background.add_task(
        _fill_address_later, new_record.id, lat, lng, "check_in_address"
    )
    return _status_from_record(new_record)


@router.post("/check-out", response_model=AttendanceStatusOut)
async def check_out(
    background: BackgroundTasks,
    lat: float = Form(...),
    lng: float = Form(...),
    accuracy: Optional[float] = Form(None),
    is_mocked: Optional[bool] = Form(None),
    photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    staff = _resolve_staff(user, db)

    biz_date = _staff_business_date(db, staff)
    rec = _todays_record(db, staff.id, biz_date)
    if rec is None:
        raise HTTPException(
            status_code=400,
            detail="No check-in found for today. Please check in first.",
        )
    if rec.check_out_time is not None:
        raise HTTPException(
            status_code=409,
            detail="You have already checked out today.",
        )

    # 🚫 Mock/spoofed GPS.
    _reject_if_mocked(is_mocked)

    # NOTE: geofence is intentionally NOT enforced on check-OUT.
    # Check-IN keeps the hard geofence (you must be at the court to start a
    # shift), but blocking check-OUT strands a staff member who has already
    # left the premises — they physically cannot clock out, so the hourly
    # sweep auto-closes their shift and flags a false "forgot to check out".
    # We still record the check-out coordinates + address below, so a manager
    # can always see where the shift was ended.
    photo_path = await _save_selfie(photo, "out") if photo is not None else None

    checkout_at = datetime.utcnow()
    rec.check_out_time = checkout_at
    rec.check_out_lat = lat
    rec.check_out_lng = lng
    rec.check_out_address = _coords_label(lat, lng)
    rec.check_out_photo_url = photo_path

    # ⏰ Early-logout detection: did they check out before their shift ended?
    # Early *login* is fine — only an early check-out raises a notice.
    rec.early_checkout = _is_early_checkout(staff, rec, checkout_at)

    db.commit()
    db.refresh(rec)

    if rec.early_checkout:
        _notify_early_logout(db, staff, rec, checkout_at)

    background.add_task(
        _fill_address_later, rec.id, lat, lng, "check_out_address"
    )
    return _status_from_record(rec)


# Grace window (minutes) before scheduled end that still counts as on-time.
_EARLY_LOGOUT_GRACE_MIN = 5


def _is_early_checkout(staff: Staff, rec: Attendance, checkout_utc: datetime) -> bool:
    """True if check-out happened before the scheduled shift end (overnight-aware)."""
    if rec.business_date is None or not staff.shift_end:
        return False
    scheduled_end = scheduled_shift_end_utc(rec.business_date, staff.shift_start, staff.shift_end)
    if scheduled_end is None:
        return False
    from datetime import timedelta

    return checkout_utc < scheduled_end - timedelta(minutes=_EARLY_LOGOUT_GRACE_MIN)


def _notify_early_logout(
    db: Session, staff: Staff, rec: Attendance, checkout_utc: datetime
) -> None:
    """Notify the ETL manager (notices section) + the staff of an early check-out."""
    scheduled_end = scheduled_shift_end_utc(rec.business_date, staff.shift_start, staff.shift_end)
    if scheduled_end is None:
        return

    # How early, in minutes (for a human-friendly message).
    early_min = int(round((scheduled_end - checkout_utc).total_seconds() / 60))
    out_local = to_ist(checkout_utc).strftime("%I:%M %p").lstrip("0")

    # Route to the right manager: outlet staff → their outlet manager ONLY;
    # ETL staff → the court (ETL manager).
    #
    # Uses the shared helper so this stays identical to every other
    # manager-audience notice and to push targeting. The previous inline
    # `if staff.outlet_id and not staff.court_id` mis-routed any staff row that
    # had BOTH ids set (nothing in the schema prevents that) — the outlet
    # manager would have silently lost events about their own staff.
    mgr_court_id, mgr_outlet_id = manager_scope_for_staff(staff)

    # Manager notice (read/unread in Settings → Notices).
    create_notice(
        db,
        audience="manager",
        type="early_logout",
        title=f"{staff.name} logged out early",
        body=(
            f"{staff.name} checked out at {out_local}, about {early_min} min "
            f"before the {staff.shift_end} shift end."
        ),
        court_id=mgr_court_id,
        outlet_id=mgr_outlet_id,
        staff_id=staff.id,
    )

    # Staff notice.
    create_notice(
        db,
        audience="staff",
        type="early_logout",
        title="Early check-out recorded",
        body=(
            f"You checked out about {early_min} min before your shift end "
            f"({staff.shift_end}). Your manager has been notified."
        ),
        court_id=staff.court_id,
        outlet_id=staff.outlet_id,
        staff_id=staff.id,
        recipient_staff_id=staff.id,
    )
