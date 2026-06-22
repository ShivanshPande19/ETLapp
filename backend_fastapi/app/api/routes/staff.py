# backend_fastapi/app/api/routes/staff.py
import os
import uuid
from typing import Optional

from fastapi import APIRouter, HTTPException, Depends, Form, File, UploadFile
from sqlalchemy.orm import Session

from ...database import get_db
from ...schemas.staff import StaffResponse, StaffListResponse, CourtAssignRequest
from ...services.staff_service import (
    get_all_staff, get_staff_by_court, get_staff_by_outlet,
    create_staff, deactivate_staff, reassign_court
)
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
def list_all_staff(db: Session = Depends(get_db)):
    return StaffListResponse(staff=get_all_staff(db))


# ── GET staff by court ────────────────────────────────────────────────────────
@router.get("/court/{court_id}", response_model=StaffListResponse)
def list_staff_by_court(court_id: int, db: Session = Depends(get_db)):
    return StaffListResponse(staff=get_staff_by_court(court_id, db))


# ── GET staff by outlet (outlet staff shown in the outlet detail sheet) ───────
@router.get("/outlet/{outlet_id}", response_model=StaffListResponse)
def list_staff_by_outlet(outlet_id: int, db: Session = Depends(get_db)):
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
def remove_staff_access(staff_id: int, db: Session = Depends(get_db)):
    success = deactivate_staff(staff_id, db)
    if not success:
        raise HTTPException(status_code=404, detail="Staff not found")
    return {"message": "Access removed successfully"}


# ── PATCH reassign court ──────────────────────────────────────────────────────
@router.patch("/{staff_id}/court", response_model=StaffResponse)
def assign_court(staff_id: int, req: CourtAssignRequest, db: Session = Depends(get_db)):
    staff = reassign_court(staff_id, req.court_id, db)
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found")
    return staff
