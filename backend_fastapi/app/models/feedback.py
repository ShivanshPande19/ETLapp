# app/models/feedback.py

from sqlalchemy import Column, Integer, String, DateTime, func, ForeignKey
from ..database import Base

class Feedback(Base):
    __tablename__ = "feedbacks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    
    court_id = Column(Integer, ForeignKey("courts.id", ondelete="CASCADE"), nullable=False, index=True)
    outlet_id = Column(Integer, ForeignKey("outlets.id", ondelete="CASCADE"), nullable=True, index=True)
    
    customer_name = Column(String, nullable=False)
    customer_phone = Column(String, nullable=False)
    
    court_rating = Column(Integer, nullable=True)   # 1-5 only
    court_comments = Column(String, nullable=True)
    
    outlet_rating = Column(Integer, nullable=True)  # 1-5 only
    outlet_comments = Column(String, nullable=True)
    
    # ✅ NEW: Track source for analytics
    source = Column(String, nullable=False, default="qr")  # qr | app
    
    created_at = Column(DateTime, server_default=func.now())
