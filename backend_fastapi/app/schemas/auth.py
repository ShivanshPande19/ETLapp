# backend_fastapi/app/schemas/auth.py
from pydantic import BaseModel
from typing import Optional

class LoginRequest(BaseModel):
    email: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    manager_name: str
    manager_email: str
    role: str
    zone: Optional[int] = None       # Ye etl_staff (court_id) ke liye kaam aayega
    outlet_id: Optional[int] = None  # Naya column outlet_manager/outlet_staff ke liye