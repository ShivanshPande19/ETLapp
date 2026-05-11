# backend_fastapi/app/schemas/staff.py
from pydantic import BaseModel, EmailStr
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
    is_active: bool

    class Config:
        from_attributes = True

class StaffListResponse(BaseModel):
    staff: list[StaffResponse]

class CourtAssignRequest(BaseModel):
    court_id: int