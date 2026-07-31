# app/api/deps.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, ExpiredSignatureError
from sqlalchemy.orm import Session

from ..core.security import decode_token
from ..database import get_db
from ..models.manager import Manager
from ..models.staff import Staff


class CurrentUser:
    """Authenticated user — resolved fresh from DB on every request."""

    def __init__(
        self,
        id: int,
        name: str,
        email: str,
        role: str,
        court_id: int | None = None,
        outlet_id: int | None = None,
        user_type: str = "manager",
    ):
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.court_id = court_id
        self.outlet_id = outlet_id
        # Which table this identity came from: "manager" | "staff".
        #
        # The JWT carries no type claim and `id` is only unique WITHIN a table
        # (manager.id == 1 and staff.id == 1 are different people), so anything
        # that persists a per-user row — e.g. device_tokens — MUST store this
        # alongside the id. Resolved in get_current_user() below, matching the
        # lookup order there.
        self.user_type = user_type

    @property
    def is_etl_manager(self) -> bool:
        return self.role in ("etl_manager", "manager")

    @property
    def is_outlet_user(self) -> bool:
        return self.role in ("outlet_manager", "outlet_staff")

    @property
    def is_etl_staff(self) -> bool:
        return self.role in ("etl_staff", "staff")

    @property
    def is_manager_account(self) -> bool:
        """True when this identity is a row in `managers`."""
        return self.user_type == "manager"

    @property
    def is_staff_account(self) -> bool:
        """True when this identity is a row in `staff`."""
        return self.user_type == "staff"


_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> CurrentUser:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        payload = decode_token(credentials.credentials)
    except ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired. Please log in again.")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token.")

    email = payload.get("sub")
    if not email:
        raise HTTPException(status_code=401, detail="Invalid token payload.")

    # Fresh DB lookup — deactivated users lose access immediately
    user = db.query(Manager).filter(
        Manager.email == email, Manager.is_active == True
    ).first()

    if user:
        return CurrentUser(
            id=user.id,
            name=user.name,
            email=user.email,
            role=user.role,
            outlet_id=user.outlet_id,
            user_type="manager",
        )

    staff = db.query(Staff).filter(
        Staff.email == email, Staff.is_active == True
    ).first()

    if staff:
        return CurrentUser(
            id=staff.id,
            name=staff.name,
            email=staff.email,
            role=staff.role,
            court_id=staff.court_id,
            outlet_id=staff.outlet_id,
            user_type="staff",
        )

    raise HTTPException(status_code=401, detail="User not found or deactivated.")


def require_etl_manager(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")
    return user


def require_outlet_user(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    if not user.is_outlet_user:
        raise HTTPException(status_code=403, detail="Outlet access required.")
    if user.outlet_id is None:
        raise HTTPException(status_code=403, detail="No outlet assigned to your account.")
    return user
