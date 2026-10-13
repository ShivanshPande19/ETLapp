"""PATCH /outlets/{id}/owner — changing an owner's email re-issues the account.

Changing the email changes the owner's LOGIN, so it is treated as handing the
account to a different address: the old password is retired and a set-password
link is emailed to the new one.

The trigger is SUBMITTING the email field — not whether the address differs.
Re-saving the same address re-issues too, which doubles as "resend the welcome
link". So these tests pin both directions:

  • email field submitted (changed OR identical)
        → password retired, link minted, welcome mail sent
  • email field omitted (name/phone only)
        → password and inbox untouched

That second line is the only remaining escape hatch, and the app's edit sheet
pre-fills the email box — so it is the one that stops an owner being locked out
by an edit that never meant to touch their login.

Plus the failure paths, because this endpoint can take an account's only
credential away: nothing may mutate unless every validation passed, and a mail
outage must not leave the manager with no way to reach the owner.
"""
import secrets

import pytest

from app.api.deps import CurrentUser, get_current_user
from app.core.security import hash_password, verify_password
from app.models.manager import Manager
from app.models.outlet_membership import MEMBERSHIP_MANAGER, MEMBERSHIP_OWNER
from app.models.staff import Staff

from conftest import make_user, seed_court, seed_manager, seed_membership, seed_outlet

OWNER_PW = "ownerPass123"


@pytest.fixture()
def sent(monkeypatch):
    """Capture outgoing mail instead of sending it."""
    box = []

    async def _fake_send_email(*, to, subject, html):
        box.append({"to": to, "subject": subject, "html": html})
        return True

    monkeypatch.setattr("app.api.routes.outlets.send_email", _fake_send_email)
    return box


@pytest.fixture()
def mail_down(monkeypatch):
    """Simulate the mail provider being unreachable."""

    async def _boom(*, to, subject, html):
        raise RuntimeError("resend unreachable")

    monkeypatch.setattr("app.api.routes.outlets.send_email", _boom)


def _etl(client_factory):
    return client_factory(make_user("etl_manager", uid=99, email="etl@test.com"))


def _seed_owned_outlet(db, owner_email="owner@old.com"):
    court = seed_court(db)
    outlet = seed_outlet(db, court.id, vendor_name="Coffee Vault")
    owner = seed_manager(db, role="outlet_manager", email=owner_email, outlet_id=outlet.id)
    owner.hashed_password = hash_password(OWNER_PW)
    db.commit()
    seed_membership(db, owner.id, outlet.id, MEMBERSHIP_OWNER)
    return outlet, owner


# ─── The email actually changed ──────────────────────────────────────────────

def test_changing_the_email_retires_the_old_password(db, client_factory, sent):
    outlet, owner = _seed_owned_outlet(db)
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "owner@new.com"}
    )
    assert r.status_code == 200, r.text

    db.refresh(owner)
    assert owner.email == "owner@new.com"
    # The whole point: the previous credential must stop working.
    assert not verify_password(OWNER_PW, owner.hashed_password)


def test_the_retired_password_is_still_a_valid_bcrypt_hash(db, client_factory, sent):
    """Blanking the column would make `verify_password` raise inside
    bcrypt.checkpw, turning a stale login attempt into a 500 instead of a
    clean 401. It must stay a real (but unguessable) digest."""
    outlet, owner = _seed_owned_outlet(db)
    _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "owner@new.com"}
    )
    db.refresh(owner)

    assert owner.hashed_password
    assert owner.hashed_password.startswith("$2")
    # Must not raise, and must not accidentally match anything.
    assert verify_password(secrets.token_urlsafe(8), owner.hashed_password) is False


def test_set_password_mail_goes_to_the_new_address_only(db, client_factory, sent):
    outlet, _ = _seed_owned_outlet(db, owner_email="owner@old.com")
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "owner@new.com"}
    )
    assert r.status_code == 200

    assert len(sent) == 1
    assert sent[0]["to"] == "owner@new.com"
    assert "owner@old.com" not in sent[0]["to"]
    assert "/auth/set-password?token=" in sent[0]["html"]
    # Deliberately the same welcome mail a brand-new owner gets, so the two
    # flows cannot drift apart.
    assert sent[0]["subject"] == "Welcome to Eat Truck Love — set your password"
    assert "Set My Password" in sent[0]["html"]
    assert "Coffee Vault" in sent[0]["html"]  # the outlet name

    body = r.json()
    assert body["email_changed"] is True
    assert body["login_reissued"] is True
    assert body["password_reset"] is True
    assert body["email_sent"] is True
    assert "/auth/set-password?token=" in body["set_password_link"]


def test_the_emailed_link_actually_sets_the_new_password(db, client_factory, sent):
    """End-to-end: the link in the mail must be usable, and the password set
    through it becomes the account's password. This is what breaks if the token
    is minted against the OLD email — `set_password` matches id AND email."""
    from app.api.routes.auth import set_password
    from app.schemas.onboarding import SetPasswordRequest

    outlet, owner = _seed_owned_outlet(db)
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "owner@new.com"}
    )
    token = r.json()["set_password_link"].split("token=", 1)[1]

    set_password(SetPasswordRequest(token=token, new_password="brandNew456"), db)

    db.refresh(owner)
    assert verify_password("brandNew456", owner.hashed_password)
    assert owner.is_active is True


def test_name_is_updated_alongside_the_email(db, client_factory, sent):
    outlet, owner = _seed_owned_outlet(db)
    _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner",
        json={"name": "Real Owner", "email": "owner@new.com"},
    )
    db.refresh(owner)
    assert owner.name == "Real Owner"
    assert owner.email == "owner@new.com"


# ─── The email did NOT change — nothing may be touched ───────────────────────

def test_editing_only_the_name_leaves_the_password_alone(db, client_factory, sent):
    """The regression that would hurt most: correcting a typo in someone's name
    must not take their login away."""
    outlet, owner = _seed_owned_outlet(db)
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"name": "Corrected Name"}
    )
    assert r.status_code == 200

    db.refresh(owner)
    assert verify_password(OWNER_PW, owner.hashed_password)
    assert sent == []
    assert r.json()["login_reissued"] is False
    assert r.json()["set_password_link"] is None


def test_resaving_the_same_email_also_reissues(db, client_factory, sent):
    """Re-saving the identical address is a deliberate "resend the link":
    password retired, welcome mail sent again."""
    outlet, owner = _seed_owned_outlet(db, owner_email="owner@old.com")
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "owner@old.com"}
    )
    assert r.status_code == 200

    db.refresh(owner)
    assert owner.email == "owner@old.com"
    assert not verify_password(OWNER_PW, owner.hashed_password)
    assert [m["to"] for m in sent] == ["owner@old.com"]

    body = r.json()
    assert body["login_reissued"] is True
    assert body["password_reset"] is True
    # The address did not change, even though the login was re-issued.
    assert body["email_changed"] is False


@pytest.mark.parametrize("variant", ["Owner@Old.com", "  owner@old.com  ", "OWNER@OLD.COM"])
def test_case_variants_reissue_but_are_not_reported_as_a_change(
    db, client_factory, sent, variant
):
    """Normalisation still decides `email_changed` (so the message reads
    correctly), but submitting the field at all re-issues the login."""
    outlet, owner = _seed_owned_outlet(db, owner_email="owner@old.com")
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": variant}
    )
    assert r.status_code == 200

    db.refresh(owner)
    assert owner.email == "owner@old.com"  # normalised, not stored as typed
    assert not verify_password(OWNER_PW, owner.hashed_password)
    assert r.json()["email_changed"] is False
    assert r.json()["login_reissued"] is True
    assert len(sent) == 1


def test_phone_only_edit_touches_nothing(db, client_factory, sent):
    outlet, owner = _seed_owned_outlet(db)
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"phone": "9876543210"}
    )
    assert r.status_code == 200
    db.refresh(owner)
    assert verify_password(OWNER_PW, owner.hashed_password)
    assert sent == []


# ─── Rejected requests must not mutate anything ──────────────────────────────

def test_malformed_email_is_rejected_before_any_change(db, client_factory, sent):
    outlet, owner = _seed_owned_outlet(db, owner_email="owner@old.com")
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "not-an-email"}
    )
    assert r.status_code == 400

    db.refresh(owner)
    assert owner.email == "owner@old.com"
    assert verify_password(OWNER_PW, owner.hashed_password)
    assert sent == []


def test_email_taken_by_another_manager_is_rejected_cleanly(db, client_factory, sent):
    outlet, owner = _seed_owned_outlet(db, owner_email="owner@old.com")
    seed_manager(db, role="outlet_manager", email="taken@x.com")

    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "taken@x.com"}
    )
    assert r.status_code == 409

    db.refresh(owner)
    assert owner.email == "owner@old.com"
    assert verify_password(OWNER_PW, owner.hashed_password)
    assert sent == []


def test_email_taken_by_a_staff_account_is_rejected(db, client_factory, sent):
    """Login resolves against BOTH tables, so a staff address would collide."""
    outlet, owner = _seed_owned_outlet(db)
    db.add(
        Staff(
            name="Someone",
            email="staffy@x.com",
            hashed_password="x",
            role="outlet_staff",
            is_active=True,
        )
    )
    db.commit()

    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "staffy@x.com"}
    )
    assert r.status_code == 409
    db.refresh(owner)
    assert verify_password(OWNER_PW, owner.hashed_password)
    assert sent == []


def test_outlet_with_no_owner_is_404(db, client_factory, sent):
    court = seed_court(db)
    outlet = seed_outlet(db, court.id)
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "x@y.com"}
    )
    assert r.status_code == 404
    assert sent == []


def test_outlet_with_two_owners_is_409(db, client_factory, sent):
    """Ambiguous — we must not guess which login to re-issue."""
    outlet, _ = _seed_owned_outlet(db, owner_email="a@x.com")
    second = seed_manager(db, role="outlet_manager", email="b@x.com", outlet_id=outlet.id)
    seed_membership(db, second.id, outlet.id, MEMBERSHIP_OWNER)

    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "c@x.com"}
    )
    assert r.status_code == 409
    assert sent == []


def test_a_co_manager_is_not_mistaken_for_the_owner(db, client_factory, sent):
    outlet, owner = _seed_owned_outlet(db, owner_email="owner@old.com")
    co = seed_manager(db, role="outlet_manager", email="co@x.com", outlet_id=outlet.id)
    co.hashed_password = hash_password("coPass123")
    db.commit()
    seed_membership(db, co.id, outlet.id, MEMBERSHIP_MANAGER)

    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "owner@new.com"}
    )
    assert r.status_code == 200

    db.refresh(owner)
    db.refresh(co)
    assert owner.email == "owner@new.com"
    # The co-manager must be entirely unaffected.
    assert co.email == "co@x.com"
    assert verify_password("coPass123", co.hashed_password)
    assert [m["to"] for m in sent] == ["owner@new.com"]


def test_unknown_outlet_is_404(db, client_factory, sent):
    r = _etl(client_factory).patch("/outlets/424242/owner", json={"email": "x@y.com"})
    assert r.status_code == 404
    assert sent == []


# ─── Mail outage ─────────────────────────────────────────────────────────────

def test_a_mail_outage_does_not_fail_the_request(db, client_factory, mail_down):
    """The account change is already committed by the time we try to send, so a
    provider outage must not 500 — and the manager must still be handed the
    link, or the owner would be stranded with no password and no way to set
    one."""
    outlet, owner = _seed_owned_outlet(db)
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "owner@new.com"}
    )
    assert r.status_code == 200, r.text

    body = r.json()
    assert body["email_sent"] is False
    assert body["login_reissued"] is True
    assert "/auth/set-password?token=" in body["set_password_link"]
    assert "could NOT be sent" in body["message"]

    db.refresh(owner)
    assert owner.email == "owner@new.com"


def test_the_link_still_works_after_a_mail_outage(db, client_factory, mail_down):
    from app.api.routes.auth import set_password
    from app.schemas.onboarding import SetPasswordRequest

    outlet, owner = _seed_owned_outlet(db)
    r = _etl(client_factory).patch(
        f"/outlets/{outlet.id}/owner", json={"email": "owner@new.com"}
    )
    token = r.json()["set_password_link"].split("token=", 1)[1]
    set_password(SetPasswordRequest(token=token, new_password="recovered99"), db)

    db.refresh(owner)
    assert verify_password("recovered99", owner.hashed_password)


# ─── Authorisation ───────────────────────────────────────────────────────────

def test_an_outlet_manager_cannot_re_issue_an_owner_login(db, client_factory, sent):
    """Only ETL management may call this. Otherwise an outlet manager could
    point someone else's outlet at an address they control."""
    outlet, owner = _seed_owned_outlet(db)
    client = client_factory(
        make_user("outlet_manager", uid=owner.id, outlet_id=outlet.id,
                  outlet_ids=[outlet.id], email="owner@old.com")
    )
    r = client.patch(f"/outlets/{outlet.id}/owner", json={"email": "attacker@x.com"})
    assert r.status_code == 403

    db.refresh(owner)
    assert owner.email == "owner@old.com"
    assert verify_password(OWNER_PW, owner.hashed_password)
    assert sent == []


def test_a_zone_manager_cannot_either(db, client_factory, sent):
    outlet, owner = _seed_owned_outlet(db)
    client = client_factory(
        make_user("crownest_zone_manager", uid=5, user_type="staff", email="zm@x.com")
    )
    r = client.patch(f"/outlets/{outlet.id}/owner", json={"email": "x@y.com"})
    assert r.status_code == 403
    assert sent == []
