# backend_fastapi/app/models/manager.py
from sqlalchemy import Column, Integer, String, Boolean, DateTime, func, ForeignKey
from ..database import Base

class Manager(Base):
    __tablename__ = "managers"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    name            = Column(String,  nullable=False)
    email           = Column(String,  nullable=False, unique=True, index=True)
    hashed_password = Column(String,  nullable=False)
    
    # Role. Full-access management roles live here (see deps.MANAGEMENT_ROLES):
    #   'azimuth_management' | 'crownest_ops_head' | 'crownest_head'
    #   (legacy 'etl_manager'/'manager' still treated as full-access management),
    # plus 'outlet_manager'. The narrow maintenance roles live in the staff table.
    role            = Column(String,  nullable=False, default="etl_manager")

    # Org this account belongs to: 'azimuth' | 'crownest' | None. Informational
    # (labels/badges); access is decided by `role`, never by org.
    org             = Column(String,  nullable=True)

    # Agar outlet_manager hai toh uski outlet ID, ETL Manager ke liye Null
    outlet_id       = Column(Integer, ForeignKey("outlets.id"), nullable=True)
    
    is_active       = Column(Boolean, nullable=False, default=True)
    created_at      = Column(DateTime, server_default=func.now())