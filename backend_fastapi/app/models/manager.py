# backend_fastapi/app/models/manager.py
from sqlalchemy import Column, Integer, String, Boolean, DateTime, func, ForeignKey
from ..database import Base

class Manager(Base):
    __tablename__ = "managers"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    name            = Column(String,  nullable=False)
    email           = Column(String,  nullable=False, unique=True, index=True)
    hashed_password = Column(String,  nullable=False)
    
    # Role can be 'etl_manager' or 'outlet_manager'
    role            = Column(String,  nullable=False, default="etl_manager")
    
    # Agar outlet_manager hai toh uski outlet ID, ETL Manager ke liye Null
    outlet_id       = Column(Integer, ForeignKey("outlets.id"), nullable=True)
    
    is_active       = Column(Boolean, nullable=False, default=True)
    created_at      = Column(DateTime, server_default=func.now())