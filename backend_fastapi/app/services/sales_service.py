from datetime import date, timedelta
from calendar import month_abbr
from typing import Optional

from sqlalchemy.orm import Session

from ..core.query_utils import now_ist
from ..models.sale import Outlet, DailySaleCache
from ..schemas.sale import (
    SalesSummaryResponse,
    VendorSaleDetail,
    VendorHistoryResponse,
    DailySnapshot,
    SalesTrendPoint,
    SalesTrendResponse,
)


def _get_date_range(period: str, date_from: Optional[str], date_to: Optional[str]) -> tuple[date, date]:
    # Use IST "today" (not the server's UTC date) so "yesterday"/week/month
    # line up with the business day. The rest of the app (attendance, court
    # cutoff, the Petpooja 4 AM buffer) is all IST-based; sales must match.
    today = now_ist().date()
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
    outlet_id: Optional[int] = None, # ✅ Added outlet_id
    period: str = "yesterday",
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> SalesSummaryResponse:
    start_date, end_date = _get_date_range(period, date_from, date_to)

    # Base query on Outlet
    query = db.query(Outlet).filter(Outlet.is_active == 1)

    # ✅ Logic: Outlet_id priority par hai, agar wo nahi toh court_id
    if outlet_id:
        query = query.filter(Outlet.id == outlet_id)
    elif court_id:
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
    vendor_name: Optional[str] = None, # ✅ Made Optional
    court_id: Optional[int] = None,    # ✅ Made Optional
    outlet_id: Optional[int] = None,   # ✅ Added outlet_id
) -> VendorHistoryResponse:
    
    # ✅ Smart routing: Agar outlet_id h toh seedha fetch, warna purana method
    if outlet_id:
        outlet = db.query(Outlet).filter(
            Outlet.id == outlet_id,
            Outlet.is_active == 1,
        ).first()
    elif vendor_name and court_id is not None:
        outlet = db.query(Outlet).filter(
            Outlet.vendor_name == vendor_name,
            Outlet.court_id == court_id,
            Outlet.is_active == 1,
        ).first()
    else:
        raise ValueError("Must provide either outlet_id, or both vendor_name and court_id")

    if not outlet:
        raise ValueError("Outlet not found")

    today = now_ist().date()
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



def _resolve_outlet_ids(db: Session, court_id: Optional[int], outlet_id: Optional[int]) -> list[int]:
    q = db.query(Outlet).filter(Outlet.is_active == 1)
    if outlet_id:
        q = q.filter(Outlet.id == outlet_id)
    elif court_id:
        q = q.filter(Outlet.court_id == court_id)
    return [o.id for o in q.all()]


async def get_sales_trend(
    db: Session,
    court_id: Optional[int] = None,
    outlet_id: Optional[int] = None,
    period: str = "yesterday",
) -> SalesTrendResponse:
    """Daily/monthly time-series for the sales chart, scoped to all courts, one
    court, or one outlet. Every series ends at 'yesterday' (IST) so today's
    in-progress sales never show — consistent with the summary."""
    today = now_ist().date()
    clean = period.lower().replace("this_", "")
    outlet_ids = _resolve_outlet_ids(db, court_id, outlet_id)

    def range_totals(start: date, end: date) -> tuple[float, int]:
        if not outlet_ids:
            return 0.0, 0
        rows = db.query(DailySaleCache).filter(
            DailySaleCache.outlet_id.in_(outlet_ids),
            DailySaleCache.sale_date >= start,
            DailySaleCache.sale_date <= end,
        ).all()
        return round(sum(r.total_sales for r in rows), 2), sum(r.bill_count for r in rows)

    points: list[SalesTrendPoint] = []
    bucket = "daily"

    if clean == "year":
        bucket = "monthly"
        y, m = today.year, today.month
        months: list[tuple[int, int]] = []
        for _ in range(12):
            months.append((y, m))
            m -= 1
            if m == 0:
                m, y = 12, y - 1
        months.reverse()
        for (yy, mm) in months:
            start = date(yy, mm, 1)
            nxt = date(yy + 1, 1, 1) if mm == 12 else date(yy, mm + 1, 1)
            end = min(nxt - timedelta(days=1), today - timedelta(days=1))
            ts, tb = range_totals(start, end) if end >= start else (0.0, 0)
            points.append(SalesTrendPoint(label=month_abbr[mm], date=str(start), total_sales=ts, total_bills=tb))
    elif clean == "month":
        # Last 4 weeks as 7-day buckets, ending yesterday (oldest -> newest).
        # Cleaner + more actionable than 30 cramped daily bars.
        bucket = "weekly"
        for w in range(4, 0, -1):
            end = today - timedelta(days=(w - 1) * 7 + 1)
            start = end - timedelta(days=6)
            ts, tb = range_totals(start, end)
            points.append(SalesTrendPoint(
                label=f"{start.day}-{end.day}",
                date=str(start),
                total_sales=ts,
                total_bills=tb,
            ))
    else:
        # yesterday & week -> last 7 days (daily), ending yesterday
        for i in range(7, 0, -1):
            d = today - timedelta(days=i)
            ts, tb = range_totals(d, d)
            points.append(SalesTrendPoint(
                label=d.strftime("%a"),
                date=str(d),
                total_sales=ts,
                total_bills=tb,
            ))

    return SalesTrendResponse(period=period, bucket=bucket, points=points)
