# backend_fastapi/app/api/routes/onboarding.py
#
# Outlet onboarding pipeline:
#   - Public HTML form for owners to apply (court chosen from DB dropdown)
#   - ETL manager reviews applications and approves (creates Outlet + outlet
#     manager login + set-password magic link) or rejects them.

import os
import uuid
import secrets
import logging
from datetime import datetime
from typing import Optional

from fastapi import (
    APIRouter, Depends, HTTPException, Request, Form, File, UploadFile, Query,
)
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from ...database import get_db
from ...models.sale import Court, Outlet
from ...models.manager import Manager
from ...models.onboarding import OutletApplication
from ...schemas.onboarding import (
    ApplicationOut, ApplicationListResponse, ApproveRequest, ApproveResponse,
    RejectRequest,
)
from ...core.config import settings
from ...core.security import create_token, hash_password
from ...services.email_service import send_email
from ..deps import get_current_user, CurrentUser

logger = logging.getLogger("onboarding")
router = APIRouter()

templates_dir = os.path.join(os.getcwd(), "app", "templates")
templates = Jinja2Templates(directory=templates_dir)

# Set-password link valid for 7 days.
_SET_PW_EXPIRY_MIN = 60 * 24 * 7

# ─── Document upload constraints ──────────────────────────────────────────────
_ALLOWED_DOC_TYPES = {
    "application/pdf": "pdf",
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}
_MAX_DOC_BYTES = 10 * 1024 * 1024  # 10 MB


async def _save_doc(f: Optional[UploadFile], prefix: str) -> Optional[str]:
    """Persist an uploaded document to the uploads volume and return its
    public URL path ('uploads/onboarding/...', served by the /uploads mount).
    Returns None if no file was provided."""
    if f is None or not f.filename:
        return None
    ext = _ALLOWED_DOC_TYPES.get(f.content_type)
    if ext is None:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid file type for {prefix}. Upload PDF, JPG, PNG or WebP.",
        )
    data = await f.read()
    if len(data) > _MAX_DOC_BYTES:
        raise HTTPException(status_code=400, detail=f"{prefix} file too large (max 10 MB).")
    if not data:
        return None

    folder = os.path.join(settings.UPLOAD_DIR, "onboarding")
    os.makedirs(folder, exist_ok=True)
    filename = f"{prefix}_{uuid.uuid4()}.{ext}"
    with open(os.path.join(folder, filename), "wb") as buf:
        buf.write(data)
    # URL path relative to the /uploads static mount (NOT the disk path).
    return f"uploads/onboarding/{filename}"


def _to_out(app: OutletApplication, court_name: Optional[str] = None) -> ApplicationOut:
    out = ApplicationOut.model_validate(app)
    out.court_name = court_name
    return out


def _require_etl_manager(user: CurrentUser):
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")


# ─── PUBLIC: application form ────────────────────────────────────────────────

@router.get("/apply", response_class=HTMLResponse)
def apply_form(request: Request, db: Session = Depends(get_db)):
    courts = (
        db.query(Court)
        .filter(Court.is_active == 1)
        .order_by(Court.name)
        .all()
    )
    return templates.TemplateResponse(
        request=request,
        name="onboarding.html",
        context={"request": request, "courts": courts},
    )


@router.post("/applications", response_class=HTMLResponse)
async def submit_application(
    request: Request,
    court_id: int = Form(...),
    outlet_name: str = Form(...),
    owner_name: str = Form(...),
    owner_phone: str = Form(...),
    owner_email: str = Form(...),
    gst: Optional[UploadFile] = File(None),
    fssai: Optional[UploadFile] = File(None),
    term_sheet: Optional[UploadFile] = File(None),
    agreement: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    # Validate court
    court = db.query(Court).filter(Court.id == court_id, Court.is_active == 1).first()
    if not court:
        raise HTTPException(status_code=400, detail="Please select a valid court.")

    # Basic field validation
    outlet_name = outlet_name.strip()
    owner_name = owner_name.strip()
    owner_phone = owner_phone.strip()
    owner_email = owner_email.strip().lower()
    if not (outlet_name and owner_name and owner_phone and owner_email):
        raise HTTPException(status_code=400, detail="All fields are required.")
    if "@" not in owner_email or "." not in owner_email.split("@")[-1]:
        raise HTTPException(status_code=400, detail="Please enter a valid email address.")

    # Save documents (best-effort; owner may not have every doc)
    gst_url = await _save_doc(gst, "gst")
    fssai_url = await _save_doc(fssai, "fssai")
    term_sheet_url = await _save_doc(term_sheet, "term")
    agreement_url = await _save_doc(agreement, "agreement")

    application = OutletApplication(
        court_id=court.id,
        outlet_name=outlet_name,
        owner_name=owner_name,
        owner_phone=owner_phone,
        owner_email=owner_email,
        gst_url=gst_url,
        fssai_url=fssai_url,
        term_sheet_url=term_sheet_url,
        agreement_url=agreement_url,
        status="pending",
    )
    db.add(application)
    db.commit()

    return templates.TemplateResponse(
        request=request,
        name="onboarding_success.html",
        context={"request": request, "outlet_name": outlet_name, "court_name": court.name},
    )


# ─── ETL MANAGER: review applications ────────────────────────────────────────

@router.get("/applications", response_model=ApplicationListResponse)
def list_applications(
    court_id: Optional[int] = Query(None),
    status: Optional[str] = Query(None, description="pending | approved | rejected"),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    _require_etl_manager(user)

    q = db.query(OutletApplication)
    if court_id is not None:
        q = q.filter(OutletApplication.court_id == court_id)
    if status:
        q = q.filter(OutletApplication.status == status)
    apps = q.order_by(OutletApplication.created_at.desc()).all()

    court_names = {c.id: c.name for c in db.query(Court).all()}
    items = [_to_out(a, court_names.get(a.court_id)) for a in apps]

    pending_q = db.query(OutletApplication).filter(
        OutletApplication.status == "pending"
    )
    if court_id is not None:
        pending_q = pending_q.filter(OutletApplication.court_id == court_id)

    return ApplicationListResponse(
        applications=items, pending_count=pending_q.count()
    )


@router.get("/applications/{application_id}", response_model=ApplicationOut)
def get_application(
    application_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    _require_etl_manager(user)
    app = db.query(OutletApplication).filter(
        OutletApplication.id == application_id
    ).first()
    if not app:
        raise HTTPException(status_code=404, detail="Application not found.")
    court = db.query(Court).filter(Court.id == app.court_id).first()
    return _to_out(app, court.name if court else None)


@router.post("/applications/{application_id}/approve", response_model=ApproveResponse)
async def approve_application(
    application_id: int,
    data: ApproveRequest,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    _require_etl_manager(user)

    app = db.query(OutletApplication).filter(
        OutletApplication.id == application_id
    ).first()
    if not app:
        raise HTTPException(status_code=404, detail="Application not found.")
    if app.status != "pending":
        raise HTTPException(
            status_code=409, detail=f"Application already {app.status}."
        )

    rest_id = (data.rest_id or "").strip()
    if not rest_id:
        raise HTTPException(
            status_code=400,
            detail="Petpooja rest_id is required to connect sales sync.",
        )
    if db.query(Outlet).filter(Outlet.rest_id == rest_id).first():
        raise HTTPException(
            status_code=409, detail="An outlet with this rest_id already exists."
        )
    if db.query(Manager).filter(Manager.email == app.owner_email).first():
        raise HTTPException(
            status_code=409,
            detail="An account with this email already exists. Use a different email.",
        )

    # 1. Create the outlet (joins the court + cron sync immediately)
    outlet = Outlet(
        court_id=app.court_id,
        vendor_name=app.outlet_name,
        rest_id=rest_id,
        is_active=1,
        pp_app_key=(data.pp_app_key or None),
        pp_app_secret=(data.pp_app_secret or None),
        pp_access_token=(data.pp_access_token or None),
        pp_cookie=(data.pp_cookie or None),
    )
    db.add(outlet)
    db.flush()  # get outlet.id

    # 2. Create the outlet-manager login (pending password — unusable until set)
    manager = Manager(
        name=app.owner_name,
        email=app.owner_email,
        hashed_password=hash_password(secrets.token_urlsafe(24)),
        role="outlet_manager",
        outlet_id=outlet.id,
        is_active=True,
    )
    db.add(manager)
    db.flush()

    app.status = "approved"
    app.created_outlet_id = outlet.id
    app.reviewed_at = datetime.utcnow()
    db.commit()
    db.refresh(outlet)
    db.refresh(manager)

    # 3. Set-password magic link
    token = create_token(
        {"sub": manager.email, "purpose": "set_password", "mid": manager.id},
        _SET_PW_EXPIRY_MIN,
    )
    base = (settings.PUBLIC_BASE_URL or "").rstrip("/")
    link = f"{base}/auth/set-password?token={token}"

    # 4. Email the owner (graceful fallback if Resend not configured)
    email_sent = await send_email(
        to=manager.email,
        subject="Welcome to ETL — set your password",
        html=_set_password_email_html(manager.name, app.outlet_name, link),
    )

    msg = (
        "Outlet approved. Welcome email sent."
        if email_sent
        else "Outlet approved. Email not sent (share the link with the owner manually)."
    )
    return ApproveResponse(
        outlet_id=outlet.id,
        manager_email=manager.email,
        set_password_link=link,
        email_sent=email_sent,
        message=msg,
    )


@router.post("/applications/{application_id}/reject")
def reject_application(
    application_id: int,
    data: RejectRequest,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    _require_etl_manager(user)
    app = db.query(OutletApplication).filter(
        OutletApplication.id == application_id
    ).first()
    if not app:
        raise HTTPException(status_code=404, detail="Application not found.")
    if app.status != "pending":
        raise HTTPException(
            status_code=409, detail=f"Application already {app.status}."
        )
    app.status = "rejected"
    app.rejection_reason = (data.reason or "").strip() or None
    app.reviewed_at = datetime.utcnow()
    db.commit()
    return {"message": "Application rejected."}


# ─── Email body ──────────────────────────────────────────────────────────────

def _set_password_email_html(owner_name: str, outlet_name: str, link: str) -> str:
    return f"""
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto;">
      <h2 style="color:#0A0A0A;">Welcome to ETL Food Court 🎉</h2>
      <p>Hi {owner_name},</p>
      <p>Your outlet <b>{outlet_name}</b> has been approved and onboarded.
         To access your Outlet Manager app, please set your password using the
         button below.</p>
      <p style="text-align:center; margin: 28px 0;">
        <a href="{link}"
           style="background:#D02128; color:#fff; padding:12px 28px;
                  border-radius:8px; text-decoration:none; font-weight:bold;">
           Set My Password
        </a>
      </p>
      <p style="color:#888; font-size:13px;">This link is valid for 7 days. If
         the button doesn't work, copy and paste this URL:</p>
      <p style="color:#888; font-size:12px; word-break:break-all;">{link}</p>
    </div>
    """
