# app/schemas/feedback.py

from pydantic import BaseModel, model_validator, field_validator, Field
from typing import List, Optional
from datetime import datetime

# ✅ FIX #8: allowed sources whitelist
_ALLOWED_SOURCES = {"qr", "app", "web", "manual"}


class FeedbackCreate(BaseModel):
    court_id: int = Field(..., ge=1)
    outlet_id: Optional[int] = Field(None, ge=1)
    customer_name: str = Field(..., min_length=2, max_length=100)
    customer_phone: str = Field(..., min_length=7, max_length=15)

    # ✅ Strict 1-5 range validation
    court_rating: Optional[int] = Field(None, ge=1, le=5)
    court_comments: Optional[str] = Field(None, max_length=1000)
    outlet_rating: Optional[int] = Field(None, ge=1, le=5)
    outlet_comments: Optional[str] = Field(None, max_length=1000)

    # ✅ FIX #8: source length-limited
    source: str = Field(default="qr", max_length=20)

    @field_validator("customer_phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        cleaned = v.strip().replace(" ", "").replace("-", "")
        if not cleaned.lstrip("+").isdigit():
            raise ValueError("Invalid phone number.")
        if len(cleaned) < 7 or len(cleaned) > 15:
            raise ValueError("Phone number must be 7-15 digits.")
        return cleaned

    @field_validator("customer_name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 2:
            raise ValueError("Name must be at least 2 characters.")
        return v

    @field_validator("court_comments", "outlet_comments", mode="before")
    @classmethod
    def clean_comments(cls, v):
        if v is None:
            return None
        v = str(v).strip()
        return v if v else None

    # ✅ FIX #8: normalize + validate source
    @field_validator("source")
    @classmethod
    def validate_source(cls, v: str) -> str:
        v = (v or "qr").strip().lower()
        if v not in _ALLOWED_SOURCES:
            return "qr"
        return v

    @model_validator(mode="after")
    def check_at_least_one_feedback(self):
        if self.court_rating is None and self.outlet_rating is None:
            raise ValueError(
                "At least one rating (Court or Outlet) is required."
            )
        if self.outlet_rating is not None and self.outlet_id is None:
            raise ValueError(
                "outlet_id is required when providing outlet_rating."
            )
        return self


class FeedbackOut(BaseModel):
    id: int
    court_id: int
    outlet_id: Optional[int]
    customer_name: str
    # ✅ Phone partially masked for privacy
    customer_phone_masked: str
    court_rating: Optional[int]
    court_comments: Optional[str]
    outlet_rating: Optional[int]
    outlet_comments: Optional[str]
    source: str
    created_at: datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_orm_masked(cls, obj) -> "FeedbackOut":
        phone = obj.customer_phone or ""
        masked = phone[:3] + "****" + phone[-2:] if len(phone) > 5 else "***"
        return cls(
            id=obj.id,
            court_id=obj.court_id,
            outlet_id=obj.outlet_id,
            customer_name=obj.customer_name,
            customer_phone_masked=masked,
            court_rating=obj.court_rating,
            court_comments=obj.court_comments,
            outlet_rating=obj.outlet_rating,
            outlet_comments=obj.outlet_comments,
            source=getattr(obj, "source", "qr"),
            created_at=obj.created_at,
        )


class FeedbackAnalytics(BaseModel):
    total_count: int
    avg_court_rating: Optional[float]
    avg_outlet_rating: Optional[float]
    five_star_count: int
    one_star_count: int
    this_week_count: int
    last_week_count: int
    # ✅ Per-star distribution of OUTLET ratings: index 0 => 1★ ... index 4 => 5★.
    # Lets the home screen render the distribution bars without loading every
    # feedback (important once pagination only fetches a single page).
    rating_distribution: List[int] = Field(default_factory=lambda: [0, 0, 0, 0, 0])
