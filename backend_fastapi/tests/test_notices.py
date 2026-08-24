"""Notices: scoping, unread-first ordering, unread_count, date filter, pagination."""
import datetime as dt

from conftest import make_user, seed_notice

# Fixed UTC instants that fall on known IST calendar days.
# IST = UTC+5:30, so 2026-08-24 12:00 UTC is on IST day 2026-08-24 (17:30 IST).
AUG24 = dt.datetime(2026, 8, 24, 12, 0, 0)
AUG23 = dt.datetime(2026, 8, 23, 12, 0, 0)
# 2026-08-23 20:00 UTC = 2026-08-24 01:30 IST -> belongs to IST day 24.
AUG24_EARLY = dt.datetime(2026, 8, 23, 20, 0, 0)


def _seed_mgr_notices(db):
    seed_notice(db, title="today-unread", is_read=False, created_at=AUG24)
    seed_notice(db, title="today-early", is_read=False, created_at=AUG24_EARLY)
    seed_notice(db, title="today-read", is_read=True, created_at=AUG24)
    seed_notice(db, title="yesterday", is_read=False, created_at=AUG23)


def test_unread_first_ordering_and_total_count(client_factory, db):
    _seed_mgr_notices(db)
    client = client_factory(make_user("etl_manager"))
    r = client.get("/notices/")
    assert r.status_code == 200
    data = r.json()
    # total unread across ALL dates = 3 (today-unread, today-early, yesterday)
    assert data["unread_count"] == 3
    # unread first
    assert data["notices"][0]["is_read"] is False
    assert data["notices"][-1]["is_read"] is True


def test_date_filter_returns_only_that_ist_day(client_factory, db):
    _seed_mgr_notices(db)
    client = client_factory(make_user("etl_manager"))
    r = client.get("/notices/?date=2026-08-24")
    data = r.json()
    titles = {n["title"] for n in data["notices"]}
    # the 20:00 UTC one rolls into IST day 24; yesterday is excluded
    assert titles == {"today-unread", "today-early", "today-read"}
    # unread_count still reflects the GLOBAL unread (3), not just this day
    assert data["unread_count"] == 3


def test_pagination_has_more(client_factory, db):
    for i in range(5):
        seed_notice(db, title=f"n{i}", is_read=False, created_at=AUG24)
    client = client_factory(make_user("etl_manager"))
    r1 = client.get("/notices/?limit=2&offset=0")
    d1 = r1.json()
    assert len(d1["notices"]) == 2
    assert d1["has_more"] is True
    r2 = client.get("/notices/?limit=2&offset=4")
    d2 = r2.json()
    assert len(d2["notices"]) == 1
    assert d2["has_more"] is False


def test_bad_date_is_rejected(client_factory, db):
    client = client_factory(make_user("etl_manager"))
    r = client.get("/notices/?date=not-a-date")
    assert r.status_code == 400


def test_scoping_manager_vs_staff(client_factory, db):
    # a manager notice and a staff notice for staff id 7
    seed_notice(db, audience="manager", title="mgr", created_at=AUG24)
    seed_notice(db, audience="staff", recipient_staff_id=7, title="stf",
                created_at=AUG24)

    mgr = client_factory(make_user("etl_manager"))
    mtitles = {n["title"] for n in mgr.get("/notices/").json()["notices"]}
    assert mtitles == {"mgr"}

    staff = client_factory(make_user("etl_staff", uid=7, court_id=1,
                                     user_type="staff"))
    stitles = {n["title"] for n in staff.get("/notices/").json()["notices"]}
    assert stitles == {"stf"}


def test_mark_read_and_read_all(client_factory, db):
    n = seed_notice(db, title="a", is_read=False, created_at=AUG24)
    seed_notice(db, title="b", is_read=False, created_at=AUG24)
    client = client_factory(make_user("etl_manager"))

    assert client.patch(f"/notices/{n.id}/read").status_code == 200
    assert client.get("/notices/").json()["unread_count"] == 1

    client.patch("/notices/read-all")
    assert client.get("/notices/").json()["unread_count"] == 0
