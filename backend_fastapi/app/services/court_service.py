from ..schemas.court import Court, CourtsResponse

# Hardcoded for now — will come from DB later
COURTS = [
    Court(id=1, name="ETL Food Court",  location="Sector 50, Noida",  status="live"),
    Court(id=2, name="ETL Court 2",     location="Sector 62, Noida",  status="live"),
    Court(id=3, name="ETL Court 3",     location="Sector 18, Noida",  status="live"),
]

def get_all_courts() -> CourtsResponse:
    return CourtsResponse(courts=COURTS)