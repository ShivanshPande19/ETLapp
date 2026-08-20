# backend_fastapi/app/schemas/onboarding.py

from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class ApplicationOut(BaseModel):
    id: int
    court_id: int
    court_name: Optional[str] = None
    outlet_name: str
    owner_name: str
    owner_phone: str
    owner_email: str
    gst_url: Optional[str] = None
    fssai_url: Optional[str] = None
    term_sheet_url: Optional[str] = None
    agreement_url: Optional[str] = None
    status: str
    rejection_reason: Optional[str] = None
    created_outlet_id: Optional[int] = None
    created_at: Optional[datetime] = None
    reviewed_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class ApplicationListResponse(BaseModel):
    applications: List[ApplicationOut]
    pending_count: int


class ApproveRequest(BaseModel):
    # Petpooja restaurant/store mapping id — REQUIRED so sales sync works.
    rest_id: str
    # Optional per-outlet Petpooja creds. If omitted, the global .env creds are used.
    pp_app_key: Optional[str] = None
    pp_app_secret: Optional[str] = None
    pp_access_token: Optional[str] = None
    pp_cookie: Optional[str] = None
    # Which POS adapter fetches this outlet's sales. Optional; defaults to
    # 'petpooja_generic' so existing clients that don't send it are unaffected.
    # Use 'petpooja_salesdata' for get_sales_data outlets, 'royal_pos' for Royal.
    pos_source: Optional[str] = None


class ApproveResponse(BaseModel):
    outlet_id: int
    manager_email: str
    # None when the outlet was linked to an EXISTING owner account (no password
    # to set); a link only for brand-new owner accounts.
    set_password_link: Optional[str] = None
    email_sent: bool
    message: str


class RejectRequest(BaseModel):
    reason: Optional[str] = None


class SetPasswordRequest(BaseModel):
    token: str
    new_password: str


class OutletWithDocs(BaseModel):
    outlet_id: int
    court_id: int
    vendor_name: str
    rest_id: str
    owner_name: Optional[str] = None
    owner_email: Optional[str] = None
    owner_phone: Optional[str] = None
    gst_url: Optional[str] = None
    fssai_url: Optional[str] = None
    term_sheet_url: Optional[str] = None
    agreement_url: Optional[str] = None
    has_petpooja_creds: bool = False
    application_id: Optional[int] = None
