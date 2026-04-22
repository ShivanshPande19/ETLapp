from datetime import date
from ..schemas.dashboard import DashboardSummary, VendorSale
from .sales_service import get_sales_summary


def get_dashboard_summary() -> DashboardSummary:
    """
    Delegates entirely to the sales service with no court_id filter.
    This ensures the Home screen banner always shows the same
    combined total as the Sales screen 'All Courts' tab.
    """
    sales = get_sales_summary(court_id=None)

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