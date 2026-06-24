from sqlalchemy.orm import Session
from sqlalchemy import text
from ..schemas.court import CourtsResponse, Court

def get_all_courts(db: Session) -> CourtsResponse:
    # Fetching live data from the DB. Geofence columns are added at boot by
    # ensure_court_columns(), so they're always present here.
    result = db.execute(
        text(
            "SELECT id, court_uid, name, is_active, latitude, longitude, "
            "geofence_radius, address, day_cutoff_hour FROM courts"
        )
    ).mappings().all()

    courts_list = []
    for row in result:
        lat = row["latitude"]
        lng = row["longitude"]
        has_geo = lat is not None and lng is not None
        courts_list.append(
            Court(
                id=row["id"],
                court_uid=row["court_uid"],
                name=row["name"],
                # Prefer the picked address; fall back to the name.
                location=row["address"] or row["name"],
                is_active=bool(row["is_active"]),
                latitude=lat,
                longitude=lng,
                geofence_radius=row["geofence_radius"],
                address=row["address"],
                day_cutoff_hour=row["day_cutoff_hour"] or 0,
                has_geofence=has_geo,
            )
        )

    return CourtsResponse(courts=courts_list)
