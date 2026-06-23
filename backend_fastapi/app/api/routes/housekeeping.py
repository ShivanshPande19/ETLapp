# app/api/routes/housekeeping.py

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import desc
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from ...database import get_db
from ...models.housekeeping import HkTask, HkRecurring
from ...core.uploads import save_upload_image
from ..deps import CurrentUser, get_current_user
from .events import notify_clients

router = APIRouter()


def _upsert_insert(db: Session):
    """Return the dialect-correct INSERT construct. Postgres and SQLite both
    expose `.on_conflict_do_update(index_elements=..., set_=...)`, but the
    SQLite construct cannot be compiled by the Postgres dialect (and vice
    versa) — so we must pick the right one at runtime."""
    dialect = db.get_bind().dialect.name
    return pg_insert(HkTask) if dialect == "postgresql" else sqlite_insert(HkTask)

_COURTS     = [1, 2, 3]
_SHIFTS     = ["morning", "day", "night"]
_WEEKLY_ID  = "flagswash"
_MONTHLY_ID = "fireaudit"

_DAILY_TASK_IDS = [
    "floorclean",
    "tablechairclean",
    "binclean",
    "trayclean",
    "binempty",
    "pestspray",
]
TASKS_PER_SHIFT = len(_DAILY_TASK_IDS)


# ─── Pydantic schemas ─────────────────────────────────────────────────────────


class TaskSubmitItem(BaseModel):
    task_id:    str
    task_title: str
    is_done:    bool
    photo_url:  Optional[str] = None
    done_at:    Optional[str] = None


class ShiftSubmitRequest(BaseModel):
    court_id:     int
    shift:        str
    date:         str
    tasks:        List[TaskSubmitItem]
    submitted_by: Optional[int] = None


class RecurringTaskRequest(BaseModel):
    court_id:  int
    photo_url: Optional[str] = None
    done_by:   Optional[int] = None


# ─── SSE helper ───────────────────────────────────────────────────────────────

# Main event loop — main.py ke lifespan mein set hoga
_main_loop: asyncio.AbstractEventLoop | None = None


def _fire_notify(event: dict) -> None:
    """AnyIO worker thread se main event loop pe safely notify karo."""
    global _main_loop
    try:
        if _main_loop is None or not _main_loop.is_running():
            return
        asyncio.run_coroutine_threadsafe(notify_clients(event), _main_loop)
    except Exception as e:
        print(f"[SSE] notify failed: {e}")


# ─── Helpers ──────────────────────────────────────────────────────────────────


def _shift_status(db: Session, court_id: int, shift: str, date: str) -> dict:
    rows = (
        db.query(HkTask)
        .filter(
            HkTask.court_id == court_id,
            HkTask.shift    == shift,
            HkTask.date     == date,
        )
        .order_by(HkTask.id)
        .all()
    )

    tasks = [
        {
            "task_id":      r.task_id,
            "task_title":   r.task_title or r.task_id,
            "is_done":      r.is_done,
            "photo_url":    r.photo_url,
            "done_at":      r.done_at,
            "done_by_name": r.done_by_name,
        }
        for r in rows
    ]

    done      = sum(1 for t in tasks if t["is_done"])
    total     = TASKS_PER_SHIFT
    submitted = (done == total) and (total > 0)

    return {
        "shift":     shift,
        "total":     total,
        "done":      done,
        "submitted": submitted,
        "tasks":     tasks,
    }


def _get_latest_recurring(
    db: Session, court_id: int, task_type: str, task_id: str
) -> Optional[HkRecurring]:
    return (
        db.query(HkRecurring)
        .filter(
            HkRecurring.court_id  == court_id,
            HkRecurring.task_type == task_type,
            HkRecurring.task_id   == task_id,
        )
        .order_by(desc(HkRecurring.done_at))
        .first()
    )


def _parse_done_at(row: Optional[HkRecurring]) -> Optional[datetime]:
    if row is None or not row.done_at:
        return None
    try:
        return datetime.fromisoformat(row.done_at)
    except (ValueError, TypeError):
        return None


def _recurring_status(
    db: Session,
    court_id: int,
    task_type: str,
    task_id: str,
    interval_days: int,
) -> dict:
    row       = _get_latest_recurring(db, court_id, task_type, task_id)
    last_done = _parse_done_at(row)

    next_due   = (last_done + timedelta(days=interval_days)) if last_done else None
    now        = datetime.now()
    is_overdue = (next_due < now) if next_due else True

    return {
        "court_id":     court_id,
        "last_done_at": last_done.isoformat() if last_done else None,
        "next_due_at":  next_due.isoformat()  if next_due  else None,
        "photo_url":    row.photo_url if row else None,
        "done_by_name": row.done_by_name if row else None,
        "is_overdue":   is_overdue,
    }


# ─── Endpoints ────────────────────────────────────────────────────────────────


@router.post("/upload-photo", status_code=status.HTTP_201_CREATED)
async def upload_housekeeping_photo(
    photo: UploadFile = File(...),
    _user=Depends(get_current_user),
):
    """Persist a (watermarked) housekeeping proof photo on the Railway volume
    and return its public URL path. Replaces the old Cloudinary flow — the
    client compresses + watermarks (location + time) before uploading."""
    photo_url = await save_upload_image(photo, "housekeeping", "hk")
    return {"photo_url": photo_url}


@router.post("/submit", status_code=status.HTTP_200_OK)
def submit_shift(
    body: ShiftSubmitRequest,
    db:   Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    if not body.tasks:
        raise HTTPException(
            status_code=422, detail="tasks list must not be empty"
        )

    for task in body.tasks:
        # Record who completed it (from the JWT, never the client body).
        done_name = user.name if task.is_done else None
        stmt = (
            _upsert_insert(db)
            .values(
                court_id     = body.court_id,
                shift        = body.shift,
                date         = body.date,
                task_id      = task.task_id,
                task_title   = task.task_title,
                is_done      = task.is_done,
                photo_url    = task.photo_url,
                done_at      = task.done_at,
                done_by_name = done_name,
            )
            .on_conflict_do_update(
                index_elements=["court_id", "shift", "date", "task_id"],
                set_={
                    "is_done":      task.is_done,
                    "photo_url":    task.photo_url,
                    "done_at":      task.done_at,
                    "task_title":   task.task_title,
                    "done_by_name": done_name,
                },
            )
        )
        db.execute(stmt)

    db.commit()

    # ✅ SSE notify
    _fire_notify({
        "type":     "housekeeping_update",
        "court_id": body.court_id,
        "shift":    body.shift,
        "date":     body.date,
    })

    return {"status": "ok", "submitted": len(body.tasks)}


@router.get("/status")
def get_status(
    date: Optional[str] = None,
    db:   Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    target = date or datetime.now().strftime("%Y-%m-%d")

    courts = [
        {
            "court_id": cid,
            "date":     target,
            "shifts":   [_shift_status(db, cid, s, target) for s in _SHIFTS],
        }
        for cid in _COURTS
    ]

    weekly_tasks  = [
        _recurring_status(db, cid, "weekly",  _WEEKLY_ID,  7)
        for cid in _COURTS
    ]
    monthly_tasks = [
        _recurring_status(db, cid, "monthly", _MONTHLY_ID, 30)
        for cid in _COURTS
    ]

    return {
        "date":          target,
        "courts":        courts,
        "weekly_tasks":  weekly_tasks,
        "monthly_tasks": monthly_tasks,
    }


@router.patch("/weekly", status_code=status.HTTP_200_OK)
def mark_weekly_done(
    body: RecurringTaskRequest,
    db:   Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    row       = _get_latest_recurring(db, body.court_id, "weekly", _WEEKLY_ID)
    last_done = _parse_done_at(row)
    now       = datetime.now()

    if last_done:
        next_due = last_done + timedelta(days=7)
        if now < next_due:
            remaining = (next_due - now).days + (
                1 if (next_due - now).seconds > 0 else 0
            )
            raise HTTPException(
                status_code=400,
                detail={
                    "code":           "COOLDOWN_ACTIVE",
                    "message":        f"Weekly task available again in {remaining} days.",
                    "remaining_days": remaining,
                    "next_due_at":    next_due.isoformat(),
                },
            )

    _add_recurring(db, body, "weekly", _WEEKLY_ID, done_by_name=user.name)

    # ✅ SSE notify
    _fire_notify({
        "type":     "housekeeping_update",
        "court_id": body.court_id,
        "shift":    "all",
        "date":     datetime.now().strftime("%Y-%m-%d"),
    })

    return {
        "status":   "ok",
        "task":     "flags_washing",
        "court_id": body.court_id,
    }


@router.patch("/monthly", status_code=status.HTTP_200_OK)
def mark_monthly_done(
    body: RecurringTaskRequest,
    db:   Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    row       = _get_latest_recurring(db, body.court_id, "monthly", _MONTHLY_ID)
    last_done = _parse_done_at(row)
    now       = datetime.now()

    if last_done:
        next_due = last_done + timedelta(days=30)
        if now < next_due:
            remaining = (next_due - now).days + (
                1 if (next_due - now).seconds > 0 else 0
            )
            raise HTTPException(
                status_code=400,
                detail={
                    "code":           "COOLDOWN_ACTIVE",
                    "message":        f"Monthly task available again in {remaining} days.",
                    "remaining_days": remaining,
                    "next_due_at":    next_due.isoformat(),
                },
            )

    _add_recurring(db, body, "monthly", _MONTHLY_ID, done_by_name=user.name)

    # ✅ SSE notify
    _fire_notify({
        "type":     "housekeeping_update",
        "court_id": body.court_id,
        "shift":    "all",
        "date":     datetime.now().strftime("%Y-%m-%d"),
    })

    return {
        "status":   "ok",
        "task":     "fire_safety_audit",
        "court_id": body.court_id,
    }


def _add_recurring(
    db: Session,
    body: RecurringTaskRequest,
    task_type: str,
    task_id: str,
    done_by_name: Optional[str] = None,
) -> None:
    row = HkRecurring(
        court_id     = body.court_id,
        task_type    = task_type,
        task_id      = task_id,
        done_at      = datetime.now().isoformat(),
        photo_url    = body.photo_url,
        done_by      = body.done_by,
        done_by_name = done_by_name,
    )
    db.add(row)
    db.commit()