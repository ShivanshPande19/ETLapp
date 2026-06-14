# app/models/maintenance.py
from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime
from ..database import Base


class MaintenanceIssue(Base):
    __tablename__ = "maintenance_issues"

    id          = Column(Integer, primary_key=True, autoincrement=True)
    court_id    = Column(Integer, nullable=False, index=True)
    court_name  = Column(String,  nullable=False, default="")

    outlet_id   = Column(Integer, nullable=False, index=True)
    outlet_name = Column(String,  nullable=False, default="")

    # Identity now comes from JWT, not client body
    staff_name      = Column(String, nullable=False, default="")
    raised_by_email = Column(String, nullable=True)

    issue_type  = Column(String, nullable=False)            # electrical|plumbing|furniture|cleaning|other
    priority    = Column(String, nullable=False, default="medium")  # low|medium|high
    description = Column(String, nullable=False)
    photo_url   = Column(String, nullable=True)             # Cloudinary proof photo

    # Lifecycle: RAISED -> ASSIGNED -> RESOLVED -> CLOSED | DISPUTED
    status      = Column(String, nullable=False, default="RAISED", index=True)

    technician_name  = Column(String, nullable=True)
    technician_phone = Column(String, nullable=True)

    # All timestamps stored as UTC
    created_at  = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at  = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    resolved_at = Column(DateTime, nullable=True)   # starts 24h verification window
    closed_at   = Column(DateTime, nullable=True)
