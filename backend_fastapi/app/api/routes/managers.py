# backend_fastapi/app/api/routes/managers.py
#
# ETL-manager account administration.
#
# ETL managers have full, unrestricted access to the app (they oversee every
# court/outlet), and there can be MANY of them. This router lets an existing
# ETL manager create additional ETL-manager logins from inside the app, list
# them, and revoke/restore their access — without ever handling a password
# directly. New accounts are activated through the same set-password magic-link
# flow used by outlet onboarding, so the creator never sees or sets the
# password.
#
# SECURITY: every endpoint requires an authenticated ETL manager
# (require_etl_manager). Nothing here is reachable by outlet users or staff.

import logging
import secrets

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr
from sqlalchemy import func
from sqlalchemy.orm import Session

from ...core.config import settings
from ...core.security import create_token, hash_password
from ...database import get_db
from ...models.manager import Manager
from ...models.staff import Staff
from ...services.email_service import send_email
from ..deps import CurrentUser, require_etl_manager

logger = logging.getLogger("managers")
router = APIRouter()

# Set-password link valid for 7 days — same as outlet onboarding.
_SET_PW_EXPIRY_MIN = 60 * 24 * 7

# The canonical role for a full-access ETL manager. Legacy accounts may carry
# the bare "manager" value, which CurrentUser.is_etl_manager also treats as an
# ETL manager; new accounts are always created with this explicit value.
_ETL_ROLE = "etl_manager"
_ETL_ROLES = ("etl_manager", "manager")


# ─── Schemas ─────────────────────────────────────────────────────────────────

class EtlManagerOut(BaseModel):
    manager_id: int
    name: str
    email: str
    is_active: bool
    is_self: bool = False  # true for the row representing the caller


class CreateEtlManagerRequest(BaseModel):
    name: str
    email: EmailStr


class CreateEtlManagerResponse(BaseModel):
    manager_id: int
    email: str
    set_password_link: str | None = None
    email_sent: bool = False
    message: str


# ─── Email body ──────────────────────────────────────────────────────────────

def _welcome_email_html(name: str, link: str) -> str:
    return f"""
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto;">
      <h2 style="color:#0A0A0A;">Welcome to the <span style="color:#D02128;">ETL</span> manager team 🎉</h2>
      <p>Hi {name},</p>
      <p>You've been given an <b>ETL Manager</b> account, with full access to the
         ETL Manager app. To get started, set your password using the button
         below.</p>
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


# ─── Endpoints ───────────────────────────────────────────────────────────────

@router.get("/etl-managers", response_model=list[EtlManagerOut])
def list_etl_managers(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_etl_manager),
):
    """All ETL-manager accounts (active first, then by name). No secrets."""
    rows = (
        db.query(Manager)
        .filter(Manager.role.in_(_ETL_ROLES))
        .order_by(Manager.is_active.desc(), func.lower(Manager.name))
        .all()
    )
    return [
        EtlManagerOut(
            manager_id=m.id,
            name=m.name,
            email=m.email,
            is_active=bool(m.is_active),
            is_self=(m.id == user.id and user.is_manager_account),
        )
        for m in rows
    ]


@router.post("/etl-managers", response_model=CreateEtlManagerResponse)
async def create_etl_manager(
    req: CreateEtlManagerRequest,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_etl_manager),
):
    """Create a new ETL-manager login and email them a set-password link.

    The account is created with an unusable random password; it only becomes
    usable once the invitee sets their own password via the emailed link, so
    the creator never handles the password.
    """
    name = (req.name or "").strip()
    email = str(req.email or "").strip().lower()
    if not name:
        raise HTTPException(status_code=400, detail="Name is required.")
    if not email:
        raise HTTPException(status_code=400, detail="Email is required.")

    # Login resolves against BOTH managers and staff, so an email that already
    # exists in either table would be ambiguous — reject it.
    if db.query(Manager).filter(func.lower(Manager.email) == email).first():
        raise HTTPException(
            status_code=409, detail="An account with this email already exists."
        )
    if db.query(Staff).filter(func.lower(Staff.email) == email).first():
        raise HTTPException(
            status_code=409,
            detail="This email is already used by a staff account.",
        )

    manager = Manager(
        name=name,
        email=email,
        hashed_password=hash_password(secrets.token_urlsafe(24)),
        role=_ETL_ROLE,
        outlet_id=None,  # ETL managers are not tied to an outlet
        is_active=True,
    )
    db.add(manager)
    db.commit()
    db.refresh(manager)

    # Set-password magic link — same purpose-scoped token the onboarding flow
    # and /auth/set-password use (validated by mid + email).
    token = create_token(
        {"sub": manager.email, "purpose": "set_password", "mid": manager.id},
        _SET_PW_EXPIRY_MIN,
    )
    base = (settings.PUBLIC_BASE_URL or "").rstrip("/")
    link = f"{base}/auth/set-password?token={token}"

    email_sent = await send_email(
        to=manager.email,
        subject="You've been added as an ETL Manager — set your password",
        html=_welcome_email_html(manager.name, link),
    )
    message = (
        "ETL manager created. Set-password email sent."
        if email_sent
        else "ETL manager created. Email not sent — share the link with them manually."
    )
    return CreateEtlManagerResponse(
        manager_id=manager.id,
        email=manager.email,
        set_password_link=link,
        email_sent=email_sent,
        message=message,
    )


def _get_etl_manager_or_404(db: Session, manager_id: int) -> Manager:
    m = (
        db.query(Manager)
        .filter(Manager.id == manager_id, Manager.role.in_(_ETL_ROLES))
        .first()
    )
    if not m:
        raise HTTPException(status_code=404, detail="ETL manager not found.")
    return m


@router.patch("/etl-managers/{manager_id}/deactivate", response_model=EtlManagerOut)
def deactivate_etl_manager(
    manager_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_etl_manager),
):
    """Revoke an ETL manager's access. Guardrails prevent locking everyone out."""
    if user.is_manager_account and manager_id == user.id:
        raise HTTPException(
            status_code=400, detail="You cannot deactivate your own account."
        )

    target = _get_etl_manager_or_404(db, manager_id)

    if not target.is_active:
        # Already inactive — nothing to do, return current state.
        return EtlManagerOut(
            manager_id=target.id, name=target.name, email=target.email,
            is_active=False,
        )

    active_count = (
        db.query(Manager)
        .filter(Manager.role.in_(_ETL_ROLES), Manager.is_active == True)  # noqa: E712
        .count()
    )
    if active_count <= 1:
        raise HTTPException(
            status_code=400,
            detail="Cannot deactivate the last active ETL manager.",
        )

    target.is_active = False
    db.commit()
    db.refresh(target)
    return EtlManagerOut(
        manager_id=target.id, name=target.name, email=target.email,
        is_active=False,
    )


@router.patch("/etl-managers/{manager_id}/reactivate", response_model=EtlManagerOut)
def reactivate_etl_manager(
    manager_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_etl_manager),
):
    """Restore a previously-deactivated ETL manager's access."""
    target = _get_etl_manager_or_404(db, manager_id)
    target.is_active = True
    db.commit()
    db.refresh(target)
    return EtlManagerOut(
        manager_id=target.id, name=target.name, email=target.email,
        is_active=True,
    )
