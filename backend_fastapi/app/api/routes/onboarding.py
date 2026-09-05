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
from typing import Optional, List

from fastapi import (
    APIRouter, Depends, HTTPException, Request, Form, File, UploadFile, Query,
)
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from sqlalchemy import func

from ...database import get_db
from ...models.sale import Court, Outlet
from ...models.manager import Manager
from ...models.onboarding import OutletApplication
from ...models.outlet_membership import OutletMembership, MEMBERSHIP_OWNER
from ...schemas.onboarding import (
    ApplicationOut, ApplicationListResponse, ApproveRequest, ApproveResponse,
    RejectRequest, OutletWithDocs,
)
from ...core.config import settings
from ...core.security import create_token, hash_password
from ...services.email_service import send_email
from ...services.notice_service import create_notice
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

    # Guard against DUPLICATE submissions (double-click / resubmit-on-refresh,
    # which previously created two identical `pending` rows). If an identical
    # application is already pending for this court+owner+outlet, don't create a
    # second one — just re-show the success page (idempotent from the owner's POV).
    dup = (
        db.query(OutletApplication)
        .filter(
            OutletApplication.court_id == court.id,
            func.lower(OutletApplication.owner_email) == owner_email,
            func.lower(OutletApplication.outlet_name) == outlet_name.lower(),
            OutletApplication.status == "pending",
        )
        .first()
    )
    if dup:
        return templates.TemplateResponse(
            request=request,
            name="onboarding_success.html",
            context={"request": request, "outlet_name": outlet_name, "court_name": court.name},
        )

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
    db.refresh(application)

    # Trigger #17 — a vendor just applied. Until now this produced NO signal at
    # all: the ETL manager only found out by opening the app and noticing
    # `pending_count` had gone up. Goes to the ETL manager tier only
    # (outlet_id=None) — the applicant has no account yet.
    try:
        create_notice(
            db,
            audience="manager",
            type="onboarding_submitted",
            title="New outlet application",
            body=(
                f"{owner_name} applied to open “{outlet_name}” at {court.name}. "
                f"Review the documents to approve or reject."
            ),
            court_id=court.id,
            outlet_id=None,
        )
    except Exception as e:  # noqa: BLE001 — never break the public form
        logger.warning("submit notice failed for #%s: %s", application.id, e)

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
    # MULTI-OUTLET: an existing account with this email is NO LONGER an error.
    # The same owner can run outlets across several courts under ONE login, so
    # we LINK the new outlet to their existing account instead of rejecting it.
    existing_owner = db.query(Manager).filter(Manager.email == app.owner_email).first()
    if existing_owner and existing_owner.role != "outlet_manager":
        # Collision with an ETL manager / other account — refuse to link.
        raise HTTPException(
            status_code=409,
            detail="That email belongs to a non-outlet account. Use a different email.",
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
        pos_source=((data.pos_source or "").strip() or "petpooja_generic"),
    )
    db.add(outlet)
    db.flush()  # get outlet.id

    # ─── Path A: EXISTING **ACTIVE** owner → link the new outlet, no new login ─
    # Only a still-ACTIVE owner is a genuine multi-outlet owner. An INACTIVE row
    # here is a LEFTOVER from a previously-deleted outlet — delete_outlet
    # deactivates the now-membershipless owner (is_active=False) instead of
    # deleting the row (email is unique, and we keep it for history). Such a
    # leftover must NOT be silently linked as a phantom "second outlet"; it is
    # handled as a FRESH onboarding below (reactivated + given a set-password
    # link), exactly like a brand-new owner.
    if existing_owner and existing_owner.is_active:
        db.add(OutletMembership(
            manager_id=existing_owner.id,
            outlet_id=outlet.id,
            membership_role=MEMBERSHIP_OWNER,
        ))
        app.status = "approved"
        app.created_outlet_id = outlet.id
        app.reviewed_at = datetime.utcnow()
        db.commit()
        db.refresh(outlet)

        # Durable notice + push to the owner (targeted to the new outlet, which
        # they now own) telling them it's available in the outlet switcher.
        try:
            create_notice(
                db,
                audience="manager",
                type="outlet_added",
                title="New outlet added to your account",
                body=(
                    f"“{app.outlet_name}” has been added to your account. Open the "
                    f"app and switch outlets to manage it."
                ),
                court_id=None,
                outlet_id=outlet.id,
            )
        except Exception as e:  # noqa: BLE001 — never fail approval on a notice
            logger.warning("outlet-added notice failed for outlet %s: %s", outlet.id, e)

        email_sent = await send_email(
            to=existing_owner.email,
            subject="A new outlet was added to your ETL account",
            html=_outlet_added_email_html(existing_owner.name, app.outlet_name),
        )
        return ApproveResponse(
            outlet_id=outlet.id,
            manager_email=existing_owner.email,
            set_password_link=None,  # existing account — no password to set
            email_sent=email_sent,
            message="Outlet approved and linked to the existing owner account.",
        )

    # ─── Path B: BRAND-NEW owner (or a REACTIVATED leftover) → login + set-pw ─
    # 2. Create — or REUSE — the outlet-manager login (pending password, unusable
    #    until set). If `existing_owner` reached here it is a deactivated leftover
    #    from a deleted outlet: since email is unique we must REUSE that row
    #    rather than insert a duplicate — reactivate it, refresh its details, and
    #    reset it to a pending password so the owner goes through the normal
    #    set-password flow just like a first-time onboarding.
    if existing_owner:
        manager = existing_owner
        manager.name = app.owner_name
        manager.role = "outlet_manager"
        manager.hashed_password = hash_password(secrets.token_urlsafe(24))
        manager.outlet_id = outlet.id  # primary/default outlet
        manager.is_active = True
    else:
        manager = Manager(
            name=app.owner_name,
            email=app.owner_email,
            hashed_password=hash_password(secrets.token_urlsafe(24)),
            role="outlet_manager",
            outlet_id=outlet.id,  # primary/default outlet
            is_active=True,
        )
        db.add(manager)
    db.flush()

    # Owner membership — the source of truth for what this account can access.
    db.add(OutletMembership(
        manager_id=manager.id,
        outlet_id=outlet.id,
        membership_role=MEMBERSHIP_OWNER,
    ))

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
async def reject_application(
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

    # Trigger #18 — tell the applicant. They have no account (and therefore no
    # device token), so EMAIL is the only channel that can reach them. Until now
    # a rejected applicant was simply never told anything.
    email_sent = False
    if app.owner_email:
        try:
            email_sent = await send_email(
                to=app.owner_email,
                subject=f"Update on your application for {app.outlet_name}",
                html=_rejection_email_html(
                    app.owner_name, app.outlet_name, app.rejection_reason
                ),
            )
        except Exception as e:  # noqa: BLE001 — rejection must still succeed
            logger.warning("rejection email failed for #%s: %s", app.id, e)

    return {"message": "Application rejected.", "email_sent": email_sent}


# ─── ETL MANAGER: outlets of a court (with onboarding documents) ─────────────

@router.get("/outlets", response_model=List[OutletWithDocs])
def list_court_outlets(
    court_id: int = Query(...),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Active outlets in a court, each enriched with the documents/owner info
    from its approved onboarding application (if it was onboarded that way)."""
    _require_etl_manager(user)

    outlets = (
        db.query(Outlet)
        .filter(Outlet.court_id == court_id, Outlet.is_active == 1)
        .order_by(Outlet.vendor_name)
        .all()
    )
    apps = (
        db.query(OutletApplication)
        .filter(OutletApplication.created_outlet_id.isnot(None))
        .all()
    )
    by_outlet = {a.created_outlet_id: a for a in apps}

    result = []
    for o in outlets:
        a = by_outlet.get(o.id)
        result.append(OutletWithDocs(
            outlet_id=o.id,
            court_id=o.court_id,
            vendor_name=o.vendor_name,
            rest_id=o.rest_id,
            owner_name=a.owner_name if a else None,
            owner_email=a.owner_email if a else None,
            owner_phone=a.owner_phone if a else None,
            gst_url=a.gst_url if a else None,
            fssai_url=a.fssai_url if a else None,
            term_sheet_url=a.term_sheet_url if a else None,
            agreement_url=a.agreement_url if a else None,
            has_petpooja_creds=bool(o.pp_app_key),
            application_id=a.id if a else None,
        ))
    return result


# ─── Email bodies ────────────────────────────────────────────────────────────

def _rejection_email_html(
    owner_name: Optional[str],
    outlet_name: Optional[str],
    reason: Optional[str],
) -> str:
    """Rejection notice for an applicant.

    The applicant has no account and no device, so email is the only channel
    that can reach them — hence this exists alongside the push triggers.
    """
    reason_block = (
        f"""
      <div style="background:#FAFAFA; border-left:3px solid #D02128;
                  padding:12px 16px; margin:20px 0;">
        <p style="margin:0; color:#333; font-size:14px;"><b>Reason:</b> {reason}</p>
      </div>"""
        if reason
        else ""
    )
    return f"""
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto;">
      <h2 style="color:#0A0A0A;">Update on your application</h2>
      <p>Hi {owner_name or 'there'},</p>
      <p>Thank you for your interest in opening <b>{outlet_name or 'an outlet'}</b>
         with ETL Food Court.</p>
      <p>After reviewing your application, we are not able to move forward with
         it at this time.</p>
      {reason_block}
      <p>You are welcome to apply again with updated details. If you believe
         something was missed, simply reply to this email and we will take
         another look.</p>
      <p style="color:#888; font-size:13px; margin-top:28px;">— ETL Food Court Team</p>
    </div>
    """


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



def _outlet_added_email_html(owner_name: str, outlet_name: str) -> str:
    """Sent when a NEW outlet is linked to an EXISTING owner account.

    No set-password link here — the owner already has a working login. They
    just open the app and switch to the new outlet from the outlet switcher.
    """
    return f"""
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto;">
      <h2 style="color:#0A0A0A;">A new outlet was added 🎉</h2>
      <p>Hi {owner_name or 'there'},</p>
      <p><b>{outlet_name}</b> has been approved and linked to your existing ETL
         account. You don't need a new login — just open the ETL Manager app and
         use the <b>outlet switcher</b> at the top to select it.</p>
      <p style="color:#888; font-size:13px; margin-top:28px;">— ETL Food Court Team</p>
    </div>
    """
