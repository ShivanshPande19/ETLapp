from datetime import date
from typing import Optional

from fastapi import APIRouter, Query, HTTPException, Depends
from sqlalchemy.orm import Session

from ...database import get_db
from ...schemas.sale import SalesSummaryResponse, VendorHistoryResponse
from ...services.sales_service import get_sales_summary, get_vendor_history
from ...services.petpooja_service import (
    sync_court_by_fetch_date,
    sync_all_active_outlets_by_fetch_date,
)

router = APIRouter()


@router.get("/summary", response_model=SalesSummaryResponse)
async def sales_summary(
    court_id: Optional[int] = Query(None),
    period: str = Query("yesterday"),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    return await get_sales_summary(
        db=db,
        court_id=court_id,
        period=period,
        date_from=date_from,
        date_to=date_to,
    )


@router.get("/vendor/history", response_model=VendorHistoryResponse)
async def vendor_history(
    vendor_name: str = Query(...),
    court_id: int = Query(...),
    db: Session = Depends(get_db),
):
    try:
        return await get_vendor_history(
            db=db,
            vendor_name=vendor_name,
            court_id=court_id,
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/sync")
async def sync_sales(
    fetch_for_date: str = Query(..., description="Date to send to Petpooja, e.g. 2026-05-16"),
    court_uid: Optional[str] = Query(None, description="Optional court UID; if omitted all active outlets sync"),
    force_refresh: bool = Query(True),
    db: Session = Depends(get_db),
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