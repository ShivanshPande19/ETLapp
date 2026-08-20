from datetime import date
from typing import Optional

from fastapi import APIRouter, Query, HTTPException, Depends
from sqlalchemy.orm import Session

from ...database import get_db
from ...schemas.sale import SalesSummaryResponse, VendorHistoryResponse, SalesTrendResponse
from ...services.sales_service import get_sales_summary, get_vendor_history, get_sales_trend
from ...services.petpooja_service import (
    sync_court_by_fetch_date,
    sync_all_active_outlets_by_fetch_date,
)
from ..deps import get_current_user, require_etl_manager, CurrentUser

router = APIRouter()


def _scope_sales_ids(
    user: CurrentUser,
    court_id: Optional[int],
    outlet_id: Optional[int],
) -> tuple[Optional[int], Optional[int]]:
    """Constrain (court_id, outlet_id) to what `user` is allowed to read.

    SECURITY (P0-1 / P0-3): sales revenue is tenant-sensitive. The client must
    NOT be able to widen its own scope via query params, so we recompute the
    scope from the JWT identity here — never trust the incoming ids for
    non-ETL-manager callers.

      • ETL manager   → unrestricted; may pass any court_id/outlet_id
                        (both None = whole company, the ETL dashboard case).
      • Outlet user   → hard-locked to their OWN outlet (outlet_manager /
                        outlet_staff). Incoming ids are ignored.
      • ETL staff     → hard-locked to their OWN court. Incoming ids ignored.
    """
    if user.is_etl_manager:
        return court_id, outlet_id
    if user.is_outlet_user:
        if user.outlet_id is None:
            raise HTTPException(status_code=403, detail="No outlet assigned to your account.")
        return None, user.outlet_id
    if user.is_etl_staff:
        if user.court_id is None:
            raise HTTPException(status_code=403, detail="No court assigned to your account.")
        return user.court_id, None
    raise HTTPException(status_code=403, detail="Access denied.")


@router.get("/summary", response_model=SalesSummaryResponse)
async def sales_summary(
    court_id: Optional[int] = Query(None),
    outlet_id: Optional[int] = Query(None), # ✅ NAYA: Outlet ID parameter
    period: str = Query("yesterday"),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # Server-side tenancy scoping — the client cannot read another tenant's
    # revenue by passing a different court_id/outlet_id.
    court_id, outlet_id = _scope_sales_ids(user, court_id, outlet_id)
    return await get_sales_summary(
        db=db,
        court_id=court_id,
        outlet_id=outlet_id, # ✅ Service ko pass kar diya
        period=period,
        date_from=date_from,
        date_to=date_to,
    )


@router.get("/trend", response_model=SalesTrendResponse)
async def sales_trend(
    court_id: Optional[int] = Query(None),
    outlet_id: Optional[int] = Query(None),
    period: str = Query("yesterday"),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    court_id, outlet_id = _scope_sales_ids(user, court_id, outlet_id)
    return await get_sales_trend(
        db=db,
        court_id=court_id,
        outlet_id=outlet_id,
        period=period,
    )


@router.get("/vendor/history", response_model=VendorHistoryResponse)
async def vendor_history(
    vendor_name: Optional[str] = Query(None), # ✅ NAYA: Made optional
    court_id: Optional[int] = Query(None),    # ✅ NAYA: Made optional
    outlet_id: Optional[int] = Query(None),   # ✅ NAYA: Added outlet_id
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # Same tenancy scoping as /summary. For an outlet user the outlet_id path is
    # forced (vendor_name/court_id are ignored by the service when outlet_id is
    # set); an ETL staff is locked to their court.
    court_id, outlet_id = _scope_sales_ids(user, court_id, outlet_id)
    try:
        return await get_vendor_history(
            db=db,
            vendor_name=vendor_name,
            court_id=court_id,
            outlet_id=outlet_id, # ✅ Service ko id pass kardi
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/sync")
async def sync_sales(
    fetch_for_date: str = Query(..., description="Date to send to Petpooja, e.g. 2026-05-16"),
    court_uid: Optional[str] = Query(None, description="Optional court UID; if omitted all active outlets sync"),
    force_refresh: bool = Query(True),
    db: Session = Depends(get_db),
    # SECURITY (P0-1): triggering a POS fetch is an ETL-manager-only action so
    # the endpoint can't be used to hammer Petpooja anonymously.
    user: CurrentUser = Depends(require_etl_manager),
):
    try:
        parsed_fetch_date = date.fromisoformat(fetch_for_date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid fetch_for_date. Use YYYY-MM-DD")

    try:
        if court_uid:
            return await sync_court_by_fetch_date(
                db=db,
                court_uid=court_uid,
                fetch_for_date=parsed_fetch_date,
                force_refresh=force_refresh,
            )

        return await sync_all_active_outlets_by_fetch_date(
            db=db,
            fetch_for_date=parsed_fetch_date,
            force_refresh=force_refresh,
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
