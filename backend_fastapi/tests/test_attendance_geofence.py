"""Attendance geofence — multi-zone roles and coarse GPS fixes.

Regression cover for the daily Crownest Zone Manager complaint: "I'm standing
inside my zone and it still says I'm outside, and attendance won't record."

The cause was treating every GPS fix as exact. A fix whose own reported
accuracy is wider than the geofence itself carries NO information about
inside/outside (Android 12+ "Approximate location" reports accuracy in
kilometres), so rejecting on it produced a false "you are outside your zone".
These tests pin the rule: such a fix is refused as UNDECIDABLE with a message
about GPS accuracy, never as a zone violation.
"""
import json

import pytest
from fastapi import HTTPException

from app.api.routes.attendance import _assigned_courts, _enforce_geofence
from app.core.geo import MAX_TRUSTED_ACCURACY_M
from app.models.sale import Court
from app.models.staff import Staff

# Two points ~1.1 km apart, plus one essentially on top of the first.
ZONE_A = (28.5000, 77.5000)
ZONE_B = (28.5100, 77.5100)
INSIDE_A = (28.50005, 77.50005)
FAR_AWAY = (28.6000, 77.6000)  # ~14 km from both


def _court(db, name, lat=None, lng=None, radius=150):
    c = Court(
        name=name,
        is_active=1,
        latitude=lat,
        longitude=lng,
        geofence_radius=radius,
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


def _zone_manager(db, courts, email="zm@test.com"):
    """A Crownest Zone Manager: a staff row scoped to a SET of zones."""
    s = Staff(
        name="Zone Mgr",
        email=email,
        hashed_password="x",
        role="crownest_zone_manager",
        court_id=courts[0].id if courts else None,
        zone_court_ids=json.dumps([c.id for c in courts]) if courts else None,
        shift_start="10:00",
        shift_end="19:00",
        is_active=True,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


# ─── _assigned_courts ────────────────────────────────────────────────────────

def test_assigned_courts_follows_zone_court_ids_order(db):
    a = _court(db, "A", *ZONE_A)
    b = _court(db, "B", *ZONE_B)
    # Deliberately list B first: element 0 is the PRIMARY zone and callers
    # depend on that ordering (geofence payload, `courts[0]` fallback).
    s = _zone_manager(db, [b, a])
    assert [c.id for c in _assigned_courts(db, s)] == [b.id, a.id]


def test_assigned_courts_dedupes_repeated_ids(db):
    a = _court(db, "A", *ZONE_A)
    s = _zone_manager(db, [a])
    s.zone_court_ids = json.dumps([a.id, a.id, a.id])
    db.commit()
    assert [c.id for c in _assigned_courts(db, s)] == [a.id]


def test_assigned_courts_falls_back_to_primary_when_zones_vanish(db):
    a = _court(db, "A", *ZONE_A)
    s = _zone_manager(db, [a])
    # Zones point at courts that no longer exist; court_id still does.
    s.zone_court_ids = json.dumps([9991, 9992])
    db.commit()
    assert [c.id for c in _assigned_courts(db, s)] == [a.id]


def test_assigned_courts_survives_garbage_json(db):
    a = _court(db, "A", *ZONE_A)
    s = _zone_manager(db, [a])
    s.zone_court_ids = "not json at all"
    db.commit()
    assert [c.id for c in _assigned_courts(db, s)] == [a.id]


# ─── _enforce_geofence — the happy paths ─────────────────────────────────────

def test_inside_primary_zone_is_credited_there(db):
    a = _court(db, "A", *ZONE_A)
    b = _court(db, "B", *ZONE_B)
    s = _zone_manager(db, [a, b])
    got = _enforce_geofence(db, s, INSIDE_A[0], INSIDE_A[1], 10.0)
    assert got is not None and got.id == a.id


def test_inside_any_assigned_zone_is_enough(db):
    """A zone manager covers several zones — being in the SECOND one passes,
    and the check-in is credited to that zone, not the primary."""
    a = _court(db, "A", *ZONE_A)
    b = _court(db, "B", *ZONE_B)
    s = _zone_manager(db, [a, b])
    got = _enforce_geofence(db, s, ZONE_B[0], ZONE_B[1], 10.0)
    assert got is not None and got.id == b.id


def test_no_geofence_configured_allows_check_in(db):
    """Legacy courts with no location set: geofencing simply doesn't apply."""
    a = _court(db, "A")  # no lat/lng
    s = _zone_manager(db, [a])
    got = _enforce_geofence(db, s, FAR_AWAY[0], FAR_AWAY[1], 10.0)
    assert got is not None and got.id == a.id


def test_accuracy_buffer_rescues_a_fix_just_outside_the_radius(db):
    """A genuine staff member with a mediocre (but trustworthy) fix sitting
    slightly outside the circle is let in via the accuracy buffer."""
    a = _court(db, "A", *ZONE_A, radius=50)
    s = _zone_manager(db, [a])
    # ~55 m north of centre: outside a 50 m radius, inside 50 + 60 m buffer.
    lat = ZONE_A[0] + 0.0005
    got = _enforce_geofence(db, s, lat, ZONE_A[1], 60.0)
    assert got is not None and got.id == a.id


# ─── _enforce_geofence — rejections ──────────────────────────────────────────

def test_genuinely_far_away_with_a_good_fix_is_a_zone_violation(db):
    """A precise fix that really is far away must still be rejected — and the
    message must name the distance and the zones."""
    a = _court(db, "A", *ZONE_A)
    b = _court(db, "B", *ZONE_B)
    s = _zone_manager(db, [a, b])
    with pytest.raises(HTTPException) as err:
        _enforce_geofence(db, s, FAR_AWAY[0], FAR_AWAY[1], 8.0)
    assert err.value.status_code == 403
    detail = err.value.detail
    assert "m from" in detail
    assert "A" in detail and "B" in detail


@pytest.mark.parametrize("accuracy", [MAX_TRUSTED_ACCURACY_M + 1, 1500.0, 3000.0])
def test_coarse_fix_is_undecidable_not_a_zone_violation(db, accuracy):
    """THE REGRESSION. The phone says "I could be anywhere within `accuracy`
    metres"; that is wider than the zone, so the only honest answer is "can't
    tell". It must NOT come back as "you are outside your zone"."""
    a = _court(db, "A", *ZONE_A)
    s = _zone_manager(db, [a])
    with pytest.raises(HTTPException) as err:
        _enforce_geofence(db, s, FAR_AWAY[0], FAR_AWAY[1], accuracy)
    assert err.value.status_code == 403
    detail = err.value.detail
    assert "accurate enough" in detail
    # Must not accuse them of being out of the zone, nor quote a distance that
    # the fix cannot actually support. ("step outside" as ADVICE is fine.)
    assert "outside your zone" not in detail.lower()
    assert "m from" not in detail
    # The measured accuracy is echoed so support can diagnose from the message.
    assert str(int(round(accuracy))) in detail


@pytest.mark.parametrize("accuracy", [None, 0.0, -1.0])
def test_unknown_accuracy_is_also_undecidable(db, accuracy):
    """No error bar at all — an older client that sends no `accuracy`, or a
    device reporting 0/negative ("I don't know") — is just as undecidable as a
    kilometre-wide fix, and must not read as a zone violation."""
    a = _court(db, "A", *ZONE_A)
    s = _zone_manager(db, [a])
    with pytest.raises(HTTPException) as err:
        _enforce_geofence(db, s, FAR_AWAY[0], FAR_AWAY[1], accuracy)
    detail = err.value.detail
    assert "accurate enough" in detail
    assert "outside your zone" not in detail.lower()
    # Nothing meaningless like "±0 m" leaks into the message.
    assert "±0 m" not in detail and "±-1 m" not in detail


def test_coarse_fix_still_passes_when_actually_inside(db):
    """A coarse fix is only a problem when it would REJECT someone. Standing
    at the centre of the zone, the buffer puts them inside regardless."""
    a = _court(db, "A", *ZONE_A)
    s = _zone_manager(db, [a])
    got = _enforce_geofence(db, s, INSIDE_A[0], INSIDE_A[1], 2000.0)
    assert got is not None and got.id == a.id


# ─── Maintenance Head shares the same multi-zone path ────────────────────────

def test_maintenance_head_uses_the_same_multi_zone_rules(db):
    a = _court(db, "A", *ZONE_A)
    b = _court(db, "B", *ZONE_B)
    s = Staff(
        name="Maint Head",
        email="mh@test.com",
        hashed_password="x",
        role="crownest_maintenance_head",
        court_id=a.id,
        zone_court_ids=json.dumps([a.id, b.id]),
        is_active=True,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    got = _enforce_geofence(db, s, ZONE_B[0], ZONE_B[1], 10.0)
    assert got is not None and got.id == b.id


def test_single_court_staff_is_unaffected(db):
    """An ordinary etl_staff has one court via `court_id` and no zone list."""
    a = _court(db, "A", *ZONE_A)
    s = Staff(
        name="Staff",
        email="s@test.com",
        hashed_password="x",
        role="etl_staff",
        court_id=a.id,
        is_active=True,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    assert [c.id for c in _assigned_courts(db, s)] == [a.id]
    got = _enforce_geofence(db, s, INSIDE_A[0], INSIDE_A[1], 10.0)
    assert got is not None and got.id == a.id
