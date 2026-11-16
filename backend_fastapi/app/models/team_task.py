# app/models/team_task.py
"""Inter-team task assignment — one person hands a task to one other person.

WHY THIS IS ITS OWN TABLE (and not a maintenance ticket)
────────────────────────────────────────────────────────
A maintenance ticket is addressed to a TEAM (a role), can only be raised by the
Ops Head, and carries repair-specific fields and a two-stage verification. A
team task is person-to-person, in any direction (a head to the ops head, a
staff member to the zone head, …), about anything.

IDENTITY
────────
People live in two tables (`managers` and `staff`) whose ids overlap —
`manager.id == 1` and `staff.id == 1` are two different people. So each side of
a task is the composite (`*_type`, `*_id`), exactly like `device_tokens`. There
is deliberately no ForeignKey on those ids. Name and role are snapshotted for
display; who may see or act on a task is always decided by (type, id).

VISIBILITY
──────────
A task is visible to its assigner and its assignee and to NOBODY else — not
even full-access management. Every read in api/routes/team_tasks.py goes
through `_visible_to`, and anything outside it answers 404.
"""

from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)

from ..database import Base

# Lifecycle. DONE can be sent back to ASSIGNED by the assigner ("reopen").
STATUS_ASSIGNED = "ASSIGNED"
STATUS_IN_PROGRESS = "IN_PROGRESS"
STATUS_DONE = "DONE"
STATUS_CANCELLED = "CANCELLED"

OPEN_STATUSES = (STATUS_ASSIGNED, STATUS_IN_PROGRESS)

PRIORITIES = ("low", "normal", "high", "urgent")


class TeamTask(Base):
    __tablename__ = "team_tasks"

    id = Column(Integer, primary_key=True, autoincrement=True)

    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    priority = Column(String, nullable=False, default="normal")

    # Optional zone tag — context only, never used for access.
    court_id = Column(Integer, nullable=True, index=True)
    court_name = Column(String, nullable=True)

    # Naive UTC, like every other timestamp in this schema. NULL = no deadline.
    due_at = Column(DateTime, nullable=True)

    # Proof of work. ON by default; the assigner may switch it off per task.
    # Enforced on the server when the task is completed.
    proof_required = Column(Boolean, nullable=False, default=True)

    status = Column(String, nullable=False, default=STATUS_ASSIGNED, index=True)

    # Who gave the task.
    assigner_type = Column(String, nullable=False)   # "manager" | "staff"
    assigner_id = Column(Integer, nullable=False)
    assigner_name = Column(String, nullable=False, default="")
    assigner_role = Column(String, nullable=True)

    # Who has to do it.
    assignee_type = Column(String, nullable=False)   # "manager" | "staff"
    assignee_id = Column(Integer, nullable=False)
    assignee_name = Column(String, nullable=False, default="")
    assignee_role = Column(String, nullable=True)

    seen_at = Column(DateTime, nullable=True)        # assignee first opened it
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    cancelled_at = Column(DateTime, nullable=True)

    # The CURRENT completion. Cleared on reopen — the earlier proof stays in the
    # activity log (team_task_events), so nothing is lost.
    completion_note = Column(Text, nullable=True)
    proof_photos = Column(Text, nullable=True)       # JSON list of upload paths
    reopen_count = Column(Integer, nullable=False, default=0)

    # Reminder bookkeeping — each fires at most once per task.
    due_soon_notified_at = Column(DateTime, nullable=True)
    overdue_notified_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(
        DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    __table_args__ = (
        # The two hot paths: "tasks for me" and "tasks I gave".
        Index("ix_team_tasks_assignee", "assignee_type", "assignee_id", "status"),
        Index("ix_team_tasks_assigner", "assigner_type", "assigner_id", "status"),
    )


class TeamTaskEvent(Base):
    """Append-only activity log for a task: who did what, when.

    kind: created | seen | started | completed | reopened | cancelled | comment
    """

    __tablename__ = "team_task_events"

    id = Column(Integer, primary_key=True, autoincrement=True)
    task_id = Column(
        Integer,
        ForeignKey("team_tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    kind = Column(String, nullable=False)

    actor_type = Column(String, nullable=False)
    actor_id = Column(Integer, nullable=False)
    actor_name = Column(String, nullable=False, default="")
    actor_role = Column(String, nullable=True)

    note = Column(Text, nullable=True)
    photos = Column(Text, nullable=True)             # JSON list (completed only)

    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
