# backend_fastapi/app/services/roster_service.py

from datetime import date
from sqlalchemy.orm import Session
from sqlalchemy import func
from ..models.staff import Staff
from ..models.attendance import Attendance
from ..schemas.attendance import RosterResponse, StaffRosterItem

def get_daily_roster(db: Session, outlet_id: int, target_date: date) -> RosterResponse:
    # 1. Us outlet ke saare active staff nikalo
    staff_members = db.query(Staff).filter(
        Staff.outlet_id == outlet_id, 
        Staff.is_active == True
    ).all()

    # 2. Aaj ki attendance nikalo us outlet ki
    attendances = db.query(Attendance).filter(
        Attendance.outlet_id == outlet_id,
        func.date(Attendance.check_in_time) == target_date
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