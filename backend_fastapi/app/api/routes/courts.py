from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from ...schemas.court import (
    CourtsResponse,
    CourtCreate,
    CourtLocationUpdate,
    CourtSettingsUpdate,
    CourtGoogleReviewUpdate,
)
from ...services.court_service import get_all_courts
from ...services.notice_service import create_notice
from ...services.push_targeting import staff_ids_for_court
from ...models.sale import Court
from ...database import get_db
from ..deps import get_current_user, CurrentUser

router = APIRouter()


def _court_out(court: Court) -> dict:
    """Serialize a Court ORM object the way the client expects."""
    has_geo = court.latitude is not None and court.longitude is not None
    review_url = getattr(court, "google_review_url", None)
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
        "day_cutoff_hour": court.day_cutoff_hour or 0,
        "has_geofence": has_geo,
        "google_review_url": review_url,
        "has_google_review": bool(review_url),
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
        day_cutoff_hour=data.day_cutoff_hour or 0,
    )
    db.add(court)
    db.commit()
    db.refresh(court)

    return _court_out(court)


def _notify_court_staff_geofence(db: Session, court: Court) -> None:
    """Tell every staff member at this court that the check-in area changed.

    Each staff gets their OWN audience="staff" notice addressed by
    `recipient_staff_id` — deliberately not a court-wide broadcast, so the
    per-user targeting rules in services/push_targeting.py still apply and
    nobody receives somebody else's notice.

    `staff_ids_for_court` covers both tiers: ETL staff via `Staff.court_id` and
    outlet staff via `Staff.outlet_id -> Outlet.court_id` (outlet staff have a
    NULL court_id, so a naive filter would silently miss all of them).
    """
    try:
        staff_ids = staff_ids_for_court(db, court.id)
        if not staff_ids:
            return

        radius = court.geofence_radius or 150
        for sid in staff_ids:
            create_notice(
                db,
                audience="staff",
                type="geofence_changed",
                title="Check-in location updated",
                body=(
                    f"The check-in area for {court.name} has been updated. You must "
                    f"now be within {radius} m of the new location to mark attendance."
                ),
                court_id=court.id,
                recipient_staff_id=sid,
            )
        print(f"[COURT] geofence change notified to {len(staff_ids)} staff at court {court.id}")
    except Exception as e:  # noqa: BLE001 — never fail the update over a notice
        print(f"[COURT] geofence notice fan-out failed for court {court.id}: {e}")


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

    moved = (
        court.latitude != data.latitude
        or court.longitude != data.longitude
        or court.geofence_radius != data.geofence_radius
    )

    court.latitude = data.latitude
    court.longitude = data.longitude
    court.geofence_radius = data.geofence_radius
    if data.address is not None:
        court.address = data.address

    db.commit()
    db.refresh(court)

    # Trigger #21 — the geofence moved, so staff who could check in from their
    # usual spot yesterday may not be able to today. High-value because the
    # failure mode is a confusing 403 at the start of a shift.
    if moved:
        _notify_court_staff_geofence(db, court)

    return _court_out(court)


@router.patch("/{court_id}/settings")
def set_court_settings(
    court_id: int,
    data: CourtSettingsUpdate,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """ETL manager: set a court's overnight business-day cutoff hour.

    0 = normal court (business day == calendar day). For an overnight court
    (e.g. 2pm→2am) set ~5 so a post-midnight check-out counts on the day the
    shift started."""
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    court = db.query(Court).filter(Court.id == court_id).first()
    if not court:
        raise HTTPException(status_code=404, detail="Court not found.")

    court.day_cutoff_hour = data.day_cutoff_hour
    db.commit()
    db.refresh(court)

    return _court_out(court)


@router.patch("/{court_id}/google-review")
def set_court_google_review_url(
    court_id: int,
    data: CourtGoogleReviewUpdate,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """ETL manager: set / clear this court's Google review link.

    Each court is a separate Google Business listing, so the link is per-court.
    Once set, the court's feedback portal shows an "also review us on Google"
    call-to-action on the thank-you screen after a customer submits.

    Send `{"google_review_url": null}` to remove it and hide the CTA again.

    The URL is validated against a Google-host allowlist (see
    schemas/court.py) because it is later used as a redirect target — an
    arbitrary host here would make GET /feedback/{id}/google an open redirect.
    """
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    court = db.query(Court).filter(Court.id == court_id).first()
    if not court:
        raise HTTPException(status_code=404, detail="Court not found.")

    # Already normalized + host-checked by the schema validator.
    court.google_review_url = data.google_review_url
    db.commit()
    db.refresh(court)

    return _court_out(court)
