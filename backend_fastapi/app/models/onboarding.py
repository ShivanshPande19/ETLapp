# backend_fastapi/app/models/onboarding.py
#
# Outlet onboarding applications submitted via the public form. The ETL manager
# reviews these and either approves (creates the Outlet + outlet-manager login)
# or rejects them.

from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.sql import func
from ..database import Base


class OutletApplication(Base):
    __tablename__ = "outlet_applications"

    id = Column(Integer, primary_key=True, index=True)

    # Which court the owner applied to (chosen from the DB dropdown → no mismatch)
    court_id = Column(Integer, ForeignKey("courts.id"), nullable=False, index=True)

    # Business + owner details
    outlet_name = Column(String, nullable=False)
    owner_name = Column(String, nullable=False)
    owner_phone = Column(String, nullable=False)
    owner_email = Column(String, nullable=False, index=True)

    # Uploaded document URLs (served from /uploads). Nullable — owner may not
    # attach every doc.
    gst_url = Column(String, nullable=True)
    fssai_url = Column(String, nullable=True)
    term_sheet_url = Column(String, nullable=True)
    agreement_url = Column(String, nullable=True)

    # Workflow
    status = Column(String, nullable=False, default="pending", index=True)  # pending | approved | rejected
    rejection_reason = Column(String, nullable=True)

    # Link to the outlet created on approval (if any)
    created_outlet_id = Column(Integer, ForeignKey("outlets.id"), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
