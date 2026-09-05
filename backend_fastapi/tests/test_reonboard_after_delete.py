"""Re-onboarding an owner AFTER their outlet was deleted must produce a FRESH,
usable login — reactivate the deactivated leftover Manager and issue a
set-password link — NOT silently link the new outlet to the dead account as a
phantom "second outlet" (the delete → re-apply bug). A genuinely ACTIVE owner
must still get the multi-outlet link-only path. And a duplicate pending
application (double-submit) must not be recreated."""
from fastapi import FastAPI
from fastapi.testclient import TestClient

from conftest import make_user, seed_court, seed_outlet, seed_manager, seed_membership
from app.api.deps import get_current_user
from app.database import get_db
from app.api.routes import onboarding as onboarding_routes
from app.models.manager import Manager
from app.models.sale import Outlet
from app.models.onboarding import OutletApplication
from app.models.outlet_membership import OutletMembership


def _client(db, user=None):
    app = FastAPI()
    app.include_router(onboarding_routes.router, prefix="/onboarding")

    def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db
    if user is not None:
        app.dependency_overrides[get_current_user] = lambda: user
    return TestClient(app)


def _seed_application(db, court_id, email, outlet_name="Cafe X", status="pending"):
    a = OutletApplication(
        court_id=court_id, outlet_name=outlet_name, owner_name="Owner",
        owner_phone="9999999999", owner_email=email, status=status,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def test_reapprove_after_delete_reactivates_owner_with_set_password(db):
    court = seed_court(db)
    # Leftover from a previously-deleted outlet: deactivated owner, NO membership
    # (delete_outlet strips the membership and deactivates the row).
    owner = Manager(name="Old Name", email="owner@test.com", hashed_password="x",
                    role="outlet_manager", outlet_id=None, is_active=False)
    db.add(owner)
    db.commit()
    db.refresh(owner)
    appn = _seed_application(db, court.id, "owner@test.com", outlet_name="Cafe X")
    aid, mid = appn.id, owner.id

    client = _client(db, make_user("etl_manager"))
    resp = client.post(
        f"/onboarding/applications/{aid}/approve",
        json={"rest_id": "rest-new", "pos_source": "petpooja_generic"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    # Fresh onboarding => a set-password link is issued (NOT the link-only path).
    assert body["set_password_link"]
    assert body["manager_email"] == "owner@test.com"

    db.expire_all()
    m = db.query(Manager).filter(Manager.id == mid).first()
    assert m.is_active is True          # reactivated
    assert m.name == "Owner"            # details refreshed from the application
    out = db.query(Outlet).filter(Outlet.rest_id == "rest-new").first()
    assert out is not None
    assert db.query(OutletMembership).filter(
        OutletMembership.manager_id == mid,
        OutletMembership.outlet_id == out.id,
    ).count() == 1


def test_reapprove_active_owner_links_as_additional_outlet(db):
    court = seed_court(db)
    o1 = seed_outlet(db, court.id, "V1", "r1")
    owner = seed_manager(db, role="outlet_manager", email="active@test.com",
                         outlet_id=o1.id)
    seed_membership(db, owner.id, o1.id, "owner")  # ACTIVE, owns 1 outlet
    appn = _seed_application(db, court.id, "active@test.com", outlet_name="V2")
    aid, mid = appn.id, owner.id

    client = _client(db, make_user("etl_manager"))
    resp = client.post(
        f"/onboarding/applications/{aid}/approve",
        json={"rest_id": "r2", "pos_source": "petpooja_generic"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    # Genuine active owner => outlet linked, NO new password link.
    assert body["set_password_link"] is None
    db.expire_all()
    assert db.query(OutletMembership).filter(
        OutletMembership.manager_id == mid,
    ).count() == 2


def test_duplicate_pending_application_not_recreated(db):
    court = seed_court(db)
    _seed_application(db, court.id, "dup@test.com", outlet_name="Dup Cafe")
    client = _client(db)  # submit is a public endpoint (no auth)
    resp = client.post(
        "/onboarding/applications",
        data={
            "court_id": str(court.id),
            "outlet_name": "Dup Cafe",
            "owner_name": "O",
            "owner_phone": "9999999999",
            "owner_email": "dup@test.com",
        },
    )
    assert resp.status_code == 200, resp.text
    # Still exactly ONE pending row for this owner+outlet (no duplicate created).
    assert db.query(OutletApplication).filter(
        OutletApplication.owner_email == "dup@test.com",
        OutletApplication.status == "pending",
    ).count() == 1
