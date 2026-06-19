# backend_fastapi/app/core/query_utils.py
#
# Small DB-portability helpers.

from datetime import date, datetime, time, timedelta
from typing import Tuple


def day_range(target: date) -> Tuple[datetime, datetime]:
    """Return [start, end) datetime bounds for a calendar day.

    Used instead of `func.date(col) == target` because Postgres has no
    `date()` function and `CAST(... AS DATE)` is unsafe on SQLite. A half-open
    range works identically on both dialects and is index-friendly.
    """
    start = datetime.combine(target, time.min)
    end = start + timedelta(days=1)
    return start, end
