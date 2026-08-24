from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ...database import get_db
from ...schemas.dashboard import DashboardSummary
from ...services.dashboard_service import get_dashboard_summary
from ..deps import require_etl_manager, CurrentUser

router = APIRouter()


@router.get("/summary", response_model=DashboardSummary)
async def dashboard_summary(
    db: Session = Depends(get_db),
    _user: CurrentUser = Depends(require_etl_manager),
):
    # ETL-wide sales dashboard. Guarded to ETL managers (whole-company data).
    return await get_dashboard_summary(db)
