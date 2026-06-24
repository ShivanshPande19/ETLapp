# app/models/attendance.py

from sqlalchemy import Column, Integer, String, Float, DateTime, Date, ForeignKey
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

    # 🗓 Business day this attendance belongs to (handles overnight courts where
    # check-out happens after midnight). Computed from the court's day_cutoff_hour
    # at check-in time. Used for "one check-in per day" and roster grouping.
    business_date = Column(Date, nullable=True, index=True)
    
    # --- Check-in Details ---
    check_in_time = Column(DateTime(timezone=True), server_default=func.now())
    check_in_lat = Column(Float, nullable=False)
    check_in_lng = Column(Float, nullable=False)
    
    # Readable Address
    check_in_address = Column(String, nullable=True) 
    
    # Photo proof ka server link 
    check_in_photo_url = Column(String, nullable=False)

    # --- Check-out Details (Phase 2) ---
    # Nullable: jab tak staff shift end nahi karta, ye khaali rehte hain.
    check_out_time = Column(DateTime(timezone=True), nullable=True)
    check_out_lat = Column(Float, nullable=True)
    check_out_lng = Column(Float, nullable=True)
    check_out_address = Column(String, nullable=True)
    check_out_photo_url = Column(String, nullable=True)