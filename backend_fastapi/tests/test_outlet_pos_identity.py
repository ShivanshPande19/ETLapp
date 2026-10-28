"""An outlet's identity is (which POS, which id, under which account) — NOT
`rest_id` alone.

`outlets.rest_id` used to carry a plain `UNIQUE`, which quietly encodes a
Petpooja-only assumption: a Petpooja `restID` really is unique across all of
Petpooja. Every other adapter reads the column differently, and for two of them
it is only unique WITHIN an account:

  * royal_pos → `restaurant_id`, numbered PER BRAND. Two brands both
    legitimately have restaurant_id "1", told apart by `pp_app_key` (the Royal
    brand_id).
  * rista     → a branch code like "GNO", unique per Rista account.

The live case that exposed it: onboarding "The Chatpata Affair (Sec-1)"
(restaurant_id 1 / brand thech722) was rejected as a duplicate of "The Chatpata
Affair BU" (restaurant_id 1 / brand thech899) — two different outlets, in
different courts, on different Royal brands.

These tests pin BOTH halves of the fix, because either alone is a hole:
  * the app-level 409 in `approve_application`, and
  * the DB-level `uq_outlet_pos_identity` index that backs it up,
including that a NULL `pp_app_key` and an empty one count as the SAME account
(Postgres treats NULLs as distinct in a unique index, which would have lost the
guard for the ordinary credential-less Petpooja outlet).
"""
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from conftest import make_user, seed_court
from app.api.deps import get_current_user
from app.database import get_db
from app.api.routes import onboarding as onboarding_routes
from app.models.sale import Outlet
from app.models.onboarding import OutletApplication


def _client(db, user=None):
    app = FastAPI()
    app.include_router(onboarding_routes.router, prefix="/onboarding")

    def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db
    if user is not None:
        app.dependency_overrides[get_current_user] = lambda: user
    return TestClient(app)


def _seed_application(db, court_id, email, outlet_name):
    a = OutletApplication(
        court_id=court_id, outlet_name=outlet_name, owner_name="Owner",
        owner_phone="9999999999", owner_email=email, status="pending",
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def _approve(db, court_id, email, outlet_name, **payload):
    appn = _seed_application(db, court_id, email, outlet_name)
    client = _client(db, make_user("etl_manager"))
    return client.post(
        f"/onboarding/applications/{appn.id}/approve", json=payload
    )


# ── The live bug ─────────────────────────────────────────────────────────────

def test_same_royal_restaurant_id_on_a_different_brand_is_onboarded(db):
    """The Chatpata Affair (Sec-1) alongside The Chatpata Affair BU."""
    bu = seed_court(db, name="Bennett University")
    sec1 = seed_court(db, name="Sec-1 Noida")

    first = _approve(
        db, bu.id, "bu@test.com", "The Chatpata Affair BU",
        rest_id="1", pos_source="royal_pos", pp_app_key="thech899",
    )
    assert first.status_code == 200, first.text

    second = _approve(
        db, sec1.id, "sec1@test.com", "The Chatpata Affair (Sec-1)",
        rest_id="1", pos_source="royal_pos", pp_app_key="thech722",
    )
    assert second.status_code == 200, second.text

    # Both exist, same restaurant_id, told apart by brand.
    rows = db.query(Outlet).filter(Outlet.rest_id == "1").all()
    assert len(rows) == 2
    assert {r.pp_app_key for r in rows} == {"thech899", "thech722"}
    assert {r.court_id for r in rows} == {bu.id, sec1.id}


# ── The guard that must survive ──────────────────────────────────────────────

def test_same_pos_same_id_same_account_is_still_rejected(db):
    """The real duplicate: identical adapter, id AND credentials."""
    court = seed_court(db)
    ok = _approve(
        db, court.id, "a@test.com", "Brand A",
        rest_id="1", pos_source="royal_pos", pp_app_key="thech722",
    )
    assert ok.status_code == 200, ok.text

    dupe = _approve(
        db, court.id, "b@test.com", "Brand A again",
        rest_id="1", pos_source="royal_pos", pp_app_key="thech722",
    )
    assert dupe.status_code == 409
    assert db.query(Outlet).filter(Outlet.rest_id == "1").count() == 1


def test_duplicate_petpooja_rest_id_without_credentials_is_rejected(db):
    """The common case must NOT be weakened: a bare restID, no app key.

    This is the NULL-vs-'' trap — if the guard compared the raw column, two
    NULL keys would read as two different accounts and both rows would land.
    """
    court = seed_court(db)
    ok = _approve(
        db, court.id, "a@test.com", "Cafe A",
        rest_id="abc123", pos_source="petpooja_generic",
    )
    assert ok.status_code == 200, ok.text

    dupe = _approve(
        db, court.id, "b@test.com", "Cafe A clone",
        rest_id="abc123", pos_source="petpooja_generic",
    )
    assert dupe.status_code == 409
    assert db.query(Outlet).filter(Outlet.rest_id == "abc123").count() == 1


def test_same_id_on_a_different_pos_is_a_different_outlet(db):
    """A Rista branch code may collide with a Petpooja restID by chance."""
    court = seed_court(db)
    a = _approve(
        db, court.id, "a@test.com", "Petpooja outlet",
        rest_id="GNO", pos_source="petpooja_generic",
    )
    assert a.status_code == 200, a.text
    b = _approve(
        db, court.id, "b@test.com", "Rista outlet",
        rest_id="GNO", pos_source="rista",
    )
    assert b.status_code == 200, b.text
    assert db.query(Outlet).filter(Outlet.rest_id == "GNO").count() == 2


# ── The DB-level backstop ────────────────────────────────────────────────────

def test_db_index_rejects_a_true_duplicate_written_directly(db):
    """Bypassing the route entirely must still hit the unique index."""
    court = seed_court(db)
    db.add(Outlet(court_id=court.id, vendor_name="One", rest_id="1",
                  pos_source="royal_pos", pp_app_key="thech722", is_active=1))
    db.commit()

    db.add(Outlet(court_id=court.id, vendor_name="Two", rest_id="1",
                  pos_source="royal_pos", pp_app_key="thech722", is_active=1))
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()


def test_db_index_treats_null_and_empty_app_key_as_one_account(db):
    """COALESCE(pp_app_key, '') — otherwise NULL != '' and the guard leaks."""
    court = seed_court(db)
    db.add(Outlet(court_id=court.id, vendor_name="One", rest_id="abc123",
                  pos_source="petpooja_generic", pp_app_key=None, is_active=1))
    db.commit()

    db.add(Outlet(court_id=court.id, vendor_name="Two", rest_id="abc123",
                  pos_source="petpooja_generic", pp_app_key="", is_active=1))
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()


def test_db_index_allows_the_same_id_under_two_brands(db):
    """The mirror of the above: different key => different outlet, no error."""
    court = seed_court(db)
    db.add(Outlet(court_id=court.id, vendor_name="BU", rest_id="1",
                  pos_source="royal_pos", pp_app_key="thech899", is_active=1))
    db.add(Outlet(court_id=court.id, vendor_name="Sec-1", rest_id="1",
                  pos_source="royal_pos", pp_app_key="thech722", is_active=1))
    db.commit()  # must not raise
    assert db.query(Outlet).filter(Outlet.rest_id == "1").count() == 2
