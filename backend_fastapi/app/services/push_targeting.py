# app/services/push_targeting.py
"""Resolve WHO receives a push — the single source of truth for tenancy.

╔══════════════════════════════════════════════════════════════════════════════╗
║  ISOLATION CONTRACT — read this before touching anything in here.            ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  audience="manager", outlet_id IS NOT NULL  →  ONLY that outlet's            ║
║                                                outlet_manager(s).            ║
║                                                NEVER an ETL manager.         ║
║                                                NEVER a neighbouring outlet.  ║
║                                                                              ║
║  audience="manager", outlet_id IS NULL      →  ONLY etl_manager(s).          ║
║                                                NEVER an outlet manager.      ║
║                                                                              ║
║  audience="staff"                           →  ONLY recipient_staff_id.      ║
║                                                Exactly one person.           ║
╚══════════════════════════════════════════════════════════════════════════════╝

The two manager branches are mutually exclusive by construction (`outlet_id`
is either NULL or it isn't), so an outlet manager can never be reached by a
court-level notice and vice-versa.

This mirrors `api/routes/notices.py::_scoped_query` exactly. If you change one,
change the other — otherwise a user could receive a push for a notice they
cannot open.

TWO RULES THAT MUST NOT BE BROKEN
─────────────────────────────────
1. NEVER use FCM topics for anything user-scoped. Topics are a broadcast and a
   push payload carries the actual title/body, so a topic leaks content. The
   existing SSE layer does broadcast on `court_id=0` (every manager and every
   outlet-staff device subscribes there) but that is only ever a "go refetch"
   ping — the real data is then fetched through an authenticated, scoped
   endpoint. Push has no such second gate. Token-targeted only.

2. NEVER target using `DeviceToken.court_id` / `.outlet_id` / `.role`. Those
   are a stale snapshot from registration time. Every query below JOINs live
   against `managers` / `staff` so that reassignments and deactivations take
   effect immediately.
"""

from __future__ import annotations

from typing import Iterable, List, Optional

from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..models.device_token import DeviceToken
from ..models.manager import Manager
from ..models.notice import Notice
from ..models.sale import Outlet
from ..models.staff import Staff
from ..models.outlet_membership import OutletMembership

# Legacy rows created by /auth/seed carry the bare value "manager"; treat it as
# an ETL manager exactly like deps.CurrentUser.is_etl_manager does.
ETL_MANAGER_ROLES = ("etl_manager", "manager")
STAFF_ROLES = ("etl_staff", "staff", "outlet_staff")


# ─── Manager routing: which manager tier owns an event about this staff? ──────

def manager_scope_for_staff(staff: Optional[Staff]) -> tuple[Optional[int], Optional[int]]:
    """Return ``(court_id, outlet_id)`` to stamp on a manager-audience notice.

    Outlet staff  → ``(None, outlet_id)`` so ONLY their own outlet manager sees
                    it. This is what keeps one vendor's staff events out of the
                    neighbouring vendor's (and the ETL manager's) notifications.
    Court staff   → ``(court_id, None)`` so ONLY ETL managers see it.

    Callers previously inlined ``if staff.outlet_id and not staff.court_id``,
    which silently mis-routed any staff row that had BOTH ids set (nothing in
    the schema prevents that) — the outlet manager would lose events about
    their own staff. Here `outlet_id` wins unconditionally, because an outlet
    staff member's manager is always their outlet manager.
    """
    if staff is None:
        return None, None
    if staff.outlet_id is not None:
        return None, staff.outlet_id
    return staff.court_id, None


# ─── Token lookups ───────────────────────────────────────────────────────────

def _tokens_for_staff_ids(db: Session, staff_ids: Iterable[int]) -> List[str]:
    """Live tokens for the given staff. Deactivated staff are excluded."""
    ids = [int(s) for s in staff_ids if s is not None]
    if not ids:
        return []
    rows = (
        db.query(DeviceToken.fcm_token)
        .join(Staff, Staff.id == DeviceToken.user_id)
        .filter(
            DeviceToken.user_type == "staff",
            DeviceToken.is_active == True,  # noqa: E712
            Staff.id.in_(ids),
            Staff.is_active == True,  # noqa: E712
        )
        .all()
    )
    return [r[0] for r in rows]


def _tokens_for_outlet_managers(db: Session, outlet_id: int) -> List[str]:
    """Live tokens for EVERY manager linked to exactly ONE outlet.

    MULTI-OUTLET: the tenancy boundary is now `outlet_memberships` — a manager
    receives an outlet's notices iff they hold a membership (owner OR manager)
    for that outlet. This covers the same-owner-many-outlets case and any
    assigned co-managers, while a manager of any other outlet still cannot
    match, and an ETL manager (no memberships) cannot match either.
    """
    if outlet_id is None:
        return []
    rows = (
        db.query(DeviceToken.fcm_token)
        .join(Manager, Manager.id == DeviceToken.user_id)
        .join(OutletMembership, OutletMembership.manager_id == Manager.id)
        .filter(
            DeviceToken.user_type == "manager",
            DeviceToken.is_active == True,  # noqa: E712
            Manager.is_active == True,  # noqa: E712
            Manager.role == "outlet_manager",
            OutletMembership.outlet_id == outlet_id,
        )
        .all()
    )
    return [r[0] for r in rows]


def _tokens_for_etl_managers(db: Session) -> List[str]:
    """Live tokens for ETL (court-level) managers only.

    `Manager.outlet_id.is_(None)` is belt-and-braces on top of the role check:
    even if an outlet manager somehow carried a legacy role value, an account
    bound to an outlet can never receive court-level notices.
    """
    rows = (
        db.query(DeviceToken.fcm_token)
        .join(Manager, Manager.id == DeviceToken.user_id)
        .filter(
            DeviceToken.user_type == "manager",
            DeviceToken.is_active == True,  # noqa: E712
            Manager.is_active == True,  # noqa: E712
            Manager.role.in_(ETL_MANAGER_ROLES),
            Manager.outlet_id.is_(None),
        )
        .all()
    )
    return [r[0] for r in rows]


# ─── The entry point used by notice_service ──────────────────────────────────

def resolve_notice_targets(db: Session, notice: Notice) -> List[str]:
    """Every FCM token that should receive this notice. Deduplicated.

    Returns an empty list rather than raising, so a targeting miss can never
    break the API call that created the notice.
    """
    if notice is None:
        return []

    tokens: List[str] = []

    if notice.audience == "staff":
        # Exactly one recipient. An audience="staff" notice with no
        # recipient_staff_id is a bug at the call site — deliver to nobody
        # rather than falling back to something broader.
        if notice.recipient_staff_id is None:
            print(
                f"[PUSH] notice#{notice.id} type={notice.type} has "
                f"audience='staff' but no recipient_staff_id — dropped"
            )
            return []
        tokens = _tokens_for_staff_ids(db, [notice.recipient_staff_id])

    elif notice.audience == "manager":
        if notice.outlet_id is not None:
            tokens = _tokens_for_outlet_managers(db, notice.outlet_id)
        else:
            tokens = _tokens_for_etl_managers(db)

    else:
        print(f"[PUSH] notice#{notice.id} unknown audience={notice.audience!r} — dropped")
        return []

    # One user may have several devices; a token could also theoretically be
    # matched twice. dict.fromkeys keeps insertion order and dedupes.
    return list(dict.fromkeys(t for t in tokens if t))


# ─── Fan-out helper for court-wide events (e.g. geofence changed) ─────────────

def staff_ids_for_court(db: Session, court_id: int) -> List[int]:
    """Every active staff member who works at this court.

    Two paths, because an outlet staff member's `court_id` is NULL — their
    court is only reachable through their outlet:

        etl_staff     → Staff.court_id == court_id
        outlet_staff  → Staff.outlet_id -> Outlet.court_id == court_id

    Used when something changes at the court level that every staff member
    needs to know about (geofence moved, business-day cutoff changed), so that
    each of them still gets an individually-addressed audience="staff" notice
    rather than a broadcast.
    """
    if court_id is None:
        return []
    rows = (
        db.query(Staff.id)
        .outerjoin(Outlet, Outlet.id == Staff.outlet_id)
        .filter(
            Staff.is_active == True,  # noqa: E712
            or_(
                Staff.court_id == court_id,
                Outlet.court_id == court_id,
            ),
        )
        .all()
    )
    return [r[0] for r in rows]


# ─── Token hygiene ───────────────────────────────────────────────────────────

def deactivate_tokens_for_user(db: Session, *, user_type: str, user_id: int) -> int:
    """Soft-disable every token owned by a user. Caller commits.

    Called on logout and whenever an account is deactivated, so a revoked user
    stops receiving pushes immediately even though `get_current_user` would
    already block their API calls.
    """
    updated = (
        db.query(DeviceToken)
        .filter(
            DeviceToken.user_type == user_type,
            DeviceToken.user_id == user_id,
            DeviceToken.is_active == True,  # noqa: E712
        )
        .update({DeviceToken.is_active: False}, synchronize_session=False)
    )
    return int(updated or 0)


def deactivate_tokens(db: Session, tokens: Iterable[str]) -> int:
    """Soft-disable specific tokens — used when FCM reports them UNREGISTERED."""
    values = [t for t in tokens if t]
    if not values:
        return 0
    updated = (
        db.query(DeviceToken)
        .filter(DeviceToken.fcm_token.in_(values))
        .update({DeviceToken.is_active: False}, synchronize_session=False)
    )
    return int(updated or 0)
