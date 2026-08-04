from datetime import datetime
import uuid

from sqlalchemy import (
    Column,
    Integer,
    String,
    Float,
    Date,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    Index,
)
from sqlalchemy.orm import relationship

from ..database import Base


def gen_uid():
    return uuid.uuid4().hex[:12].upper()


class Court(Base):
    __tablename__ = "courts"

    id = Column(Integer, primary_key=True, index=True)
    court_uid = Column(String, unique=True, nullable=False, default=gen_uid)
    name = Column(String, nullable=False)
    manager_id = Column(Integer, ForeignKey("managers.id"), nullable=True)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime, default=datetime.utcnow)

    # ── Geofencing ────────────────────────────────────────────────────────────
    # Center of the court (set via map when creating/editing). Nullable so that
    # existing courts created before this feature keep working — until a manager
    # sets a location, geofencing is simply skipped for that court.
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    # Allowed radius (in metres) within which staff must be to mark attendance.
    geofence_radius = Column(Integer, default=150)
    # Human-readable address picked from the map (for display only).
    address = Column(String, nullable=True)

    # ── Overnight business-day handling ────────────────────────────────────────
    # The hour (0-11, local IST) before which activity still belongs to the
    # PREVIOUS calendar day. 0 (default) = normal court: business day == calendar
    # day. For a court that runs e.g. 2pm→2am, set this to ~5 so a 2am check-out
    # still counts on the day the shift started.
    day_cutoff_hour = Column(Integer, default=0)

    outlets = relationship("Outlet", back_populates="court", cascade="all, delete-orphan")


class Outlet(Base):
    __tablename__ = "outlets"

    id = Column(Integer, primary_key=True, index=True)
    court_id = Column(Integer, ForeignKey("courts.id"), nullable=False, index=True)
    vendor_name = Column(String, nullable=False)
    rest_id = Column(String, unique=True, nullable=False)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime, default=datetime.utcnow)

    # ✅ Per-outlet Petpooja credentials (nullable). If null, the sync falls
    # back to the global keys in settings/.env. This supports both a single
    # shared ETL Petpooja account AND outlets that carry their own creds.
    pp_app_key = Column(String, nullable=True)
    pp_app_secret = Column(String, nullable=True)
    pp_access_token = Column(String, nullable=True)
    pp_cookie = Column(String, nullable=True)

    # ✅ Which POS adapter fetches this outlet's sales. Selects the adapter in
    # app/services/sales_sources. Defaults to 'petpooja_generic' so every
    # existing outlet keeps its current behaviour with zero migration.
    # Other values: 'petpooja_salesdata' (get_sales_data flow), 'royal_pos'.
    pos_source = Column(String, nullable=False, default="petpooja_generic")

    court = relationship("Court", back_populates="outlets")
    sales_cache = relationship("DailySaleCache", back_populates="outlet", cascade="all, delete-orphan")


class DailySaleCache(Base):
    __tablename__ = "daily_sale_cache"

    id = Column(Integer, primary_key=True, index=True)
    outlet_id = Column(Integer, ForeignKey("outlets.id"), nullable=False, index=True)
    sale_date = Column(Date, nullable=False, index=True)
    total_sales = Column(Float, default=0.0)
    bill_count = Column(Integer, default=0)
    avg_bill = Column(Float, default=0.0)
    raw_json = Column(String, nullable=True)
    fetched_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("outlet_id", "sale_date", name="uq_outlet_sale_date"),
        Index("ix_daily_sale_cache_outlet_date", "outlet_id", "sale_date"),
    )

    outlet = relationship("Outlet", back_populates="sales_cache")


# NAYA TABLE: Individual bills ko track karne ke liye taaki overlap/duplicates na hon
#
# NOTE: kept as a FROZEN BACKUP of pre-multisource data. As of the multi-source
# refactor, the sync no longer writes here — `SalesOrder` (below) is the source
# of truth and its rows are backfilled from this table on first boot. Drop this
# manually once the new pipeline is proven in prod.
class PetpoojaOrder(Base):
    __tablename__ = "petpooja_orders"

    order_id = Column(Integer, primary_key=True, index=True) # Petpooja ka unique orderID
    outlet_id = Column(Integer, ForeignKey("outlets.id"), nullable=False, index=True)
    business_date = Column(Date, nullable=False, index=True) # Apna 4 AM buffer wala date
    created_on = Column(DateTime, nullable=False) # Bill fatne ka exact time
    total_amount = Column(Float, default=0.0)

    outlet = relationship("Outlet")


# ✅ MULTI-SOURCE bills table. Source-agnostic replacement for petpooja_orders.
# One row per revenue-counting bill from ANY POS (Petpooja generic / sales_data,
# Royal POS, ...). `DailySaleCache` is recomputed from these rows and is what the
# UI reads — this table's shape can evolve without touching the app contract.
#
# The composite UNIQUE(outlet_id, source, external_ref) is the key design point:
# `external_ref` is a STRING (Petpooja generic global orderID, Petpooja
# sales_data per-outlet Receipt number, etc.) and only needs to be unique WITHIN
# an outlet+source, so per-outlet sequential receipt numbers never collide.
class SalesOrder(Base):
    __tablename__ = "sales_orders"

    id = Column(Integer, primary_key=True, index=True)  # surrogate PK
    outlet_id = Column(Integer, ForeignKey("outlets.id"), nullable=False, index=True)
    source = Column(String, nullable=False, default="petpooja_generic")
    external_ref = Column(String, nullable=False)  # source's own bill id, as string
    business_date = Column(Date, nullable=False, index=True)
    created_on = Column(DateTime, nullable=False)
    total_amount = Column(Float, default=0.0)
    status = Column(String, nullable=True)  # audit/reconciliation only

    __table_args__ = (
        UniqueConstraint(
            "outlet_id", "source", "external_ref", name="uq_sales_orders_outlet_source_ref"
        ),
        Index("ix_sales_orders_outlet_bizdate", "outlet_id", "business_date"),
    )

    outlet = relationship("Outlet")