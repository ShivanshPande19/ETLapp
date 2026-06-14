# app/models/attendance.py

from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.sql import func
from app.database import Base

class Attendance(Base):
    __tablename__ = "attendance"

    id = Column(Integer, primary_key=True, index=True)
    
    # 🔗 Linked to Staff table (Yahan 'staff.id' use kiya h)
    staff_id = Column(Integer, ForeignKey("staff.id", ondelete="CASCADE"), nullable=False)
    
    # 🔗 Nullable rakha hai taaki ETL aur Outlet dono staff chal jayein
    outlet_id = Column(Integer, ForeignKey("outlets.id", ondelete="CASCADE"), nullable=True)
    court_id = Column(Integer, ForeignKey("courts.id", ondelete="CASCADE"), nullable=True)
    
    # --- Check-in Details ---
    check_in_time = Column(DateTime(timezone=True), server_default=func.now())
    check_in_lat = Column(Float, nullable=False)
    check_in_lng = Column(Float, nullable=False)
    
    # Readable Address
    check_in_address = Column(String, nullable=True) 
    
    # Photo proof ka server link 
    check_in_photo_url = Column(String, nullable=False)