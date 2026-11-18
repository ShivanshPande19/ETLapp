"""The vendor sheet's week/month breakdown: get_vendor_history with an explicit
range returns one zero-filled row per day, never past yesterday, while the
headline 7-day numbers stay exactly what they were."""
import asyncio
import datetime as dt

from conftest import seed_court, seed_outlet
from app.services import sales_service as ss
from app.models.sale import DailySaleCache

TODAY = dt.datetime(2026, 11, 18, 12, 0, 0)


def _seed(db, oid, day, sales, bills=1):
    db.add(DailySaleCache(outlet_id=oid, sale_date=day, total_sales=sales,
                          bill_count=bills, avg_bill=sales / bills))
    db.commit()


def _run(db, oid, **kw):
    return asyncio.run(ss.get_vendor_history(db, outlet_id=oid, **kw))


def test_default_is_last_7_days(db, monkeypatch):
    monkeypatch.setattr(ss, "now_ist", lambda: TODAY)
    o = seed_outlet(db, seed_court(db).id, "V", "r")
    _seed(db, o.id, dt.date(2026, 11, 17), 500, 5)
    r = _run(db, o.id)
    assert [s.date for s in r.daily_history] == [
        str(dt.date(2026, 11, 11) + dt.timedelta(days=i)) for i in range(7)
    ]
    assert r.total_sales == 500.0 and r.week_total == 500.0


def test_month_range_zero_filled_and_capped_at_yesterday(db, monkeypatch):
    monkeypatch.setattr(ss, "now_ist", lambda: TODAY)
    o = seed_outlet(db, seed_court(db).id, "V2", "r2")
    _seed(db, o.id, dt.date(2026, 11, 1), 1000, 10)
    _seed(db, o.id, dt.date(2026, 11, 17), 700, 7)
    _seed(db, o.id, dt.date(2026, 11, 18), 9999, 99)   # today: must not show
    _seed(db, o.id, dt.date(2026, 10, 31), 4444, 4)    # outside the range

    r = _run(db, o.id, date_from=dt.date(2026, 11, 1), date_to=dt.date(2026, 11, 30))

    days = r.daily_history
    assert days[0].date == "2026-11-01" and days[-1].date == "2026-11-17"
    assert len(days) == 17
    assert days[0].total_sales == 1000.0 and days[0].total_bills == 10
    assert days[1].total_sales == 0.0 and days[1].total_bills == 0
    assert days[-1].total_sales == 700.0
    assert sum(d.total_sales for d in days) == 1700.0
    # Headline numbers are unchanged by the range.
    assert r.total_sales == 700.0
    assert r.week_total == 700.0


def test_past_week_range(db, monkeypatch):
    monkeypatch.setattr(ss, "now_ist", lambda: TODAY)
    o = seed_outlet(db, seed_court(db).id, "V3", "r3")
    _seed(db, o.id, dt.date(2026, 9, 3), 300, 3)
    r = _run(db, o.id, date_from=dt.date(2026, 9, 1), date_to=dt.date(2026, 9, 7))
    assert [d.date for d in r.daily_history][0] == "2026-09-01"
    assert len(r.daily_history) == 7
    assert r.daily_history[2].total_sales == 300.0


def test_future_range_is_empty(db, monkeypatch):
    monkeypatch.setattr(ss, "now_ist", lambda: TODAY)
    o = seed_outlet(db, seed_court(db).id, "V4", "r4")
    r = _run(db, o.id, date_from=dt.date(2026, 12, 1), date_to=dt.date(2026, 12, 31))
    assert r.daily_history == []
