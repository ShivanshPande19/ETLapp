from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum as SAEnum
from app.database import Base                         # ← fixed
from datetime import datetime
import enum


class ShiftEnum(str, enum.Enum):
    morning = "morning"
    day     = "day"
    night   = "night"


class HousekeepingRecord(Base):
    __tablename__ = "housekeeping_records"

    id           = Column(Integer, primary_key=True, index=True)
    court_id     = Column(Integer, nullable=False, index=True)
    shift        = Column(SAEnum(ShiftEnum), nullable=False)
    task_id      = Column(String(32), nullable=False)
    task_title   = Column(String(128), nullable=False)
    is_done      = Column(Boolean, default=False)
    photo_url    = Column(String(512), nullable=True)
    done_at      = Column(DateTime, nullable=True)
    submitted_by = Column(Integer, nullable=True)
    date         = Column(String(10), nullable=False, index=True)
    created_at   = Column(DateTime, default=datetime.utcnow)
    updated_at   = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class WeeklyTaskRecord(Base):
    __tablename__ = "weekly_task_records"

    id           = Column(Integer, primary_key=True, index=True)
    court_id     = Column(Integer, nullable=False, unique=True)
    task_id      = Column(String(32), default="flags_washing")
    last_done_at = Column(DateTime, nullable=True)
    photo_url    = Column(String(512), nullable=True)
    done_by      = Column(Integer, nullable=True)
    updated_at   = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class MonthlyTaskRecord(Base):
    __tablename__ = "monthly_task_records"

    id           = Column(Integer, primary_key=True, index=True)
    court_id     = Column(Integer, nullable=False, unique=True)
    task_id      = Column(String(32), default="fire_safety_audit")
    last_done_at = Column(DateTime, nullable=True)
    photo_url    = Column(String(512), nullable=True)
    done_by      = Column(Integer, nullable=True)
    updated_at   = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)