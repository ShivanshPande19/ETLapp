# app/api/routes/maintenance.py
from __future__ import annotations

import json
import logging
from datetime import datetime
from enum import Enum
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, Path, UploadFile
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import or_
from sqlalchemy.orm import Session

from ...database import get_db
from ...models.maintenance import MaintenanceIssue
from ...models.sale import Court, Outlet
from ...core.uploads import save_upload_image
from ...services.notice_service import create_notice
from ..deps import (
    CurrentUser, get_current_user, require_etl_manager, require_outlet_user,
    require_ops_head, MAINTENANCE_ROLES,
)
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

class MentionInput(BaseModel):
    kind: str            # "role" | "user"
    value: str           # a role key, or "staff:<id>" / "manager:<id>"


class RaiseTicketInput(BaseModel):
    issue_type:  IssueType
    priority:    IssuePriority = IssuePriority.medium
    description: str = Field(..., min_length=5, max_length=1000)
    photo_url:   Optional[str] = Field(None, max_length=500)
    # MULTI-OUTLET: which of the caller's outlets this ticket is for. Optional —
    # staff and single-outlet owners can omit it (their only outlet is used); a
    # multi-outlet owner MUST specify. Always validated against membership.
    outlet_id:   Optional[int] = None

    # ── Ops-head extras (ignored for outlet-user raises) ──────────────────────
    # "general" (court/zone-level) needs court_id; "outlet" needs outlet_id.
    scope:        Optional[str] = None                 # "general" | "outlet"
    court_id:     Optional[int] = None                 # required for general scope
    target_teams: Optional[List[str]] = None           # subset of MAINTENANCE_ROLES
    mentions:     Optional[List[MentionInput]] = None
    is_urgent:    Optional[bool] = None

    @field_validator("description")
    @classmethod
    def strip_desc(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 5:
            raise ValueError("Description must be at least 5 characters.")
        return v


class RouteTicketInput(BaseModel):
    """Ops-head triage: set/replace the target teams + mentions on a ticket."""
    target_teams: List[str] = Field(default_factory=list)
    mentions:     Optional[List[MentionInput]] = None
    scope:        Optional[str] = None
    is_urgent:    Optional[bool] = None


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
    # ── Role-split fields ─────────────────────────────────────────────────────
    scope: str = "outlet"
    is_urgent: bool = False
    triage_status: str = "routed"
    target_teams: List[str] = Field(default_factory=list)
    mentions: List[dict] = Field(default_factory=list)
    raised_by_role: Optional[str] = None


class IssueListOut(BaseModel):
    items: List[IssueOut]
    total: int
    limit: int
    offset: int


# ─── Helpers ─────────────────────────────────────────────────────────────────

VERIFICATION_WINDOW_HOURS = 24


def _json_list(raw: Optional[str]) -> list:
    """Parse a JSON-list text column defensively (never raises)."""
    if not raw:
        return []
    try:
        v = json.loads(raw)
        return v if isinstance(v, list) else []
    except Exception:
        return []


def _dump_list(v: Optional[list]) -> Optional[str]:
    return json.dumps(v) if v else None


def _validate_targets(targets: Optional[List[str]]) -> list:
    """Keep only valid maintenance-team role keys; reject anything else."""
    if not targets:
        return []
    bad = [t for t in targets if t not in MAINTENANCE_ROLES]
    if bad:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid target team(s): {bad}. Allowed: {sorted(MAINTENANCE_ROLES)}",
        )
    # de-dupe, keep order
    return list(dict.fromkeys(targets))


def _mentions_to_dicts(mentions) -> list:
    out = []
    for m in (mentions or []):
        kind = getattr(m, "kind", None) if not isinstance(m, dict) else m.get("kind")
        value = getattr(m, "value", None) if not isinstance(m, dict) else m.get("value")
        if kind in ("role", "user") and value:
            out.append({"kind": kind, "value": value})
    return out


def _user_matches_mentions(user: CurrentUser, mentions: list) -> bool:
    tag = f"{user.user_type}:{user.id}"
    for m in mentions:
        if not isinstance(m, dict):
            continue
        if m.get("kind") == "user" and m.get("value") == tag:
            return True
        if m.get("kind") == "role" and m.get("value") == user.role:
            return True
    return False


def _can_action_ticket(user: CurrentUser, issue: MaintenanceIssue) -> bool:
    """May this user assign/resolve/view this ticket?
    Management → any. Maintenance → only if their role is a target OR they are
    mentioned (by role or individually)."""
    if user.is_management:
        return True
    if user.is_maintenance:
        if user.maintenance_role in _json_list(issue.target_teams):
            return True
        return _user_matches_mentions(user, _json_list(issue.mentions))
    return False


def _apply_maintenance_visibility(q, user: CurrentUser):
    """Restrict a query to tickets a maintenance user may see (target or
    mention). Uses LIKE on the JSON text so pagination still works."""
    role_tag = f'"{user.maintenance_role}"'
    user_tag = f'"{user.user_type}:{user.id}"'
    return q.filter(
        or_(
            MaintenanceIssue.target_teams.like(f"%{role_tag}%"),
            MaintenanceIssue.mentions.like(f"%{role_tag}%"),
            MaintenanceIssue.mentions.like(f"%{user_tag}%"),
        )
    )


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
        scope=i.scope or "outlet",
        is_urgent=bool(i.is_urgent),
        triage_status=i.triage_status or "routed",
        target_teams=_json_list(i.target_teams),
        mentions=_json_list(i.mentions),
        raised_by_role=i.raised_by_role,
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


# ─── Role-based ticket notifications (the locked matrix) ──────────────────────
#
# "Management tier" for maintenance alerts = Azimuth Management + Crownest Head
# (they behave identically). The Ops Head raises tickets and is not separately
# alerted for its own. Immediate alerts are fired here; the 6h reminders and
# 2d/4d escalations are driven by the scheduler (services/scheduler_service.py).
MANAGEMENT_TIER_ROLES = ["azimuth_management", "crownest_head"]


def _notify_triage(db: Session, issue: MaintenanceIssue) -> None:
    """Outlet-raised ticket → land in the Crownest Ops Head triage queue."""
    urgency = " — HIGH PRIORITY" if (issue.priority or "").lower() == "high" else ""
    try:
        create_notice(
            db,
            audience="role",
            type="maintenance_triage",
            title=f"New ticket to route{urgency}",
            body=(
                f"{issue.outlet_name or 'An outlet'} raised a {issue.issue_type} issue "
                f"at {issue.court_name or 'the court'}: {issue.description[:120]}"
            ),
            court_id=issue.court_id,
            outlet_id=(issue.outlet_id or None),
            target_roles=["crownest_ops_head"],
        )
    except Exception as e:  # noqa: BLE001 — a notice must never break the API
        logger.warning("triage notice failed for #%s: %s", issue.id, e)


def _dispatch_routed_notifications(db: Session, issue: MaintenanceIssue) -> None:
    """Fire the IMMEDIATE role-based notifications when a ticket's targets /
    mentions are set (ops-head raise, or triage/route). The 6h reminders and
    2d/4d escalations are handled by the scheduler."""
    targets = _json_list(issue.target_teams)
    mentions = _json_list(issue.mentions)
    if not targets and not mentions:
        return

    where = issue.outlet_name or issue.court_name or "the site"
    desc = (issue.description or "")[:140]
    urgent = " [URGENT]" if issue.is_urgent else ""
    outlet_id = issue.outlet_id or None

    def _notice(**kw):
        try:
            create_notice(db, court_id=issue.court_id, outlet_id=outlet_id, **kw)
        except Exception as e:  # noqa: BLE001
            logger.warning("ticket notice failed for #%s: %s", issue.id, e)

    # 1) Targeted maintenance team(s) — immediate; they also own the 6h reminder.
    if targets:
        _notice(
            audience="role", type="maintenance_assigned",
            title=f"New maintenance ticket #{issue.id}{urgent}",
            body=f"{issue.issue_type} at {where}: {desc}",
            target_roles=targets,
        )

    # 2) Mentions — always notified immediately (role and/or individual).
    mention_roles = [m["value"] for m in mentions if m.get("kind") == "role" and m.get("value")]
    if mention_roles:
        _notice(
            audience="role", type="maintenance_mention",
            title=f"You're mentioned on ticket #{issue.id}{urgent}",
            body=f"{issue.issue_type} at {where}: {desc}",
            target_roles=mention_roles,
        )
    for m in mentions:
        if m.get("kind") != "user":
            continue
        val = str(m.get("value") or "")
        if val.startswith("staff:") and val[6:].isdigit():
            _notice(
                audience="role", type="maintenance_mention",
                title=f"You're mentioned on ticket #{issue.id}{urgent}",
                body=f"{issue.issue_type} at {where}: {desc}",
                recipient_staff_id=int(val[6:]),
            )
        elif val.startswith("manager:") and val[8:].isdigit():
            _notice(
                audience="role", type="maintenance_mention",
                title=f"You're mentioned on ticket #{issue.id}{urgent}",
                body=f"{issue.issue_type} at {where}: {desc}",
                recipient_manager_id=int(val[8:]),
            )

    # 3) Management tier — ONE immediate alert, but ONLY when Azimuth Maintenance
    #    is a target (locked matrix). A Crownest-Maintenance-only ticket reaches
    #    the management tier via the 4-day escalation instead, not at raise time.
    if "azimuth_maintenance" in targets:
        _notice(
            audience="role", type="maintenance_new_review",
            title=f"Maintenance ticket #{issue.id} raised{urgent}",
            body=f"{issue.issue_type} at {where} — assigned to Azimuth Maintenance.",
            target_roles=MANAGEMENT_TIER_ROLES,
        )


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
    user: CurrentUser = Depends(get_current_user),
):
    """Raise a maintenance ticket.

    • **Crownest Ops Head** — general (court/zone-level) OR outlet-specific, and
      may set target team(s) + mentions + urgent right at raise time.
    • **Outlet manager/staff** — raise for their OWN outlet (resolved from
      membership); the ticket lands in the ops-head TRIAGE queue
      (triage_status='pending', no targets) to be routed.
    """
    is_ops = user.is_ops_head
    if not (is_ops or user.is_outlet_user):
        raise HTTPException(status_code=403, detail="You cannot raise maintenance tickets.")

    scope = "outlet"
    court = None
    outlet = None
    target_teams: list = []
    mentions: list = []
    is_urgent = False

    if is_ops:
        scope = (body.scope or "outlet").lower()
        if scope not in ("general", "outlet"):
            raise HTTPException(status_code=400, detail="scope must be 'general' or 'outlet'.")
        target_teams = _validate_targets(body.target_teams)
        mentions = _mentions_to_dicts(body.mentions)
        is_urgent = bool(body.is_urgent)

        if scope == "general":
            if body.court_id is None:
                raise HTTPException(status_code=400, detail="court_id (zone) is required for a general ticket.")
            court = db.query(Court).filter(Court.id == body.court_id, Court.is_active == 1).first()
            if not court:
                raise HTTPException(status_code=404, detail="Court (zone) not found.")
        else:  # outlet-specific
            if body.outlet_id is None:
                raise HTTPException(status_code=400, detail="outlet_id is required for an outlet ticket.")
            outlet = db.query(Outlet).filter(Outlet.id == body.outlet_id, Outlet.is_active == 1).first()
            if not outlet:
                raise HTTPException(status_code=404, detail="Outlet not found or inactive.")
            court = db.query(Court).filter(Court.id == outlet.court_id).first()
            if not court:
                raise HTTPException(status_code=404, detail="Associated court not found.")
    else:
        # Outlet user → their OWN outlet, resolved from membership (never trusted
        # blindly): single-outlet caller may omit outlet_id; a multi-outlet owner
        # must send one, and it must be an outlet they belong to.
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

    # Outlet-raised tickets always start in triage; ops-head tickets are 'routed'
    # once they carry target teams (else they too await routing).
    triage_status = "routed" if (is_ops and target_teams) else "pending"

    issue = MaintenanceIssue(
        court_id=court.id,
        court_name=court.name,
        outlet_id=(outlet.id if outlet else 0),
        outlet_name=(outlet.vendor_name.split("(")[0].strip() if outlet else ""),
        staff_name=user.name,              # ✅ identity from JWT, not body
        raised_by_email=user.email,
        issue_type=body.issue_type.value,
        priority=body.priority.value,
        description=body.description,
        photo_url=body.photo_url,
        status=IssueStatus.RAISED.value,
        scope=scope,
        raised_by_role=user.role,
        raised_by_id=user.id,
        raised_by_table=user.user_type,
        is_urgent=is_urgent,
        target_teams=_dump_list(target_teams),
        mentions=_dump_list(mentions),
        triage_status=triage_status,
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)

    await _notify(issue)

    if is_ops:
        # Ops-head raise: start the 6h-reminder clock once the ticket has a
        # target team, then fire the immediate role-based notifications
        # (targeted team(s) + mentions + management-tier once for an azimuth
        # target). Crownest-maint-only tickets skip the immediate mgmt alert.
        if target_teams:
            issue.last_reminder_at = datetime.utcnow()
            db.commit()
        _dispatch_routed_notifications(db, issue)
    else:
        # Outlet-raised: lands in the Crownest Ops Head triage queue to be routed.
        _notify_triage(db, issue)
    return _to_out(issue)


@router.put("/maintenance/{issue_id}/route", response_model=IssueOut)
async def route_ticket(
    body: RouteTicketInput,
    issue_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_ops_head),
):
    """Ops-head triage: set/replace a ticket's target team(s) + mentions (+
    optionally scope/urgent). Used to route outlet-raised tickets to the right
    maintenance team, or to re-route/redirect an existing ticket."""
    issue = _get_issue_or_404(db, issue_id)

    targets = _validate_targets(body.target_teams)
    mentions = _mentions_to_dicts(body.mentions)

    issue.target_teams = _dump_list(targets)
    issue.mentions = _dump_list(mentions)
    if body.scope:
        s = body.scope.lower()
        if s not in ("general", "outlet"):
            raise HTTPException(status_code=400, detail="scope must be 'general' or 'outlet'.")
        issue.scope = s
    if body.is_urgent is not None:
        issue.is_urgent = bool(body.is_urgent)
    issue.triage_status = "routed" if targets else "pending"

    db.commit()
    db.refresh(issue)

    await _notify(issue)
    # Start the 6h-reminder clock now the ticket has target team(s), then fire
    # the immediate role-based notifications for this routing.
    if targets:
        issue.last_reminder_at = datetime.utcnow()
        db.commit()
    _dispatch_routed_notifications(db, issue)
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
    elif user.is_maintenance:
        # Maintenance worker: only tickets that target their role or mention them.
        q = _apply_maintenance_visibility(q, user)
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
    elif user.is_maintenance:
        # Maintenance worker: only a ticket that targets their role or mentions them.
        if not _can_action_ticket(user, issue):
            raise HTTPException(
                status_code=403, detail="This ticket is not assigned to you."
            )
    elif user.is_etl_staff:
        # Scope ETL staff to their own court (mirrors list_issues); without this
        # any ETL staff could read any court's ticket by guessing its id.
        if user.court_id is None or issue.court_id != user.court_id:
            raise HTTPException(
                status_code=403, detail="This ticket belongs to another court."
            )
    # Management accounts are unrestricted (they oversee every zone).
    return _to_out(issue)


@router.put("/maintenance/{issue_id}/assign", response_model=IssueOut)
async def assign_technician(
    body: AssignTechnicianInput,
    issue_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Assign a technician. Allowed for management OR a targeted maintenance
    role (the head assigns their own technician). Only valid from RAISED or
    DISPUTED."""
    issue = _get_issue_or_404(db, issue_id)
    if not _can_action_ticket(user, issue):
        raise HTTPException(status_code=403, detail="This ticket is not assigned to you.")

    if issue.status not in (IssueStatus.RAISED.value, IssueStatus.DISPUTED.value, IssueStatus.ASSIGNED.value):
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
    user: CurrentUser = Depends(get_current_user),
):
    """Mark resolved — starts the 24h verification window. Allowed for
    management OR a targeted maintenance role."""
    issue = _get_issue_or_404(db, issue_id)
    if not _can_action_ticket(user, issue):
        raise HTTPException(status_code=403, detail="This ticket is not assigned to you.")

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
    user: CurrentUser = Depends(get_current_user),
):
    """Verify the fix (only when RESOLVED). The owning outlet verifies their own
    ticket; management (incl. the ops head who raised a general/ops ticket) may
    also verify."""
    issue = _get_issue_or_404(db, issue_id)
    if user.is_management:
        pass
    elif user.is_outlet_user:
        _assert_outlet_owns(user, issue)
    else:
        raise HTTPException(status_code=403, detail="You cannot verify this ticket.")

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
