# backend_fastapi/app/api/routes/outlets.py
#
# Multi-outlet ownership endpoints:
#   • GET    /outlets/mine                        → the outlets the caller can
#                                                    access (powers the app's
#                                                    outlet switcher).
#   • GET    /outlets/{id}/managers               → who has access to an outlet.
#   • POST   /outlets/{id}/managers               → owner assigns a co-manager.
#   • DELETE /outlets/{id}/managers/{manager_id}  → owner revokes a co-manager.
#
# ACCESS MODEL (decided with the team):
#   owner   → full access to the outlet AND may add/remove co-managers.
#   manager → view/operate the outlet, but CANNOT manage access.
# Only an owner (or an ETL manager) may call the manage-access endpoints.

import secrets
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Path
from pydantic import BaseModel, Field
from sqlalchemy import text, inspect
from sqlalchemy.orm import Session

from ...database import get_db
from ...core.config import settings
from ...core.security import create_token, hash_password
from ...models.manager import Manager
from ...models.staff import Staff
from ...models.sale import Outlet, Court
from ...models.onboarding import OutletApplication
from ...models.outlet_membership import (
    OutletMembership,
    MEMBERSHIP_OWNER,
    MEMBERSHIP_MANAGER,
)
from ...services.email_service import send_email
from ..deps import get_current_user, require_etl_manager, CurrentUser

router = APIRouter()

# Set-password link validity for an invited co-manager (7 days), matching
# onboarding.
_SET_PW_EXPIRY_MIN = 60 * 24 * 7


# ─── Schemas ──────────────────────────────────────────────────────────────────

class MyOutlet(BaseModel):
    outlet_id: int
    vendor_name: str
    court_id: int
    court_name: str
    membership_role: str  # "owner" | "manager"


class OutletManagerOut(BaseModel):
    manager_id: int
    name: str
    email: str
    membership_role: str
    is_active: bool


class AddManagerRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    email: str = Field(..., min_length=3, max_length=200)


class AddManagerResponse(BaseModel):
    manager_id: int
    email: str
    membership_role: str
    set_password_link: Optional[str] = None
    email_sent: bool
    message: str


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _require_outlet_owner(db: Session, user: CurrentUser, outlet_id: int) -> None:
    """Only an OWNER of this outlet (or an ETL manager) may manage its access."""
    if user.is_etl_manager:
        return
    if user.user_type != "manager":
        raise HTTPException(status_code=403, detail="Only the outlet owner can manage access.")
    owns = (
        db.query(OutletMembership)
        .filter(
            OutletMembership.manager_id == user.id,
            OutletMembership.outlet_id == outlet_id,
            OutletMembership.membership_role == MEMBERSHIP_OWNER,
        )
        .first()
    )
    if not owns:
        raise HTTPException(status_code=403, detail="Only the outlet owner can manage access.")


def _add_manager_email_html(name: str, outlet_name: str, link: Optional[str]) -> str:
    if link:
        cta = f"""
        <p style="text-align:center; margin: 28px 0;">
          <a href="{link}" style="background:#0A0A0A; color:#fff; padding:12px 28px;
             border-radius:8px; text-decoration:none; font-weight:bold;">Set My Password</a>
        </p>
        <p style="color:#888; font-size:12px; word-break:break-all;">{link}</p>"""
    else:
        cta = ("<p>Use your existing ETL login — the new outlet will appear in "
               "the outlet switcher at the top of the app.</p>")
    return f"""
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto;">
      <h2 style="color:#0A0A0A;">You've been given outlet access</h2>
      <p>Hi {name or 'there'},</p>
      <p>You now have manager access to <b>{outlet_name}</b> on ETL.</p>
      {cta}
      <p style="color:#888; font-size:13px; margin-top:28px;">— ETL Food Court Team</p>
    </div>
    """


# ─── Endpoints ──────────────────────────────────────────────────────────────

@router.get("/mine", response_model=List[MyOutlet])
def my_outlets(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Outlets the caller can access — powers the app's outlet switcher.

    Only outlet managers have memberships; ETL managers/staff get an empty list
    (they don't use the switcher)."""
    if user.user_type != "manager" or user.role != "outlet_manager":
        return []
    rows = (
        db.query(OutletMembership, Outlet, Court)
        .join(Outlet, Outlet.id == OutletMembership.outlet_id)
        .join(Court, Court.id == Outlet.court_id)
        .filter(
            OutletMembership.manager_id == user.id,
            Outlet.is_active == 1,
        )
        .order_by(Court.name, Outlet.vendor_name)
        .all()
    )
    return [
        MyOutlet(
            outlet_id=o.id,
            vendor_name=o.vendor_name,
            court_id=o.court_id,
            court_name=c.name,
            membership_role=m.membership_role,
        )
        for (m, o, c) in rows
    ]


@router.get("/{outlet_id}/managers", response_model=List[OutletManagerOut])
def list_outlet_managers(
    outlet_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    _require_outlet_owner(db, user, outlet_id)
    rows = (
        db.query(OutletMembership, Manager)
        .join(Manager, Manager.id == OutletMembership.manager_id)
        .filter(OutletMembership.outlet_id == outlet_id)
        .order_by(OutletMembership.membership_role, Manager.name)
        .all()
    )
    return [
        OutletManagerOut(
            manager_id=mgr.id,
            name=mgr.name,
            email=mgr.email,
            membership_role=mem.membership_role,
            is_active=bool(mgr.is_active),
        )
        for (mem, mgr) in rows
    ]


@router.post("/{outlet_id}/managers", response_model=AddManagerResponse, status_code=201)
async def add_outlet_manager(
    body: AddManagerRequest,
    outlet_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Owner assigns a LIMITED co-manager to this outlet.

    New email → creates a login + sends a set-password link. Existing outlet
    account → simply linked (no new password). The co-manager gets
    `membership_role='manager'` and therefore cannot manage access themselves.
    """
    _require_outlet_owner(db, user, outlet_id)

    outlet = db.query(Outlet).filter(Outlet.id == outlet_id, Outlet.is_active == 1).first()
    if not outlet:
        raise HTTPException(status_code=404, detail="Outlet not found or inactive.")

    name = body.name.strip()
    email = body.email.strip().lower()
    if not name or "@" not in email or "." not in email.split("@")[-1]:
        raise HTTPException(status_code=400, detail="Valid name and email are required.")

    existing = db.query(Manager).filter(Manager.email == email).first()
    if existing and existing.role != "outlet_manager":
        raise HTTPException(
            status_code=409,
            detail="That email belongs to a non-outlet account. Use a different email.",
        )

    # Already linked to this outlet?
    if existing:
        dup = (
            db.query(OutletMembership)
            .filter(
                OutletMembership.manager_id == existing.id,
                OutletMembership.outlet_id == outlet_id,
            )
            .first()
        )
        if dup:
            raise HTTPException(status_code=409, detail="This person already has access to this outlet.")

        db.add(OutletMembership(
            manager_id=existing.id, outlet_id=outlet_id, membership_role=MEMBERSHIP_MANAGER
        ))
        db.commit()
        email_sent = await send_email(
            to=existing.email,
            subject=f"You've been given access to {outlet.vendor_name}",
            html=_add_manager_email_html(existing.name, outlet.vendor_name, None),
        )
        return AddManagerResponse(
            manager_id=existing.id,
            email=existing.email,
            membership_role=MEMBERSHIP_MANAGER,
            set_password_link=None,
            email_sent=email_sent,
            message="Existing account linked to this outlet as a manager.",
        )

    # Brand-new co-manager account (pending password).
    mgr = Manager(
        name=name,
        email=email,
        hashed_password=hash_password(secrets.token_urlsafe(24)),
        role="outlet_manager",
        outlet_id=outlet.id,  # primary/default outlet
        is_active=True,
    )
    db.add(mgr)
    db.flush()
    db.add(OutletMembership(
        manager_id=mgr.id, outlet_id=outlet_id, membership_role=MEMBERSHIP_MANAGER
    ))
    db.commit()
    db.refresh(mgr)

    token = create_token(
        {"sub": mgr.email, "purpose": "set_password", "mid": mgr.id},
        _SET_PW_EXPIRY_MIN,
    )
    base = (settings.PUBLIC_BASE_URL or "").rstrip("/")
    link = f"{base}/auth/set-password?token={token}"
    email_sent = await send_email(
        to=mgr.email,
        subject=f"You've been added as a manager for {outlet.vendor_name}",
        html=_add_manager_email_html(mgr.name, outlet.vendor_name, link),
    )
    return AddManagerResponse(
        manager_id=mgr.id,
        email=mgr.email,
        membership_role=MEMBERSHIP_MANAGER,
        set_password_link=link,
        email_sent=email_sent,
        message=(
            "Manager invited. Set-password email sent."
            if email_sent
            else "Manager invited. Email not sent — share the set-password link manually."
        ),
    )


@router.delete("/{outlet_id}/managers/{manager_id}")
def remove_outlet_manager(
    outlet_id: int = Path(..., ge=1),
    manager_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Owner revokes a co-manager's access to this outlet.

    Cannot remove yourself, and cannot remove an OWNER membership (owners are
    managed via ETL onboarding, not here)."""
    _require_outlet_owner(db, user, outlet_id)

    if user.user_type == "manager" and manager_id == user.id:
        raise HTTPException(status_code=400, detail="You cannot remove your own access.")

    mem = (
        db.query(OutletMembership)
        .filter(
            OutletMembership.manager_id == manager_id,
            OutletMembership.outlet_id == outlet_id,
        )
        .first()
    )
    if not mem:
        raise HTTPException(status_code=404, detail="That manager has no access to this outlet.")
    if mem.membership_role == MEMBERSHIP_OWNER:
        raise HTTPException(status_code=403, detail="Cannot remove an owner's access.")

    db.delete(mem)
    db.flush()

    # Keep the manager's PRIMARY outlet_id consistent with their remaining
    # memberships. Without this the legacy `outlet_id` column would still point
    # at the just-removed outlet and the deps fallback would silently re-grant
    # access — i.e. the revoke wouldn't actually revoke. Memberships are the
    # single source of truth, so primary must follow them.
    remaining = [
        r[0] for r in db.query(OutletMembership.outlet_id)
        .filter(OutletMembership.manager_id == manager_id).all()
    ]
    mgr = db.get(Manager, manager_id)
    if mgr is not None:
        mgr.outlet_id = remaining[0] if remaining else None

    db.commit()
    return {"removed": True, "outlet_id": outlet_id, "manager_id": manager_id}



# ─── ETL admin: update an outlet's owner details ─────────────────────────────
#
# TEMPORARY/ADMIN: outlets onboarded with placeholder owner details need their
# real name/email/phone filled in. Gated to ETL managers only. Updating the
# email changes the owner's LOGIN — safe here because these accounts haven't
# been used yet. Can be removed after the initial data cleanup if desired.

class UpdateOwnerRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    email: Optional[str] = Field(None, min_length=3, max_length=200)
    phone: Optional[str] = Field(None, max_length=30)


@router.patch("/{outlet_id}/owner")
def update_outlet_owner(
    body: UpdateOwnerRequest,
    outlet_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_etl_manager),
):
    """ETL manager: correct an outlet owner's name / email / phone."""
    outlet = db.query(Outlet).filter(Outlet.id == outlet_id).first()
    if not outlet:
        raise HTTPException(status_code=404, detail="Outlet not found.")

    owners = (
        db.query(OutletMembership)
        .filter(
            OutletMembership.outlet_id == outlet_id,
            OutletMembership.membership_role == MEMBERSHIP_OWNER,
        )
        .all()
    )
    if not owners:
        raise HTTPException(status_code=404, detail="This outlet has no owner on record.")
    if len(owners) > 1:
        raise HTTPException(
            status_code=409,
            detail="This outlet has multiple owners — edit via the manager list instead.",
        )

    mgr = db.get(Manager, owners[0].manager_id)
    if mgr is None:
        raise HTTPException(status_code=404, detail="Owner account not found.")

    if body.name is not None:
        name = body.name.strip()
        if name:
            mgr.name = name

    new_email = None
    if body.email is not None:
        new_email = body.email.strip().lower()
        if "@" not in new_email or "." not in new_email.split("@")[-1]:
            raise HTTPException(status_code=400, detail="Please provide a valid email address.")
        # Uniqueness: no OTHER manager and no staff may already use this email.
        clash_mgr = (
            db.query(Manager)
            .filter(Manager.email == new_email, Manager.id != mgr.id)
            .first()
        )
        clash_staff = db.query(Staff).filter(Staff.email == new_email).first()
        if clash_mgr or clash_staff:
            raise HTTPException(status_code=409, detail="That email is already in use.")
        mgr.email = new_email

    # Keep the onboarding application record (what the ETL UI shows) in sync.
    appn = (
        db.query(OutletApplication)
        .filter(OutletApplication.created_outlet_id == outlet_id)
        .first()
    )
    if appn is not None:
        if body.name is not None and body.name.strip():
            appn.owner_name = body.name.strip()
        if new_email is not None:
            appn.owner_email = new_email
        if body.phone is not None:
            appn.owner_phone = body.phone.strip()

    db.commit()
    db.refresh(mgr)
    return {
        "outlet_id": outlet_id,
        "manager_id": mgr.id,
        "name": mgr.name,
        "email": mgr.email,
        "message": "Owner details updated.",
    }


# ─── ETL admin: delete an outlet from a court ────────────────────────────────
#
# Removes the outlet and every row tied to it, child-first, in ONE transaction
# (prod is Postgres with FK enforcement, and the schema uses create_all — not
# migrations guaranteeing ON DELETE CASCADE — so we delete explicitly, exactly
# like the court delete does). Managers linked to this outlet are NOT deleted
# (they may run other outlets); we just remove their membership here and clear a
# primary outlet_id that pointed at it, so the deps layer recomputes access from
# their remaining memberships.

@router.delete("/{outlet_id}")
def delete_outlet(
    outlet_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_etl_manager),
):
    """ETL manager: permanently delete an outlet and all its data."""
    outlet = db.query(Outlet).filter(Outlet.id == outlet_id).first()
    if not outlet:
        raise HTTPException(status_code=404, detail="Outlet not found.")
    outlet_name = outlet.vendor_name

    # Outlet staff (scoped by outlet_id). Their attendance/notices/tokens go too.
    staff_ids = [r[0] for r in db.query(Staff.id).filter(Staff.outlet_id == outlet_id).all()]
    sid_list = ",".join(str(int(s)) for s in staff_ids)

    existing_tables = set(inspect(db.get_bind()).get_table_names())
    counts: dict[str, int] = {}

    def _run(table: str, sql: str) -> None:
        if table not in existing_tables:
            return
        res = db.execute(text(sql), {"oid": outlet_id})
        counts[table] = res.rowcount if res.rowcount is not None else 0

    try:
        staff_cond = f" OR staff_id IN ({sid_list})" if sid_list else ""
        recip_cond = f" OR recipient_staff_id IN ({sid_list})" if sid_list else ""
        dev_staff_cond = (
            f"user_type = 'staff' AND user_id IN ({sid_list})" if sid_list else "1=0"
        )

        # child rows first ---------------------------------------------------
        _run("attendance", f"DELETE FROM attendance WHERE outlet_id = :oid{staff_cond}")
        _run("notices", f"DELETE FROM notices WHERE outlet_id = :oid{staff_cond}{recip_cond}")
        _run("feedbacks", "DELETE FROM feedbacks WHERE outlet_id = :oid")
        _run("maintenance_issues", "DELETE FROM maintenance_issues WHERE outlet_id = :oid")
        _run("daily_sale_cache", "DELETE FROM daily_sale_cache WHERE outlet_id = :oid")
        _run("sales_orders", "DELETE FROM sales_orders WHERE outlet_id = :oid")
        _run("petpooja_orders", "DELETE FROM petpooja_orders WHERE outlet_id = :oid")
        _run("device_tokens", f"DELETE FROM device_tokens WHERE {dev_staff_cond}")
        _run("outlet_memberships", "DELETE FROM outlet_memberships WHERE outlet_id = :oid")
        _run("staff", "DELETE FROM staff WHERE outlet_id = :oid")
        # detach the onboarding application (keep the record, drop the FK link)
        _run("outlet_applications", "UPDATE outlet_applications SET created_outlet_id = NULL WHERE created_outlet_id = :oid")
        # clear any manager whose PRIMARY outlet pointed here (don't delete them)
        _run("managers", "UPDATE managers SET outlet_id = NULL WHERE outlet_id = :oid")
        # ... outlet last
        _run("outlets", "DELETE FROM outlets WHERE id = :oid")

        db.commit()
    except Exception as e:  # noqa: BLE001 — atomic: nothing partial survives
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Delete failed, rolled back: {e}")

    return {
        "deleted": True,
        "outlet_id": outlet_id,
        "outlet_name": outlet_name,
        "staff_deleted": len(staff_ids),
        "rows_deleted": counts,
    }
