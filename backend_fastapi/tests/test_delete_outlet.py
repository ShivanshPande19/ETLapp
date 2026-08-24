"""M6 — delete_outlet must not leave zombie manager accounts."""
from conftest import (
    make_user,
    seed_court,
    seed_outlet,
    seed_manager,
    seed_membership,
)
from app.models.manager import Manager
from app.models.outlet_membership import OutletMembership
from app.models.sale import Outlet


def test_single_outlet_owner_is_deactivated_on_delete(client_factory, db):
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "SoloVendor", "solo")
    owner = seed_manager(db, role="outlet_manager", email="solo@test.com",
                         outlet_id=outlet.id)
    seed_membership(db, owner.id, outlet.id, "owner")
    # Capture ids as plain ints — the route deletes rows out-of-band, so the
    # seeded ORM objects go stale after the request.
    oid, mid = outlet.id, owner.id

    client = client_factory(make_user("etl_manager"))
    resp = client.delete(f"/outlets/{oid}")
    assert resp.status_code == 200

    db.expire_all()
    # outlet + membership gone
    assert db.query(Outlet).filter(Outlet.id == oid).first() is None
    assert db.query(OutletMembership).filter(
        OutletMembership.outlet_id == oid).count() == 0
    # the now-membershipless owner is deactivated (no zombie login), not deleted
    refreshed = db.query(Manager).filter(Manager.id == mid).first()
    assert refreshed is not None
    assert not refreshed.is_active


def test_multi_outlet_owner_survives_delete(client_factory, db):
    court = seed_court(db)
    o1 = seed_outlet(db, court.id, "V1", "v1")
    o2 = seed_outlet(db, court.id, "V2", "v2")
    owner = seed_manager(db, role="outlet_manager", email="multi@test.com",
                         outlet_id=o1.id)
    seed_membership(db, owner.id, o1.id, "owner")
    seed_membership(db, owner.id, o2.id, "owner")
    o1_id, mid = o1.id, owner.id

    client = client_factory(make_user("etl_manager"))
    resp = client.delete(f"/outlets/{o1_id}")
    assert resp.status_code == 200

    db.expire_all()
    # still owns o2 -> must stay active
    refreshed = db.query(Manager).filter(Manager.id == mid).first()
    assert refreshed.is_active
    assert db.query(OutletMembership).filter(
        OutletMembership.manager_id == mid).count() == 1


def test_delete_outlet_requires_etl_manager(client_factory, db):
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "V", "v")
    oid = outlet.id
    client = client_factory(make_user("outlet_manager", outlet_ids=[oid]))
    resp = client.delete(f"/outlets/{oid}")
    assert resp.status_code == 403
