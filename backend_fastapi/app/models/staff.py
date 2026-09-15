# backend_fastapi/app/models/staff.py
from sqlalchemy import Column, Integer, String, Boolean, DateTime, func, ForeignKey
from ..database import Base

class Staff(Base):
    __tablename__ = "staff"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    name            = Column(String,  nullable=False)
    email           = Column(String,  nullable=False, unique=True, index=True)
    hashed_password = Column(String,  nullable=False)
    
    # Role. Narrow worker roles live here (see deps.MAINTENANCE_ROLES):
    #   'etl_staff' | 'outlet_staff' | 'azimuth_maintenance' |
    #   'crownest_maintenance_head'. The maintenance roles are worker accounts
    #   with a narrow (tickets-only) view; crownest_maintenance_head also logs
    #   attendance like etl_staff and appears in the roster (with a badge).
    role            = Column(String,  nullable=False, default="etl_staff")

    # Org this account belongs to: 'azimuth' | 'crownest' | None. Informational.
    org             = Column(String,  nullable=True)
    
    # ETL staff ke liye court assign hoga
    court_id        = Column(Integer, ForeignKey("courts.id"), nullable=True)   
    
    # A Crownest Maintenance Head can cover MULTIPLE zones — JSON list of court
    # ids (e.g. "[1, 3]"). `court_id` above stays the primary (first) zone for
    # back-compat (business-day cutoff etc.); geofence + roster use this set.
    zone_court_ids  = Column(String, nullable=True)

    # Outlet staff ke liye outlet assign hoga
    outlet_id       = Column(Integer, ForeignKey("outlets.id"), nullable=True)
    
    # ✅ Contact + profile photo (collected at onboarding)
    phone           = Column(String,  nullable=True)
    photo_url       = Column(String,  nullable=True)

    # ✅ Shift timings set by the ETL manager (stored as "HH:MM", 24h, local
    # IST). Nullable = no shift assigned yet. If shift_end <= shift_start the
    # shift is treated as overnight (crosses midnight).
    shift_start     = Column(String,  nullable=True)
    shift_end       = Column(String,  nullable=True)

    is_active       = Column(Boolean, nullable=False, default=True)
    created_at      = Column(DateTime, server_default=func.now())