# backend_fastapi/app/api/routes/roster.py

from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from datetime import date
from typing import Optional

from ...database import get_db
from ...schemas.attendance import RosterResponse
from ...services.roster_service import get_daily_roster
from ..deps import get_current_user, CurrentUser

router = APIRouter()

@router.get("/", response_model=RosterResponse)
def get_roster(
    outlet_id: int = Query(...),
    target_date: Optional[date] = Query(None, description="Format YYYY-MM-DD. Defaults to today."),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # ✅ Auth: outlet users can only see their own outlet; ETL managers any.
    if user.is_outlet_user:
        if user.outlet_id != outlet_id:
            raise HTTPException(
                status_code=403,
                detail="You can only view your own outlet's roster.",
            )
    elif not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="Access denied.")

    if not target_date:
        target_date = date.today()

    return get_daily_roster(db, outlet_id, target_date)