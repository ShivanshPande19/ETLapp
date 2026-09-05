"""Outlet documents: view is free (anyone who can access the outlet); every
CHANGE re-authenticates the acting account's own password; scope is enforced
(ETL manager → any outlet, outlet user → only their own); a change writes a
notice to the OTHER side."""
from conftest import (
    make_user,
    seed_court,
    seed_outlet,
    seed_manager,
    seed_membership,
)
from app.core.security import hash_password
from app.models.manager import Manager
from app.models.notice import Notice


_PDF = ("gst.pdf", b"%PDF-1.4 fake gst document", "application/pdf")


def _owner(db, outlet_id, password="secret123", email="docowner@test.com"):
    m = seed_manager(db, role="outlet_manager", email=email, outlet_id=outlet_id)
    m.hashed_password = hash_password(password)
    db.commit()
    db.refresh(m)
    seed_membership(db, m.id, outlet_id, "owner")
    return m


def test_view_documents_is_free_and_starts_empty(client_factory, db):
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "V", "r")
    owner = _owner(db, outlet.id)
    client = client_factory(
        make_user("outlet_manager", uid=owner.id, outlet_ids=[outlet.id])
    )
    resp = client.get(f"/outlets/{outlet.id}/documents")
    assert resp.status_code == 200
    docs = {d["doc_type"]: d["url"] for d in resp.json()["documents"]}
    assert set(docs) == {"gst", "fssai", "term_sheet", "agreement"}
    assert all(v is None for v in docs.values())


def test_upload_requires_correct_password_then_persists(client_factory, db):
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "V", "r")
    owner = _owner(db, outlet.id, password="rightpass")
    client = client_factory(
        make_user("outlet_manager", uid=owner.id, name="Owner O",
                  outlet_ids=[outlet.id])
    )

    # Wrong password → 403, nothing stored.
    bad = client.post(
        f"/outlets/{outlet.id}/documents/gst",
        files={"file": _PDF},
        data={"password": "WRONG"},
    )
    assert bad.status_code == 403

    # Correct password → stored + a notice fired (owner edit → ETL tier).
    ok = client.post(
        f"/outlets/{outlet.id}/documents/gst",
        files={"file": _PDF},
        data={"password": "rightpass"},
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["url"].startswith("uploads/documents/")

    got = client.get(f"/outlets/{outlet.id}/documents")
    docs = {d["doc_type"]: d["url"] for d in got.json()["documents"]}
    assert docs["gst"] is not None
    assert docs["fssai"] is None

    # Owner edit notifies the ETL tier (audience=manager, outlet_id NULL).
    etl_notice = (
        db.query(Notice)
        .filter(Notice.type == "document_updated",
                Notice.outlet_id.is_(None))
        .first()
    )
    assert etl_notice is not None


def test_unknown_doc_type_rejected(client_factory, db):
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "V", "r")
    owner = _owner(db, outlet.id)
    client = client_factory(
        make_user("outlet_manager", uid=owner.id, outlet_ids=[outlet.id])
    )
    resp = client.post(
        f"/outlets/{outlet.id}/documents/passport",
        files={"file": _PDF},
        data={"password": "secret123"},
    )
    assert resp.status_code == 400


def test_outlet_user_cannot_touch_another_outlet(client_factory, db):
    court = seed_court(db)
    mine = seed_outlet(db, court.id, "Mine", "r1")
    other = seed_outlet(db, court.id, "Other", "r2")
    owner = _owner(db, mine.id)
    # Caller owns `mine` only.
    client = client_factory(
        make_user("outlet_manager", uid=owner.id, outlet_ids=[mine.id])
    )
    # View of another outlet → 403.
    assert client.get(f"/outlets/{other.id}/documents").status_code == 403
    # Upload to another outlet → 403 (scope checked before password).
    resp = client.post(
        f"/outlets/{other.id}/documents/gst",
        files={"file": _PDF},
        data={"password": "secret123"},
    )
    assert resp.status_code == 403


def test_etl_manager_can_manage_any_outlet_and_notifies_outlet(client_factory, db):
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, "V", "r")
    # An ETL manager with a real password row (id matches the CurrentUser).
    etl = seed_manager(db, role="etl_manager", email="etl@test.com")
    etl.hashed_password = hash_password("etlpass")
    db.commit()
    db.refresh(etl)

    client = client_factory(make_user("etl_manager", uid=etl.id, name="ETL Admin"))

    # ETL can view any outlet with no membership.
    assert client.get(f"/outlets/{outlet.id}/documents").status_code == 200

    ok = client.post(
        f"/outlets/{outlet.id}/documents/fssai",
        files={"file": ("f.pdf", b"%PDF-1.4 fssai", "application/pdf")},
        data={"password": "etlpass"},
    )
    assert ok.status_code == 200, ok.text

    # ETL edit notifies the OUTLET's manager (audience=manager, outlet_id set).
    outlet_notice = (
        db.query(Notice)
        .filter(Notice.type == "document_updated",
                Notice.outlet_id == outlet.id)
        .first()
    )
    assert outlet_notice is not None

    # Remove it (with password) → cleared.
    rm = client.request(
        "DELETE",
        f"/outlets/{outlet.id}/documents/fssai",
        json={"password": "etlpass"},
    )
    assert rm.status_code == 200, rm.text
    got = client.get(f"/outlets/{outlet.id}/documents")
    docs = {d["doc_type"]: d["url"] for d in got.json()["documents"]}
    assert docs["fssai"] is None
