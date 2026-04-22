from fastapi import APIRouter
from ...schemas.dashboard import DashboardSummary
from ...services.dashboard_service import get_dashboard_summary

router = APIRouter()

@router.get("/summary", response_model=DashboardSummary)
def dashboard_summary():
    return get_dashboard_summary()