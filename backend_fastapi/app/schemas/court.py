from pydantic import BaseModel, Field
from typing import List, Optional

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
