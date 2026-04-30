# app/models/maintenance.py
from sqlalchemy import Column, Integer, String, DateTime, func
from ..database import Base


class MaintenanceIssue(Base):
    __tablename__ = "maintenance_issues"

    id          = Column(Integer,  primary_key=True, autoincrement=True)
    court_id    = Column(Integer,  nullable=False, index=True)
    court_name  = Column(String,   nullable=False, default="")
    cart_id     = Column(String,   nullable=False)          # e.g. "A", "B", "C"
    cart_name   = Column(String,   nullable=False, default="")
    staff_name  = Column(String,   nullable=False, default="")
    issue_type  = Column(String,   nullable=False)          # electrical|plumbing|furniture|other
    description = Column(String,   nullable=False)
    status      = Column(String,   nullable=False, default="open")   # open|in_progress|resolved
    created_at  = Column(DateTime, server_default=func.now())
    updated_at  = Column(DateTime, server_default=func.now(), onupdate=func.now())
    resolved_at = Column(DateTime, nullable=True)
