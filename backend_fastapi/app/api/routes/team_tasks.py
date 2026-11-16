# app/api/routes/team_tasks.py
"""Team tasks — one person gives a task to one other person.

RULES (each is enforced here, on the server — the app only mirrors them)
────────────────────────────────────────────────────────────────────────
• Who takes part: the heads and the field tier only, and who may give a task
  to whom follows the matrix in services/team_task_service.py (`can_assign`).
  Everyone else — ETL staff, outlet owners / outlet staff — gets 403 on every
  endpoint.
• Visibility: a task is visible to its assigner and its assignee, nobody else.
  Anyone else — including full-access management — gets 404, not 403, so a
  task's existence is not disclosed either.
• Who may do what:
      assignee  → seen, start, complete
      assigner  → reopen (a DONE task), cancel (an open task)
      either    → comment
• Proof of work: ON by default. When it is on, completing without at least one
  photo is rejected. The assigner may switch it off when giving the task.
• Lifecycle:  ASSIGNED → IN_PROGRESS → DONE        (assignee)
              DONE → ASSIGNED                       (assigner reopens, with a reason)
              ASSIGNED | IN_PROGRESS → CANCELLED    (assigner)
  Every transition is a conditional UPDATE on the expected current status, so
  two taps racing each other cannot both succeed.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import and_, case, or_
from sqlalchemy.orm import Session

from ...core.uploads import save_upload_image
from ...database import get_db
from ...models.sale import Court
from ...models.team_task import (
    OPEN_STATUSES,
    PRIORITIES,
    STATUS_ASSIGNED,
    STATUS_CANCELLED,
    STATUS_DONE,
    STATUS_IN_PROGRESS,
    TeamTask,
    TeamTaskEvent,
)
from ...services import team_task_service as svc
from ..deps import CurrentUser, get_current_user

router = APIRouter()

MAX_PROOF_PHOTOS = 6
# Only paths this API itself handed out (see /upload-photo) are accepted as
# proof, so a client cannot attach an arbitrary URL to a task.
_PROOF_PATH = re.compile(r"^uploads/team_tasks/[A-Za-z0-9_.-]+$")

_IST = timedelta(hours=5, minutes=30)


# ─── Access ──────────────────────────────────────────────────────────────────

def require_team_member(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    if not svc.is_team_role(user.role):
        raise HTTPException(
            status_code=403, detail="Team tasks are not available for your account."
        )
    return user


def _mine(user: CurrentUser):
    return and_(
        TeamTask.assignee_type == user.user_type, TeamTask.assignee_id == user.id
    )


def _sent(user: CurrentUser):
    return and_(
        TeamTask.assigner_type == user.user_type, TeamTask.assigner_id == user.id
    )


def _visible_to(user: CurrentUser):
    """THE visibility rule: the two people on the task, nobody else."""
    return or_(_mine(user), _sent(user))


def _is_assignee(user: CurrentUser, t: TeamTask) -> bool:
    return t.assignee_type == user.user_type and t.assignee_id == user.id


def _is_assigner(user: CurrentUser, t: TeamTask) -> bool:
    return t.assigner_type == user.user_type and t.assigner_id == user.id


def _get_or_404(db: Session, user: CurrentUser, task_id: int) -> TeamTask:
    task = (
        db.query(TeamTask)
        .filter(TeamTask.id == task_id, _visible_to(user))
        .first()
    )
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return task


# ─── Schemas ─────────────────────────────────────────────────────────────────

def _to_naive_utc(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def _iso(dt: Optional[datetime]) -> Optional[str]:
    """Explicit UTC, so the app never guesses the zone."""
    return None if dt is None else dt.isoformat() + "Z"


class TaskCreateIn(BaseModel):
    title: str = Field(..., max_length=120)
    description: Optional[str] = Field(None, max_length=2000)
    assignee: str = Field(..., description='"manager:<id>" or "staff:<id>"')
    priority: str = "normal"
    court_id: Optional[int] = None
    due_at: Optional[datetime] = None
    proof_required: bool = True

    @field_validator("title")
    @classmethod
    def _title(cls, v: str) -> str:
        v = (v or "").strip()
        if not v:
            raise ValueError("Give the task a title.")
        return v

    @field_validator("description")
    @classmethod
    def _desc(cls, v: Optional[str]) -> Optional[str]:
        v = (v or "").strip()
        return v or None

    @field_validator("priority")
    @classmethod
    def _prio(cls, v: str) -> str:
        if v not in PRIORITIES:
            raise ValueError(f"priority must be one of {list(PRIORITIES)}")
        return v


class CompleteIn(BaseModel):
    note: Optional[str] = Field(None, max_length=1000)
    photos: List[str] = Field(default_factory=list)


class NoteIn(BaseModel):
    note: str = Field(..., max_length=1000)

    @field_validator("note")
    @classmethod
    def _note(cls, v: str) -> str:
        v = (v or "").strip()
        if not v:
            raise ValueError("Write a short note.")
        return v


class OptionalNoteIn(BaseModel):
    note: Optional[str] = Field(None, max_length=1000)


class PersonOut(BaseModel):
    key: str
    name: str
    role: Optional[str] = None
    role_label: str = ""
    zone: Optional[str] = None


class EventOut(BaseModel):
    id: int
    kind: str
    actor_name: str
    actor_role_label: str
    mine: bool
    note: Optional[str] = None
    photos: List[str] = []
    created_at: Optional[str] = None


class TaskOut(BaseModel):
    id: int
    title: str
    description: Optional[str] = None
    priority: str
    court_id: Optional[int] = None
    court_name: Optional[str] = None
    due_at: Optional[str] = None
    is_overdue: bool
    proof_required: bool
    status: str
    assigner: PersonOut
    assignee: PersonOut
    seen_at: Optional[str] = None
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    cancelled_at: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    completion_note: Optional[str] = None
    proof_photos: List[str] = []
    reopen_count: int = 0
    # What THIS caller may do. Decided here so the app never has to.
    i_am_assigner: bool
    i_am_assignee: bool
    can_start: bool
    can_complete: bool
    can_reopen: bool
    can_cancel: bool
    can_comment: bool


class TaskDetailOut(TaskOut):
    events: List[EventOut] = []


class SummaryOut(BaseModel):
    mine_open: int      # tasks waiting on me
    mine_overdue: int
    sent_open: int      # tasks I gave that are still open
    sent_overdue: int


class TaskListOut(BaseModel):
    tasks: List[TaskOut]
    has_more: bool
    summary: SummaryOut


# ─── Serialisation ───────────────────────────────────────────────────────────

def _json_list(raw: Optional[str]) -> List[str]:
    if not raw:
        return []
    try:
        v = json.loads(raw)
        return [str(x) for x in v] if isinstance(v, list) else []
    except Exception:  # noqa: BLE001
        return []


def _is_overdue(t: TeamTask, now: datetime) -> bool:
    return t.status in OPEN_STATUSES and t.due_at is not None and t.due_at < now


def _task_fields(t: TeamTask, user: CurrentUser, now: datetime) -> dict:
    assignee = _is_assignee(user, t)
    assigner = _is_assigner(user, t)
    is_open = t.status in OPEN_STATUSES
    return dict(
        id=t.id,
        title=t.title,
        description=t.description,
        priority=t.priority,
        court_id=t.court_id,
        court_name=t.court_name,
        due_at=_iso(t.due_at),
        is_overdue=_is_overdue(t, now),
        proof_required=bool(t.proof_required),
        status=t.status,
        assigner=PersonOut(
            key=svc.person_key(t.assigner_type, t.assigner_id),
            name=t.assigner_name,
            role=t.assigner_role,
            role_label=svc.role_label(t.assigner_role),
        ),
        assignee=PersonOut(
            key=svc.person_key(t.assignee_type, t.assignee_id),
            name=t.assignee_name,
            role=t.assignee_role,
            role_label=svc.role_label(t.assignee_role),
        ),
        seen_at=_iso(t.seen_at),
        started_at=_iso(t.started_at),
        completed_at=_iso(t.completed_at),
        cancelled_at=_iso(t.cancelled_at),
        created_at=_iso(t.created_at),
        updated_at=_iso(t.updated_at),
        completion_note=t.completion_note,
        proof_photos=_json_list(t.proof_photos),
        reopen_count=int(t.reopen_count or 0),
        i_am_assigner=assigner,
        i_am_assignee=assignee,
        can_start=assignee and t.status == STATUS_ASSIGNED,
        can_complete=assignee and is_open,
        can_reopen=assigner and t.status == STATUS_DONE,
        can_cancel=assigner and is_open,
        can_comment=t.status != STATUS_CANCELLED,
    )


def _out(t: TeamTask, user: CurrentUser, now: Optional[datetime] = None) -> TaskOut:
    return TaskOut(**_task_fields(t, user, now or datetime.utcnow()))


def _detail(db: Session, t: TeamTask, user: CurrentUser) -> TaskDetailOut:
    rows = (
        db.query(TeamTaskEvent)
        .filter(TeamTaskEvent.task_id == t.id)
        .order_by(TeamTaskEvent.id.asc())
        .all()
    )
    events = [
        EventOut(
            id=e.id,
            kind=e.kind,
            actor_name=e.actor_name,
            actor_role_label=svc.role_label(e.actor_role),
            mine=(e.actor_type == user.user_type and e.actor_id == user.id),
            note=e.note,
            photos=_json_list(e.photos),
            created_at=_iso(e.created_at),
        )
        for e in rows
    ]
    return TaskDetailOut(**_task_fields(t, user, datetime.utcnow()), events=events)


def _summary(db: Session, user: CurrentUser, now: datetime) -> SummaryOut:
    open_q = db.query(TeamTask).filter(TeamTask.status.in_(OPEN_STATUSES))
    late = and_(TeamTask.due_at.isnot(None), TeamTask.due_at < now)
    return SummaryOut(
        mine_open=open_q.filter(_mine(user)).count(),
        mine_overdue=open_q.filter(_mine(user), late).count(),
        sent_open=open_q.filter(_sent(user)).count(),
        sent_overdue=open_q.filter(_sent(user), late).count(),
    )


# ─── Small helpers ───────────────────────────────────────────────────────────

def _log(
    db: Session,
    task: TeamTask,
    user: CurrentUser,
    kind: str,
    note: Optional[str] = None,
    photos: Optional[List[str]] = None,
) -> None:
    db.add(
        TeamTaskEvent(
            task_id=task.id,
            kind=kind,
            actor_type=user.user_type,
            actor_id=user.id,
            actor_name=user.name,
            actor_role=user.role,
            note=note,
            photos=json.dumps(photos) if photos else None,
        )
    )


def _transition(db: Session, task: TeamTask, allowed_from, values: dict) -> None:
    """Move a task to a new state ONLY if it is still in an expected one.

    A conditional UPDATE rather than read-then-write: if two requests race
    (a double tap, or the assigner cancelling while the assignee completes),
    exactly one wins and the other gets a clear 409.
    """
    values = dict(values)
    values.setdefault("updated_at", datetime.utcnow())
    changed = (
        db.query(TeamTask)
        .filter(TeamTask.id == task.id, TeamTask.status.in_(tuple(allowed_from)))
        .update(values, synchronize_session=False)
    )
    if not changed:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="This task has already changed. Refresh and try again.",
        )


def _due_label(due_at: Optional[datetime]) -> str:
    """"16 Nov, 5:30 PM" in IST, for notification text."""
    if due_at is None:
        return ""
    local = due_at + _IST
    hour12 = local.hour % 12 or 12
    ampm = "AM" if local.hour < 12 else "PM"
    return f"{local.day} {local.strftime('%b')}, {hour12}:{local.minute:02d} {ampm}"


def _q(title: str) -> str:
    t = (title or "").strip()
    return "“" + (t if len(t) <= 80 else t[:79].rstrip() + "…") + "”"


# ─── Endpoints ───────────────────────────────────────────────────────────────

@router.get("/people", response_model=List[PersonOut])
def list_people(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    """Everyone the caller can give a task to (the internal team, minus self)."""
    return [
        PersonOut(**p)
        for p in svc.list_people(
            db, exclude=(user.user_type, user.id), from_role=user.role
        )
    ]


@router.get("/summary", response_model=SummaryOut)
def summary(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    return _summary(db, user, datetime.utcnow())


@router.post("/upload-photo", status_code=201)
async def upload_task_photo(
    photo: UploadFile = File(...),
    user: CurrentUser = Depends(require_team_member),
):
    """Store one proof photo and return its path, to be passed to /complete."""
    photo_url = await save_upload_image(photo, "team_tasks", "task")
    return {"photo_url": photo_url}


@router.post("/", response_model=TaskDetailOut, status_code=201)
def create_task(
    body: TaskCreateIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    parsed = svc.parse_person_key(body.assignee)
    if parsed is None:
        raise HTTPException(status_code=400, detail="Choose who the task is for.")
    a_type, a_id = parsed
    if a_type == user.user_type and a_id == user.id:
        raise HTTPException(status_code=400, detail="You can't assign a task to yourself.")

    person = svc.find_person(db, a_type, a_id)
    if person is None:
        # One message for "no such person", "deactivated" and "not on the
        # team", so the directory cannot be probed through this endpoint.
        raise HTTPException(status_code=400, detail="That person can't be assigned tasks.")
    if not svc.can_assign(user.role, person.role):
        raise HTTPException(
            status_code=403,
            detail="You can only give tasks to the Crownest Ops Head.",
        )

    court_name = None
    if body.court_id is not None:
        court = db.query(Court).filter(Court.id == body.court_id).first()
        if court is None:
            raise HTTPException(status_code=400, detail="Unknown zone.")
        court_name = court.name

    now = datetime.utcnow()
    due_at = _to_naive_utc(body.due_at)
    # A minute of grace for phone clocks that run slightly ahead.
    if due_at is not None and due_at < now - timedelta(minutes=1):
        raise HTTPException(status_code=400, detail="The deadline must be in the future.")

    task = TeamTask(
        title=body.title,
        description=body.description,
        priority=body.priority,
        court_id=body.court_id,
        court_name=court_name,
        due_at=due_at,
        proof_required=body.proof_required,
        status=STATUS_ASSIGNED,
        assigner_type=user.user_type,
        assigner_id=user.id,
        assigner_name=user.name,
        assigner_role=user.role,
        assignee_type=a_type,
        assignee_id=a_id,
        assignee_name=person.name,
        assignee_role=person.role,
        created_at=now,
        updated_at=now,
    )
    db.add(task)
    db.flush()
    _log(db, task, user, "created")
    db.commit()
    db.refresh(task)

    due = f" · Due {_due_label(task.due_at)}" if task.due_at else ""
    svc.notify_person(
        db,
        user_type=a_type,
        user_id=a_id,
        type="task_assigned",
        title=f"New task from {user.name}",
        body=f"{_q(task.title)}{due}",
        task=task,
    )
    svc.ping_task(db, task)
    return _detail(db, task, user)


@router.get("/", response_model=TaskListOut)
def list_tasks(
    box: str = Query("mine", pattern="^(mine|sent)$"),
    status: str = Query("open", pattern="^(open|done|cancelled|all)$"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    """`box=mine` → tasks given TO me; `box=sent` → tasks I gave."""
    now = datetime.utcnow()
    q = db.query(TeamTask).filter(_mine(user) if box == "mine" else _sent(user))

    if status == "open":
        q = q.filter(TeamTask.status.in_(OPEN_STATUSES))
    elif status == "done":
        q = q.filter(TeamTask.status == STATUS_DONE)
    elif status == "cancelled":
        q = q.filter(TeamTask.status == STATUS_CANCELLED)

    # Open work first, soonest deadline first (no deadline last), then the more
    # urgent; finished work newest first.
    status_rank = case(
        {STATUS_ASSIGNED: 0, STATUS_IN_PROGRESS: 0, STATUS_DONE: 1, STATUS_CANCELLED: 2},
        value=TeamTask.status,
        else_=3,
    )
    no_deadline = case((TeamTask.due_at.is_(None), 1), else_=0)
    prio_rank = case(
        {"urgent": 0, "high": 1, "normal": 2, "low": 3},
        value=TeamTask.priority,
        else_=2,
    )
    if status in ("done", "cancelled"):
        q = q.order_by(TeamTask.updated_at.desc(), TeamTask.id.desc())
    else:
        q = q.order_by(
            status_rank.asc(),
            no_deadline.asc(),
            TeamTask.due_at.asc(),
            prio_rank.asc(),
            TeamTask.id.desc(),
        )

    rows = q.offset(offset).limit(limit + 1).all()
    has_more = len(rows) > limit
    return TaskListOut(
        tasks=[_out(t, user, now) for t in rows[:limit]],
        has_more=has_more,
        summary=_summary(db, user, now),
    )


@router.get("/{task_id}", response_model=TaskDetailOut)
def get_task(
    task_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    return _detail(db, _get_or_404(db, user, task_id), user)


@router.post("/{task_id}/seen", response_model=TaskDetailOut)
def mark_seen(
    task_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    """The assignee opened the task. Idempotent; a no-op for the assigner."""
    task = _get_or_404(db, user, task_id)
    if _is_assignee(user, task) and task.seen_at is None:
        now = datetime.utcnow()
        changed = (
            db.query(TeamTask)
            .filter(TeamTask.id == task.id, TeamTask.seen_at.is_(None))
            .update({"seen_at": now}, synchronize_session=False)
        )
        if changed:
            _log(db, task, user, "seen")
        db.commit()
        db.refresh(task)
        if changed:
            svc.ping_task(db, task)
    return _detail(db, task, user)


@router.post("/{task_id}/start", response_model=TaskDetailOut)
def start_task(
    task_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    task = _get_or_404(db, user, task_id)
    if not _is_assignee(user, task):
        raise HTTPException(status_code=403, detail="Only the person doing the task can start it.")
    now = datetime.utcnow()
    _transition(
        db,
        task,
        (STATUS_ASSIGNED,),
        {
            "status": STATUS_IN_PROGRESS,
            "started_at": now,
            "seen_at": task.seen_at or now,
        },
    )
    _log(db, task, user, "started")
    db.commit()
    db.refresh(task)
    svc.ping_task(db, task)
    return _detail(db, task, user)


@router.post("/{task_id}/complete", response_model=TaskDetailOut)
def complete_task(
    task_id: int,
    body: CompleteIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    task = _get_or_404(db, user, task_id)
    if not _is_assignee(user, task):
        raise HTTPException(status_code=403, detail="Only the person doing the task can complete it.")

    photos = list(dict.fromkeys(p.strip() for p in body.photos if p and p.strip()))
    if len(photos) > MAX_PROOF_PHOTOS:
        raise HTTPException(
            status_code=400, detail=f"Attach at most {MAX_PROOF_PHOTOS} photos."
        )
    if any(not _PROOF_PATH.match(p) for p in photos):
        raise HTTPException(status_code=400, detail="Invalid proof photo.")
    if task.proof_required and not photos:
        raise HTTPException(
            status_code=400,
            detail="A proof photo is required to complete this task.",
        )

    note = (body.note or "").strip() or None
    now = datetime.utcnow()
    _transition(
        db,
        task,
        OPEN_STATUSES,
        {
            "status": STATUS_DONE,
            "completed_at": now,
            "started_at": task.started_at or now,
            "seen_at": task.seen_at or now,
            "completion_note": note,
            "proof_photos": json.dumps(photos) if photos else None,
        },
    )
    _log(db, task, user, "completed", note=note, photos=photos)
    db.commit()
    db.refresh(task)

    proof = " Proof attached." if photos else ""
    svc.notify_person(
        db,
        user_type=task.assigner_type,
        user_id=task.assigner_id,
        type="task_completed",
        title="Task completed",
        body=f"{user.name} completed {_q(task.title)}.{proof}",
        task=task,
    )
    svc.ping_task(db, task)
    return _detail(db, task, user)


@router.post("/{task_id}/reopen", response_model=TaskDetailOut)
def reopen_task(
    task_id: int,
    body: NoteIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    """The assigner sends a completed task back, with the reason."""
    task = _get_or_404(db, user, task_id)
    if not _is_assigner(user, task):
        raise HTTPException(status_code=403, detail="Only the person who gave the task can reopen it.")
    _transition(
        db,
        task,
        (STATUS_DONE,),
        {
            "status": STATUS_ASSIGNED,
            "completed_at": None,
            "started_at": None,
            # The proof that was rejected stays in the activity log.
            "completion_note": None,
            "proof_photos": None,
            "reopen_count": int(task.reopen_count or 0) + 1,
        },
    )
    _log(db, task, user, "reopened", note=body.note)
    db.commit()
    db.refresh(task)

    svc.notify_person(
        db,
        user_type=task.assignee_type,
        user_id=task.assignee_id,
        type="task_reopened",
        title="Task sent back",
        body=f"{user.name} reopened {_q(task.title)}: {body.note[:160]}",
        task=task,
    )
    svc.ping_task(db, task)
    return _detail(db, task, user)


@router.post("/{task_id}/cancel", response_model=TaskDetailOut)
def cancel_task(
    task_id: int,
    body: OptionalNoteIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    task = _get_or_404(db, user, task_id)
    if not _is_assigner(user, task):
        raise HTTPException(status_code=403, detail="Only the person who gave the task can cancel it.")
    note = (body.note or "").strip() or None
    _transition(
        db,
        task,
        OPEN_STATUSES,
        {"status": STATUS_CANCELLED, "cancelled_at": datetime.utcnow()},
    )
    _log(db, task, user, "cancelled", note=note)
    db.commit()
    db.refresh(task)

    svc.notify_person(
        db,
        user_type=task.assignee_type,
        user_id=task.assignee_id,
        type="task_cancelled",
        title="Task cancelled",
        body=f"{user.name} cancelled {_q(task.title)}.",
        task=task,
    )
    svc.ping_task(db, task)
    return _detail(db, task, user)


@router.post("/{task_id}/comments", response_model=TaskDetailOut)
def add_comment(
    task_id: int,
    body: NoteIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_team_member),
):
    task = _get_or_404(db, user, task_id)
    if task.status == STATUS_CANCELLED:
        raise HTTPException(status_code=409, detail="This task was cancelled.")
    _log(db, task, user, "comment", note=body.note)
    task.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(task)

    # To the OTHER person on the task.
    if _is_assigner(user, task):
        to_type, to_id = task.assignee_type, task.assignee_id
    else:
        to_type, to_id = task.assigner_type, task.assigner_id
    svc.notify_person(
        db,
        user_type=to_type,
        user_id=to_id,
        type="task_comment",
        title=f"{user.name} commented",
        body=f"{_q(task.title)}: {body.note[:160]}",
        task=task,
    )
    svc.ping_task(db, task)
    return _detail(db, task, user)
