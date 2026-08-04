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

    # ── Google review funnel ──────────────────────────────────────────────────
    # Stamped the FIRST time this customer taps "also review us on Google" on
    # the thank-you screen (see GET /feedback/{id}/google). Only the first tap
    # is recorded, so this counts unique hand-offs, not taps.
    #
    # NULL = never tapped. This measures how many people we handed off to
    # Google; it can NOT confirm they actually posted a review — Google has no
    # API for that, so posting is unverifiable by design.
    google_cta_clicked_at = Column(DateTime, nullable=True)
