from sqlalchemy.orm import Session
from sqlalchemy import text
from ..schemas.court import CourtsResponse, Court

def get_all_courts(db: Session) -> CourtsResponse:
    # Fetching live data from SQLite DB instead of hardcoded list
    result = db.execute(text("SELECT id, court_uid, name, is_active FROM courts")).fetchall()
    
    courts_list = []
    for row in result:
        courts_list.append(
            Court(
                id=row[0],
                court_uid=row[1],
                name=row[2],
                location=row[2], # DB me location column nahi hai toh name use kar rahe hain
                is_active=bool(row[3])
            )
        )
    
    return CourtsResponse(courts=courts_list)