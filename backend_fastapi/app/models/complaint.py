# app/models/complaint.py

from sqlalchemy import Column, Integer, String, DateTime, func
from ..database import Base


class Complaint(Base):
    __tablename__ = "complaints"

    id          = Column(Integer,  primary_key=True, autoincrement=True)
    court_id    = Column(Integer,  nullable=False, index=True)
    category    = Column(String,   nullable=False)   # food|staff|cleanliness|other
    description = Column(String,   nullable=False)
    status      = Column(String,   nullable=False, default="open")  # open|in_progress|resolved
    created_at  = Column(DateTime, server_default=func.now())
    resolved_at = Column(DateTime, nullable=True)

