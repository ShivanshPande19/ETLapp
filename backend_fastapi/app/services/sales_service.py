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

# Friendly POS label shown in the app, derived from Outlet.pos_source (instead
# of a hardcoded "Petpooja"), so multi-source outlets are labelled correctly.
_SOURCE_LABELS = {
    "petpooja_generic": "Petpooja",
    "petpooja_salesdata": "Petpooja",
    "royal_pos": "Royal POS",
}

def _source_label(pos_source: Optional[str]) -> str:
    # Unknown / legacy (NULL) outlets keep the historical "Petpooja" label.
    return _SOURCE_LABELS.get((pos_source or "").strip(), "Petpooja")

def _get_date_range(period: str, date_from: Optional[str], date_to: Optional[str]) -> tuple[date, date]:
    # Use IST "today" (not the server's UTC date) so "yesterday"/week/month
    # line up with the business day. The rest of the app (attendance, court
    # cutoff, the Petpooja 4 AM buffer) is all IST-based; sales must match.
    today = now_ist().date()
    yesterday = today - timedelta(days=1)

    # ── Explicit range wins over any preset ──────────────────────────────────
    # The client computes concrete from/to for EVERY selection (a single day,
    # this/previous week, this/previous month, this/previous year, or a fully
    # custom range) and sends them here, so the backend is the single, simple
    # "sum this window" engine. This removes all the old ambiguity where a
    # preset silently meant "…up to yesterday".
    if date_from and date_to:
        s = date.fromisoformat(date_from)
        e = date.fromisoformat(date_to)
        return (s, e) if s <= e else (e, s)
    if date_from:
        # Single day (from only).
        d = date.fromisoformat(date_from)
        return d, d

    # ── Fallback presets (used by callers that don't send explicit dates, e.g.
    #    the court cards' "yesterday" quick view). All end at yesterday. ───────
    clean_period = period.lower().replace("this_", "")
    if clean_period == "week":
        return today - timedelta(days=today.weekday()), yesterday
    if clean_period == "month":
        return today.replace(day=1), yesterday
    if clean_period == "year":
        return today.replace(month=1, day=1), yesterday
    return yesterday, yesterday  # "yesterday" + any unknown


def _bucket_series(
    db: Session,
    outlet_ids: list[int],
    start: date,
    end: date,
) -> tuple[list[SalesTrendPoint], str]:
    """Sum DailySaleCache across ``outlet_ids`` over ``[start, end]`` and split
    it into a sensible number of chart points. Granularity adapts to the span
    so a chart is never one fat bar nor thousands of thin ones:

        span <= 31 days  -> one point PER DAY      (bucket="daily")
        span <= 92 days  -> one point per 7 days    (bucket="weekly")
        else             -> one point per month     (bucket="monthly")

    Every point is capped at yesterday (IST) so today's in-progress sales never
    appear — consistent with the summary.
    """
    yday = now_ist().date() - timedelta(days=1)
    end = min(end, yday)
    if not outlet_ids or start > end:
        return [], "daily"

    def totals(s: date, e: date) -> tuple[float, int]:
        rows = db.query(DailySaleCache).filter(
            DailySaleCache.outlet_id.in_(outlet_ids),
            DailySaleCache.sale_date >= s,
            DailySaleCache.sale_date <= e,
        ).all()
        return round(sum(r.total_sales for r in rows), 2), sum(r.bill_count for r in rows)

    points: list[SalesTrendPoint] = []
    span = (end - start).days + 1

    if span <= 31:
        bucket = "daily"
        d = start
        while d <= end:
            ts, tb = totals(d, d)
            points.append(SalesTrendPoint(
                label=d.strftime("%d %b"), date=str(d),
                total_sales=ts, total_bills=tb,
            ))
            d += timedelta(days=1)
    elif span <= 92:
        bucket = "weekly"
        s = start
        while s <= end:
            e = min(s + timedelta(days=6), end)
            ts, tb = totals(s, e)
            points.append(SalesTrendPoint(
                label=s.strftime("%d %b"), date=str(s),
                total_sales=ts, total_bills=tb,
            ))
            s = e + timedelta(days=1)
    else:
        bucket = "monthly"
        y, mm = start.year, start.month
        while date(y, mm, 1) <= end:
            m_start = date(y, mm, 1)
            nxt = date(y + 1, 1, 1) if mm == 12 else date(y, mm + 1, 1)
            m_end = min(nxt - timedelta(days=1), end)
            ts, tb = totals(max(m_start, start), m_end)
            points.append(SalesTrendPoint(
                label=month_abbr[mm], date=str(m_start),
                total_sales=ts, total_bills=tb,
            ))
            y, mm = (y + 1, 1) if mm == 12 else (y, mm + 1)

    return points, bucket

def _date_label(start: date, end: date) -> str:
    if start == end:
        return start.strftime("%b %d, %Y")
    if start.year == end.year:
        return f"{start.strftime('%b %d')} - {end.strftime('%b %d, %Y')}"
    return f"{start.strftime('%b %d, %Y')} - {end.strftime('%b %d, %Y')}"

async def get_sales_summary(
    db: Session,
    court_id: Optional[int] = None,
    outlet_id: Optional[int] = None, # ✓ Added outlet_id
    period: str = "yesterday",
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    outlet_ids: Optional[list[int]] = None,  # ✓ MULTI-OUTLET: aggregate over a set
) -> SalesSummaryResponse:
    start_date, end_date = _get_date_range(period, date_from, date_to)

    # Base query on Outlet
    query = db.query(Outlet).filter(Outlet.is_active == 1)

    # ✓ Priority: explicit outlet_ids set (multi-outlet owner) > single
    #   outlet_id > court_id. An empty set means "no accessible outlets" and
    #   must return nothing (the -1 sentinel guarantees an empty IN()).
    if outlet_ids is not None:
        query = query.filter(Outlet.id.in_(outlet_ids or [-1]))
    elif outlet_id:
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
                source_system=_source_label(outlet.pos_source),
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
    vendor_name: Optional[str] = None, # ✓ Made Optional
    court_id: Optional[int] = None,    # ✓ Made Optional
    outlet_id: Optional[int] = None,   # ✓ Added outlet_id
    date_from: Optional[str] = None,   # ✓ range-aware per-brand detail
    date_to: Optional[str] = None,
) -> VendorHistoryResponse:
    
    # ✓ Smart routing: Agar outlet_id h toh seedha fetch, warna purana method
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

    # ── Range mode: per-brand numbers for the EXACT selected window ──────────
    # This is what makes a brand's detail sheet match the range chosen on the
    # sales screen (previously it was hard-wired to a rolling last-7-days view,
    # so per-brand numbers never matched an arbitrary range).
    if date_from and date_to:
        s = date.fromisoformat(date_from)
        e = date.fromisoformat(date_to)
        if s > e:
            s, e = e, s
        yday = now_ist().date() - timedelta(days=1)
        e = min(e, yday)

        pts, _bucket = _bucket_series(db, [outlet.id], s, e)
        daily_history = [
            DailySnapshot(date=p.date, total_sales=p.total_sales, total_bills=p.total_bills)
            for p in pts
        ]
        range_total = round(sum(p.total_sales for p in pts), 2)
        range_bills = sum(p.total_bills for p in pts)

        # Previous window of equal length (for a period-over-period delta).
        prev_total = 0.0
        if s <= e:
            span_days = (e - s).days + 1
            prev_end = s - timedelta(days=1)
            prev_start = prev_end - timedelta(days=span_days - 1)
            prev_rows = db.query(DailySaleCache).filter(
                DailySaleCache.outlet_id == outlet.id,
                DailySaleCache.sale_date >= prev_start,
                DailySaleCache.sale_date <= prev_end,
            ).all()
            prev_total = round(sum(r.total_sales for r in prev_rows), 2)

        best = max(daily_history, key=lambda x: x.total_sales) if daily_history else None

        synced_rows = db.query(DailySaleCache).filter(
            DailySaleCache.outlet_id == outlet.id,
            DailySaleCache.sale_date >= s,
            DailySaleCache.sale_date <= e,
        ).all()
        last_synced = max((c.fetched_at for c in synced_rows if c.fetched_at), default=None)

        return VendorHistoryResponse(
            vendor_name=outlet.vendor_name,
            source_system=_source_label(outlet.pos_source),
            total_sales=range_total,
            bill_count=range_bills,
            avg_bill_value=round(range_total / range_bills, 2) if range_bills else 0.0,
            last_synced=str(last_synced) if last_synced else "",
            week_total=range_total,          # reused as "selected-range total"
            last_week_total=prev_total,      # previous equal-length window
            best_day=best.date if best else "",
            daily_history=daily_history,
        )

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
        source_system=_source_label(outlet.pos_source),
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
    outlet_ids: Optional[list[int]] = None,  # ✓ MULTI-OUTLET: aggregate over a set
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> SalesTrendResponse:
    """Daily/monthly time-series for the sales chart, scoped to all courts, one
    court, one outlet, or an explicit set of outlets (a multi-outlet owner).
    Every series ends at 'yesterday' (IST) so today's in-progress sales never
    show — consistent with the summary."""
    today = now_ist().date()
    clean = period.lower().replace("this_", "")
    # An explicit set wins (multi-outlet owner viewing "all my outlets").
    outlet_ids = list(outlet_ids) if outlet_ids is not None else _resolve_outlet_ids(db, court_id, outlet_id)

    # ── Explicit range → span-adaptive buckets (matches the summary window) ──
    if date_from and date_to:
        s = date.fromisoformat(date_from)
        e = date.fromisoformat(date_to)
        if s > e:
            s, e = e, s
        pts, bucket = _bucket_series(db, outlet_ids, s, e)
        return SalesTrendResponse(period=period, bucket=bucket, points=pts)

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

    yday = today - timedelta(days=1)

    def totals_upto_yesterday(s: date, e: date) -> tuple[float, int]:
        # Count only completed business days (<= yesterday). Buckets that lie in
        # the future contribute 0, so every chart keeps its full, pre-set shape
        # (no single fat bar) while the visible totals still add up to the
        # summary for the same period.
        e2 = min(e, yday)
        return range_totals(s, e2) if s <= e2 else (0.0, 0)

    if clean == "year":
        # All 12 months of the current calendar year (Jan..Dec). Months that
        # haven't happened yet show 0 so the chart is always a full 12-bar shape.
        bucket = "monthly"
        yr = today.year
        for mm in range(1, 13):
            start = date(yr, mm, 1)
            nxt = date(yr, mm + 1, 1) if mm < 12 else date(yr + 1, 1, 1)
            ts, tb = totals_upto_yesterday(start, nxt - timedelta(days=1))
            points.append(SalesTrendPoint(
                label=month_abbr[mm], date=str(start),
                total_sales=ts, total_bills=tb,
            ))
    elif clean == "month":
        # All 7-day buckets of the current month (1-7, 8-14, 15-21, 22-28,
        # 29-EOM). Weeks not reached yet show 0 so the chart is a proper
        # multi-bar shape, not one big block. Day-of-month based, so the weekday
        # the 1st falls on (e.g. Wednesday) never distorts it.
        bucket = "weekly"
        first = today.replace(day=1)
        nxt_month = (date(first.year + 1, 1, 1)
                     if first.month == 12
                     else date(first.year, first.month + 1, 1))
        last_day = (nxt_month - timedelta(days=1)).day
        day = 1
        while day <= last_day:
            end_day = min(day + 6, last_day)
            start = first.replace(day=day)
            ts, tb = totals_upto_yesterday(start, first.replace(day=end_day))
            points.append(SalesTrendPoint(
                label=f"{day}-{end_day}",
                date=str(start),
                total_sales=ts,
                total_bills=tb,
            ))
            day = end_day + 1
    elif clean == "week":
        # All 7 days of the current calendar week (Mon..Sun). Days not reached
        # yet show 0 so the chart is always a full 7-bar shape.
        bucket = "daily"
        monday = today - timedelta(days=today.weekday())
        for i in range(7):
            d = monday + timedelta(days=i)
            ts, tb = totals_upto_yesterday(d, d)
            points.append(SalesTrendPoint(
                label=d.strftime("%a"),
                date=str(d),
                total_sales=ts,
                total_bills=tb,
            ))
    else:
        # 'yesterday' -> last 7 days (daily) for context, ending yesterday.
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
