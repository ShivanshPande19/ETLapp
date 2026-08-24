"""Feedback read scoping across roles, incl. L8 (my-court for ETL managers)."""
from conftest import (
    make_user,
    seed_court,
    seed_outlet,
    seed_feedback,
)


def _seed_two_courts(db):
    c1 = seed_court(db, "Court 1")
    c2 = seed_court(db, "Court 2")
    o1 = seed_outlet(db, c1.id, "Ovenly", "r1")
    o2 = seed_outlet(db, c2.id, "Burrito", "r2")
    # court-rated feedback in each court
    seed_feedback(db, c1.id, court_rating=5)
    seed_feedback(db, c2.id, court_rating=2)
    # outlet-only reviews
    seed_feedback(db, c1.id, outlet_id=o1.id, outlet_rating=4)
    seed_feedback(db, c2.id, outlet_id=o2.id, outlet_rating=3)
    return c1, c2, o1, o2


def test_my_court_works_for_etl_manager_across_all_courts(client_factory, db):
    # L8: previously an ETL manager (court_id always None) got 403 here.
    c1, c2, _, _ = _seed_two_courts(db)
    client = client_factory(make_user("etl_manager"))
    resp = client.get("/feedback/my-court")
    assert resp.status_code == 200
    data = resp.json()
    # only court-rated feedback is returned (2 across both courts)
    assert len(data) == 2


def test_my_court_manager_can_focus_single_court(client_factory, db):
    c1, c2, _, _ = _seed_two_courts(db)
    client = client_factory(make_user("etl_manager"))
    resp = client.get(f"/feedback/my-court?court_id={c1.id}")
    assert resp.status_code == 200
    assert len(resp.json()) == 1


def test_my_court_locks_etl_staff_to_their_court(client_factory, db):
    c1, c2, _, _ = _seed_two_courts(db)
    staff = make_user("etl_staff", uid=10, court_id=c1.id, user_type="staff")
    client = client_factory(staff)
    resp = client.get("/feedback/my-court")
    assert resp.status_code == 200
    # only court 1's court-rated feedback
    assert len(resp.json()) == 1


def test_my_court_403_for_etl_staff_without_court(client_factory, db):
    _seed_two_courts(db)
    staff = make_user("etl_staff", uid=11, court_id=None, user_type="staff")
    client = client_factory(staff)
    resp = client.get("/feedback/my-court")
    assert resp.status_code == 403


def test_court_feedbacks_requires_etl_manager(client_factory, db):
    c1, _, _, _ = _seed_two_courts(db)
    # outlet user must be rejected
    client = client_factory(make_user("outlet_manager", outlet_ids=[1]))
    resp = client.get(f"/feedback/court/{c1.id}")
    assert resp.status_code == 403
    # etl manager allowed
    client2 = client_factory(make_user("etl_manager"))
    resp2 = client2.get(f"/feedback/court/{c1.id}")
    assert resp2.status_code == 200
