"""A closed outlet must keep reporting the months it traded, and disappear
from everything that only concerns a TRADING outlet.

`Outlet.is_active` is a hard on/off, and switching a closed outlet off takes
its past sales with it: every `daily_sale_cache` read is scoped by an outlet
list already narrowed to `is_active == 1`, so the cache rows are simply never
reached. The Chatpata Affair BU closed on 3 Oct after ~Rs 2.35L across 47
trading days — that history has to survive.

So a closed outlet keeps `is_active = 1` and carries `closed_on` instead.

The property that matters most here is the NEGATIVE one, pinned first below:
`closed_on IS NULL` must behave EXACTLY as before the column existed. Every
outlet in production is NULL except the one being retired, so a regression in
that path would be a silent, app-wide reporting bug.
"""
import asyncio
import datetime as dt

from conftest import (
    make_user, seed_court, seed_outlet, seed_manager, seed_membership,
)
from app.services import sales_service as ss
from app.models.sale import DailySaleCache, Outlet
from app.core.query_utils import outlet_is_trading, outlet_traded_on_or_after


def _seed_cache(db, outlet_id, day: dt.date, sales: float, bills: int = 1):
    db.add(DailySaleCache(outlet_id=outlet_id, sale_date=day, total_sales=sales,
                          bill_count=bills, avg_bill=sales / max(bills, 1)))
    db.commit()


def _close(db, outlet, on: dt.date):
    outlet.closed_on = on
    db.commit()


def _summary(db, **kw):
    return asyncio.run(ss.get_sales_summary(db, **kw))


# ── The guarantee: an OPEN outlet is untouched ───────────────────────────────

def test_open_outlet_is_unaffected_by_the_new_column(db, monkeypatch):
    """closed_on IS NULL => identical behaviour to before the column existed."""
    monkeypatch.setattr(ss, "now_ist", lambda: dt.datetime(2026, 10, 28, 12, 0, 0))
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "Open Co", "r-open")
    assert outlet.closed_on is None          # default must be NULL, not a date
    _seed_cache(db, outlet.id, dt.date(2026, 10, 27), 5000, 50)

    r = _summary(db, outlet_id=outlet.id, period="yesterday")
    assert r.total_sales == 5000
    assert [v.vendor_name for v in r.vendors] == ["Open Co"]


# ── History must survive ─────────────────────────────────────────────────────

def test_closed_outlet_still_reports_the_days_it_traded(db, monkeypatch):
    """The whole point: a window reaching back into its trading days works."""
    monkeypatch.setattr(ss, "now_ist", lambda: dt.datetime(2026, 10, 28, 12, 0, 0))
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "Chatpata BU", "r-bu")
    _seed_cache(db, outlet.id, dt.date(2026, 9, 29), 6855, 72)
    _seed_cache(db, outlet.id, dt.date(2026, 10, 3), 340, 2)
    _close(db, outlet, dt.date(2026, 10, 3))

    r = _summary(db, outlet_id=outlet.id,
                 date_from="2026-09-01", date_to="2026-10-03")
    assert r.total_sales == 6855 + 340
    assert r.total_bills == 74
    assert [v.vendor_name for v in r.vendors] == ["Chatpata BU"]


def test_closed_outlet_history_is_identical_to_before_it_closed(db, monkeypatch):
    """Closing must not change a single historical figure."""
    monkeypatch.setattr(ss, "now_ist", lambda: dt.datetime(2026, 10, 28, 12, 0, 0))
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "Chatpata BU", "r-bu")
    _seed_cache(db, outlet.id, dt.date(2026, 9, 29), 6855, 72)
    window = {"date_from": "2026-09-01", "date_to": "2026-09-30"}

    before = _summary(db, outlet_id=outlet.id, **window)
    _close(db, outlet, dt.date(2026, 10, 3))
    after = _summary(db, outlet_id=outlet.id, **window)

    assert before.total_sales == after.total_sales == 6855
    assert before.total_bills == after.total_bills == 72


# ── Gone from the present ────────────────────────────────────────────────────

def test_closed_outlet_is_absent_from_a_window_after_it_closed(db, monkeypatch):
    """No dead Rs 0 row in today's list."""
    monkeypatch.setattr(ss, "now_ist", lambda: dt.datetime(2026, 10, 28, 12, 0, 0))
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "Chatpata BU", "r-bu")
    _seed_cache(db, outlet.id, dt.date(2026, 10, 3), 340, 2)
    _close(db, outlet, dt.date(2026, 10, 3))

    r = _summary(db, court_id=court.id, period="yesterday")   # 27 Oct
    assert r.vendors == []
    assert r.total_sales == 0


def test_a_courts_list_keeps_open_outlets_and_drops_the_closed_one(db, monkeypatch):
    """The mixed case — the one that matters in a real court."""
    monkeypatch.setattr(ss, "now_ist", lambda: dt.datetime(2026, 10, 28, 12, 0, 0))
    court = seed_court(db)
    live = seed_outlet(db, court.id, "Still Open", "r-live")
    dead = seed_outlet(db, court.id, "Closed Co", "r-dead")
    _seed_cache(db, live.id, dt.date(2026, 10, 27), 1000, 10)
    _seed_cache(db, dead.id, dt.date(2026, 10, 27), 7777, 70)  # must be ignored
    _close(db, dead, dt.date(2026, 10, 3))

    r = _summary(db, court_id=court.id, period="yesterday")
    assert [v.vendor_name for v in r.vendors] == ["Still Open"]
    assert r.total_sales == 1000


# ── The owner's outlet switcher ──────────────────────────────────────────────

def test_switcher_drops_a_closed_outlet_but_keeps_the_open_one(db, client_factory):
    court = seed_court(db)
    live = seed_outlet(db, court.id, "Still Open", "r-live")
    dead = seed_outlet(db, court.id, "Closed Co", "r-dead")
    owner = seed_manager(db, role="outlet_manager", email="owner@test.com")
    seed_membership(db, owner.id, live.id)
    seed_membership(db, owner.id, dead.id)
    _close(db, dead, dt.date(2026, 10, 3))

    client = client_factory(
        make_user("outlet_manager", uid=owner.id, outlet_ids=[live.id, dead.id])
    )
    resp = client.get("/outlets/mine")
    assert resp.status_code == 200, resp.text
    assert [o["vendor_name"] for o in resp.json()] == ["Still Open"]


# ── The predicates themselves ────────────────────────────────────────────────

def test_predicates_select_the_right_rows(db):
    court = seed_court(db)
    open_o = seed_outlet(db, court.id, "Open", "r1")
    closed_o = seed_outlet(db, court.id, "Closed", "r2")
    _close(db, closed_o, dt.date(2026, 10, 3))

    trading = {o.id for o in db.query(Outlet).filter(outlet_is_trading()).all()}
    assert trading == {open_o.id}

    # A window starting before the close date keeps the closed outlet...
    before = {o.id for o in db.query(Outlet).filter(
        outlet_traded_on_or_after(dt.date(2026, 9, 1))).all()}
    assert before == {open_o.id, closed_o.id}

    # ...and one starting after it does not.
    after = {o.id for o in db.query(Outlet).filter(
        outlet_traded_on_or_after(dt.date(2026, 10, 27))).all()}
    assert after == {open_o.id}

    # Boundary: the close date itself still counts as a trading day.
    on_day = {o.id for o in db.query(Outlet).filter(
        outlet_traded_on_or_after(dt.date(2026, 10, 3))).all()}
    assert closed_o.id in on_day


def test_an_inactive_outlet_is_excluded_by_both_predicates(db):
    """closed_on is additive — is_active stays the hard off switch."""
    court = seed_court(db)
    o = seed_outlet(db, court.id, "Disabled", "r3")
    o.is_active = 0
    db.commit()

    assert db.query(Outlet).filter(outlet_is_trading()).count() == 0
    assert db.query(Outlet).filter(
        outlet_traded_on_or_after(dt.date(2020, 1, 1))).count() == 0
