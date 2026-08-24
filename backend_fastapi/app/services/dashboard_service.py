from datetime import date

from sqlalchemy.orm import Session

from ..schemas.dashboard import DashboardSummary, VendorSale
from .sales_service import get_sales_summary


async def get_dashboard_summary(db: Session) -> DashboardSummary:
    # get_sales_summary is async and requires a DB session — the previous
    # version called it without `db` and without `await`, so this endpoint
    # always 500'd. court_id=None → whole-company aggregate (ETL dashboard).
    sales = await get_sales_summary(db, court_id=None)
    vendor_breakdown = [
        VendorSale(
            vendor_name=v.vendor_name,
            source_system=v.source_system,
            total_sales=v.total_sales,
            bill_count=v.bill_count,
        )
        for v in sales.vendors
    ]
    return DashboardSummary(
        date=sales.date,
        total_sales=sales.total_sales,
        total_bills=sales.total_bills,
        vendor_breakdown=vendor_breakdown,
        last_synced=date.today().isoformat() + "T00:00:00",
    )
