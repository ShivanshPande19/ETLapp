# backend_fastapi/app/services/roster_service.py

from datetime import date
from typing import Optional
from sqlalchemy.orm import Session
from ..models.staff import Staff
from ..models.attendance import Attendance
from ..models.sale import Court
from ..core.query_utils import day_range
from ..schemas.attendance import (
    RosterResponse,
    StaffRosterItem,
    CourtRosterItem,
    EtlRosterResponse,
)

def get_daily_roster(db: Session, outlet_id: int, target_date: date) -> RosterResponse:
    # 1. Us outlet ke saare active staff nikalo
    staff_members = db.query(Staff).filter(
        Staff.outlet_id == outlet_id, 
        Staff.is_active == True
    ).all()

    # 2. Aaj ki attendance nikalo us outlet ki (portable day-range; Postgres-safe)
    _start, _end = day_range(target_date)
    attendances = db.query(Attendance).filter(
        Attendance.outlet_id == outlet_id,
        Attendance.check_in_time >= _start,
        Attendance.check_in_time < _end,
    ).all()

    # Dictionary banalo taaki fast search ho sake {staff_id: attendance_record}
    attendance_map = {a.staff_id: a for a in attendances}

    roster_list = []
    present_count = 0

    # 3. Har staff ko check karo
    for staff in staff_members:
        record = attendance_map.get(staff.id)
        
        if record:
            status = "present"
            present_count += 1
            # ✅ Raw UTC times — schema serializes with 'Z' aur client toLocal()
            # karke sahi local time dikhata hai (manual +5:30 hack hata diya).
            chk_in = record.check_in_time
            chk_out = record.check_out_time
            selfie = record.check_in_photo_url
        else:
            status = "absent"
            chk_in = None
            chk_out = None
            selfie = None

        roster_list.append(StaffRosterItem(
            staff_id=staff.id,
            name=staff.name,
            status=status,
            check_in_time=chk_in,
            check_out_time=chk_out,
            selfie_url=selfie
        ))

    return RosterResponse(
        date=target_date,
        total_staff=len(staff_members),
        present_count=present_count,
        staff_list=roster_list
    )


def _build_court_roster(db: Session, court: Court, target_date: date) -> CourtRosterItem:
    """Ek court ke ETL staff ka roster banata hai (court_id se scoped)."""
    # ETL staff us court ke (court_id set hota hai; outlet staff ka court_id null
    # hota hai isliye wo apne aap exclude ho jaate hain).
    staff_members = db.query(Staff).filter(
        Staff.court_id == court.id,
        Staff.is_active == True,
    ).all()

    _start, _end = day_range(target_date)
    attendances = db.query(Attendance).filter(
        Attendance.court_id == court.id,
        Attendance.check_in_time >= _start,
        Attendance.check_in_time < _end,
    ).all()
    attendance_map = {a.staff_id: a for a in attendances}

    roster_list = []
    present_count = 0
    for staff in staff_members:
        record = attendance_map.get(staff.id)
        if record:
            status = "present"
            present_count += 1
            chk_in = record.check_in_time
            chk_out = record.check_out_time
            selfie = record.check_in_photo_url
        else:
            status = "absent"
            chk_in = None
            chk_out = None
            selfie = None

        roster_list.append(StaffRosterItem(
            staff_id=staff.id,
            name=staff.name,
            status=status,
            check_in_time=chk_in,
            check_out_time=chk_out,
            selfie_url=selfie,
        ))

    # Present staff pehle, phir naam se sort (frontend ke liye consistent order)
    roster_list.sort(key=lambda s: (s.status != "present", s.name.lower()))

    return CourtRosterItem(
        court_id=court.id,
        court_name=court.name,
        total_staff=len(staff_members),
        present_count=present_count,
        staff_list=roster_list,
    )


def get_etl_court_roster(
    db: Session,
    target_date: date,
    court_id: Optional[int] = None,
) -> EtlRosterResponse:
    """ETL manager ke liye court-wise staff attendance roster.
    court_id diya ho toh sirf wahi court, warna saare active courts."""
    court_query = db.query(Court).filter(Court.is_active == 1)
    if court_id is not None:
        court_query = court_query.filter(Court.id == court_id)
    courts = court_query.order_by(Court.name).all()

    court_items = [_build_court_roster(db, court, target_date) for court in courts]

    total_staff = sum(c.total_staff for c in court_items)
    total_present = sum(c.present_count for c in court_items)

    return EtlRosterResponse(
        date=target_date,
        total_courts=len(court_items),
        total_staff=total_staff,
        total_present=total_present,
        courts=court_items,
    )