# backend_fastapi/app/api/routes/roster.py

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from datetime import date
from typing import Optional

from ...database import get_db
from ...schemas.attendance import RosterResponse
from ...services.roster_service import get_daily_roster

router = APIRouter()

@router.get("/", response_model=RosterResponse)
def get_roster(
    outlet_id: int = Query(...),
    target_date: Optional[date] = Query(None, description="Format YYYY-MM-DD. Defaults to today."),
    db: Session = Depends(get_db)
):
    if not target_date:
        target_date = date.today()
        
    return get_daily_roster(db, outlet_id, target_date)