# app/services/team_task_service.py
"""Team tasks: who may take part, the people directory, notifications, reminders.

Kept apart from api/routes/team_tasks.py so the scheduler can run the reminder
pass without importing a router, and so the rules below have one home.

WHO TAKES PART, AND WHO MAY GIVE A TASK TO WHOM
───────────────────────────────────────────────
Two tiers take part:

  HEADS  — Azimuth Management, Crownest Head, Operations - Office,
           Crownest Ops Head
           (+ the legacy full-access management roles)
  FIELD  — Crownest Zone Manager, Crownest Maintenance Head,
           Azimuth Maintenance

  a head   → any other head, or anyone in the field tier
  field    → the Crownest Ops Head ONLY

Nobody else takes part at all: ETL staff, outlet owners and outlet staff can
neither give nor receive a team task, never appear in the
directory, and get 403 from every endpoint. `can_assign` is the one place this
matrix lives; the directory and the create endpoint both go through it.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta
from typing import List, Optional, Tuple

from sqlalchemy.orm import Session

from ..api.deps import MAINTENANCE_ROLES, MANAGEMENT_ROLES, ZONE_MANAGER_ROLES
from ..api.routes.events import fire_notify
from ..models.manager import Manager
from ..models.sale import Court
from ..models.staff import Staff
from ..models.team_task import OPEN_STATUSES, TeamTask
from .notice_service import create_notice

logger = logging.getLogger("team_tasks")

OPS_HEAD_ROLE = "crownest_ops_head"

# Heads: may give a task to any head and to the field tier.
HEAD_ROLES = frozenset(MANAGEMENT_ROLES)
# Field: may give a task only to the Ops Head; may receive from any head.
FIELD_ROLES = frozenset(ZONE_MANAGER_ROLES | MAINTENANCE_ROLES)

# Everyone who takes part. ETL staff and outlet roles are deliberately absent.
TEAM_TASK_ROLES = frozenset(HEAD_ROLES | FIELD_ROLES)

ROLE_LABELS = {
    "crownest_head": "Crownest Head",
    "operations_office": "Operations - Office",
    "crownest_ops_head": "Crownest Ops Head",
    "azimuth_management": "Azimuth Management",
    "etl_manager": "Management",
    "manager": "Management",
    "crownest_zone_manager": "Zone Head",
    "crownest_maintenance_head": "Crownest Maintenance Head",
    "azimuth_maintenance": "Azimuth Maintenance",
    "etl_staff": "ETL Staff",
    "staff": "ETL Staff",
}

# Directory order: heads first, floor staff last.
_ROLE_ORDER = [
    "crownest_head",
    "operations_office",
    "crownest_ops_head",
    "azimuth_management",
    "etl_manager",
    "manager",
    "crownest_zone_manager",
    "crownest_maintenance_head",
    "azimuth_maintenance",
    "etl_staff",
    "staff",
]

# A task due within this window gets one "due soon" reminder.
DUE_SOON_WINDOW = timedelta(hours=2)


def role_label(role: Optional[str]) -> str:
    return ROLE_LABELS.get(role or "", role or "")


def is_team_role(role: Optional[str]) -> bool:
    return role in TEAM_TASK_ROLES


def can_assign(from_role: Optional[str], to_role: Optional[str]) -> bool:
    """THE assignment matrix (see the module docstring)."""
    if from_role in HEAD_ROLES:
        return to_role in TEAM_TASK_ROLES
    if from_role in FIELD_ROLES:
        return to_role == OPS_HEAD_ROLE
    return False


def person_key(user_type: str, user_id: int) -> str:
    return f"{user_type}:{user_id}"


def parse_person_key(key: Optional[str]) -> Optional[Tuple[str, int]]:
    """"manager:3" -> ("manager", 3). None for anything malformed."""
    if not key or ":" not in key:
        return None
    kind, _, raw = key.partition(":")
    if kind not in ("manager", "staff"):
        return None
    try:
        ident = int(raw)
    except (TypeError, ValueError):
        return None
    return (kind, ident) if ident > 0 else None


def _zone_ids(raw) -> List[int]:
    if not raw:
        return []
    try:
        v = json.loads(raw)
        return [int(x) for x in v] if isinstance(v, list) else []
    except Exception:  # noqa: BLE001
        return []


def find_person(db: Session, user_type: str, user_id: int):
    """The ACTIVE internal account behind (type, id), or None.

    None covers every reason a task must not go to them: no such row,
    deactivated, or a vendor (outlet) account.
    """
    model = Manager if user_type == "manager" else Staff if user_type == "staff" else None
    if model is None:
        return None
    row = (
        db.query(model)
        .filter(model.id == user_id, model.is_active == True)  # noqa: E712
        .first()
    )
    if row is None or not is_team_role(row.role):
        return None
    return row


def list_people(
    db: Session,
    *,
    exclude: Optional[Tuple[str, int]] = None,
    from_role: Optional[str] = None,
) -> List[dict]:
    """Everyone the caller (`from_role`) can give a task to, minus the caller.
    Names, roles and zone only — no email or phone leaves here."""
    court_names = {c.id: c.name for c in db.query(Court.id, Court.name).all()}
    people: List[dict] = []

    for m in (
        db.query(Manager)
        .filter(Manager.is_active == True, Manager.role.in_(tuple(TEAM_TASK_ROLES)))  # noqa: E712
        .all()
    ):
        people.append(
            {
                "key": person_key("manager", m.id),
                "name": m.name,
                "role": m.role,
                "role_label": role_label(m.role),
                "zone": None,
            }
        )

    for s in (
        db.query(Staff)
        .filter(Staff.is_active == True, Staff.role.in_(tuple(TEAM_TASK_ROLES)))  # noqa: E712
        .all()
    ):
        ids = _zone_ids(s.zone_court_ids) or ([s.court_id] if s.court_id else [])
        zone = ", ".join(court_names[i] for i in ids if i in court_names) or None
        people.append(
            {
                "key": person_key("staff", s.id),
                "name": s.name,
                "role": s.role,
                "role_label": role_label(s.role),
                "zone": zone,
            }
        )

    if exclude is not None:
        skip = person_key(*exclude)
        people = [p for p in people if p["key"] != skip]
    if from_role is not None:
        people = [p for p in people if can_assign(from_role, p["role"])]

    def _rank(p: dict):
        r = p["role"]
        return (_ROLE_ORDER.index(r) if r in _ROLE_ORDER else len(_ROLE_ORDER), p["name"].lower())

    people.sort(key=_rank)
    return people


# ─── Notifications ───────────────────────────────────────────────────────────

def _home_court(db: Session, user_type: str, user_id: int) -> Optional[int]:
    """The court whose live channel this person's app listens on. Staff-table
    accounts subscribe to their own court; manager accounts to the shared
    channel (None)."""
    if user_type != "staff":
        return None
    row = db.query(Staff.court_id).filter(Staff.id == user_id).first()
    return row[0] if row else None


def notify_person(
    db: Session,
    *,
    user_type: str,
    user_id: int,
    type: str,
    title: str,
    body: Optional[str],
    task: TeamTask,
) -> None:
    """One inbox notice + live ping + push, addressed to exactly one person.

    Goes through the same choke point as every other notification
    (notice_service.create_notice), so targeting stays in push_targeting and a
    user can always open what they were pushed. Never raises — a notification
    failing must not undo the task change that triggered it.
    """
    try:
        create_notice(
            db,
            audience="role",
            type=type,
            title=title,
            body=body,
            # The recipient's own court, so the live "refresh your bell" ping
            # reaches the channel their app is listening on.
            court_id=_home_court(db, user_type, user_id),
            recipient_manager_id=user_id if user_type == "manager" else None,
            recipient_staff_id=user_id if user_type == "staff" else None,
            route=f"/tasks/{task.id}",
        )
    except Exception as e:  # noqa: BLE001
        db.rollback()
        logger.error("notify failed for task#%s (%s): %s", getattr(task, "id", "?"), type, e)


def ping_task(db: Session, task: TeamTask) -> None:
    """Tell both people's open apps to re-fetch their tasks.

    Carries ids only — the lists themselves are fetched through the
    authenticated, party-scoped endpoints. Sent on the shared channel and on
    each party's own court channel, which is where staff-table accounts listen.
    """
    try:
        courts = {0}
        for kind, ident in (
            (task.assigner_type, task.assigner_id),
            (task.assignee_type, task.assignee_id),
        ):
            c = _home_court(db, kind, ident)
            if c:
                courts.add(c)
        for c in sorted(courts):
            fire_notify({"type": "task_update", "court_id": c, "task_id": task.id})
    except Exception as e:  # noqa: BLE001
        logger.warning("task ping failed: %s", e)


def _short(title: str, limit: int = 80) -> str:
    t = (title or "").strip()
    return t if len(t) <= limit else t[: limit - 1].rstrip() + "…"


# ─── Reminders (called hourly by the scheduler) ──────────────────────────────

def run_task_reminders(db: Session, now: Optional[datetime] = None) -> dict:
    """One pass over open tasks with a deadline.

    • due within DUE_SOON_WINDOW  → one "due soon" nudge to the assignee
    • past its deadline           → one "overdue" notice to the assignee AND one
                                    to the assigner

    Each fires at most once per task (stamped on the row), so a task that stays
    overdue for a week does not notify every hour.
    """
    now = now or datetime.utcnow()
    out = {"due_soon": 0, "overdue": 0}

    open_with_deadline = (
        db.query(TeamTask)
        .filter(TeamTask.status.in_(OPEN_STATUSES), TeamTask.due_at.isnot(None))
    )

    overdue = open_with_deadline.filter(
        TeamTask.due_at < now, TeamTask.overdue_notified_at.is_(None)
    ).all()
    for t in overdue:
        t.overdue_notified_at = now
        # A task already overdue never also needs the "due soon" nudge.
        t.due_soon_notified_at = t.due_soon_notified_at or now
        db.commit()
        notify_person(
            db,
            user_type=t.assignee_type,
            user_id=t.assignee_id,
            type="task_overdue",
            title="Task overdue",
            body=f"“{_short(t.title)}” from {t.assigner_name} is past its deadline.",
            task=t,
        )
        notify_person(
            db,
            user_type=t.assigner_type,
            user_id=t.assigner_id,
            type="task_overdue",
            title="Task overdue",
            body=f"{t.assignee_name} has not completed “{_short(t.title)}”.",
            task=t,
        )
        out["overdue"] += 1

    due_soon = open_with_deadline.filter(
        TeamTask.due_at >= now,
        TeamTask.due_at <= now + DUE_SOON_WINDOW,
        TeamTask.due_soon_notified_at.is_(None),
    ).all()
    for t in due_soon:
        t.due_soon_notified_at = now
        db.commit()
        notify_person(
            db,
            user_type=t.assignee_type,
            user_id=t.assignee_id,
            type="task_due_soon",
            title="Task due soon",
            body=f"“{_short(t.title)}” from {t.assigner_name} is due within 2 hours.",
            task=t,
        )
        out["due_soon"] += 1

    return out
