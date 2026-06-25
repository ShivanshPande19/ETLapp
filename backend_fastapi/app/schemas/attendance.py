# backend_fastapi/app/schemas/attendance.py

from pydantic import BaseModel, field_serializer
from typing import List, Optional
from datetime import date, datetime, timezone


def _iso_utc_z(dt: Optional[datetime]) -> Optional[str]:
    """Serialize a (naive or aware) datetime as UTC ISO 8601 with a trailing
    'Z' so Flutter's DateTime.parse(...).toLocal() shows the correct local
    time regardless of the device timezone."""
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt.isoformat() + "Z"


# ─── Staff's own attendance status (check-in / check-out) ────────────────────

class AttendanceStatusOut(BaseModel):
    attendance_id: Optional[int] = None
    checked_in: bool = False
    check_in_time: Optional[datetime] = None
    check_in_address: Optional[str] = None
    check_in_photo_url: Optional[str] = None

    checked_out: bool = False
    check_out_time: Optional[datetime] = None
    check_out_address: Optional[str] = None

    # Status flags for the UI / calendar.
    early_checkout: bool = False
    auto_closed: bool = False

    # Minutes between check-in and check-out (null until checked out).
    work_duration_minutes: Optional[int] = None

    @field_serializer("check_in_time", "check_out_time")
    def _ser_dt(self, dt: Optional[datetime], _info) -> Optional[str]:
        return _iso_utc_z(dt)


# ─── Manager roster ──────────────────────────────────────────────────────────

class StaffRosterItem(BaseModel):
    staff_id: int
    name: str
    status: str  # "present" or "absent"
    check_in_time: Optional[datetime] = None
    check_out_time: Optional[datetime] = None
    selfie_url: Optional[str] = None

    @field_serializer("check_in_time", "check_out_time")
    def _ser_dt(self, dt: Optional[datetime], _info) -> Optional[str]:
        return _iso_utc_z(dt)


class RosterResponse(BaseModel):
    date: date
    total_staff: int
    present_count: int
    staff_list: List[StaffRosterItem]


# ─── ETL manager court-wise roster ───────────────────────────────────────────

class CourtRosterItem(BaseModel):
    court_id: int
    court_name: str
    total_staff: int
    present_count: int
    staff_list: List[StaffRosterItem]


class EtlRosterResponse(BaseModel):
    date: date
    total_courts: int
    total_staff: int
    total_present: int
    courts: List[CourtRosterItem]
