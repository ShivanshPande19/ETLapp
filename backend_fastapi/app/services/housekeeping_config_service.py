# app/services/housekeeping_config_service.py
"""Per-court housekeeping checklist configuration.

A court's checklist = ordered shifts (name + timings), each with its own daily
tasks, plus court-level weekly & monthly recurring tasks. Stored in hk_shift /
hk_taskdef. Completions (HkTask / HkRecurring) reference the stable `key`s, so
renaming a shift/task never orphans history.
"""

import uuid

from sqlalchemy.orm import Session

from ..models.housekeeping import HkShift, HkTaskDef


def _gen_key(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:8]}"


# ── Default template (mirrors the legacy hardcoded checklist) ────────────────
# Existing courts (1,2,3) get exactly this, so nothing changes for them.
_DEFAULT_DAILY = [
    {"key": "floorclean", "title": "Floor Cleaning", "icon": "cleaning_services"},
    {"key": "tablechairclean", "title": "Table & Chair Clean", "icon": "chair"},
    {"key": "binclean", "title": "Bins Cleaning (outside)", "icon": "delete_forever"},
    {"key": "trayclean", "title": "Tray Cleaning", "icon": "restaurant"},
    {"key": "binempty", "title": "Garbage Bin Empty", "icon": "delete_outline"},
    {"key": "pestspray", "title": "Pest Spray", "icon": "pest_control"},
]

_DEFAULT_SHIFTS = [
    {"key": "morning", "name": "Morning", "start_time": "06:00", "end_time": "12:00"},
    {"key": "day", "name": "Day", "start_time": "12:00", "end_time": "17:00"},
    {"key": "night", "name": "Night", "start_time": "17:00", "end_time": "23:00"},
]

_DEFAULT_WEEKLY = [
    {"key": "flagswash", "title": "Flags Washing", "icon": "flag", "interval_days": 7},
]
_DEFAULT_MONTHLY = [
    {"key": "fireaudit", "title": "Fire Safety Audit", "icon": "fire_extinguisher", "interval_days": 30},
]


def default_template() -> dict:
    """A fresh, editable template for a new court (no keys yet → generated on save)."""
    return {
        "shifts": [
            {
                "name": s["name"],
                "start_time": s["start_time"],
                "end_time": s["end_time"],
                "tasks": [{"title": t["title"], "icon": t["icon"]} for t in _DEFAULT_DAILY],
            }
            for s in _DEFAULT_SHIFTS
        ],
        "weekly": [
            {"title": w["title"], "icon": w["icon"], "interval_days": w["interval_days"]}
            for w in _DEFAULT_WEEKLY
        ],
        "monthly": [
            {"title": m["title"], "icon": m["icon"], "interval_days": m["interval_days"]}
            for m in _DEFAULT_MONTHLY
        ],
    }


def has_config(db: Session, court_id: int) -> bool:
    return db.query(HkShift).filter(HkShift.court_id == court_id).first() is not None


def seed_default_config(db: Session, court_id: int) -> None:
    """Seed the LEGACY default (with the original stable keys) for a court that
    has no config yet — keeps existing courts behaving exactly as before."""
    if has_config(db, court_id):
        return
    for i, s in enumerate(_DEFAULT_SHIFTS):
        db.add(HkShift(
            court_id=court_id, key=s["key"], name=s["name"],
            start_time=s["start_time"], end_time=s["end_time"], sort_order=i,
        ))
        for j, t in enumerate(_DEFAULT_DAILY):
            db.add(HkTaskDef(
                court_id=court_id, scope="daily", shift_key=s["key"],
                key=t["key"], title=t["title"], icon=t["icon"], sort_order=j,
            ))
    for j, w in enumerate(_DEFAULT_WEEKLY):
        db.add(HkTaskDef(
            court_id=court_id, scope="weekly", key=w["key"], title=w["title"],
            icon=w["icon"], interval_days=w["interval_days"], sort_order=j,
        ))
    for j, m in enumerate(_DEFAULT_MONTHLY):
        db.add(HkTaskDef(
            court_id=court_id, scope="monthly", key=m["key"], title=m["title"],
            icon=m["icon"], interval_days=m["interval_days"], sort_order=j,
        ))
    db.commit()


def get_court_config(db: Session, court_id: int, seed_if_empty: bool = True) -> dict:
    """Return the full checklist config for a court (seeding legacy defaults if
    none exists)."""
    if seed_if_empty and not has_config(db, court_id):
        seed_default_config(db, court_id)

    shifts = (
        db.query(HkShift)
        .filter(HkShift.court_id == court_id)
        .order_by(HkShift.sort_order, HkShift.id)
        .all()
    )
    taskdefs = (
        db.query(HkTaskDef)
        .filter(HkTaskDef.court_id == court_id)
        .order_by(HkTaskDef.sort_order, HkTaskDef.id)
        .all()
    )

    daily_by_shift: dict[str, list] = {}
    weekly, monthly = [], []
    for t in taskdefs:
        item = {
            "key": t.key, "title": t.title, "icon": t.icon,
            "interval_days": t.interval_days, "sort_order": t.sort_order,
        }
        if t.scope == "daily":
            daily_by_shift.setdefault(t.shift_key, []).append(item)
        elif t.scope == "weekly":
            weekly.append(item)
        elif t.scope == "monthly":
            monthly.append(item)

    return {
        "court_id": court_id,
        "shifts": [
            {
                "key": s.key, "name": s.name,
                "start_time": s.start_time, "end_time": s.end_time,
                "sort_order": s.sort_order,
                "tasks": daily_by_shift.get(s.key, []),
            }
            for s in shifts
        ],
        "weekly": weekly,
        "monthly": monthly,
    }


def save_court_config(db: Session, court_id: int, payload: dict) -> dict:
    """Replace a court's checklist config. Preserves stable keys passed in
    (so completion history stays linked); generates keys for new items."""
    # Wipe current config for this court, then rebuild from payload.
    db.query(HkTaskDef).filter(HkTaskDef.court_id == court_id).delete()
    db.query(HkShift).filter(HkShift.court_id == court_id).delete()

    for i, s in enumerate(payload.get("shifts", []) or []):
        skey = (s.get("key") or "").strip() or _gen_key("shift")
        db.add(HkShift(
            court_id=court_id, key=skey,
            name=(s.get("name") or "Shift").strip(),
            start_time=s.get("start_time"), end_time=s.get("end_time"),
            sort_order=i,
        ))
        for j, t in enumerate(s.get("tasks", []) or []):
            db.add(HkTaskDef(
                court_id=court_id, scope="daily", shift_key=skey,
                key=(t.get("key") or "").strip() or _gen_key("task"),
                title=(t.get("title") or "Task").strip(),
                icon=t.get("icon"), sort_order=j,
            ))

    for scope, default_interval in (("weekly", 7), ("monthly", 30)):
        for j, t in enumerate(payload.get(scope, []) or []):
            db.add(HkTaskDef(
                court_id=court_id, scope=scope,
                key=(t.get("key") or "").strip() or _gen_key("task"),
                title=(t.get("title") or "Task").strip(),
                icon=t.get("icon"),
                interval_days=t.get("interval_days") or default_interval,
                sort_order=j,
            ))

    db.commit()
    return get_court_config(db, court_id, seed_if_empty=False)
