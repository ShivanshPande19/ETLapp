# backend_fastapi/app/api/routes/roster.py

from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from datetime import date
from typing import Optional

from ...database import get_db
from ...schemas.attendance import RosterResponse, EtlRosterResponse
from ...services.roster_service import get_daily_roster, get_etl_court_roster
from ...core.query_utils import now_ist
from ..deps import get_current_user, CurrentUser

router = APIRouter()

@router.get("/etl", response_model=EtlRosterResponse)
def get_etl_roster(
    target_date: Optional[date] = Query(None, description="Format YYYY-MM-DD. Defaults to today."),
    court_id: Optional[int] = Query(None, description="Filter to a single court. Omit for all courts."),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """ETL manager: court-wise staff attendance roster. Sirf ETL manager
    access kar sakta hai (outlet managers/staff ko 403)."""
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    if not target_date:
        target_date = now_ist().date()

    return get_etl_court_roster(db, target_date, court_id)


@router.get("/", response_model=RosterResponse)
def get_roster(
    outlet_id: int = Query(...),
    target_date: Optional[date] = Query(None, description="Format YYYY-MM-DD. Defaults to today."),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # ✅ Auth: outlet users can only see their own outlet; ETL managers any.
    if user.is_outlet_user:
        if outlet_id not in user.outlet_ids:  # MULTI-OUTLET
            raise HTTPException(
                status_code=403,
                detail="You can only view your own outlet's roster.",
            )
    elif not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="Access denied.")

    if not target_date:
        target_date = now_ist().date()

    return get_daily_roster(db, outlet_id, target_date)