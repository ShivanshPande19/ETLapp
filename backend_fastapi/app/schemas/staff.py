# backend_fastapi/app/schemas/staff.py
from pydantic import BaseModel, EmailStr, Field
from typing import Optional

class StaffCreate(BaseModel):
    name: str
    email: EmailStr
    password: str
    court_id: int

class StaffResponse(BaseModel):
    id: int
    name: str
    email: str
    role: str
    court_id: Optional[int]
    phone: Optional[str] = None
    photo_url: Optional[str] = None
    shift_start: Optional[str] = None
    shift_end: Optional[str] = None
    is_active: bool

    class Config:
        from_attributes = True

class StaffListResponse(BaseModel):
    staff: list[StaffResponse]

class CourtAssignRequest(BaseModel):
    court_id: int


class ShiftUpdateRequest(BaseModel):
    # "HH:MM" 24h strings, or null to clear the shift.
    shift_start: Optional[str] = Field(default=None, pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    shift_end: Optional[str] = Field(default=None, pattern=r"^([01]\d|2[0-3]):[0-5]\d$")