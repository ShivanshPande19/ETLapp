from datetime import date, timedelta
from typing import Optional

from sqlalchemy.orm import Session

from ..models.sale import Outlet, DailySaleCache
from ..schemas.sale import (
    SalesSummaryResponse,
    VendorSaleDetail,
    VendorHistoryResponse,
    DailySnapshot,
)


def _get_date_range(period: str, date_from: Optional[str], date_to: Optional[str]) -> tuple[date, date]:
    today = date.today()
    yesterday = today - timedelta(days=1)

    clean_period = period.lower().replace("this_", "")

    if clean_period == "yesterday":
        return yesterday, yesterday

    if clean_period == "week":
        return today - timedelta(days=7), yesterday

    if clean_period == "month":
        return today - timedelta(days=30), yesterday

    if clean_period == "year":
        return today - timedelta(days=365), yesterday

    # FIX: Custom select karne par range nahi, balki exact SINGLE DATE pick hogi
    if clean_period == "custom" and date_from:
        single_date = date.fromisoformat(date_from)
        return single_date, single_date  # Dono ko same day kar diya taaki exact match ho

    return yesterday, yesterday


def _date_label(start: date, end: date) -> str:
    if start == end:
        return start.strftime("%b %d, %Y")
    if start.year == end.year:
        return f"{start.strftime('%b %d')} - {end.strftime('%b %d, %Y')}"
    return f"{start.strftime('%b %d, %Y')} - {end.strftime('%b %d, %Y')}"


async def get_sales_summary(
    db: Session,
    court_id: Optional[int] = None,
    period: str = "yesterday",
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> SalesSummaryResponse:
    start_date, end_date = _get_date_range(period, date_from, date_to)

    query = db.query(Outlet).filter(Outlet.is_active == 1)
    if court_id is not None:
        query = query.filter(Outlet.court_id == court_id)

    outlets = query.all()
    vendor_details = []

    for outlet in outlets:
        caches = db.query(DailySaleCache).filter(
            DailySaleCache.outlet_id == outlet.id,
            DailySaleCache.sale_date >= start_date,
            DailySaleCache.sale_date <= end_date,
        ).all()

        total_sales = sum(c.total_sales for c in caches)
        bill_count = sum(c.bill_count for c in caches)
        
        last_synced = max((c.fetched_at for c in caches if c.fetched_at), default=None)

        vendor_details.append(
            VendorSaleDetail(
                vendor_name=outlet.vendor_name,
                source_system="Petpooja",
                total_sales=round(total_sales, 2),
                bill_count=bill_count,
                avg_bill_value=round(total_sales / bill_count, 2) if bill_count else 0.0,
                last_synced=str(last_synced) if last_synced else "",
            )
        )

    grand_total_sales = sum(v.total_sales for v in vendor_details)
    grand_total_bills = sum(v.bill_count for v in vendor_details)

    return SalesSummaryResponse(
        date=_date_label(start_date, end_date),
        period=period,
        total_sales=round(grand_total_sales, 2),
        total_bills=grand_total_bills,
        avg_bill_value=round(grand_total_sales / grand_total_bills, 2) if grand_total_bills else 0.0,
        vendors=vendor_details,
    )


async def get_vendor_history(
    db: Session,
    vendor_name: str,
    court_id: int,
) -> VendorHistoryResponse:
    outlet = db.query(Outlet).filter(
        Outlet.vendor_name == vendor_name,
        Outlet.court_id == court_id,
        Outlet.is_active == 1,
    ).first()

    if not outlet:
        raise ValueError(f"Vendor '{vendor_name}' not found in court {court_id}")

    today = date.today()
    history = []

    for i in range(7, 0, -1):
        day = today - timedelta(days=i)

        cache = db.query(DailySaleCache).filter(
            DailySaleCache.outlet_id == outlet.id,
            DailySaleCache.sale_date == day,
        ).first()

        history.append(
            DailySnapshot(
                date=str(day),
                total_sales=cache.total_sales if cache else 0.0,
                total_bills=cache.bill_count if cache else 0,
            )
        )

    week_total = round(sum(s.total_sales for s in history), 2)

    previous_week_total = 0.0
    for i in range(14, 7, -1):
        day = today - timedelta(days=i)

        cache = db.query(DailySaleCache).filter(
            DailySaleCache.outlet_id == outlet.id,
            DailySaleCache.sale_date == day,
        ).first()

        if cache:
            previous_week_total += cache.total_sales

    previous_week_total = round(previous_week_total, 2)

    best = max(history, key=lambda x: x.total_sales) if history else None

    latest_cache = db.query(DailySaleCache).filter(
        DailySaleCache.outlet_id == outlet.id,
        DailySaleCache.sale_date == today - timedelta(days=1),
    ).first()

    return VendorHistoryResponse(
        vendor_name=outlet.vendor_name,
        source_system="Petpooja",
        total_sales=latest_cache.total_sales if latest_cache else 0.0,
        bill_count=latest_cache.bill_count if latest_cache else 0,
        avg_bill_value=latest_cache.avg_bill if latest_cache else 0.0,
        last_synced=str(latest_cache.fetched_at) if latest_cache else "",
        week_total=week_total,
        last_week_total=previous_week_total,
        best_day=best.date if best else "",
        daily_history=history,
    )