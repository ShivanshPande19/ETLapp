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


def _validate_date_params(date_from: Optional[str], date_to: Optional[str]) -> None:
    """Reject malformed date_from/date_to with a clean 400 (instead of letting
    date.fromisoformat raise deep in the service → 500)."""
    for label, value in (("date_from", date_from), ("date_to", date_to)):
        if value:
            try:
                date.fromisoformat(value)
            except ValueError:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid {label}. Use YYYY-MM-DD.",
                )


def _scope_outlets(
    user: CurrentUser,
    court_id: Optional[int],
    outlet_id: Optional[int],
) -> tuple[Optional[int], Optional[int], Optional[list[int]]]:
    """Constrain a summary/trend request to what `user` may read.

    Returns ``(court_id, outlet_id, outlet_ids)`` to pass to the service.

    SECURITY (P0 + MULTI-OUTLET): the client can never widen its own scope.
      • ETL manager   → unrestricted; client court_id/outlet_id honored
                        (both None = whole company).
      • Outlet user   → if a specific outlet_id is requested it MUST be one of
                        theirs (else 403); otherwise aggregate across ALL their
                        outlets (multi-outlet owner "all my outlets" view).
      • ETL staff     → locked to their own court.
    """
    if user.is_etl_manager:
        return court_id, outlet_id, None
    if user.is_outlet_user:
        if not user.outlet_ids:
            raise HTTPException(status_code=403, detail="No outlet assigned to your account.")
        if outlet_id is not None:
            if outlet_id not in user.outlet_ids:
                raise HTTPException(status_code=403, detail="You cannot access that outlet.")
            return None, outlet_id, None
        # No specific selection → all of the owner's outlets, aggregated.
        return None, None, list(user.outlet_ids)
    if user.is_etl_staff:
        if user.court_id is None:
            raise HTTPException(status_code=403, detail="No court assigned to your account.")
        return user.court_id, None, None
    raise HTTPException(status_code=403, detail="Access denied.")


def _scope_single_outlet(
    user: CurrentUser,
    court_id: Optional[int],
    outlet_id: Optional[int],
    vendor_name: Optional[str],
) -> tuple[Optional[int], Optional[int], Optional[str]]:
    """Vendor history returns ONE vendor's series, so resolve to a single
    outlet the caller may access."""
    if user.is_etl_manager:
        return court_id, outlet_id, vendor_name
    if user.is_outlet_user:
        if not user.outlet_ids:
            raise HTTPException(status_code=403, detail="No outlet assigned to your account.")
        target = outlet_id
        if target is None and len(user.outlet_ids) == 1:
            target = user.outlet_ids[0]
        if target is None:
            raise HTTPException(status_code=400, detail="outlet_id is required.")
        if target not in user.outlet_ids:
            raise HTTPException(status_code=403, detail="You cannot access that outlet.")
        return None, target, None
    if user.is_etl_staff:
        if user.court_id is None:
            raise HTTPException(status_code=403, detail="No court assigned to your account.")
        return user.court_id, None, vendor_name
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
    _validate_date_params(date_from, date_to)
    court_id, outlet_id, outlet_ids = _scope_outlets(user, court_id, outlet_id)
    return await get_sales_summary(
        db=db,
        court_id=court_id,
        outlet_id=outlet_id, # ✅ Service ko pass kar diya
        outlet_ids=outlet_ids,
        period=period,
        date_from=date_from,
        date_to=date_to,
    )


@router.get("/trend", response_model=SalesTrendResponse)
async def sales_trend(
    court_id: Optional[int] = Query(None),
    outlet_id: Optional[int] = Query(None),
    period: str = Query("yesterday"),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    _validate_date_params(date_from, date_to)
    court_id, outlet_id, outlet_ids = _scope_outlets(user, court_id, outlet_id)
    return await get_sales_trend(
        db=db,
        court_id=court_id,
        outlet_id=outlet_id,
        outlet_ids=outlet_ids,
        period=period,
        date_from=date_from,
        date_to=date_to,
    )


@router.get("/vendor/history", response_model=VendorHistoryResponse)
async def vendor_history(
    vendor_name: Optional[str] = Query(None), # ✅ NAYA: Made optional
    court_id: Optional[int] = Query(None),    # ✅ NAYA: Made optional
    outlet_id: Optional[int] = Query(None),   # ✅ NAYA: Added outlet_id
    date_from: Optional[str] = Query(None),   # ✅ range-aware per-brand detail
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    court_id, outlet_id, vendor_name = _scope_single_outlet(
        user, court_id, outlet_id, vendor_name
    )
    try:
        return await get_vendor_history(
            db=db,
            vendor_name=vendor_name,
            court_id=court_id,
            outlet_id=outlet_id, # ✅ Service ko id pass kardi
            date_from=date_from,
            date_to=date_to,
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/sync")
async def sync_sales(
    fetch_for_date: str = Query(..., description="Date to send to Petpooja, e.g. 2026-05-16"),
    court_uid: Optional[str] = Query(None, description="Optional court UID; if omitted all active outlets sync"),
    force_refresh: bool = Query(True),
    db: Session = Depends(get_db),
    # SECURITY (P0-1): triggering a POS fetch is an ETL-manager-only action.
    user: CurrentUser = Depends(require_etl_manager),
):
    try:
        parsed_fetch_date = date.fromisoformat(fetch_for_date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid fetch_for_date. Use YYYY-MM-DD")

    try:
        if court_uid:
            result = await sync_court_by_fetch_date(
                db=db,
                court_uid=court_uid,
                fetch_for_date=parsed_fetch_date,
                force_refresh=force_refresh,
            )
        else:
            result = await sync_all_active_outlets_by_fetch_date(
                db=db,
                fetch_for_date=parsed_fetch_date,
                force_refresh=force_refresh,
            )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    # If we attempted outlets and EVERY one failed, this is a real failure —
    # don't report it as a 200 "success" (which is what used to happen). The
    # per-outlet details still show which ones failed.
    attempted = result.get("outlets_synced", 0)
    failed = result.get("outlets_failed", 0)
    if attempted > 0 and failed >= attempted:
        raise HTTPException(
            status_code=502,
            detail="Sales sync failed for all outlets — check POS credentials / connectivity.",
        )
    return result
