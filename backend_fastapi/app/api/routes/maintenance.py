# app/api/routes/maintenance.py
from __future__ import annotations

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
from ..deps import CurrentUser, get_current_user, require_etl_manager, require_outlet_user
from .events import notify_clients

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
    if issue.outlet_id != user.outlet_id:
        raise HTTPException(status_code=403, detail="This ticket belongs to another outlet.")


async def _notify(issue: MaintenanceIssue):
    try:
        await notify_clients({
            "type": "maintenance_update",
            "court_id": issue.court_id,
            "issue_id": issue.id,
            "status": issue.status,
        })
    except Exception:
        pass  # SSE failure must never break the API call


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
    """Outlet staff/manager raises a ticket for THEIR OWN outlet (from JWT)."""
    outlet = db.query(Outlet).filter(
        Outlet.id == user.outlet_id, Outlet.is_active == 1
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
    return _to_out(issue)


@router.get("/maintenance", response_model=IssueListOut)
async def list_issues(
    status_filter: Optional[IssueStatus] = Query(None, alias="status"),
    priority: Optional[IssuePriority] = Query(None),
    court_id: Optional[int] = Query(None),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Role-scoped listing. Outlet users see only their outlet; ETL managers see all courts."""
    q = db.query(MaintenanceIssue)

    if user.is_outlet_user:
        if user.outlet_id is None:
            raise HTTPException(status_code=403, detail="No outlet assigned.")
        q = q.filter(MaintenanceIssue.outlet_id == user.outlet_id)
    elif user.is_etl_manager:
        if court_id:
            q = q.filter(MaintenanceIssue.court_id == court_id)
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
    return _to_out(issue)
