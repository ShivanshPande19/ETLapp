from pydantic import BaseModel, Field, field_validator
from typing import List, Optional
from urllib.parse import urlparse

# ── Google review link safety ────────────────────────────────────────────────
# A court's google_review_url is used as a REDIRECT TARGET by
# GET /feedback/{id}/google. If any URL were accepted, that endpoint would
# become an open redirect living on our own domain — ideal for phishing, since
# a link starting with our trusted host would bounce victims anywhere.
#
# So the host is allowlisted to Google-owned review domains. Note the check is
# an exact match or a dotted-suffix match ("*.google.com"), never a substring:
# `"google.com" in host` would happily accept "google.com.evil.tld".
_ALLOWED_REVIEW_HOSTS = {
    "search.google.com",     # /local/writereview?placeid=... (the canonical one)
    "www.google.com",
    "google.com",
    "maps.google.com",
    "g.page",                # g.page/r/<id>/review short links
    "maps.app.goo.gl",       # Maps app share links
    "goo.gl",
}


def validate_google_review_url(value: Optional[str]) -> Optional[str]:
    """Normalize + hard-validate a per-court Google review URL.

    Returns None for blank input (meaning "no link configured" — the portal
    then hides the Google CTA entirely). Raises ValueError otherwise.
    """
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None

    if len(value) > 500:
        raise ValueError("Review URL is too long (max 500 characters).")

    parsed = urlparse(value)
    # Require an explicit https scheme: a scheme-less value like
    # "search.google.com/..." parses with an empty netloc and would sail
    # straight past a host check.
    if parsed.scheme != "https":
        raise ValueError("Review URL must start with https://")

    host = (parsed.hostname or "").lower()
    if not host:
        raise ValueError("Review URL is missing a hostname.")

    allowed = host in _ALLOWED_REVIEW_HOSTS or any(
        host.endswith("." + h) for h in _ALLOWED_REVIEW_HOSTS
    )
    if not allowed:
        raise ValueError(
            "Review URL must be a Google link (e.g. "
            "https://search.google.com/local/writereview?placeid=... "
            "or https://g.page/r/.../review)."
        )
    return value


class Court(BaseModel):
    id: int
    court_uid: Optional[str] = None
    name: str
    location: Optional[str] = "Food Court"
    is_active: bool

    # ── Geofencing ────────────────────────────────────────────────────────────
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    geofence_radius: Optional[int] = None
    address: Optional[str] = None
    day_cutoff_hour: Optional[int] = 0
    # Convenience flag for the client: is geofencing configured for this court?
    has_geofence: bool = False

    # ── Google review funnel ──────────────────────────────────────────────────
    google_review_url: Optional[str] = None
    # Convenience flag for the client: does this court hand off to Google?
    has_google_review: bool = False

    class Config:
        from_attributes = True

class CourtsResponse(BaseModel):
    courts: List[Court]


class CourtCreate(BaseModel):
    name: str
    # Free-text location label (kept for backward compatibility / display).
    location: Optional[str] = None
    # Map-picked geofence center + radius (optional at create time).
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    geofence_radius: Optional[int] = Field(default=None, ge=20, le=2000)
    address: Optional[str] = None
    day_cutoff_hour: Optional[int] = Field(default=0, ge=0, le=11)


class CourtLocationUpdate(BaseModel):
    """Set / edit an existing court's geofence location (no other court data is
    touched)."""
    latitude: float
    longitude: float
    geofence_radius: int = Field(default=150, ge=20, le=2000)
    address: Optional[str] = None


class CourtSettingsUpdate(BaseModel):
    """Update non-location court settings (overnight business-day cutoff)."""
    day_cutoff_hour: int = Field(ge=0, le=11)


class CourtGoogleReviewUpdate(BaseModel):
    """Set / clear a court's Google review link.

    Send null or "" to clear it, which switches the Google CTA off on that
    court's feedback portal.
    """
    google_review_url: Optional[str] = Field(
        default=None,
        max_length=500,
        description=(
            "https:// Google review link for THIS court's listing. "
            "Send null or an empty string to remove it."
        ),
    )

    @field_validator("google_review_url")
    @classmethod
    def _check_url(cls, v: Optional[str]) -> Optional[str]:
        return validate_google_review_url(v)
