# backend_fastapi/app/api/routes/staff.py
import os
import uuid
from typing import Optional

from fastapi import APIRouter, HTTPException, Depends, Form, File, UploadFile
from sqlalchemy.orm import Session

from ...database import get_db
from ...schemas.staff import StaffResponse, StaffListResponse, CourtAssignRequest, ShiftUpdateRequest
from ...services.staff_service import (
    get_all_staff, get_staff_by_court, get_staff_by_outlet,
    create_staff, deactivate_staff, reassign_court
)
from ...services.notice_service import create_notice
from ...services.push_targeting import deactivate_tokens_for_user
from ...models.staff import Staff
from ...models.sale import Court
from ...core.config import settings
from ..deps import get_current_user, CurrentUser

router = APIRouter()

# ─── Photo upload constraints ─────────────────────────────────────────────────
_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}
_MAX_PHOTO_BYTES = 5 * 1024 * 1024  # 5 MB


async def _save_staff_photo(photo: Optional[UploadFile]) -> Optional[str]:
    """Persist a staff profile photo to the uploads volume; returns its URL
    path ('uploads/staff/...'). None if no photo provided."""
    if photo is None or not photo.filename:
        return None
    ext = _ALLOWED_IMAGE_TYPES.get(photo.content_type)
    if ext is None:
        raise HTTPException(
            status_code=400, detail="Invalid photo. Upload a JPG, PNG or WebP."
        )
    data = await photo.read()
    if len(data) > _MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Photo too large (max 5 MB).")
    if not data:
        return None
    folder = os.path.join(settings.UPLOAD_DIR, "staff")
    os.makedirs(folder, exist_ok=True)
    filename = f"staff_{uuid.uuid4()}.{ext}"
    with open(os.path.join(folder, filename), "wb") as f:
        f.write(data)
    return f"uploads/staff/{filename}"


# ── GET all staff ─────────────────────────────────────────────────────────────
@router.get("/", response_model=StaffListResponse)
def list_all_staff(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # ETL manager only — this lists every ETL staff member (with PII).
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")
    return StaffListResponse(staff=get_all_staff(db))


# ── GET staff by court ────────────────────────────────────────────────────────
@router.get("/court/{court_id}", response_model=StaffListResponse)
def list_staff_by_court(
    court_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # ETL manager only — court-wise staff listing.
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")
    return StaffListResponse(staff=get_staff_by_court(court_id, db))


# ── GET staff by outlet (outlet staff shown in the outlet detail sheet) ───────
@router.get("/outlet/{outlet_id}", response_model=StaffListResponse)
def list_staff_by_outlet(
    outlet_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # ETL manager (any outlet) or the outlet's own manager/staff.
    if user.is_etl_manager:
        pass
    elif user.is_outlet_user and user.outlet_id == outlet_id:
        pass
    else:
        raise HTTPException(status_code=403, detail="Access denied.")
    return StaffListResponse(staff=get_staff_by_outlet(outlet_id, db))


# ── POST add new ETL staff (multipart: name, phone, email, password, photo) ────
@router.post("/", response_model=StaffResponse, status_code=201)
async def add_staff(
    name: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    court_id: int = Form(...),
    phone: Optional[str] = Form(None),
    photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # ETL manager only — and only ever creates etl_staff (handled in service).
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    name = name.strip()
    email = email.strip().lower()
    if not name or not email or not password:
        raise HTTPException(
            status_code=400, detail="Name, email and password are required."
        )

    photo_url = await _save_staff_photo(photo)

    staff = create_staff(
        db,
        name=name,
        email=email,
        password=password,
        role="etl_staff",
        court_id=court_id,
        phone=(phone or "").strip() or None,
        photo_url=photo_url,
    )
    if not staff:
        raise HTTPException(status_code=400, detail="Email already registered")
    return staff


# ── POST add outlet staff (outlet manager only; for their own outlet) ─────────
@router.post("/outlet", response_model=StaffResponse, status_code=201)
async def add_outlet_staff(
    name: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    phone: Optional[str] = Form(None),
    photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # Only an outlet manager can add staff — and only to their OWN outlet
    # (outlet_id is taken from the token, never the client).
    if user.role != "outlet_manager" or user.outlet_id is None:
        raise HTTPException(
            status_code=403, detail="Outlet manager access required."
        )

    name = name.strip()
    email = email.strip().lower()
    if not name or not email or not password:
        raise HTTPException(
            status_code=400, detail="Name, email and password are required."
        )

    photo_url = await _save_staff_photo(photo)

    staff = create_staff(
        db,
        name=name,
        email=email,
        password=password,
        role="outlet_staff",
        outlet_id=user.outlet_id,
        phone=(phone or "").strip() or None,
        photo_url=photo_url,
    )
    if not staff:
        raise HTTPException(status_code=400, detail="Email already registered")
    return staff


# ── PATCH deactivate (remove access) ─────────────────────────────────────────
@router.patch("/{staff_id}/deactivate")
def remove_staff_access(
    staff_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    staff = db.query(Staff).filter(Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found")

    # ETL manager can remove any; an outlet manager only their own outlet's staff.
    if user.is_etl_manager:
        pass
    elif user.role == "outlet_manager" and user.outlet_id is not None:
        if staff.outlet_id != user.outlet_id:
            raise HTTPException(
                status_code=403,
                detail="You can only remove your own outlet's staff.",
            )
    else:
        raise HTTPException(status_code=403, detail="Manager access required.")

    # Trigger #22 — tell them BEFORE deactivating.
    #
    # Ordering matters: push targeting joins live against `staff` and filters on
    # `Staff.is_active == True` (so a revoked account stops receiving), which
    # means a notice created after deactivation would reach nobody. Their access
    # dies on the next request anyway (get_current_user re-queries is_active),
    # so without this the account just silently stops working.
    try:
        create_notice(
            db,
            audience="staff",
            type="access_removed",
            title="Your access has been removed",
            body=(
                "Your ETL account has been deactivated by your manager. "
                "Contact them if you think this is a mistake."
            ),
            court_id=staff.court_id,
            outlet_id=staff.outlet_id,
            staff_id=staff.id,
            recipient_staff_id=staff.id,
        )
    except Exception as e:  # noqa: BLE001
        print(f"[STAFF] deactivation notice failed for {staff_id}: {e}")

    success = deactivate_staff(staff_id, db)
    if not success:
        raise HTTPException(status_code=404, detail="Staff not found")

    # Stop pushing to their devices now that the account is gone.
    try:
        n = deactivate_tokens_for_user(db, user_type="staff", user_id=staff_id)
        db.commit()
        if n:
            print(f"[STAFF] disabled {n} device token(s) for staff {staff_id}")
    except Exception as e:  # noqa: BLE001
        db.rollback()
        print(f"[STAFF] token cleanup failed for {staff_id}: {e}")

    return {"message": "Access removed successfully"}


# ── PATCH reassign court ──────────────────────────────────────────────────────
@router.patch("/{staff_id}/court", response_model=StaffResponse)
def assign_court(
    staff_id: int,
    req: CourtAssignRequest,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # Court reassignment applies to ETL (court-level) staff — ETL manager only.
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    staff = reassign_court(staff_id, req.court_id, db)
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found")

    # Trigger #23 — a court move silently changes three things for this person:
    # their geofence (attendance._staff_court), their business-day cutoff
    # (Court.day_cutoff_hour) and which manager sees their events. Worth a push.
    try:
        court = db.query(Court).filter(Court.id == req.court_id).first()
        create_notice(
            db,
            audience="staff",
            type="court_changed",
            title="You have been moved to a new court",
            body=(
                f"You are now assigned to {court.name}. Your check-in location has "
                f"changed — make sure you are at the new court before marking "
                f"attendance."
                if court
                else "Your court assignment has changed. Your check-in location "
                     "has changed too."
            ),
            court_id=req.court_id,
            staff_id=staff.id,
            recipient_staff_id=staff.id,
        )
    except Exception as e:  # noqa: BLE001
        print(f"[STAFF] court-change notice failed for {staff_id}: {e}")

    return staff


# ── PATCH set shift timings (ETL manager only) ───────────────────────────────
@router.patch("/{staff_id}/shift", response_model=StaffResponse)
def set_shift(
    staff_id: int,
    req: ShiftUpdateRequest,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Set/clear a staff member's shift timings and notify them."""
    staff = db.query(Staff).filter(Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found")

    # Authorization: ETL manager can set any; an outlet manager only for their
    # own outlet's staff.
    if user.is_etl_manager:
        pass
    elif user.role == "outlet_manager" and user.outlet_id is not None:
        if staff.outlet_id != user.outlet_id:
            raise HTTPException(
                status_code=403,
                detail="You can only set shifts for your own outlet's staff.",
            )
    else:
        raise HTTPException(status_code=403, detail="Manager access required.")

    # Both provided, or both cleared — never a half-set shift.
    if bool(req.shift_start) != bool(req.shift_end):
        raise HTTPException(
            status_code=400,
            detail="Provide both shift start and end (or clear both).",
        )

    staff.shift_start = req.shift_start
    staff.shift_end = req.shift_end
    db.commit()
    db.refresh(staff)

    # Notify the staff that their shift changed.
    if staff.shift_start and staff.shift_end:
        body = f"Your shift is now {staff.shift_start}–{staff.shift_end}."
    else:
        body = "Your shift timings were cleared."
    create_notice(
        db,
        audience="staff",
        type="shift_changed",
        title="Shift timings updated",
        body=body,
        court_id=staff.court_id,
        outlet_id=staff.outlet_id,
        staff_id=staff.id,
        recipient_staff_id=staff.id,
    )

    return staff
