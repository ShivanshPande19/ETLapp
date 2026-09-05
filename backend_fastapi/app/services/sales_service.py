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
    ComparePoint,
    SalesCompareResponse,
)

# Friendly POS label shown in the app, derived from Outlet.pos_source (instead
# of a hardcoded "Petpooja"), so multi-source outlets are labelled correctly.
_SOURCE_LABELS = {
    "petpooja_generic": "Petpooja",
    "petpooja_salesdata": "Petpooja",
    "royal_pos": "Royal POS",
    "rista": "Rista",
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

    # Explicit window wins over any preset. The client sends concrete from/to
    # for a picked day, a custom range, AND for "previous week/month/year"
    # (which it computes), so the backend just sums that window. Same date twice
    # => that single day.
    if date_from and date_to:
        s = date.fromisoformat(date_from)
        e = date.fromisoformat(date_to)
        return (s, e) if s <= e else (e, s)
    if date_from:
        single_date = date.fromisoformat(date_from)
        return single_date, single_date

    clean_period = period.lower().replace("this_", "")

    if clean_period == "yesterday":
        return yesterday, yesterday

    if clean_period == "week":
        # Current calendar week so far: Monday of this week -> yesterday.
        return today - timedelta(days=today.weekday()), yesterday

    if clean_period == "month":
        # Current calendar month so far: 1st of this month -> yesterday.
        # (Previously a rolling last-30-days window, which bled into last month.)
        return today.replace(day=1), yesterday

    if clean_period == "year":
        # Current calendar year so far: Jan 1 -> yesterday.
        return today.replace(month=1, day=1), yesterday

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

    # ── Explicit range (custom range OR a "previous" period from the client) →
    #    adaptive buckets so the chart matches the selected window. ───────────
    if date_from and date_to:
        s = date.fromisoformat(date_from)
        e = date.fromisoformat(date_to)
        if s > e:
            s, e = e, s
        e = min(e, yday)
        rp: list[SalesTrendPoint] = []
        bkt = "daily"
        if outlet_ids and s <= e:
            span = (e - s).days + 1
            if span <= 31:
                bkt = "daily"
                d = s
                while d <= e:
                    ts, tb = range_totals(d, d)
                    rp.append(SalesTrendPoint(label=d.strftime("%d %b"), date=str(d), total_sales=ts, total_bills=tb))
                    d += timedelta(days=1)
            elif span <= 92:
                bkt = "weekly"
                ws = s
                while ws <= e:
                    we = min(ws + timedelta(days=6), e)
                    ts, tb = range_totals(ws, we)
                    rp.append(SalesTrendPoint(label=ws.strftime("%d %b"), date=str(ws), total_sales=ts, total_bills=tb))
                    ws = we + timedelta(days=1)
            else:
                bkt = "monthly"
                y, mm = s.year, s.month
                while date(y, mm, 1) <= e:
                    m_start = date(y, mm, 1)
                    nxt = date(y + 1, 1, 1) if mm == 12 else date(y, mm + 1, 1)
                    m_end = min(nxt - timedelta(days=1), e)
                    ts, tb = range_totals(max(m_start, s), m_end)
                    rp.append(SalesTrendPoint(label=month_abbr[mm], date=str(m_start), total_sales=ts, total_bills=tb))
                    y, mm = (y + 1, 1) if mm == 12 else (y, mm + 1)
        return SalesTrendResponse(period=period, bucket=bkt, points=rp)

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



def _growth_pct(current: float, previous: float) -> float:
    """Fair growth %. If there is no previous baseline, report +100% when there
    IS current revenue (brand-new activity) and 0% when both are zero."""
    if previous > 0:
        return round((current - previous) / previous * 100, 1)
    return 100.0 if current > 0 else 0.0


async def get_sales_comparison(
    db: Session,
    court_id: Optional[int] = None,
    outlet_id: Optional[int] = None,
    outlet_ids: Optional[list[int]] = None,
    granularity: str = "week",
) -> SalesCompareResponse:
    """This-period-so-far vs the SAME number of days in the previous period.

    The totals + growth compare LIKE FOR LIKE (partial vs partial) so early in a
    period you don't see a misleading crash. ``points`` is an aligned bucket
    series (this vs last) for a side-by-side chart — the previous period is shown
    in full there for visual context, but the headline growth uses the same span.

    granularity:
      * "week"  → daily buckets Mon..Sun; this-week-to-date vs last-week same days
      * "month" → weekly (day-of-month) buckets; this-month-to-date vs last-month same days
      * "year"  → monthly buckets Jan..Dec; this-year-to-date vs last-year same days
    """
    today = now_ist().date()
    yday = today - timedelta(days=1)
    ids = list(outlet_ids) if outlet_ids is not None else _resolve_outlet_ids(db, court_id, outlet_id)

    def rt(start: date, end: date) -> tuple[float, int]:
        if not ids or start > end:
            return 0.0, 0
        rows = db.query(DailySaleCache).filter(
            DailySaleCache.outlet_id.in_(ids),
            DailySaleCache.sale_date >= start,
            DailySaleCache.sale_date <= end,
        ).all()
        return round(sum(r.total_sales for r in rows), 2), sum(r.bill_count for r in rows)

    def _first_of_prev_month(first_of_this: date) -> date:
        if first_of_this.month == 1:
            return first_of_this.replace(year=first_of_this.year - 1, month=12)
        return first_of_this.replace(month=first_of_this.month - 1)

    def _days_in_month(first_of_month: date) -> int:
        nxt = (first_of_month.replace(year=first_of_month.year + 1, month=1)
               if first_of_month.month == 12
               else first_of_month.replace(month=first_of_month.month + 1))
        return (nxt - timedelta(days=1)).day

    g = (granularity or "week").lower().replace("this_", "").strip()
    points: list[ComparePoint] = []

    if g == "month":
        bucket = "weekly"
        cur_start = today.replace(day=1)
        cur_end = yday
        prev_start = _first_of_prev_month(cur_start)
        prev_days = _days_in_month(prev_start)
        cur_days = _days_in_month(cur_start)
        n = max((cur_end - cur_start).days + 1, 0)
        span = min(n, prev_days)
        prev_end = prev_start + timedelta(days=span - 1) if span > 0 else prev_start - timedelta(days=1)
        cur_total, cur_bills = rt(cur_start, cur_end) if n > 0 else (0.0, 0)
        prev_total, prev_bills = rt(prev_start, prev_end) if span > 0 else (0.0, 0)

        def dom_total(first_of_month: date, d1: int, d2: int, days_in_month: int, upto_day=None):
            hi = min(d2, days_in_month)
            if upto_day is not None:
                hi = min(hi, upto_day)
            if d1 > hi:
                return 0.0, 0
            return rt(first_of_month.replace(day=d1), first_of_month.replace(day=hi))

        for (d1, d2) in [(1, 7), (8, 14), (15, 21), (22, 28), (29, 31)]:
            cs, cb = dom_total(cur_start, d1, d2, cur_days, upto_day=cur_end.day if cur_end >= cur_start else 0)
            ps, pb = dom_total(prev_start, d1, d2, prev_days)
            points.append(ComparePoint(label=f"{d1}-{min(d2, max(cur_days, prev_days))}",
                                       current_sales=cs, current_bills=cb,
                                       previous_sales=ps, previous_bills=pb))
        cur_label = (f"This month ({cur_start:%d %b}–{cur_end:%d %b})"
                     if n > 0 else f"This month ({cur_start:%b})")
        prev_label = (f"Last month ({prev_start:%d %b}–{prev_end:%d %b})"
                      if span > 0 else f"Last month ({prev_start:%b})")

    elif g == "year":
        bucket = "monthly"
        cur_start = today.replace(month=1, day=1)
        cur_end = yday
        prev_start = cur_start.replace(year=cur_start.year - 1)
        n = max((cur_end - cur_start).days + 1, 0)
        prev_end = prev_start + timedelta(days=n - 1) if n > 0 else prev_start - timedelta(days=1)
        cur_total, cur_bills = rt(cur_start, cur_end) if n > 0 else (0.0, 0)
        prev_total, prev_bills = rt(prev_start, prev_end) if n > 0 else (0.0, 0)
        for m in range(1, 13):
            c_s = date(today.year, m, 1)
            c_nxt = date(today.year + 1, 1, 1) if m == 12 else date(today.year, m + 1, 1)
            cs, cb = rt(c_s, min(c_nxt - timedelta(days=1), yday)) if c_s <= yday else (0.0, 0)
            p_s = date(today.year - 1, m, 1)
            p_nxt = date(today.year, 1, 1) if m == 12 else date(today.year - 1, m + 1, 1)
            ps, pb = rt(p_s, p_nxt - timedelta(days=1))
            points.append(ComparePoint(label=month_abbr[m], current_sales=cs, current_bills=cb,
                                       previous_sales=ps, previous_bills=pb))
        cur_label = f"{today.year} (Jan–{cur_end:%d %b})" if n > 0 else f"{today.year}"
        prev_label = f"{today.year - 1} (Jan–{prev_end:%d %b})" if n > 0 else f"{today.year - 1}"

    else:  # "week" (default)
        bucket = "daily"
        cur_start = today - timedelta(days=today.weekday())  # Monday of this week
        cur_end = yday
        prev_start = cur_start - timedelta(days=7)
        n = max((cur_end - cur_start).days + 1, 0)
        prev_end = prev_start + timedelta(days=n - 1) if n > 0 else prev_start - timedelta(days=1)
        cur_total, cur_bills = rt(cur_start, cur_end) if n > 0 else (0.0, 0)
        prev_total, prev_bills = rt(prev_start, prev_end) if n > 0 else (0.0, 0)
        for i in range(7):
            cd = cur_start + timedelta(days=i)
            pd = prev_start + timedelta(days=i)
            cs, cb = rt(cd, cd) if cd <= yday else (0.0, 0)
            ps, pb = rt(pd, pd)  # last week is fully complete
            points.append(ComparePoint(label=cd.strftime("%a"), current_sales=cs, current_bills=cb,
                                       previous_sales=ps, previous_bills=pb))
        cur_label = (f"This week ({cur_start:%d %b}–{cur_end:%d %b})"
                     if n > 0 else f"This week ({cur_start:%d %b})")
        prev_label = (f"Last week ({prev_start:%d %b}–{prev_end:%d %b})"
                      if n > 0 else f"Last week ({prev_start:%d %b})")
        g = "week"

    return SalesCompareResponse(
        granularity=g,
        bucket=bucket,
        current_label=cur_label,
        previous_label=prev_label,
        current_total=round(cur_total, 2),
        previous_total=round(prev_total, 2),
        current_bills=cur_bills,
        previous_bills=prev_bills,
        growth_pct=_growth_pct(cur_total, prev_total),
        points=points,
    )
