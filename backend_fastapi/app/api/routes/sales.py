from fastapi import APIRouter
from typing import Optional
from ...schemas.sale import SalesSummaryResponse
from ...services.sales_service import get_sales_summary

router = APIRouter()

@router.get("/summary", response_model=SalesSummaryResponse)
def sales_summary(court_id: Optional[int] = None):
    return get_sales_summary(court_id)