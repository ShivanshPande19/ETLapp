from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from ...schemas.court import CourtsResponse, CourtCreate
from ...services.court_service import get_all_courts
from ...models.sale import Court
from ...database import get_db
from ..deps import get_current_user, CurrentUser

router = APIRouter()


@router.get("/", response_model=CourtsResponse)
def list_courts(db: Session = Depends(get_db)):
    return get_all_courts(db)


@router.post("/", status_code=201)
def create_court(
    data: CourtCreate,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """ETL manager: create a new court."""
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    name = (data.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Court name is required.")

    existing = db.query(Court).filter(func.lower(Court.name) == name.lower()).first()
    if existing:
        raise HTTPException(
            status_code=409, detail="A court with this name already exists."
        )

    court = Court(name=name, manager_id=user.id, is_active=1)
    db.add(court)
    db.commit()
    db.refresh(court)

    return {
        "id": court.id,
        "court_uid": court.court_uid,
        "name": court.name,
        "location": data.location or court.name,
        "is_active": True,
    }
