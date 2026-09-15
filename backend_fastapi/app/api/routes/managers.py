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
from ...models.sale import Court
from ...services.email_service import send_email
from ...services.push_targeting import deactivate_tokens_for_user
from ..deps import (
    CurrentUser, require_etl_manager, require_management,
    MANAGEMENT_ROLES, MAINTENANCE_ROLES,
)

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



# ══════════════════════════════════════════════════════════════════════════════
# ROLE SPLIT — generalised account administration (Phase 2)
#
# Lets a MANAGEMENT account (Azimuth Management / Crownest Ops Head / Crownest
# Head) create + manage every ETL-side role. The three management roles live in
# `managers`; the two maintenance roles live in `staff` (so Crownest Maintenance
# Head reuses attendance/roster). Maintenance accounts are NEVER self-serviceable
# — only a management account can create them.
#
# Activation reuses the same set-password magic-link as the legacy manager flow,
# now extended to staff-table accounts in /auth/set-password (utype claim).
# ══════════════════════════════════════════════════════════════════════════════

# The roles this admin surface can create, and which table each lives in.
_CREATABLE_ROLES = {
    "azimuth_management":        "manager",
    "crownest_ops_head":         "manager",
    "crownest_head":             "manager",
    "azimuth_maintenance":       "staff",
    "crownest_maintenance_head": "staff",
}
_ROLE_LABELS = {
    "azimuth_management":        "Azimuth Management",
    "crownest_ops_head":         "Crownest Ops Head",
    "crownest_head":             "Crownest Head",
    "azimuth_maintenance":       "Azimuth Maintenance",
    "crownest_maintenance_head": "Crownest Maintenance Head",
    # Legacy — shown in listings so existing accounts are visible/manageable.
    "etl_manager":               "ETL Manager (legacy)",
    "manager":                   "ETL Manager (legacy)",
}
_ORG_BY_ROLE = {
    "azimuth_management":        "azimuth",
    "azimuth_maintenance":       "azimuth",
    "crownest_ops_head":         "crownest",
    "crownest_head":             "crownest",
    "crownest_maintenance_head": "crownest",
}


class CreateAccountRequest(BaseModel):
    name: str
    email: EmailStr
    role: str
    # Zone (court) — REQUIRED for crownest_maintenance_head (drives their
    # attendance geofence + roster); ignored for every other role.
    court_id: int | None = None


class CreateAccountResponse(BaseModel):
    kind: str            # "manager" | "staff"
    account_id: int
    email: str
    role: str
    set_password_link: str | None = None
    email_sent: bool = False
    message: str


class AccountOut(BaseModel):
    kind: str            # "manager" | "staff"
    account_id: int
    name: str
    email: str
    role: str
    role_label: str
    org: str | None = None
    zone_court_id: int | None = None
    zone_name: str | None = None
    is_active: bool
    is_self: bool = False


def _role_welcome_email_html(name: str, role_label: str, link: str) -> str:
    return f"""
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto;">
      <h2 style="color:#0A0A0A;">Welcome to <span style="color:#D02128;">ETL</span> 🎉</h2>
      <p>Hi {name},</p>
      <p>You've been given a <b>{role_label}</b> account on the ETL Manager app.
         To get started, set your password using the button below.</p>
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


@router.post("/accounts", response_model=CreateAccountResponse)
async def create_account(
    req: CreateAccountRequest,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_management),
):
    """Create ANY ETL-side role account and email a set-password link.

    Management-only. The role decides the table (managers vs staff). The account
    is created with an unusable random password + is_active=True; it becomes
    usable only once the invitee sets their own password via the emailed link,
    so the creator never handles a password.
    """
    name = (req.name or "").strip()
    email = str(req.email or "").strip().lower()
    role = (req.role or "").strip()

    if not name:
        raise HTTPException(status_code=400, detail="Name is required.")
    if role not in _CREATABLE_ROLES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid role. Allowed: {sorted(_CREATABLE_ROLES)}",
        )

    # Email must be unique across BOTH tables (login resolves against both).
    if db.query(Manager).filter(func.lower(Manager.email) == email).first():
        raise HTTPException(status_code=409, detail="An account with this email already exists.")
    if db.query(Staff).filter(func.lower(Staff.email) == email).first():
        raise HTTPException(status_code=409, detail="An account with this email already exists.")

    kind = _CREATABLE_ROLES[role]
    org = _ORG_BY_ROLE.get(role)
    random_pw = hash_password(secrets.token_urlsafe(24))

    # Zone handling: only crownest_maintenance_head takes a court (its attendance
    # geofence + roster grouping). Required for that role, forbidden for others.
    court_id = None
    if role == "crownest_maintenance_head":
        if req.court_id is None:
            raise HTTPException(status_code=400, detail="A zone (court) is required for a Maintenance Head.")
        court = db.query(Court).filter(Court.id == req.court_id, Court.is_active == 1).first()
        if not court:
            raise HTTPException(status_code=404, detail="Selected zone (court) not found.")
        court_id = court.id

    if kind == "manager":
        acct = Manager(
            name=name, email=email, hashed_password=random_pw,
            role=role, org=org, outlet_id=None, is_active=True,
        )
        db.add(acct); db.commit(); db.refresh(acct)
        token = create_token(
            {"sub": acct.email, "purpose": "set_password", "mid": acct.id},
            _SET_PW_EXPIRY_MIN,
        )
    else:  # staff
        acct = Staff(
            name=name, email=email, hashed_password=random_pw,
            role=role, org=org, court_id=court_id, outlet_id=None, is_active=True,
        )
        db.add(acct); db.commit(); db.refresh(acct)
        token = create_token(
            {"sub": acct.email, "purpose": "set_password", "utype": "staff", "uid": acct.id},
            _SET_PW_EXPIRY_MIN,
        )

    base = (settings.PUBLIC_BASE_URL or "").rstrip("/")
    link = f"{base}/auth/set-password?token={token}"
    email_sent = await send_email(
        to=acct.email,
        subject=f"You've been added as {_ROLE_LABELS.get(role, role)} — set your password",
        html=_role_welcome_email_html(name, _ROLE_LABELS.get(role, role), link),
    )
    return CreateAccountResponse(
        kind=kind,
        account_id=acct.id,
        email=acct.email,
        role=role,
        set_password_link=link,
        email_sent=email_sent,
        message=(
            "Account created. Set-password email sent."
            if email_sent
            else "Account created. Email not sent — share the link with them manually."
        ),
    )


@router.get("/accounts", response_model=list[AccountOut])
def list_accounts(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_management),
):
    """Every ETL-side account: management (managers) + maintenance (staff).
    Outlet managers/staff and court/etl_staff are intentionally NOT listed here
    (this surface is for the ETL org roles only)."""
    out: list[AccountOut] = []

    mgrs = (
        db.query(Manager)
        .filter(Manager.role.in_(tuple(MANAGEMENT_ROLES)))
        .order_by(Manager.is_active.desc(), func.lower(Manager.name))
        .all()
    )
    for m in mgrs:
        out.append(AccountOut(
            kind="manager", account_id=m.id, name=m.name, email=m.email,
            role=m.role, role_label=_ROLE_LABELS.get(m.role, m.role),
            org=getattr(m, "org", None),
            is_active=bool(m.is_active),
            is_self=(user.is_manager_account and m.id == user.id),
        ))

    maint = (
        db.query(Staff)
        .filter(Staff.role.in_(tuple(MAINTENANCE_ROLES)))
        .order_by(Staff.is_active.desc(), func.lower(Staff.name))
        .all()
    )
    court_names = {c.id: c.name for c in db.query(Court.id, Court.name).all()}
    for s in maint:
        out.append(AccountOut(
            kind="staff", account_id=s.id, name=s.name, email=s.email,
            role=s.role, role_label=_ROLE_LABELS.get(s.role, s.role),
            org=getattr(s, "org", None),
            zone_court_id=s.court_id,
            zone_name=court_names.get(s.court_id),
            is_active=bool(s.is_active),
            is_self=(user.is_staff_account and s.id == user.id),
        ))
    return out


def _active_management_count(db: Session) -> int:
    return (
        db.query(Manager)
        .filter(Manager.role.in_(tuple(MANAGEMENT_ROLES)), Manager.is_active == True)  # noqa: E712
        .count()
    )


@router.patch("/accounts/{kind}/{account_id}/deactivate", response_model=AccountOut)
def deactivate_account(
    kind: str,
    account_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_management),
):
    """Revoke an ETL-side account's access. Guardrails: can't deactivate self,
    and can't remove the last active management account (lock-out safety)."""
    if kind not in ("manager", "staff"):
        raise HTTPException(status_code=400, detail="Unknown account kind.")

    if kind == "manager":
        target = db.query(Manager).filter(
            Manager.id == account_id, Manager.role.in_(tuple(MANAGEMENT_ROLES))
        ).first()
        if not target:
            raise HTTPException(status_code=404, detail="Management account not found.")
        if user.is_manager_account and target.id == user.id:
            raise HTTPException(status_code=400, detail="You cannot deactivate your own account.")
        if target.is_active and _active_management_count(db) <= 1:
            raise HTTPException(status_code=400, detail="Cannot deactivate the last active management account.")
        target.is_active = False
        db.commit(); db.refresh(target)
        _safe_kill_tokens(db, "manager", target.id)
        return AccountOut(
            kind="manager", account_id=target.id, name=target.name, email=target.email,
            role=target.role, role_label=_ROLE_LABELS.get(target.role, target.role),
            org=getattr(target, "org", None), is_active=False,
        )
    else:
        target = db.query(Staff).filter(
            Staff.id == account_id, Staff.role.in_(tuple(MAINTENANCE_ROLES))
        ).first()
        if not target:
            raise HTTPException(status_code=404, detail="Maintenance account not found.")
        if user.is_staff_account and target.id == user.id:
            raise HTTPException(status_code=400, detail="You cannot deactivate your own account.")
        target.is_active = False
        db.commit(); db.refresh(target)
        _safe_kill_tokens(db, "staff", target.id)
        court_names = {c.id: c.name for c in db.query(Court.id, Court.name).all()}
        return AccountOut(
            kind="staff", account_id=target.id, name=target.name, email=target.email,
            role=target.role, role_label=_ROLE_LABELS.get(target.role, target.role),
            org=getattr(target, "org", None), zone_court_id=target.court_id,
            zone_name=court_names.get(target.court_id), is_active=False,
        )


@router.patch("/accounts/{kind}/{account_id}/reactivate", response_model=AccountOut)
def reactivate_account(
    kind: str,
    account_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_management),
):
    """Restore a previously-deactivated ETL-side account."""
    if kind not in ("manager", "staff"):
        raise HTTPException(status_code=400, detail="Unknown account kind.")
    if kind == "manager":
        target = db.query(Manager).filter(
            Manager.id == account_id, Manager.role.in_(tuple(MANAGEMENT_ROLES))
        ).first()
        if not target:
            raise HTTPException(status_code=404, detail="Management account not found.")
        target.is_active = True
        db.commit(); db.refresh(target)
        return AccountOut(
            kind="manager", account_id=target.id, name=target.name, email=target.email,
            role=target.role, role_label=_ROLE_LABELS.get(target.role, target.role),
            org=getattr(target, "org", None), is_active=True,
        )
    else:
        target = db.query(Staff).filter(
            Staff.id == account_id, Staff.role.in_(tuple(MAINTENANCE_ROLES))
        ).first()
        if not target:
            raise HTTPException(status_code=404, detail="Maintenance account not found.")
        target.is_active = True
        db.commit(); db.refresh(target)
        court_names = {c.id: c.name for c in db.query(Court.id, Court.name).all()}
        return AccountOut(
            kind="staff", account_id=target.id, name=target.name, email=target.email,
            role=target.role, role_label=_ROLE_LABELS.get(target.role, target.role),
            org=getattr(target, "org", None), zone_court_id=target.court_id,
            zone_name=court_names.get(target.court_id), is_active=True,
        )


def _safe_kill_tokens(db: Session, user_type: str, user_id: int) -> None:
    """Soft-disable a revoked account's push tokens. Never breaks the request."""
    try:
        deactivate_tokens_for_user(db, user_type=user_type, user_id=user_id)
        db.commit()
    except Exception as e:  # noqa: BLE001
        db.rollback()
        logger.warning("token cleanup failed for %s#%s: %s", user_type, user_id, e)
