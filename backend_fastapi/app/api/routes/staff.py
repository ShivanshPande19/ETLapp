# backend_fastapi/app/api/routes/staff.py
from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from ...database import get_db
from ...schemas.staff import StaffCreate, StaffResponse, StaffListResponse, CourtAssignRequest
from ...services.staff_service import (
    get_all_staff, get_staff_by_court,
    create_staff, deactivate_staff, reassign_court
)

router = APIRouter()

# ── GET all staff (manager only) ──────────────────────────────────────────────
@router.get("/", response_model=StaffListResponse)
def list_all_staff(db: Session = Depends(get_db)):
    return StaffListResponse(staff=get_all_staff(db))

# ── GET staff by court ────────────────────────────────────────────────────────
@router.get("/court/{court_id}", response_model=StaffListResponse)
def list_staff_by_court(court_id: int, db: Session = Depends(get_db)):
    return StaffListResponse(staff=get_staff_by_court(court_id, db))

# ── POST add new staff ────────────────────────────────────────────────────────
@router.post("/", response_model=StaffResponse, status_code=201)
def add_staff(data: StaffCreate, db: Session = Depends(get_db)):
    staff = create_staff(data, db)
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