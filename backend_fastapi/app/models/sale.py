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

    outlets = relationship("Outlet", back_populates="court", cascade="all, delete-orphan")


class Outlet(Base):
    __tablename__ = "outlets"

    id = Column(Integer, primary_key=True, index=True)
    court_id = Column(Integer, ForeignKey("courts.id"), nullable=False, index=True)
    vendor_name = Column(String, nullable=False)
    rest_id = Column(String, unique=True, nullable=False)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime, default=datetime.utcnow)

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