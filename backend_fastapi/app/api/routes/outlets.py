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

import logging
import os
import secrets
import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Path, File, Form, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import text, inspect
from sqlalchemy.orm import Session

from ...database import get_db
from ...core.config import settings
from ...core.security import create_token, hash_password, verify_password
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
from ...services.notice_service import create_notice
from ..deps import get_current_user, require_etl_manager, CurrentUser

logger = logging.getLogger("outlets")

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

    # Managers who belong to this outlet TODAY. After we strip their membership
    # below, any of them left with ZERO memberships becomes a "zombie": still
    # is_active + role='outlet_manager' but every outlet endpoint 403s ("no
    # outlet assigned"), with no cleanup. We deactivate those + prune their
    # device tokens after the deletes (see below). Captured BEFORE the delete.
    member_manager_ids: list[int] = []
    if "outlet_memberships" in existing_tables:
        member_manager_ids = [
            int(r[0])
            for r in db.execute(
                text("SELECT manager_id FROM outlet_memberships WHERE outlet_id = :oid"),
                {"oid": outlet_id},
            ).all()
        ]
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

        # Deactivate now-membershipless outlet managers (avoid zombie accounts)
        # and prune their manager device tokens. Only outlet_manager rows are
        # ever touched — an ETL manager is never affected. Managers who still
        # own/manage another outlet are skipped.
        zombie_deactivated = 0
        for mid in member_manager_ids:
            remaining = db.execute(
                text("SELECT COUNT(*) FROM outlet_memberships WHERE manager_id = :mid"),
                {"mid": mid},
            ).scalar()
            if remaining and int(remaining) > 0:
                continue
            res = db.execute(
                text(
                    "UPDATE managers SET is_active = :inactive, outlet_id = NULL "
                    "WHERE id = :mid AND role = 'outlet_manager'"
                ),
                {"mid": mid, "inactive": False},
            )
            if res.rowcount:
                zombie_deactivated += int(res.rowcount)
            if "device_tokens" in existing_tables:
                db.execute(
                    text(
                        "DELETE FROM device_tokens "
                        "WHERE user_type = 'manager' AND user_id = :mid"
                    ),
                    {"mid": mid},
                )
        counts["managers_deactivated"] = zombie_deactivated

        # ... outlet last
        _run("outlets", "DELETE FROM outlets WHERE id = :oid")

        db.commit()
    except Exception:  # noqa: BLE001 — atomic: nothing partial survives
        db.rollback()
        # Log the real cause server-side; never leak internal/DB text to client.
        logger.exception("Outlet delete failed and was rolled back")
        raise HTTPException(
            status_code=500, detail="Could not delete the outlet. Please try again."
        )

    return {
        "deleted": True,
        "outlet_id": outlet_id,
        "outlet_name": outlet_name,
        "staff_deleted": len(staff_ids),
        "rows_deleted": counts,
    }



# ─── Outlet documents (GST / FSSAI / term sheet / agreement) ─────────────────
#
# Documents live on the OUTLET (backfilled from the onboarding application), so
# they can be uploaded / replaced / removed at ANY time — by the outlet's owner
# or an ETL manager. VIEWING is free (anyone who can access the outlet); every
# CHANGE re-authenticates the acting account with its OWN password (a lightweight
# "unlock", so a left-open phone can't be used to alter documents). Any change
# notifies the OTHER side: an ETL edit pings the outlet's manager; an owner edit
# pings the ETL managers.

_DOC_COLUMNS = {
    "gst": "gst_url",
    "fssai": "fssai_url",
    "term_sheet": "term_sheet_url",
    "agreement": "agreement_url",
}
_DOC_LABELS = {
    "gst": "GST certificate",
    "fssai": "FSSAI licence",
    "term_sheet": "Term sheet",
    "agreement": "Agreement",
}
_ALLOWED_DOC_TYPES = {
    "application/pdf": "pdf",
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}
_MAX_DOC_BYTES = 10 * 1024 * 1024  # 10 MB


class DocPasswordBody(BaseModel):
    password: str


def _outlet_for_docs(db: Session, user: CurrentUser, outlet_id: int) -> Outlet:
    """Fetch an active outlet the caller may access (ETL manager → any; outlet
    user → only their own via membership)."""
    outlet = db.query(Outlet).filter(Outlet.id == outlet_id, Outlet.is_active == 1).first()
    if not outlet:
        raise HTTPException(status_code=404, detail="Outlet not found or inactive.")
    if not user.can_access_outlet(outlet_id):
        raise HTTPException(status_code=403, detail="You cannot access this outlet.")
    return outlet


def _reauth(db: Session, user: CurrentUser, password: Optional[str]) -> None:
    """Re-authenticate the acting account by its own password before a change.
    Only manager accounts (ETL or outlet) manage documents."""
    if user.user_type != "manager":
        raise HTTPException(status_code=403, detail="Only managers can change documents.")
    pw = (password or "").strip()
    if not pw:
        raise HTTPException(status_code=400, detail="Password is required to change documents.")
    m = db.query(Manager).filter(Manager.id == user.id, Manager.is_active == True).first()  # noqa: E712
    if not m or not verify_password(pw, m.hashed_password):
        raise HTTPException(status_code=403, detail="Incorrect password.")


async def _save_document(f: UploadFile, outlet_id: int, doc_type: str) -> str:
    ext = _ALLOWED_DOC_TYPES.get(f.content_type or "")
    if ext is None:
        raise HTTPException(status_code=400, detail="Invalid file type. Upload PDF, JPG, PNG or WebP.")
    data = await f.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty file.")
    if len(data) > _MAX_DOC_BYTES:
        raise HTTPException(status_code=400, detail="File too large (max 10 MB).")
    folder = os.path.join(settings.UPLOAD_DIR, "documents")
    os.makedirs(folder, exist_ok=True)
    filename = f"{doc_type}_{outlet_id}_{uuid.uuid4()}.{ext}"
    with open(os.path.join(folder, filename), "wb") as buf:
        buf.write(data)
    return f"uploads/documents/{filename}"


def _notify_doc_change(db: Session, user: CurrentUser, outlet: Outlet, doc_type: str, action: str) -> None:
    label = _DOC_LABELS.get(doc_type, "document")
    verb = "uploaded" if action == "upload" else "removed"
    try:
        if user.is_etl_manager:
            # ETL admin changed it → tell the outlet's manager.
            create_notice(
                db,
                audience="manager",
                type="document_updated",
                title=f"{label} {verb}",
                body=f"An ETL admin {verb} the {label} for {outlet.vendor_name}.",
                outlet_id=outlet.id,
            )
        else:
            # Outlet owner/manager changed it → tell the ETL managers.
            create_notice(
                db,
                audience="manager",
                type="document_updated",
                title=f"Outlet {label.lower()} {verb}",
                body=f"{user.name} {verb} the {label} for {outlet.vendor_name}.",
                court_id=outlet.court_id,
                outlet_id=None,
            )
    except Exception as e:  # noqa: BLE001 — a notice must never break the change
        logger.warning("doc-change notice failed for outlet %s: %s", outlet.id, e)


@router.get("/{outlet_id}/documents")
def get_outlet_documents(
    outlet_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """View an outlet's documents (no password needed). Returns each doc type
    with its current URL (or null)."""
    outlet = _outlet_for_docs(db, user, outlet_id)
    return {
        "outlet_id": outlet.id,
        "outlet_name": outlet.vendor_name,
        "documents": [
            {"doc_type": dt, "label": _DOC_LABELS[dt], "url": getattr(outlet, col)}
            for dt, col in _DOC_COLUMNS.items()
        ],
    }


@router.post("/{outlet_id}/documents/{doc_type}")
async def upload_outlet_document(
    outlet_id: int = Path(..., ge=1),
    doc_type: str = Path(...),
    file: UploadFile = File(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Upload or replace ONE document. Requires the acting account's password."""
    if doc_type not in _DOC_COLUMNS:
        raise HTTPException(status_code=400, detail="Unknown document type.")
    outlet = _outlet_for_docs(db, user, outlet_id)
    _reauth(db, user, password)
    url = await _save_document(file, outlet_id, doc_type)
    setattr(outlet, _DOC_COLUMNS[doc_type], url)
    db.commit()
    _notify_doc_change(db, user, outlet, doc_type, "upload")
    return {"doc_type": doc_type, "label": _DOC_LABELS[doc_type], "url": url}


@router.delete("/{outlet_id}/documents/{doc_type}")
def delete_outlet_document(
    body: DocPasswordBody,
    outlet_id: int = Path(..., ge=1),
    doc_type: str = Path(...),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Remove ONE document. Requires the acting account's password."""
    if doc_type not in _DOC_COLUMNS:
        raise HTTPException(status_code=400, detail="Unknown document type.")
    outlet = _outlet_for_docs(db, user, outlet_id)
    _reauth(db, user, body.password)
    col = _DOC_COLUMNS[doc_type]
    changed = getattr(outlet, col) is not None
    setattr(outlet, col, None)
    db.commit()
    if changed:
        _notify_doc_change(db, user, outlet, doc_type, "remove")
    return {"doc_type": doc_type, "removed": True}
