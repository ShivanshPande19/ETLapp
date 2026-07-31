# app/schemas/device.py
from typing import Optional

from pydantic import BaseModel, Field, field_validator

_ALLOWED_PLATFORMS = {"android", "ios", "web"}


class DeviceRegisterIn(BaseModel):
    """Body for POST /devices/register.

    The user is NEVER taken from the body — it is resolved from the bearer
    token, so a client cannot register a token against somebody else's account.
    """

    fcm_token: str = Field(..., min_length=10, max_length=4096)
    platform: Optional[str] = None
    app_version: Optional[str] = None

    @field_validator("fcm_token")
    @classmethod
    def _strip_token(cls, v: str) -> str:
        v = (v or "").strip()
        if not v:
            raise ValueError("fcm_token cannot be blank")
        return v

    @field_validator("platform")
    @classmethod
    def _normalise_platform(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        v = v.strip().lower()
        return v if v in _ALLOWED_PLATFORMS else None


class DeviceUnregisterIn(BaseModel):
    """Body for POST /devices/unregister.

    Sent on logout. `fcm_token` is optional: when omitted, every token owned by
    the caller is disabled (useful for a "sign out everywhere" action).
    """

    fcm_token: Optional[str] = None

    @field_validator("fcm_token")
    @classmethod
    def _strip_token(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        v = v.strip()
        return v or None


class DeviceRegisterOut(BaseModel):
    status: str = "ok"
    # True when this token previously belonged to a DIFFERENT account and was
    # transferred (shared device). Handy in logs when debugging.
    transferred: bool = False
    push_enabled: bool = True


class DeviceUnregisterOut(BaseModel):
    status: str = "ok"
    disabled: int = 0
