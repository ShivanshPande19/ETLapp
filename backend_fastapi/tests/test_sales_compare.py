"""get_sales_comparison must compare LIKE FOR LIKE — this-period-so-far vs the
SAME number of days in the previous period — so the headline growth is fair,
while the bucket series stays aligned (this vs last) for a side-by-side chart."""
import asyncio
import datetime as dt

from conftest import seed_court, seed_outlet
from app.services import sales_service as ss
from app.models.sale import DailySaleCache


def _seed_cache(db, outlet_id, day: dt.date, sales: float, bills: int = 1):
    db.add(DailySaleCache(outlet_id=outlet_id, sale_date=day,
                          total_sales=sales, bill_count=bills, avg_bill=sales / max(bills, 1)))
    db.commit()


def _run(db, outlet_id, granularity):
    return asyncio.run(ss.get_sales_comparison(db, outlet_id=outlet_id, granularity=granularity))


def test_week_same_span_growth_and_aligned_points(db, monkeypatch):
    # Fix "today" = Wed 2026-09-02 → this week Mon=Aug31, Tue=Sep1 completed;
    # today (Wed Sep2) not yet counted. Same-span last week = Aug24(Mon), Aug25(Tue).
    monkeypatch.setattr(ss, "now_ist", lambda: dt.datetime(2026, 9, 2, 12, 0, 0))
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "V", "r")
    oid = outlet.id

    # This week (so far): Mon 1000, Tue 2000
    _seed_cache(db, oid, dt.date(2026, 8, 31), 1000)
    _seed_cache(db, oid, dt.date(2026, 9, 1), 2000)
    # This week Wed (today) — must NOT count (sales end at yesterday)
    _seed_cache(db, oid, dt.date(2026, 9, 2), 9999)
    # Last week (full): Mon 500, Tue 700, Wed 999, ... rest
    _seed_cache(db, oid, dt.date(2026, 8, 24), 500)
    _seed_cache(db, oid, dt.date(2026, 8, 25), 700)
    _seed_cache(db, oid, dt.date(2026, 8, 26), 999)

    r = _run(db, oid, "week")

    # Same-span totals: this week Mon+Tue = 3000 vs last week Mon+Tue = 1200
    assert r.current_total == 3000.0
    assert r.previous_total == 1200.0
    assert r.growth_pct == 150.0  # (3000-1200)/1200*100
    assert r.granularity == "week"
    assert len(r.points) == 7
    # Aligned by weekday: Mon current 1000 / prev 500; Tue 2000 / 700
    assert r.points[0].label == "Mon"
    assert r.points[0].current_sales == 1000.0
    assert r.points[0].previous_sales == 500.0
    assert r.points[1].current_sales == 2000.0
    assert r.points[1].previous_sales == 700.0
    # Wed: current not counted yet (0), previous full week shows 999
    assert r.points[2].current_sales == 0.0
    assert r.points[2].previous_sales == 999.0


def test_week_no_previous_baseline_reports_100(db, monkeypatch):
    monkeypatch.setattr(ss, "now_ist", lambda: dt.datetime(2026, 9, 2, 12, 0, 0))
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "V2", "r2")
    _seed_cache(db, outlet.id, dt.date(2026, 8, 31), 1500)  # only this week has data
    r = _run(db, outlet.id, "week")
    assert r.current_total == 1500.0
    assert r.previous_total == 0.0
    assert r.growth_pct == 100.0


def test_year_monthly_buckets_same_span(db, monkeypatch):
    # Fix today = 2026-02-10 → this year Jan1..Feb9 vs last year Jan1..Feb9.
    monkeypatch.setattr(ss, "now_ist", lambda: dt.datetime(2026, 2, 10, 12, 0, 0))
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "V3", "r3")
    oid = outlet.id
    _seed_cache(db, oid, dt.date(2026, 1, 15), 4000)   # this year Jan
    _seed_cache(db, oid, dt.date(2025, 1, 15), 2000)   # last year Jan (same span)
    _seed_cache(db, oid, dt.date(2025, 6, 15), 8000)   # last year Jun — OUT of same span

    r = _run(db, oid, "year")
    assert r.granularity == "year"
    assert r.bucket == "monthly"
    assert len(r.points) == 12
    assert r.current_total == 4000.0
    assert r.previous_total == 2000.0   # Jun 8000 excluded from same-span total
    assert r.growth_pct == 100.0
    # Jan bucket aligned
    assert r.points[0].label == "Jan"
    assert r.points[0].current_sales == 4000.0
    assert r.points[0].previous_sales == 2000.0
    # Jun bucket: previous shows full last-year month (8000) for chart context
    assert r.points[5].previous_sales == 8000.0
