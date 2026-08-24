"""H1 — one attendance row per staff per business day (double check-in guard)."""
import datetime as dt

import pytest
from sqlalchemy.exc import IntegrityError

from app.models.attendance import Attendance


def _row(staff_id, business_date):
    # check_in_lat/lng + check_in_photo_url are NOT NULL on the model.
    return Attendance(
        staff_id=staff_id,
        business_date=business_date,
        check_in_time=dt.datetime.utcnow(),
        check_in_lat=1.0,
        check_in_lng=1.0,
        check_in_photo_url="x.jpg",
    )


def test_duplicate_staff_business_date_is_rejected(db):
    b = dt.date(2026, 1, 1)
    db.add(_row(1, b))
    db.commit()

    # A concurrent/second check-in for the SAME staff+day must violate the
    # unique constraint (this is what makes the route's `except IntegrityError`
    # a real guard instead of dead code).
    db.add(_row(1, b))
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()


def test_same_staff_different_day_is_allowed(db):
    db.add(_row(1, dt.date(2026, 1, 1)))
    db.add(_row(1, dt.date(2026, 1, 2)))
    db.commit()
    assert db.query(Attendance).filter(Attendance.staff_id == 1).count() == 2


def test_different_staff_same_day_is_allowed(db):
    b = dt.date(2026, 1, 1)
    db.add(_row(1, b))
    db.add(_row(2, b))
    db.commit()
    assert db.query(Attendance).count() == 2


def test_null_business_date_rows_are_distinct(db):
    # Legacy rows with NULL business_date must not collide (NULLs are distinct).
    db.add(_row(1, None))
    db.add(_row(1, None))
    db.commit()  # must not raise
    assert db.query(Attendance).filter(Attendance.staff_id == 1).count() == 2
