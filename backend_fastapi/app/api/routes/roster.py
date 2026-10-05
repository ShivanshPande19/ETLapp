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
    """Court-wise staff attendance roster. Full-access management sees every
    court; a view-only Crownest Zone Manager sees ONLY its assigned court(s).
    Outlet managers/staff get 403."""
    if user.is_etl_manager:
        pass
    elif user.is_zone_manager:
        if not user.court_ids:
            raise HTTPException(status_code=403, detail="No zone assigned to your account.")
        if court_id is not None and court_id not in set(user.court_ids):
            raise HTTPException(status_code=403, detail="You cannot access that court.")
    else:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    if not target_date:
        target_date = now_ist().date()

    resp = get_etl_court_roster(db, target_date, court_id)

    # Zone manager: keep only its courts + recompute totals; the roaming
    # maintenance team spans all zones, so it's hidden from a zone-scoped view.
    if user.is_zone_manager:
        allowed = set(user.court_ids)
        resp.courts = [c for c in resp.courts if c.court_id in allowed]
        resp.maintenance_team = []
        resp.total_courts = len(resp.courts)
        # Count DISTINCT people across the visible courts. A multi-zone colleague
        # (e.g. the zone manager themself) appears in several of its courts but
        # must be counted ONCE in the summary.
        seen: dict[int, bool] = {}
        for c in resp.courts:
            for s in c.staff_list:
                if s.staff_id not in seen:
                    seen[s.staff_id] = (s.status == "present")
        resp.total_staff = len(seen)
        resp.total_present = sum(1 for present in seen.values() if present)

    return resp


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