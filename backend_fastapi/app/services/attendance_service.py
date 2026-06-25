# app/services/attendance_service.py
"""Attendance calendar builders (staff + manager views).

Status per day:
  present     🟢  checked in + on-time manual check-out (or still on shift today)
  early       🟡  manual check-out before scheduled shift end
  auto_closed 🟠  system auto-closed a forgotten check-out
  absent      🔴  a past business day (since the staff joined) with no record
Future days and days before the staff joined are simply omitted (neutral).
"""

from calendar import monthrange
from datetime import date
from typing import Optional

from sqlalchemy.orm import Session

from ..models.attendance import Attendance
from ..models.staff import Staff
from ..models.sale import Court, Outlet
from ..core.query_utils import (
    current_business_date,
    business_date_for,
    to_ist,
)


def _court_cutoff(db: Session, court_id: Optional[int]) -> int:
    if not court_id:
        return 0
    c = db.query(Court).filter(Court.id == court_id).first()
    return (c.day_cutoff_hour or 0) if c else 0


def _staff_cutoff(db: Session, staff: Staff) -> int:
    """Business-day cutoff for a staff — from their court, or (for outlet staff)
    their outlet's court."""
    if staff.court_id:
        return _court_cutoff(db, staff.court_id)
    if staff.outlet_id:
        outlet = db.query(Outlet).filter(Outlet.id == staff.outlet_id).first()
        if outlet and outlet.court_id:
            return _court_cutoff(db, outlet.court_id)
    return 0


def _record_status(rec: Attendance) -> str:
    if rec.auto_closed:
        return "auto_closed"
    if rec.early_checkout:
        return "early"
    return "present"


def build_staff_calendar(
    db: Session, staff: Staff, year: int, month: int, cutoff: Optional[int] = None
) -> dict:
    """Per-day attendance status for one staff in a given month."""
    if cutoff is None:
        cutoff = _staff_cutoff(db, staff)

    month_start = date(year, month, 1)
    month_end = date(year, month, monthrange(year, month)[1])
    today_biz = current_business_date(cutoff)

    # Day the staff joined (don't mark "absent" before this).
    joined = None
    if staff.created_at is not None:
        joined = to_ist(staff.created_at).date()

    # Fetch this month's rows (by business_date, with a legacy fallback).
    rows = db.query(Attendance).filter(Attendance.staff_id == staff.id).all()
    by_date: dict[date, Attendance] = {}
    for r in rows:
        bd = r.business_date
        if bd is None and r.check_in_time is not None:
            bd = business_date_for(to_ist(r.check_in_time), cutoff)
        if bd is None:
            continue
        if month_start <= bd <= month_end:
            # Keep the latest check-in if somehow duplicated.
            prev = by_date.get(bd)
            if prev is None or (r.check_in_time and prev.check_in_time and r.check_in_time > prev.check_in_time):
                by_date[bd] = r

    days = []
    counts = {"present": 0, "early": 0, "auto_closed": 0, "absent": 0}

    d = month_start
    while d <= month_end:
        if d > today_biz:
            d = date.fromordinal(d.toordinal() + 1)
            continue  # future → neutral
        if joined is not None and d < joined:
            d = date.fromordinal(d.toordinal() + 1)
            continue  # before joining → neutral

        rec = by_date.get(d)
        if rec is not None:
            status = _record_status(rec)
        elif d == today_biz:
            d = date.fromordinal(d.toordinal() + 1)
            continue  # today, not marked yet → neutral (don't show red)
        else:
            status = "absent"

        counts[status] = counts.get(status, 0) + 1
        entry = {"date": d.isoformat(), "status": status}
        if rec is not None:
            entry["check_in_time"] = (
                to_ist(rec.check_in_time).isoformat() if rec.check_in_time else None
            )
            entry["check_out_time"] = (
                to_ist(rec.check_out_time).isoformat() if rec.check_out_time else None
            )
        days.append(entry)
        d = date.fromordinal(d.toordinal() + 1)

    return {
        "month": f"{year:04d}-{month:02d}",
        "days": days,
        "summary": counts,
    }


def build_court_calendars(
    db: Session, year: int, month: int, court_id: Optional[int] = None
) -> dict:
    """Manager view: each court → its ETL staff → per-day calendar."""
    court_q = db.query(Court).filter(Court.is_active == 1)
    if court_id is not None:
        court_q = court_q.filter(Court.id == court_id)
    courts = court_q.order_by(Court.name).all()

    out_courts = []
    for court in courts:
        cutoff = court.day_cutoff_hour or 0
        staff_members = (
            db.query(Staff)
            .filter(Staff.court_id == court.id, Staff.is_active == True)  # noqa: E712
            .order_by(Staff.name)
            .all()
        )
        staff_cals = []
        for s in staff_members:
            cal = build_staff_calendar(db, s, year, month, cutoff=cutoff)
            staff_cals.append(
                {
                    "staff_id": s.id,
                    "name": s.name,
                    "shift_start": s.shift_start,
                    "shift_end": s.shift_end,
                    "photo_url": s.photo_url,
                    "days": cal["days"],
                    "summary": cal["summary"],
                }
            )
        out_courts.append(
            {
                "court_id": court.id,
                "court_name": court.name,
                "day_cutoff_hour": cutoff,
                "staff": staff_cals,
            }
        )

    return {"month": f"{year:04d}-{month:02d}", "courts": out_courts}



def build_outlet_calendars(
    db: Session, year: int, month: int, outlet_id: int
) -> dict:
    """Outlet-manager view: every staff of ONE outlet → per-day calendar.

    Outlet staff inherit their outlet's court cutoff for the business day.
    """
    outlet = db.query(Outlet).filter(Outlet.id == outlet_id).first()
    cutoff = _court_cutoff(db, outlet.court_id) if outlet else 0

    staff_members = (
        db.query(Staff)
        .filter(Staff.outlet_id == outlet_id, Staff.is_active == True)  # noqa: E712
        .order_by(Staff.name)
        .all()
    )

    staff_cals = []
    for s in staff_members:
        cal = build_staff_calendar(db, s, year, month, cutoff=cutoff)
        staff_cals.append(
            {
                "staff_id": s.id,
                "name": s.name,
                "shift_start": s.shift_start,
                "shift_end": s.shift_end,
                "photo_url": s.photo_url,
                "days": cal["days"],
                "summary": cal["summary"],
            }
        )

    return {
        "month": f"{year:04d}-{month:02d}",
        "outlet_id": outlet_id,
        "outlet_name": outlet.vendor_name if outlet else "Outlet",
        "staff": staff_cals,
    }
