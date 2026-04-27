# app/api/routes/housekeeping.py
# ─────────────────────────────────────────────────────────────────────────────
# Housekeeping router — uses your project's existing SQLAlchemy session.
# Drop-in replacement for the in-memory dict version.
# API contract is IDENTICAL — no Flutter changes needed.
# ─────────────────────────────────────────────────────────────────────────────

from __future__ import annotations

from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import desc
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

# ── Your existing project imports ─────────────────────────────────────────────
from ...database import get_db                    # SessionLocal dependency
from ...models.housekeeping import HkTask, HkRecurring

# Re-use your existing auth dependency (adjust import path if different)
try:
    from ...core.security import get_current_user
except ImportError:
    try:
        from ...api.deps import get_current_user
    except ImportError:
        def get_current_user():
            return {"id": 0}

router = APIRouter()

_COURTS       = [1, 2, 3]
_SHIFTS       = ["morning", "day", "night"]
_WEEKLY_ID    = "flagswash"
_MONTHLY_ID   = "fireaudit"


# ─── Pydantic schemas ─────────────────────────────────────────────────────────

class TaskSubmitItem(BaseModel):
    task_id:    str
    task_title: str
    is_done:    bool
    photo_url:  Optional[str] = None
    done_at:    Optional[str] = None


class ShiftSubmitRequest(BaseModel):
    court_id:     int
    shift:        str        # morning | day | night
    date:         str        # YYYY-MM-DD
    tasks:        List[TaskSubmitItem]
    submitted_by: Optional[int] = None


class RecurringTaskRequest(BaseModel):
    court_id:  int
    photo_url: Optional[str] = None
    done_by:   Optional[int] = None


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
            "task_id":    r.task_id,
            "task_title": r.task_title or r.task_id,
            "is_done":    r.is_done,
            "photo_url":  r.photo_url,
            "done_at":    r.done_at,
        }
        for r in rows
    ]

    done  = sum(1 for t in tasks if t["is_done"])
    total = len(tasks)

    return {
        "shift":     shift,
        "total":     total,
        "done":      done,
        "submitted": total > 0,
        "tasks":     tasks,
    }


def _recurring_status(
    db: Session,
    court_id: int,
    task_type: str,
    task_id: str,
    interval_days: int,
) -> dict:
    row = (
        db.query(HkRecurring)
        .filter(
            HkRecurring.court_id  == court_id,
            HkRecurring.task_type == task_type,
            HkRecurring.task_id   == task_id,
        )
        .order_by(desc(HkRecurring.done_at))
        .first()
    )

    last_done: Optional[datetime] = None
    if row and row.done_at:
        try:
            last_done = datetime.fromisoformat(row.done_at)
        except ValueError:
            pass

    next_due   = (last_done + timedelta(days=interval_days)) if last_done else None
    is_overdue = (next_due < datetime.now()) if next_due else True

    return {
        "court_id":     court_id,
        "last_done_at": last_done.isoformat() if last_done else None,
        "next_due_at":  next_due.isoformat()  if next_due  else None,
        "photo_url":    row.photo_url if row else None,
        "is_overdue":   is_overdue,
    }


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/submit", status_code=status.HTTP_200_OK)
def submit_shift(
    body: ShiftSubmitRequest,
    db:   Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """
    Staff submits their shift checklist.
    Uses SQLite UPSERT — re-submitting a task updates it, never duplicates.
    """
    if not body.tasks:
        raise HTTPException(status_code=422, detail="tasks list must not be empty")

    for task in body.tasks:
        # SQLite UPSERT: INSERT or UPDATE on conflict
        stmt = (
            sqlite_insert(HkTask)
            .values(
                court_id   = body.court_id,
                shift      = body.shift,
                date       = body.date,
                task_id    = task.task_id,
                task_title = task.task_title,
                is_done    = task.is_done,
                photo_url  = task.photo_url,
                done_at    = task.done_at,
            )
            .on_conflict_do_update(
                index_elements=["court_id", "shift", "date", "task_id"],
                set_={
                    "is_done":    task.is_done,
                    "photo_url":  task.photo_url,
                    "done_at":    task.done_at,
                    "task_title": task.task_title,
                },
            )
        )
        db.execute(stmt)

    db.commit()
    return {"status": "ok", "submitted": len(body.tasks)}


@router.get("/status")
def get_status(
    date: Optional[str] = None,
    db:   Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """Full housekeeping status for every court — manager + staff report."""
    target = date or datetime.now().strftime("%Y-%m-%d")

    courts = [
        {
            "court_id": cid,
            "date":     target,
            "shifts":   [_shift_status(db, cid, s, target) for s in _SHIFTS],
        }
        for cid in _COURTS
    ]

    weekly_tasks  = [_recurring_status(db, cid, "weekly",  _WEEKLY_ID,  7)  for cid in _COURTS]
    monthly_tasks = [_recurring_status(db, cid, "monthly", _MONTHLY_ID, 30) for cid in _COURTS]

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
    _user=Depends(get_current_user),
):
    _add_recurring(db, body, "weekly", _WEEKLY_ID)
    return {"status": "ok", "task": "flags_washing", "court_id": body.court_id}


@router.patch("/monthly", status_code=status.HTTP_200_OK)
def mark_monthly_done(
    body: RecurringTaskRequest,
    db:   Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _add_recurring(db, body, "monthly", _MONTHLY_ID)
    return {"status": "ok", "task": "fire_safety_audit", "court_id": body.court_id}


def _add_recurring(
    db: Session, body: RecurringTaskRequest, task_type: str, task_id: str
):
    row = HkRecurring(
        court_id  = body.court_id,
        task_type = task_type,
        task_id   = task_id,
        done_at   = datetime.now().isoformat(),
        photo_url = body.photo_url,
        done_by   = body.done_by,
    )
    db.add(row)
    db.commit()
