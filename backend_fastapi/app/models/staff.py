# backend_fastapi/app/models/staff.py
from sqlalchemy import Column, Integer, String, Boolean, DateTime, func
from ..database import Base

class Staff(Base):
    __tablename__ = "staff"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    name            = Column(String,  nullable=False)
    email           = Column(String,  nullable=False, unique=True, index=True)
    hashed_password = Column(String,  nullable=False)
    role            = Column(String,  nullable=False, default="staff")
    court_id        = Column(Integer, nullable=True)   # court assign hogi baad mein
    is_active       = Column(Boolean, nullable=False, default=True)
    created_at      = Column(DateTime, server_default=func.now())