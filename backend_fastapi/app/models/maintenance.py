# app/models/maintenance.py
from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text
from ..database import Base


class MaintenanceIssue(Base):
    __tablename__ = "maintenance_issues"

    id          = Column(Integer, primary_key=True, autoincrement=True)
    court_id    = Column(Integer, nullable=False, index=True)
    court_name  = Column(String,  nullable=False, default="")

    # For a "general" (court/zone-level) ticket there is no specific outlet, so
    # outlet_id carries the sentinel 0 and outlet_name is blank.
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

    # ── Role-split additions ──────────────────────────────────────────────────
    # "general" (court/zone-level) | "outlet" (a specific outlet).
    scope           = Column(String,  nullable=False, default="outlet")
    # Who raised it (identity from JWT, never client body).
    raised_by_role  = Column(String,  nullable=True)
    raised_by_id    = Column(Integer, nullable=True)
    raised_by_table = Column(String,  nullable=True)   # "manager" | "staff"
    is_urgent       = Column(Boolean, nullable=False, default=False)
    # JSON text — list of maintenance role keys this ticket is assigned to,
    # e.g. ["azimuth_maintenance","crownest_maintenance_head"] (one or both).
    target_teams    = Column(Text,    nullable=True)
    # JSON text — extra people to notify. Each item:
    #   {"kind":"role","value":"<role>"} or {"kind":"user","value":"staff:<id>"|"manager:<id>"}
    mentions        = Column(Text,    nullable=True)
    # "pending" = outlet-raised, awaiting ops-head routing; "routed" = targets set.
    triage_status   = Column(String,  nullable=False, default="routed")
    # Reminder / escalation bookkeeping (driven by the scheduler in Phase 4).
    last_reminder_at = Column(DateTime, nullable=True)
    escalated_2d    = Column(Boolean, nullable=False, default=False)
    escalated_4d    = Column(Boolean, nullable=False, default=False)

    # ── Two-stage verification (ROLE SPLIT) ────────────────────────────────────
    # Who verifies a resolved ticket depends on WHO RAISED it:
    #   • ops-raised (zone or outlet) → Ops Head verifies, then it closes.
    #   • outlet-raised               → Ops Head verifies FIRST (sets
    #     ops_verified_at), then the owning outlet manager verifies to close.
    ops_verified_at   = Column(DateTime, nullable=True)
    # JSON text — list of proof photo URLs the maintenance team attached when
    # marking the ticket resolved (shown to the verifier).
    resolution_photos = Column(Text, nullable=True)
