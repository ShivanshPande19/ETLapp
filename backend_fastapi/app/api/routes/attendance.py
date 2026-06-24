# app/api/routes/attendance.py

from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException, status
from sqlalchemy.orm import Session
import httpx
import os
import uuid

from app.database import get_db
from app.models.attendance import Attendance
from app.models.staff import Staff
from app.models.sale import Court
from app.schemas.attendance import AttendanceStatusOut
from app.core.config import settings
from app.core.query_utils import day_range
from app.core.geo import (
    distance_meters,
    MAX_ACCURACY_BUFFER_M,
    DEFAULT_GEOFENCE_RADIUS_M,
)
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


# ─── Helpers ──────────────────────────────────────────────────────────────────

async def get_address_from_coords(lat: float, lng: float) -> str:
    """Free reverse geocoding (OpenStreetMap Nominatim). Falls back to raw
    coords if the service is unavailable/rate-limited."""
    url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lng}&format=json"
    headers = {"User-Agent": "ETL_Manager_App/1.0"}
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get(url, headers=headers)
            if response.status_code == 200:
                data = response.json()
                return data.get("display_name", f"Lat: {lat}, Lng: {lng}")
    except Exception:
        pass
    return f"Lat: {lat}, Lng: {lng}"


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


def _enforce_geofence(
    db: Session, staff: Staff, lat: float, lng: float, accuracy: Optional[float]
) -> None:
    """Block attendance if the staff is outside their court's geofence.

    Skipped silently when:
      • the staff has no court linked, or
      • the court has no location set (legacy courts) — until a manager sets a
        location via the map, geofencing simply doesn't apply.

    A small buffer (capped) based on the device-reported GPS accuracy is added
    to the allowed radius so a poor fix doesn't reject a genuine staff member.
    """
    if not staff.court_id:
        return

    court = db.query(Court).filter(Court.id == staff.court_id).first()
    if not court or court.latitude is None or court.longitude is None:
        return  # no geofence configured for this court → allow

    radius = court.geofence_radius or DEFAULT_GEOFENCE_RADIUS_M
    buffer = min(accuracy or 0.0, MAX_ACCURACY_BUFFER_M)
    distance = distance_meters(lat, lng, court.latitude, court.longitude)

    if distance > radius + buffer:
        raise HTTPException(
            status_code=403,
            detail=(
                f"You are about {int(round(distance))} m away from "
                f"{court.name}. You must be within {radius} m of the court to "
                f"mark attendance."
            ),
        )


def _todays_record(db: Session, staff_id: int) -> Optional[Attendance]:
    _start, _end = day_range(date.today())
    return (
        db.query(Attendance)
        .filter(
            Attendance.staff_id == staff_id,
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
        delta = rec.check_out_time - rec.check_in_time
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
    return _status_from_record(_todays_record(db, staff.id))


@router.get("/geofence")
def my_geofence(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Return the logged-in staff's court geofence so the client can pre-check
    location before opening the camera. `has_geofence=false` means no
    restriction applies (legacy court / no location set)."""
    staff = _resolve_staff(user, db)

    court = (
        db.query(Court).filter(Court.id == staff.court_id).first()
        if staff.court_id
        else None
    )
    if not court or court.latitude is None or court.longitude is None:
        return {"has_geofence": False}

    return {
        "has_geofence": True,
        "court_id": court.id,
        "court_name": court.name,
        "latitude": court.latitude,
        "longitude": court.longitude,
        "geofence_radius": court.geofence_radius or DEFAULT_GEOFENCE_RADIUS_M,
        "accuracy_buffer": MAX_ACCURACY_BUFFER_M,
    }


@router.post(
    "/check-in",
    response_model=AttendanceStatusOut,
    status_code=status.HTTP_201_CREATED,
)
async def mark_attendance(
    lat: float = Form(...),
    lng: float = Form(...),
    accuracy: Optional[float] = Form(None),
    photo: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    staff = _resolve_staff(user, db)

    # ✅ One check-in per day — block duplicates.
    existing = _todays_record(db, staff.id)
    if existing:
        raise HTTPException(
            status_code=409,
            detail="You have already checked in today.",
        )

    # ✅ Geofence: must be within the assigned court's radius (if configured).
    _enforce_geofence(db, staff, lat, lng, accuracy)

    file_path = await _save_selfie(photo, "in")
    real_address = await get_address_from_coords(lat, lng)

    new_record = Attendance(
        staff_id=staff.id,
        outlet_id=staff.outlet_id,
        court_id=staff.court_id,
        check_in_lat=lat,
        check_in_lng=lng,
        check_in_address=real_address,
        check_in_photo_url=file_path,
    )
    db.add(new_record)
    db.commit()
    db.refresh(new_record)

    return _status_from_record(new_record)


@router.post("/check-out", response_model=AttendanceStatusOut)
async def check_out(
    lat: float = Form(...),
    lng: float = Form(...),
    photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    staff = _resolve_staff(user, db)

    rec = _todays_record(db, staff.id)
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

    photo_path = await _save_selfie(photo, "out") if photo is not None else None
    real_address = await get_address_from_coords(lat, lng)

    rec.check_out_time = datetime.utcnow()
    rec.check_out_lat = lat
    rec.check_out_lng = lng
    rec.check_out_address = real_address
    rec.check_out_photo_url = photo_path

    db.commit()
    db.refresh(rec)

    return _status_from_record(rec)
