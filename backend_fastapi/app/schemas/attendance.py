# backend_fastapi/app/schemas/attendance.py

from pydantic import BaseModel
from typing import List, Optional
from datetime import date, datetime

class StaffRosterItem(BaseModel):
    staff_id: int
    name: str
    status: str  # "present" or "absent"
    check_in_time: Optional[datetime] = None
    selfie_url: Optional[str] = None

class RosterResponse(BaseModel):
    date: date
    total_staff: int
    present_count: int
    staff_list: List[StaffRosterItem]