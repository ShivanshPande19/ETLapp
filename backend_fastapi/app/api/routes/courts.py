from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from ...schemas.court import CourtsResponse, CourtCreate, CourtLocationUpdate
from ...services.court_service import get_all_courts
from ...models.sale import Court
from ...database import get_db
from ..deps import get_current_user, CurrentUser

router = APIRouter()


def _court_out(court: Court) -> dict:
    """Serialize a Court ORM object the way the client expects."""
    has_geo = court.latitude is not None and court.longitude is not None
    return {
        "id": court.id,
        "court_uid": court.court_uid,
        "name": court.name,
        "location": court.address or court.name,
        "is_active": bool(court.is_active),
        "latitude": court.latitude,
        "longitude": court.longitude,
        "geofence_radius": court.geofence_radius,
        "address": court.address,
        "has_geofence": has_geo,
    }


@router.get("/", response_model=CourtsResponse)
def list_courts(db: Session = Depends(get_db)):
    return get_all_courts(db)


@router.post("/", status_code=201)
def create_court(
    data: CourtCreate,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """ETL manager: create a new court (optionally with a geofence location)."""
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

    # Geofence is optional at creation — but if a coordinate is given, both
    # lat & lng must be present.
    if (data.latitude is None) != (data.longitude is None):
        raise HTTPException(
            status_code=400,
            detail="Both latitude and longitude are required to set a location.",
        )

    court = Court(
        name=name,
        manager_id=user.id,
        is_active=1,
        latitude=data.latitude,
        longitude=data.longitude,
        geofence_radius=data.geofence_radius or 150,
        address=(data.address or data.location),
    )
    db.add(court)
    db.commit()
    db.refresh(court)

    return _court_out(court)


@router.patch("/{court_id}/location")
def set_court_location(
    court_id: int,
    data: CourtLocationUpdate,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """ETL manager: set / edit an existing court's geofence location.

    Only the location fields are updated — name, staff, sales etc. are left
    untouched (no data loss)."""
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    court = db.query(Court).filter(Court.id == court_id).first()
    if not court:
        raise HTTPException(status_code=404, detail="Court not found.")

    court.latitude = data.latitude
    court.longitude = data.longitude
    court.geofence_radius = data.geofence_radius
    if data.address is not None:
        court.address = data.address

    db.commit()
    db.refresh(court)

    return _court_out(court)
