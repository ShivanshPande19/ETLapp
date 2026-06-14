# backend_fastapi/app/models/staff.py
from sqlalchemy import Column, Integer, String, Boolean, DateTime, func, ForeignKey
from ..database import Base

class Staff(Base):
    __tablename__ = "staff"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    name            = Column(String,  nullable=False)
    email           = Column(String,  nullable=False, unique=True, index=True)
    hashed_password = Column(String,  nullable=False)
    
    # Role can be 'etl_staff' or 'outlet_staff'
    role            = Column(String,  nullable=False, default="etl_staff")
    
    # ETL staff ke liye court assign hoga
    court_id        = Column(Integer, ForeignKey("courts.id"), nullable=True)   
    
    # Outlet staff ke liye outlet assign hoga
    outlet_id       = Column(Integer, ForeignKey("outlets.id"), nullable=True)
    
    is_active       = Column(Boolean, nullable=False, default=True)
    created_at      = Column(DateTime, server_default=func.now())