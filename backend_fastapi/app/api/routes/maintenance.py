# app/api/routes/maintenance.py
from __future__ import annotations

import logging
from datetime import datetime
from enum import Enum
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, Path, UploadFile
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from ...database import get_db
from ...models.maintenance import MaintenanceIssue
from ...models.sale import Court, Outlet
from ...core.uploads import save_upload_image
from ...services.notice_service import create_notice
from ..deps import CurrentUser, get_current_user, require_etl_manager, require_outlet_user
from .events import notify_clients

logger = logging.getLogger("maintenance")

router = APIRouter()

# ─── Enums (strict validation) ───────────────────────────────────────────────

class IssueType(str, Enum):
    electrical = "electrical"
    plumbing   = "plumbing"
    furniture  = "furniture"
    cleaning   = "cleaning"
    other      = "other"


class IssuePriority(str, Enum):
    low    = "low"
    medium = "medium"
    high   = "high"


class IssueStatus(str, Enum):
    RAISED   = "RAISED"
    ASSIGNED = "ASSIGNED"
    RESOLVED = "RESOLVED"
    CLOSED   = "CLOSED"
    DISPUTED = "DISPUTED"


# ─── Request / Response Schemas ──────────────────────────────────────────────

class RaiseTicketInput(BaseModel):
    issue_type:  IssueType
    priority:    IssuePriority = IssuePriority.medium
    description: str = Field(..., min_length=5, max_length=1000)
    photo_url:   Optional[str] = Field(None, max_length=500)
    # MULTI-OUTLET: which of the caller's outlets this ticket is for. Optional —
    # staff and single-outlet owners can omit it (their only outlet is used); a
    # multi-outlet owner MUST specify. Always validated against membership.
    outlet_id:   Optional[int] = None

    @field_validator("description")
    @classmethod
    def strip_desc(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 5:
            raise ValueError("Description must be at least 5 characters.")
        return v


class AssignTechnicianInput(BaseModel):
    technician_name:  str = Field(..., min_length=2, max_length=100)
    technician_phone: str = Field(..., min_length=7, max_length=15)

    @field_validator("technician_phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        cleaned = v.strip().replace(" ", "").replace("-", "")
        if not cleaned.lstrip("+").isdigit():
            raise ValueError("Invalid phone number.")
        return cleaned


class VerifyTicketInput(BaseModel):
    is_satisfied: bool


class IssueOut(BaseModel):
    id: int
    court_id: int
    court_name: str
    outlet_id: int
    outlet_name: str
    staff_name: str
    issue_type: str
    priority: str
    description: str
    photo_url: Optional[str] = None
    status: str
    technician_name: Optional[str] = None
    technician_phone: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    resolved_at: Optional[str] = None
    closed_at: Optional[str] = None
    auto_close_at: Optional[str] = None   # resolved_at + 24h, for UI countdown


class IssueListOut(BaseModel):
    items: List[IssueOut]
    total: int
    limit: int
    offset: int


# ─── Helpers ─────────────────────────────────────────────────────────────────

VERIFICATION_WINDOW_HOURS = 24


def _utc_iso(dt: Optional[datetime]) -> Optional[str]:
    """Always emit explicit UTC so Flutter parses correctly."""
    if dt is None:
        return None
    return dt.isoformat() + "Z"


def _to_out(i: MaintenanceIssue) -> IssueOut:
    auto_close = None
    if i.status == IssueStatus.RESOLVED.value and i.resolved_at:
        from datetime import timedelta
        auto_close = _utc_iso(i.resolved_at + timedelta(hours=VERIFICATION_WINDOW_HOURS))

    return IssueOut(
        id=i.id,
        court_id=i.court_id,
        court_name=i.court_name,
        outlet_id=i.outlet_id,
        outlet_name=i.outlet_name,
        staff_name=i.staff_name,
        issue_type=i.issue_type,
        priority=i.priority or "medium",
        description=i.description,
        photo_url=i.photo_url,
        status=i.status,
        technician_name=i.technician_name,
        technician_phone=i.technician_phone,
        created_at=_utc_iso(i.created_at),
        updated_at=_utc_iso(i.updated_at),
        resolved_at=_utc_iso(i.resolved_at),
        closed_at=_utc_iso(i.closed_at),
        auto_close_at=auto_close,
    )


def _get_issue_or_404(db: Session, issue_id: int) -> MaintenanceIssue:
    issue = db.query(MaintenanceIssue).filter(MaintenanceIssue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Ticket not found.")
    return issue


def _assert_outlet_owns(user: CurrentUser, issue: MaintenanceIssue):
    # MULTI-OUTLET: the ticket must belong to one of the caller's outlets.
    if issue.outlet_id not in user.outlet_ids:
        raise HTTPException(status_code=403, detail="This ticket belongs to another outlet.")


async def _notify(issue: MaintenanceIssue):
    try:
        await notify_clients({
            "type": "maintenance_update",
            "court_id": issue.court_id,
            # outlet_id lets an outlet client tell "my ticket" from a
            # neighbouring outlet's without a second round-trip.
            "outlet_id": issue.outlet_id,
            "issue_id": issue.id,
            "status": issue.status,
        })
    except Exception:
        pass  # SSE failure must never break the API call


# ─── Persistent notices (+ push) ─────────────────────────────────────────────
#
# SSE alone is ephemeral: it only reaches a device whose app is open. These
# helpers add a durable Notice row, which create_notice() also turns into an
# FCM push. Targeting rules (services/push_targeting.py):
#   outlet_id set  → ONLY that outlet's manager
#   outlet_id None → ONLY ETL managers
# so a ticket never leaks to a neighbouring vendor.

def _notify_etl(db: Session, issue: MaintenanceIssue, *, type: str, title: str, body: str) -> None:
    """Durable notice for the ETL manager tier (outlet_id deliberately NULL)."""
    try:
        create_notice(
            db,
            audience="manager",
            type=type,
            title=title,
            body=body,
            court_id=issue.court_id,
            outlet_id=None,
        )
    except Exception as e:  # noqa: BLE001 — notifications must not break the API
        logger.warning("ETL notice failed for #%s: %s", issue.id, e)


def _notify_outlet(db: Session, issue: MaintenanceIssue, *, type: str, title: str, body: str) -> None:
    """Durable notice for the owning outlet's manager only."""
    try:
        create_notice(
            db,
            audience="manager",
            type=type,
            title=title,
            body=body,
            court_id=None,
            outlet_id=issue.outlet_id,
        )
    except Exception as e:  # noqa: BLE001
        logger.warning("outlet notice failed for #%s: %s", issue.id, e)


def _ticket_label(issue: MaintenanceIssue) -> str:
    return f"{issue.issue_type} · {issue.outlet_name or 'outlet'}"


# ─── Endpoints ───────────────────────────────────────────────────────────────

@router.post("/maintenance/upload-photo", status_code=201)
async def upload_maintenance_photo(
    photo: UploadFile = File(...),
    user: CurrentUser = Depends(require_outlet_user),
):
    """Persist a maintenance proof photo on the Railway volume (replaces the
    old Cloudinary flow) and return its public URL path."""
    photo_url = await save_upload_image(photo, "maintenance", "mnt")
    return {"photo_url": photo_url}


@router.post("/maintenance/", response_model=IssueOut, status_code=201)
async def raise_ticket(
    body: RaiseTicketInput,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_outlet_user),
):
    """Outlet staff/manager raises a ticket for one of THEIR OWN outlets.

    The outlet is resolved from the caller's membership (never trusted blindly):
    a single-outlet caller can omit `outlet_id`; a multi-outlet owner must send
    one, and it must be an outlet they belong to.
    """
    target_outlet_id = body.outlet_id
    if target_outlet_id is None:
        if len(user.outlet_ids) == 1:
            target_outlet_id = user.outlet_ids[0]
        else:
            raise HTTPException(
                status_code=400,
                detail="outlet_id is required — you manage multiple outlets.",
            )
    if target_outlet_id not in user.outlet_ids:
        raise HTTPException(status_code=403, detail="You cannot raise a ticket for that outlet.")

    outlet = db.query(Outlet).filter(
        Outlet.id == target_outlet_id, Outlet.is_active == 1
    ).first()
    if not outlet:
        raise HTTPException(status_code=404, detail="Your outlet was not found or is inactive.")

    court = db.query(Court).filter(Court.id == outlet.court_id).first()
    if not court:
        raise HTTPException(status_code=404, detail="Associated court not found.")

    issue = MaintenanceIssue(
        court_id=court.id,
        court_name=court.name,
        outlet_id=outlet.id,
        outlet_name=outlet.vendor_name.split("(")[0].strip(),
        staff_name=user.name,              # ✅ identity from JWT, not body
        raised_by_email=user.email,
        issue_type=body.issue_type.value,
        priority=body.priority.value,
        description=body.description,
        photo_url=body.photo_url,
        status=IssueStatus.RAISED.value,
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)

    await _notify(issue)

    # Trigger #6 — new ticket. Goes to the ETL manager tier only; the outlet
    # already knows (they just raised it).
    urgency = " — HIGH PRIORITY" if (issue.priority or "").lower() == "high" else ""
    _notify_etl(
        db,
        issue,
        type="maintenance_raised",
        title=f"New maintenance ticket{urgency}",
        body=(
            f"{issue.outlet_name or 'An outlet'} raised a {issue.issue_type} issue "
            f"at {issue.court_name or 'the court'}: {issue.description[:120]}"
        ),
    )
    return _to_out(issue)


@router.get("/maintenance", response_model=IssueListOut)
async def list_issues(
    status_filter: Optional[IssueStatus] = Query(None, alias="status"),
    priority: Optional[IssuePriority] = Query(None),
    court_id: Optional[int] = Query(None),
    outlet_id: Optional[int] = Query(None),  # ✅ MULTI-OUTLET: optional outlet filter (switcher)
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Role-scoped listing. Outlet users see only their outlet(s); ETL managers see all courts."""
    q = db.query(MaintenanceIssue)

    if user.is_outlet_user:
        if not user.outlet_ids:
            raise HTTPException(status_code=403, detail="No outlet assigned.")
        if outlet_id is not None:
            # A specific selection must be one of the caller's outlets.
            if outlet_id not in user.outlet_ids:
                raise HTTPException(status_code=403, detail="You cannot access that outlet.")
            q = q.filter(MaintenanceIssue.outlet_id == outlet_id)
        else:
            q = q.filter(MaintenanceIssue.outlet_id.in_(user.outlet_ids))
    elif user.is_etl_manager:
        if court_id:
            q = q.filter(MaintenanceIssue.court_id == court_id)
        if outlet_id:
            q = q.filter(MaintenanceIssue.outlet_id == outlet_id)
    elif user.is_etl_staff:
        if user.court_id is None:
            raise HTTPException(status_code=403, detail="No court assigned.")
        q = q.filter(MaintenanceIssue.court_id == user.court_id)
    else:
        raise HTTPException(status_code=403, detail="Access denied.")

    if status_filter:
        q = q.filter(MaintenanceIssue.status == status_filter.value)
    if priority:
        q = q.filter(MaintenanceIssue.priority == priority.value)

    total = q.count()
    rows = (
        q.order_by(MaintenanceIssue.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return IssueListOut(
        items=[_to_out(i) for i in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/maintenance/{issue_id}", response_model=IssueOut)
async def get_issue(
    issue_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    issue = _get_issue_or_404(db, issue_id)
    if user.is_outlet_user:
        _assert_outlet_owns(user, issue)
    elif user.is_etl_staff:
        # Scope ETL staff to their own court (mirrors list_issues); without this
        # any ETL staff could read any court's ticket by guessing its id.
        if user.court_id is None or issue.court_id != user.court_id:
            raise HTTPException(
                status_code=403, detail="This ticket belongs to another court."
            )
    # ETL managers are unrestricted (they oversee every court).
    return _to_out(issue)


@router.put("/maintenance/{issue_id}/assign", response_model=IssueOut)
async def assign_technician(
    body: AssignTechnicianInput,
    issue_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_etl_manager),
):
    """Manager assigns a technician. Only valid from RAISED or DISPUTED."""
    issue = _get_issue_or_404(db, issue_id)

    if issue.status not in (IssueStatus.RAISED.value, IssueStatus.DISPUTED.value):
        raise HTTPException(
            status_code=409,
            detail=f"Cannot assign technician — ticket is {issue.status}.",
        )

    issue.technician_name = body.technician_name.strip()
    issue.technician_phone = body.technician_phone
    issue.status = IssueStatus.ASSIGNED.value
    db.commit()
    db.refresh(issue)

    await _notify(issue)

    # Trigger #7 — technician assigned. The outlet that raised it needs the
    # name/phone, so this one goes to the OWNING outlet only.
    _notify_outlet(
        db,
        issue,
        type="maintenance_assigned",
        title="Technician assigned",
        body=(
            f"{issue.technician_name} ({issue.technician_phone}) has been assigned "
            f"to your {issue.issue_type} ticket."
        ),
    )
    return _to_out(issue)


@router.put("/maintenance/{issue_id}/resolve", response_model=IssueOut)
async def mark_resolved(
    issue_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_etl_manager),
):
    """Manager marks resolved — starts the 24h verification window for the outlet."""
    issue = _get_issue_or_404(db, issue_id)

    if issue.status not in (IssueStatus.RAISED.value, IssueStatus.ASSIGNED.value, IssueStatus.DISPUTED.value):
        raise HTTPException(
            status_code=409,
            detail=f"Cannot resolve — ticket is {issue.status}.",
        )

    issue.status = IssueStatus.RESOLVED.value
    issue.resolved_at = datetime.utcnow()
    db.commit()
    db.refresh(issue)

    await _notify(issue)

    # Trigger #8 — the highest-value push in the module. The outlet now has a
    # hard 24h deadline to verify or the ticket auto-closes without their say
    # (see scheduler_service.auto_close_expired_tickets).
    _notify_outlet(
        db,
        issue,
        type="maintenance_resolved",
        title="Please verify the repair",
        body=(
            f"Your {issue.issue_type} ticket was marked resolved. Confirm within "
            f"{VERIFICATION_WINDOW_HOURS}h or it closes automatically."
        ),
    )
    return _to_out(issue)


@router.put("/maintenance/{issue_id}/verify", response_model=IssueOut)
async def verify_closure(
    body: VerifyTicketInput,
    issue_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_outlet_user),
):
    """Outlet verifies the fix. Only THEIR ticket, only when RESOLVED."""
    issue = _get_issue_or_404(db, issue_id)
    _assert_outlet_owns(user, issue)

    if issue.status != IssueStatus.RESOLVED.value:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot verify — ticket is {issue.status}, must be RESOLVED.",
        )

    if body.is_satisfied:
        issue.status = IssueStatus.CLOSED.value
        issue.closed_at = datetime.utcnow()
    else:
        issue.status = IssueStatus.DISPUTED.value
        issue.resolved_at = None

    db.commit()
    db.refresh(issue)

    await _notify(issue)

    # Triggers #9 / #10 — the outlet's verdict. Both go to the ETL manager tier,
    # since they are the ones who must act on a dispute.
    if issue.status == IssueStatus.CLOSED.value:
        _notify_etl(
            db,
            issue,
            type="maintenance_closed",
            title="Ticket verified and closed",
            body=(
                f"{issue.outlet_name or 'The outlet'} confirmed the "
                f"{issue.issue_type} repair. Ticket #{issue.id} is closed."
            ),
        )
    else:
        _notify_etl(
            db,
            issue,
            type="maintenance_disputed",
            title="Repair disputed — needs rework",
            body=(
                f"{issue.outlet_name or 'The outlet'} was not satisfied with the "
                f"{issue.issue_type} repair. Ticket #{issue.id} needs to be "
                f"reassigned."
            ),
        )
    return _to_out(issue)
