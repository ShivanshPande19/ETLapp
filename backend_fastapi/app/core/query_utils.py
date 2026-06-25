# backend_fastapi/app/core/query_utils.py
#
# Small DB-portability + time helpers.

from datetime import date, datetime, time, timedelta, timezone
from typing import Optional, Tuple

# India is the only operating region. Prefer a real tz database entry, fall
# back to a fixed +05:30 offset if zoneinfo data isn't bundled.
try:  # pragma: no cover
    from zoneinfo import ZoneInfo
    IST = ZoneInfo("Asia/Kolkata")
except Exception:  # pragma: no cover
    IST = timezone(timedelta(hours=5, minutes=30))


def day_range(target: date) -> Tuple[datetime, datetime]:
    """Return [start, end) datetime bounds for a calendar day.

    Used instead of `func.date(col) == target` because Postgres has no
    `date()` function and `CAST(... AS DATE)` is unsafe on SQLite. A half-open
    range works identically on both dialects and is index-friendly.
    """
    start = datetime.combine(target, time.min)
    end = start + timedelta(days=1)
    return start, end


# ─── Business-day handling (overnight courts) ─────────────────────────────────

def now_ist() -> datetime:
    """Current time as a timezone-aware IST datetime."""
    return datetime.now(IST)


def to_ist(dt: datetime) -> datetime:
    """Convert a UTC datetime (naive == UTC, or aware) to aware IST."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(IST)


def business_date_for(dt_ist: datetime, cutoff_hour: int = 0) -> date:
    """Business day a moment belongs to, given the court's rollover hour.

    cutoff_hour = 0 → business day == calendar day (normal court).
    For an overnight court (e.g. 2pm→2am) set cutoff ~5: any time whose IST hour
    is before the cutoff is attributed to the PREVIOUS calendar day, so a 2am
    check-out lands on the day the shift started.
    """
    if dt_ist.tzinfo is None:
        dt_ist = dt_ist.replace(tzinfo=IST)
    if cutoff_hour and dt_ist.hour < cutoff_hour:
        return (dt_ist - timedelta(days=1)).date()
    return dt_ist.date()


def current_business_date(cutoff_hour: int = 0) -> date:
    """Today's business date for a court with the given cutoff hour."""
    return business_date_for(now_ist(), cutoff_hour)


def parse_hhmm(value: Optional[str]) -> Optional[time]:
    """Parse a 'HH:MM' string into a time; None if missing/invalid."""
    if not value:
        return None
    try:
        hh, mm = value.split(":")
        return time(hour=int(hh), minute=int(mm))
    except (ValueError, AttributeError):
        return None


def scheduled_shift_end_utc(
    biz_date: date, shift_start: Optional[str], shift_end: Optional[str]
) -> Optional[datetime]:
    """Naive-UTC datetime when a staff's shift is scheduled to end on a given
    business date. Handles overnight shifts (end <= start ⇒ ends next day).
    Returns None if shift_end isn't set.
    """
    start_t = parse_hhmm(shift_start)
    end_t = parse_hhmm(shift_end)
    if end_t is None:
        return None

    end_day = biz_date
    if start_t is not None and end_t <= start_t:
        end_day = biz_date + timedelta(days=1)  # overnight shift

    end_ist = datetime.combine(end_day, end_t, tzinfo=IST)
    return end_ist.astimezone(timezone.utc).replace(tzinfo=None)


def scheduled_shift_start_utc(
    biz_date: date, shift_start: Optional[str]
) -> Optional[datetime]:
    """Naive-UTC datetime when a staff's shift is scheduled to start on a given
    business date. Returns None if shift_start isn't set."""
    start_t = parse_hhmm(shift_start)
    if start_t is None:
        return None
    start_ist = datetime.combine(biz_date, start_t, tzinfo=IST)
    return start_ist.astimezone(timezone.utc).replace(tzinfo=None)


def business_day_end_utc(biz_date: date, cutoff_hour: int = 0) -> datetime:
    """Naive-UTC moment a business day rolls over.

    cutoff 0 → next calendar midnight IST. cutoff h → next day at h:00 IST.
    Used as a fallback auto-close time when a staff has no shift end set.
    """
    end_ist = datetime.combine(biz_date + timedelta(days=1), time(hour=cutoff_hour), tzinfo=IST)
    return end_ist.astimezone(timezone.utc).replace(tzinfo=None)
