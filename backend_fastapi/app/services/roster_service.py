# backend_fastapi/app/services/roster_service.py

import json
from datetime import date
from typing import Optional
from sqlalchemy import or_, and_
from sqlalchemy.orm import Session
from ..models.staff import Staff
from ..models.attendance import Attendance
from ..models.sale import Court
from ..core.query_utils import day_range
from ..schemas.attendance import (
    RosterResponse,
    StaffRosterItem,
    CourtRosterItem,
    EtlRosterResponse,
)

def get_daily_roster(db: Session, outlet_id: int, target_date: date) -> RosterResponse:
    # 1. Us outlet ke saare active staff nikalo
    staff_members = db.query(Staff).filter(
        Staff.outlet_id == outlet_id, 
        Staff.is_active == True
    ).all()

    # 2. Aaj ki attendance nikalo us outlet ki — business_date pe match karo
    # (overnight-safe), legacy null rows ke liye calendar-day fallback.
    _start, _end = day_range(target_date)
    attendances = db.query(Attendance).filter(
        Attendance.outlet_id == outlet_id,
        or_(
            Attendance.business_date == target_date,
            and_(
                Attendance.business_date.is_(None),
                Attendance.check_in_time >= _start,
                Attendance.check_in_time < _end,
            ),
        ),
    ).all()

    # Dictionary banalo taaki fast search ho sake {staff_id: attendance_record}
    attendance_map = {a.staff_id: a for a in attendances}

    roster_list = []
    present_count = 0

    # 3. Har staff ko check karo
    for staff in staff_members:
        record = attendance_map.get(staff.id)
        
        if record:
            status = "present"
            present_count += 1
            # ✅ Raw UTC times — schema serializes with 'Z' aur client toLocal()
            # karke sahi local time dikhata hai (manual +5:30 hack hata diya).
            chk_in = record.check_in_time
            chk_out = record.check_out_time
            selfie = record.check_in_photo_url
            in_photo = record.check_in_photo_url
            out_photo = record.check_out_photo_url
            early = bool(record.early_checkout)
            auto = bool(record.auto_closed)
        else:
            status = "absent"
            chk_in = None
            chk_out = None
            selfie = None
            in_photo = None
            out_photo = None
            early = False
            auto = False

        roster_list.append(StaffRosterItem(
            staff_id=staff.id,
            name=staff.name,
            role=staff.role,
            status=status,
            check_in_time=chk_in,
            check_out_time=chk_out,
            selfie_url=selfie,
            check_in_photo_url=in_photo,
            check_out_photo_url=out_photo,
            early_checkout=early,
            auto_closed=auto,
        ))

    return RosterResponse(
        date=target_date,
        total_staff=len(staff_members),
        present_count=present_count,
        staff_list=roster_list
    )


def _build_court_roster(db: Session, court: Court, target_date: date) -> CourtRosterItem:
    """Ek court ke ETL staff ka roster banata hai (court_id se scoped)."""
    # ETL staff us court ke (court_id set hota hai; outlet staff ka court_id null
    # hota hai isliye wo apne aap exclude ho jaate hain).
    # Multi-zone roles ko yahan se exclude karte hain:
    #   • crownest_maintenance_head → "Maintenance · All Zones" section me ek baar.
    #   • crownest_zone_manager     → har assigned zone me staff_id se match karke
    #     alag se add hota hai (_zone_managers_for_court), warna sirf apne primary
    #     court_id wale zone me + galat attendance match ke saath dikhta.
    staff_members = db.query(Staff).filter(
        Staff.court_id == court.id,
        Staff.is_active == True,
        Staff.role.notin_(["crownest_maintenance_head", "crownest_zone_manager"]),
    ).all()

    _start, _end = day_range(target_date)
    attendances = db.query(Attendance).filter(
        Attendance.court_id == court.id,
        or_(
            Attendance.business_date == target_date,
            and_(
                Attendance.business_date.is_(None),
                Attendance.check_in_time >= _start,
                Attendance.check_in_time < _end,
            ),
        ),
    ).all()
    attendance_map = {a.staff_id: a for a in attendances}

    roster_list = []
    present_count = 0
    for staff in staff_members:
        record = attendance_map.get(staff.id)
        if record:
            status = "present"
            present_count += 1
            chk_in = record.check_in_time
            chk_out = record.check_out_time
            selfie = record.check_in_photo_url
            in_photo = record.check_in_photo_url
            out_photo = record.check_out_photo_url
            early = bool(record.early_checkout)
            auto = bool(record.auto_closed)
        else:
            status = "absent"
            chk_in = None
            chk_out = None
            selfie = None
            in_photo = None
            out_photo = None
            early = False
            auto = False

        roster_list.append(StaffRosterItem(
            staff_id=staff.id,
            name=staff.name,
            role=staff.role,
            status=status,
            check_in_time=chk_in,
            check_out_time=chk_out,
            selfie_url=selfie,
            check_in_photo_url=in_photo,
            check_out_photo_url=out_photo,
            early_checkout=early,
            auto_closed=auto,
        ))

    # Present staff pehle, phir naam se sort (frontend ke liye consistent order)
    roster_list.sort(key=lambda s: (s.status != "present", s.name.lower()))

    return CourtRosterItem(
        court_id=court.id,
        court_name=court.name,
        total_staff=len(staff_members),
        present_count=present_count,
        staff_list=roster_list,
    )


def _build_maintenance_team(db: Session, target_date: date) -> list[StaffRosterItem]:
    """Roaming maintenance heads (Crownest Maintenance Head) cover every zone,
    so they aren't tied to a single court's roster. They're returned once as an
    'all zones' group; attendance is matched by staff_id (NOT court_id) because
    they can check in from wherever they are."""
    heads = db.query(Staff).filter(
        Staff.role == "crownest_maintenance_head",
        Staff.is_active == True,
    ).order_by(Staff.name).all()
    if not heads:
        return []

    _start, _end = day_range(target_date)
    head_ids = [h.id for h in heads]
    attendances = db.query(Attendance).filter(
        Attendance.staff_id.in_(head_ids),
        or_(
            Attendance.business_date == target_date,
            and_(
                Attendance.business_date.is_(None),
                Attendance.check_in_time >= _start,
                Attendance.check_in_time < _end,
            ),
        ),
    ).all()
    attendance_map = {a.staff_id: a for a in attendances}

    items = []
    for staff in heads:
        record = attendance_map.get(staff.id)
        if record:
            items.append(StaffRosterItem(
                staff_id=staff.id,
                name=staff.name,
                role=staff.role,
                status="present",
                check_in_time=record.check_in_time,
                check_out_time=record.check_out_time,
                selfie_url=record.check_in_photo_url,
                check_in_photo_url=record.check_in_photo_url,
                check_out_photo_url=record.check_out_photo_url,
                early_checkout=bool(record.early_checkout),
                auto_closed=bool(record.auto_closed),
            ))
        else:
            items.append(StaffRosterItem(
                staff_id=staff.id,
                name=staff.name,
                role=staff.role,
                status="absent",
            ))
    return items


def _zone_court_ids_for_staff(staff: Staff) -> list[int]:
    """A staff's assigned zone court-ids from the `zone_court_ids` JSON list,
    falling back to [court_id]. Mirrors deps._parse_zone_court_ids."""
    raw = getattr(staff, "zone_court_ids", None)
    if raw:
        try:
            v = json.loads(raw)
            if isinstance(v, list):
                ids = [int(x) for x in v]
                if ids:
                    return ids
        except Exception:
            pass
    return [staff.court_id] if staff.court_id else []


def _zone_managers_for_court(
    db: Session, court_id: int, target_date: date
) -> list[StaffRosterItem]:
    """Crownest Zone Managers assigned to THIS court (via zone_court_ids), shown
    in the court's roster alongside its staff (with a 'Zone Manager' badge on the
    client, keyed off `role`).

    A zone manager may cover several zones but checks in from wherever it is, so
    — exactly like the roaming maintenance head — attendance is matched by
    `staff_id` (NOT court_id). It therefore shows as PRESENT in EVERY one of its
    assigned zones once it has checked in anywhere that business day."""
    zms = (
        db.query(Staff)
        .filter(
            Staff.role == "crownest_zone_manager",
            Staff.is_active == True,
        )
        .order_by(Staff.name)
        .all()
    )
    assigned = [z for z in zms if court_id in _zone_court_ids_for_staff(z)]
    if not assigned:
        return []

    _start, _end = day_range(target_date)
    ids = [z.id for z in assigned]
    attendances = db.query(Attendance).filter(
        Attendance.staff_id.in_(ids),
        or_(
            Attendance.business_date == target_date,
            and_(
                Attendance.business_date.is_(None),
                Attendance.check_in_time >= _start,
                Attendance.check_in_time < _end,
            ),
        ),
    ).all()
    attendance_map = {a.staff_id: a for a in attendances}

    items: list[StaffRosterItem] = []
    for z in assigned:
        record = attendance_map.get(z.id)
        if record:
            items.append(StaffRosterItem(
                staff_id=z.id,
                name=z.name,
                role=z.role,
                status="present",
                check_in_time=record.check_in_time,
                check_out_time=record.check_out_time,
                selfie_url=record.check_in_photo_url,
                check_in_photo_url=record.check_in_photo_url,
                check_out_photo_url=record.check_out_photo_url,
                early_checkout=bool(record.early_checkout),
                auto_closed=bool(record.auto_closed),
            ))
        else:
            items.append(StaffRosterItem(
                staff_id=z.id,
                name=z.name,
                role=z.role,
                status="absent",
            ))
    return items


def get_etl_court_roster(
    db: Session,
    target_date: date,
    court_id: Optional[int] = None,
) -> EtlRosterResponse:
    """ETL manager ke liye court-wise staff attendance roster.
    court_id diya ho toh sirf wahi court, warna saare active courts."""
    court_query = db.query(Court).filter(Court.is_active == 1)
    if court_id is not None:
        court_query = court_query.filter(Court.id == court_id)
    courts = court_query.order_by(Court.name).all()

    court_items = [_build_court_roster(db, court, target_date) for court in courts]

    # Base (regular ETL/outlet staff) totals — captured BEFORE attaching zone
    # managers, so a multi-zone zone manager isn't counted once per zone in the
    # global totals.
    base_staff = sum(c.total_staff for c in court_items)
    base_present = sum(c.present_count for c in court_items)

    # Attach Crownest Zone Managers to EACH of their assigned zones. Matched by
    # staff_id, so a 2-zone manager who checked in anywhere shows present in BOTH
    # zones. Per-court counts include them (so each card's "x / y in" is right);
    # the global totals count each zone manager ONCE (distinct by staff_id).
    zm_present_by_id: dict[int, bool] = {}
    for item in court_items:
        zms = _zone_managers_for_court(db, item.court_id, target_date)
        if not zms:
            continue
        for zi in zms:
            item.staff_list.append(zi)
            item.total_staff += 1
            if zi.status == "present":
                item.present_count += 1
            if zi.staff_id not in zm_present_by_id:
                zm_present_by_id[zi.staff_id] = (zi.status == "present")
        # Keep each card present-first, then by name (zone managers included).
        item.staff_list.sort(key=lambda s: (s.status != "present", s.name.lower()))

    # Roaming maintenance heads span every zone — counted ONCE (not per court).
    maintenance_team = _build_maintenance_team(db, target_date)
    maint_present = sum(1 for m in maintenance_team if m.status == "present")

    total_staff = base_staff + len(zm_present_by_id) + len(maintenance_team)
    total_present = (
        base_present
        + sum(1 for present in zm_present_by_id.values() if present)
        + maint_present
    )

    return EtlRosterResponse(
        date=target_date,
        total_courts=len(court_items),
        total_staff=total_staff,
        total_present=total_present,
        courts=court_items,
        maintenance_team=maintenance_team,
    )
