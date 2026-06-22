# backend_fastapi/app/services/staff_service.py
from sqlalchemy.orm import Session
from ..models.staff import Staff
from ..core.security import hash_password


def get_staff_by_court(court_id: int, db: Session) -> list[Staff]:
    return db.query(Staff).filter(
        Staff.court_id == court_id,
        Staff.is_active == True
    ).all()


def get_staff_by_outlet(outlet_id: int, db: Session) -> list[Staff]:
    return db.query(Staff).filter(
        Staff.outlet_id == outlet_id,
        Staff.is_active == True
    ).all()

def get_all_staff(db: Session) -> list[Staff]:
    return db.query(Staff).filter(Staff.is_active == True).all()

def create_staff(
    db: Session,
    *,
    name: str,
    email: str,
    password: str,
    role: str = "etl_staff",
    court_id: int | None = None,
    outlet_id: int | None = None,
    phone: str | None = None,
    photo_url: str | None = None,
) -> Staff | None:
    """Create a staff account.
    - ETL managers create etl_staff (court_id set).
    - Outlet managers create outlet_staff (outlet_id set).
    """
    existing = db.query(Staff).filter(Staff.email == email).first()
    if existing:
        return None  # Already exists
    staff = Staff(
        name=name,
        email=email,
        hashed_password=hash_password(password),
        role=role,
        court_id=court_id,
        outlet_id=outlet_id,
        phone=phone,
        photo_url=photo_url,
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