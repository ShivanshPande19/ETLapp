# schemas/housekeeping.py
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from enum import Enum

class ShiftEnum(str, Enum):
    morning = "morning"
    day     = "day"
    night   = "night"

# ── Request bodies ─────────────────────────────────────────────────────────────

class TaskSubmitItem(BaseModel):
    task_id    : str
    task_title : str
    is_done    : bool
    photo_url  : Optional[str] = None
    done_at    : Optional[datetime] = None

class ShiftSubmitRequest(BaseModel):
    court_id     : int = Field(..., ge=1, le=3)
    shift        : ShiftEnum
    date: str = Field(..., pattern=r"^\d{4}-\d{2}-\d{2}$")  # YYYY-MM-DD
    tasks        : List[TaskSubmitItem]
    submitted_by : Optional[int] = None

class WeeklyTaskDoneRequest(BaseModel):
    court_id  : int = Field(..., ge=1, le=3)
    photo_url : Optional[str] = None
    done_by   : Optional[int] = None

class MonthlyTaskDoneRequest(BaseModel):
    court_id  : int = Field(..., ge=1, le=3)
    photo_url : Optional[str] = None
    done_by   : Optional[int] = None

# ── Response bodies ────────────────────────────────────────────────────────────

class TaskStatusItem(BaseModel):
    task_id    : str
    task_title : str
    is_done    : bool
    photo_url  : Optional[str]
    done_at    : Optional[datetime]

    class Config:
        from_attributes = True

class ShiftStatus(BaseModel):
    shift      : ShiftEnum
    total      : int
    done       : int
    submitted  : bool
    tasks      : List[TaskStatusItem]

class CourtDayStatus(BaseModel):
    court_id : int
    date     : str
    shifts   : List[ShiftStatus]

class WeeklyTaskStatus(BaseModel):
    court_id     : int
    last_done_at : Optional[datetime]
    next_due_at  : Optional[datetime]   # last_done_at + 7 days
    photo_url    : Optional[str]
    is_overdue   : bool

    class Config:
        from_attributes = True

class MonthlyTaskStatus(BaseModel):
    court_id     : int
    last_done_at : Optional[datetime]
    next_due_at  : Optional[datetime]   # last_done_at + 30 days
    photo_url    : Optional[str]
    is_overdue   : bool

    class Config:
        from_attributes = True

class FullStatusResponse(BaseModel):
    date          : str
    courts        : List[CourtDayStatus]
    weekly_tasks  : List[WeeklyTaskStatus]
    monthly_tasks : List[MonthlyTaskStatus]

class SubmitResponse(BaseModel):
    success  : bool
    message  : str
    court_id : int
    shift    : ShiftEnum
    date     : str
