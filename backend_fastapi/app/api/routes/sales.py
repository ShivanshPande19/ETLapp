from fastapi import APIRouter, Query, HTTPException
from typing import Optional
from ...schemas.sale import SalesSummaryResponse, VendorHistoryResponse
from ...services.sales_service import get_sales_summary, get_vendor_history

router = APIRouter()

@router.get("/summary", response_model=SalesSummaryResponse)
def sales_summary(
    court_id:  Optional[int] = Query(None),
    period:    str           = Query("yesterday"),
    date_from: Optional[str] = Query(None),
    date_to:   Optional[str] = Query(None),
):
    return get_sales_summary(
        court_id  = court_id,
        period    = period,
        date_from = date_from,
        date_to   = date_to,
    )

@router.get("/vendor/history", response_model=VendorHistoryResponse)
def vendor_history(
    vendor_name: str = Query(...),
    court_id:    int = Query(...),
):
    try:
        return get_vendor_history(vendor_name=vendor_name, court_id=court_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
