# app/api/deps.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, ExpiredSignatureError
from sqlalchemy.orm import Session

from ..core.security import decode_token
from ..database import get_db
from ..models.manager import Manager
from ..models.staff import Staff
from ..models.outlet_membership import OutletMembership


# ─── Role taxonomy (single source of truth) ──────────────────────────────────
#
# ROLE SPLIT: the old single `etl_manager` full-access role is split into three
# full-access MANAGEMENT roles across two orgs, plus two narrow MAINTENANCE
# worker roles. Access is decided ONLY by these sets (never by `org`).
#
#   Management (managers table, full company-wide access):
#     azimuth_management | crownest_ops_head | crownest_head
#     + legacy etl_manager / manager  (kept full-access during transition)
#   Maintenance (staff table, narrow tickets-only view):
#     azimuth_maintenance | crownest_maintenance_head
#
# Only crownest_ops_head may RAISE maintenance tickets (on top of full access).
MANAGEMENT_ROLES = frozenset({
    "azimuth_management",
    "crownest_ops_head",
    "crownest_head",
    "etl_manager",   # legacy full-access — treat as management until reassigned
    "manager",       # legacy alias created by /auth/seed
})
MAINTENANCE_ROLES = frozenset({
    "azimuth_maintenance",
    "crownest_maintenance_head",
})
OPS_HEAD_ROLE = "crownest_ops_head"


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
        outlet_ids: list[int] | None = None,
        org: str | None = None,
    ):
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        # Org label ('azimuth' | 'crownest' | None). Informational only.
        self.org = org
        self.court_id = court_id
        # `outlet_id` = the PRIMARY/default outlet (legacy single-outlet column).
        # Kept for backward compatibility and as the default selection.
        self.outlet_id = outlet_id
        # `outlet_ids` = the FULL set of outlets this identity may access.
        #
        # MULTI-OUTLET (Option A): an outlet_manager can own/manage many outlets
        # via `outlet_memberships`. ALL tenancy scoping must use this set
        # (membership check), never the single `outlet_id`. Falls back to
        # [outlet_id] when no explicit set is given (staff, legacy).
        if outlet_ids is not None:
            self.outlet_ids = list(outlet_ids)
        elif outlet_id is not None:
            self.outlet_ids = [outlet_id]
        else:
            self.outlet_ids = []
        # Which table this identity came from: "manager" | "staff".
        #
        # The JWT carries no type claim and `id` is only unique WITHIN a table
        # (manager.id == 1 and staff.id == 1 are different people), so anything
        # that persists a per-user row — e.g. device_tokens — MUST store this
        # alongside the id. Resolved in get_current_user() below, matching the
        # lookup order there.
        self.user_type = user_type

    @property
    def is_management(self) -> bool:
        """Full company-wide access (all zones/outlets/sales). The three new
        management roles + legacy etl_manager/manager."""
        return self.role in MANAGEMENT_ROLES

    @property
    def is_etl_manager(self) -> bool:
        """Backward-compat alias of `is_management`. Every existing
        `is_etl_manager` / `require_etl_manager` check now means "full-access
        management account", which includes azimuth_management,
        crownest_ops_head and crownest_head (not just legacy etl_manager)."""
        return self.is_management

    @property
    def is_ops_head(self) -> bool:
        """Crownest Ops Head — the ONLY role that can raise maintenance tickets
        (in addition to full management access)."""
        return self.role == OPS_HEAD_ROLE

    @property
    def is_maintenance(self) -> bool:
        """Narrow maintenance worker role
        (azimuth_maintenance / crownest_maintenance_head)."""
        return self.role in MAINTENANCE_ROLES

    @property
    def maintenance_role(self) -> str | None:
        """The maintenance role key (for ticket target/visibility matching), or
        None for non-maintenance accounts."""
        return self.role if self.role in MAINTENANCE_ROLES else None

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

    def can_access_outlet(self, outlet_id: int | None) -> bool:
        """Tenancy gate: may this user read/act on the given outlet?

        ETL managers are unrestricted (they oversee every court/outlet).
        Everyone else must have the outlet in their membership set.
        """
        if outlet_id is None:
            return False
        if self.is_etl_manager:
            return True
        return outlet_id in self.outlet_ids


_bearer = HTTPBearer(auto_error=False)


def _resolve_outlet_ids(db: Session, manager: Manager) -> list[int]:
    """All outlets an outlet_manager may access, from `outlet_memberships`.

    Falls back to the legacy primary `Manager.outlet_id` if the membership row
    hasn't been backfilled yet (belt-and-braces; the boot backfill normally
    seeds it). ETL managers have no memberships and get an empty set.
    """
    if manager.role != "outlet_manager":
        return []
    rows = (
        db.query(OutletMembership.outlet_id)
        .filter(OutletMembership.manager_id == manager.id)
        .all()
    )
    ids = [r[0] for r in rows]
    if not ids and manager.outlet_id is not None:
        ids = [manager.outlet_id]
    return ids


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

    # SECURITY: only genuine login tokens may authenticate an API request. The
    # set-password / reset-password magic-link tokens are signed with the SAME
    # secret and carry a valid `sub`, so without this check they would double as
    # a full API bearer credential for the whole of their (multi-day) lifetime —
    # i.e. a leaked set-password email would grant live account access, not just
    # the ability to set a password. Login tokens (create_access_token) carry no
    # `purpose` claim; purpose-scoped tokens are validated only by their own
    # dedicated endpoints (/auth/set-password, /auth/reset-password).
    if payload.get("purpose"):
        raise HTTPException(status_code=401, detail="Invalid token.")

    email = payload.get("sub")
    if not email:
        raise HTTPException(status_code=401, detail="Invalid token payload.")

    # Fresh DB lookup — deactivated users lose access immediately
    user = db.query(Manager).filter(
        Manager.email == email, Manager.is_active == True
    ).first()

    if user:
        outlet_ids = _resolve_outlet_ids(db, user)
        # Primary = the manager's own column, else the first accessible outlet.
        primary = user.outlet_id if user.outlet_id is not None else (
            outlet_ids[0] if outlet_ids else None
        )
        return CurrentUser(
            id=user.id,
            name=user.name,
            email=user.email,
            role=user.role,
            outlet_id=primary,
            outlet_ids=outlet_ids,
            user_type="manager",
            org=getattr(user, "org", None),
        )

    staff = db.query(Staff).filter(
        Staff.email == email, Staff.is_active == True
    ).first()

    if staff:
        # Staff remain single-outlet (their own outlet only).
        staff_outlets = [staff.outlet_id] if staff.outlet_id is not None else []
        return CurrentUser(
            id=staff.id,
            name=staff.name,
            email=staff.email,
            role=staff.role,
            court_id=staff.court_id,
            outlet_id=staff.outlet_id,
            outlet_ids=staff_outlets,
            user_type="staff",
            org=getattr(staff, "org", None),
        )

    raise HTTPException(status_code=401, detail="User not found or deactivated.")


def require_management(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    """Full-access management gate: Azimuth Management, Crownest Ops Head,
    Crownest Head (+ legacy etl_manager/manager)."""
    if not user.is_management:
        raise HTTPException(status_code=403, detail="Management access required.")
    return user


def require_etl_manager(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    """Backward-compatible alias of `require_management` — kept so every existing
    route compiles unchanged. Both mean "full-access management account"."""
    if not user.is_management:
        raise HTTPException(status_code=403, detail="Management access required.")
    return user


def require_ops_head(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    """Crownest Ops Head only (can raise/route maintenance tickets)."""
    if not user.is_ops_head:
        raise HTTPException(status_code=403, detail="Ops Head access required.")
    return user


def require_maintenance(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    """Narrow maintenance worker roles only."""
    if not user.is_maintenance:
        raise HTTPException(status_code=403, detail="Maintenance access required.")
    return user


def require_outlet_user(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    if not user.is_outlet_user:
        raise HTTPException(status_code=403, detail="Outlet access required.")
    # MULTI-OUTLET: an outlet user must be linked to at least one outlet.
    if not user.outlet_ids:
        raise HTTPException(status_code=403, detail="No outlet assigned to your account.")
    return user
