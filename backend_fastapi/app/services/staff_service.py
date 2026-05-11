# backend_fastapi/app/services/staff_service.py
from sqlalchemy.orm import Session
from ..models.staff import Staff
from ..core.security import hash_password
from ..schemas.staff import StaffCreate

def get_staff_by_court(court_id: int, db: Session) -> list[Staff]:
    return db.query(Staff).filter(
        Staff.court_id == court_id,
        Staff.is_active == True
    ).all()

def get_all_staff(db: Session) -> list[Staff]:
    return db.query(Staff).filter(Staff.is_active == True).all()

def create_staff(data: StaffCreate, db: Session) -> Staff:
    existing = db.query(Staff).filter(Staff.email == data.email).first()
    if existing:
        return None  # Already exists
    staff = Staff(
        name=data.name,
        email=data.email,
        hashed_password=hash_password(data.password),
        role="staff",
        court_id=data.court_id,
        is_active=True,
    )
    db.add(staff)
    db.commit()
    db.refresh(staff)
    return staff

def deactivate_staff(staff_id: int, db: Session) -> bool:
    staff = db.query(Staff).filter(Staff.id == staff_id).first()
    if not staff:
        return False
    staff.is_active = False
    db.commit()
    return True

def reassign_court(staff_id: int, court_id: int, db: Session) -> Staff | None:
    staff = db.query(Staff).filter(Staff.id == staff_id).first()
    if not staff:
        return None
    staff.court_id = court_id
    db.commit()
    db.refresh(staff)
    return staff