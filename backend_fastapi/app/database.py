import os
import pathlib
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import declarative_base, sessionmaker

# ─── DB URL resolution ────────────────────────────────────────────────────────
# Priority:
#   1. DATABASE_URL env (Railway Postgres plugin sets this automatically) → prod
#   2. Local SQLite file → dev (Mac)
#
# Railway/Heroku sometimes provide the legacy "postgres://" scheme which
# SQLAlchemy 2.x rejects — normalize it to "postgresql://".
_env_url = os.getenv("DATABASE_URL", "").strip()

if _env_url:
    if _env_url.startswith("postgres://"):
        _env_url = _env_url.replace("postgres://", "postgresql://", 1)
    DATABASE_URL = _env_url
else:
    # Local dev fallback — SQLite file (persisted on Railway volume if used).
    if os.getenv("RAILWAY_ENVIRONMENT_NAME"):
        db_path = "/app/data/etl.db"
    else:
        db_path = "app/etl.db"
    _db_file = pathlib.Path(db_path)
    _db_file.parent.mkdir(parents=True, exist_ok=True)
    DATABASE_URL = f"sqlite:///{_db_file}"

_is_sqlite = DATABASE_URL.startswith("sqlite")
_connect_args = {"check_same_thread": False} if _is_sqlite else {}

engine = create_engine(
    DATABASE_URL,
    connect_args=_connect_args,
    pool_pre_ping=True,
    echo=False,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def ensure_attendance_columns() -> None:
    """Lightweight, idempotent migration.

    `Base.metadata.create_all` creates missing tables but never ALTERs an
    existing one, so newly-added model columns won't appear on an already
    created `attendance` table. This adds any missing check-out columns.
    Safe to run on every boot (best-effort).

    On a fresh Postgres DB `create_all` builds the full table, so the ALTER
    branch never runs there — but we still pick dialect-correct types just in
    case.
    """
    if _is_sqlite:
        types = {
            "check_out_time": "DATETIME",
            "check_out_lat": "FLOAT",
            "check_out_lng": "FLOAT",
            "check_out_address": "VARCHAR",
            "check_out_photo_url": "VARCHAR",
            "business_date": "DATE",
            "early_checkout": "BOOLEAN DEFAULT 0",
            "auto_closed": "BOOLEAN DEFAULT 0",
        }
    else:
        types = {
            "check_out_time": "TIMESTAMP",
            "check_out_lat": "DOUBLE PRECISION",
            "check_out_lng": "DOUBLE PRECISION",
            "check_out_address": "VARCHAR",
            "check_out_photo_url": "VARCHAR",
            "business_date": "DATE",
            "early_checkout": "BOOLEAN DEFAULT FALSE",
            "auto_closed": "BOOLEAN DEFAULT FALSE",
        }
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "attendance" not in insp.get_table_names():
                return  # create_all will build it fresh with all columns
            existing = {c["name"] for c in insp.get_columns("attendance")}
    except Exception as e:
        print(f"[MIGRATION] ensure_attendance_columns inspect skipped: {e}")
        return

    # Add each missing column in its OWN transaction, so one failure can never
    # roll back the others. Booleans carry a DEFAULT so existing rows backfill
    # via the DDL itself (no separate UPDATE — that previously broke on Postgres
    # because `SET bool_col = 0` is invalid there and rolled back the ALTER).
    for col, col_type in types.items():
        if col in existing:
            continue
        try:
            with engine.begin() as conn:
                conn.execute(
                    text(f"ALTER TABLE attendance ADD COLUMN {col} {col_type}")
                )
        except Exception as e:
            print(f"[MIGRATION] add attendance.{col} skipped: {e}")

    # Backfill business_date for existing rows from the check-in date so
    # historical attendance still groups correctly (best-effort, dialect-safe).
    if "business_date" not in existing:
        try:
            with engine.begin() as conn:
                conn.execute(
                    text(
                        "UPDATE attendance SET business_date = "
                        + ("date(check_in_time) " if _is_sqlite else "CAST(check_in_time AS DATE) ")
                        + "WHERE business_date IS NULL AND check_in_time IS NOT NULL"
                    )
                )
        except Exception as e:
            print(f"[MIGRATION] backfill business_date skipped: {e}")

    # Best-effort: prevent duplicate check-ins for the same staff+business day
    # (defends against a double-submit race). NULL business_date rows are
    # treated as distinct on both dialects, so legacy rows are unaffected.
    try:
        with engine.begin() as conn:
            conn.execute(
                text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_staff_bizdate "
                    "ON attendance (staff_id, business_date)"
                )
            )
    except Exception as e:
        print(f"[MIGRATION] attendance unique index skipped: {e}")


def ensure_outlet_columns() -> None:
    """Add per-outlet Petpooja credential columns to an existing `outlets`
    table (create_all never ALTERs existing tables). Best-effort + idempotent."""
    needed = {
        "pp_app_key": "VARCHAR",
        "pp_app_secret": "VARCHAR",
        "pp_access_token": "VARCHAR",
        "pp_cookie": "VARCHAR",
        # Which POS adapter fetches this outlet. DEFAULT backfills existing rows
        # via the DDL itself so every legacy outlet keeps the generic flow.
        "pos_source": "VARCHAR DEFAULT 'petpooja_generic'",
    }
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "outlets" not in insp.get_table_names():
                return  # create_all will build it fresh with all columns
            existing = {c["name"] for c in insp.get_columns("outlets")}
            for col, col_type in needed.items():
                if col not in existing:
                    conn.execute(
                        text(f"ALTER TABLE outlets ADD COLUMN {col} {col_type}")
                    )
    except Exception as e:  # never block startup on a best-effort migration
        print(f"[MIGRATION] ensure_outlet_columns skipped: {e}")

    # Any row that predates the DEFAULT (or was inserted NULL) → generic flow.
    try:
        with engine.begin() as conn:
            conn.execute(
                text(
                    "UPDATE outlets SET pos_source = 'petpooja_generic' "
                    "WHERE pos_source IS NULL"
                )
            )
    except Exception as e:
        print(f"[MIGRATION] backfill outlets.pos_source skipped: {e}")


def backfill_sales_orders() -> None:
    """One-time, idempotent copy of ``petpooja_orders`` → ``sales_orders``.

    Expand → migrate → contract: the new multi-source pipeline reads/writes
    ``sales_orders``; this seeds it with the existing Momo Box history so
    ``DailySaleCache`` recompute (now summing ``sales_orders``) reconciles
    exactly with the old numbers. Rows already present are skipped via the
    ``(outlet_id, source, external_ref)`` unique key, so this is safe on every
    boot and independent of whether a new sync has already run.
    """
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            tables = set(insp.get_table_names())
            if "petpooja_orders" not in tables or "sales_orders" not in tables:
                return  # nothing to migrate (fresh DB) — create_all made the table

            conflict = (
                "OR IGNORE " if _is_sqlite else ""
            )
            tail = (
                "" if _is_sqlite
                else "ON CONFLICT (outlet_id, source, external_ref) DO NOTHING"
            )
            cast = "CAST(order_id AS TEXT)" if _is_sqlite else "CAST(order_id AS VARCHAR)"
            conn.execute(
                text(
                    f"INSERT {conflict}INTO sales_orders "
                    "(outlet_id, source, external_ref, business_date, created_on, total_amount, status) "
                    f"SELECT outlet_id, 'petpooja_generic', {cast}, business_date, created_on, "
                    f"total_amount, 'completed' FROM petpooja_orders {tail}"
                )
            )
        print("[MIGRATION] backfill_sales_orders ran ✓")
    except Exception as e:
        print(f"[MIGRATION] backfill_sales_orders skipped: {e}")


def backfill_outlet_memberships() -> None:
    """One-time, idempotent seed of ``outlet_memberships`` from the legacy
    ``Manager.outlet_id`` column.

    Every existing outlet_manager becomes an ``owner`` of their current outlet,
    so multi-outlet scoping (which reads memberships) behaves EXACTLY as the
    old single-``outlet_id`` scoping did for current accounts — zero behaviour
    change on deploy. Rows already present are skipped via the
    ``(manager_id, outlet_id)`` unique key, so this is safe on every boot.
    """
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            tables = set(insp.get_table_names())
            if "managers" not in tables or "outlet_memberships" not in tables:
                return  # fresh DB — create_all just made the table

            conflict = "OR IGNORE " if _is_sqlite else ""
            tail = (
                "" if _is_sqlite
                else "ON CONFLICT (manager_id, outlet_id) DO NOTHING"
            )
            conn.execute(
                text(
                    f"INSERT {conflict}INTO outlet_memberships "
                    "(manager_id, outlet_id, membership_role) "
                    "SELECT id, outlet_id, 'owner' FROM managers "
                    "WHERE role = 'outlet_manager' AND outlet_id IS NOT NULL "
                    f"{tail}"
                )
            )
        print("[MIGRATION] backfill_outlet_memberships ran ✓")
    except Exception as e:
        print(f"[MIGRATION] backfill_outlet_memberships skipped: {e}")


def ensure_staff_columns() -> None:
    """Add profile columns (phone, photo_url) to an existing `staff` table.
    Best-effort + idempotent."""
    needed = {"phone": "VARCHAR", "photo_url": "VARCHAR", "shift_start": "VARCHAR", "shift_end": "VARCHAR"}
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "staff" not in insp.get_table_names():
                return
            existing = {c["name"] for c in insp.get_columns("staff")}
            for col, col_type in needed.items():
                if col not in existing:
                    conn.execute(
                        text(f"ALTER TABLE staff ADD COLUMN {col} {col_type}")
                    )
    except Exception as e:
        print(f"[MIGRATION] ensure_staff_columns skipped: {e}")


def ensure_notice_columns() -> None:
    """Add `outlet_id` to an existing `notices` table (created before outlet
    notice routing). Best-effort + idempotent."""
    needed = {"outlet_id": "INTEGER"}
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "notices" not in insp.get_table_names():
                return  # create_all builds it fresh with all columns
            existing = {c["name"] for c in insp.get_columns("notices")}
            for col, col_type in needed.items():
                if col not in existing:
                    conn.execute(
                        text(f"ALTER TABLE notices ADD COLUMN {col} {col_type}")
                    )
    except Exception as e:
        print(f"[MIGRATION] ensure_notice_columns skipped: {e}")


def ensure_court_columns() -> None:
    """Add geofencing columns (latitude, longitude, geofence_radius, address)
    to an existing `courts` table. create_all never ALTERs existing tables, so
    courts created before the geofencing feature need these added at boot.
    Best-effort + idempotent. Existing rows get NULL (no data loss) and simply
    skip geofencing until a manager sets a location."""
    if _is_sqlite:
        needed = {
            "latitude": "FLOAT",
            "longitude": "FLOAT",
            "geofence_radius": "INTEGER",
            "address": "VARCHAR",
            "day_cutoff_hour": "INTEGER",
            "google_review_url": "VARCHAR",
        }
    else:
        needed = {
            "latitude": "DOUBLE PRECISION",
            "longitude": "DOUBLE PRECISION",
            "geofence_radius": "INTEGER",
            "address": "VARCHAR",
            "day_cutoff_hour": "INTEGER",
            "google_review_url": "VARCHAR",
        }
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "courts" not in insp.get_table_names():
                return  # create_all will build it fresh with all columns
            existing = {c["name"] for c in insp.get_columns("courts")}
            for col, col_type in needed.items():
                if col not in existing:
                    conn.execute(
                        text(f"ALTER TABLE courts ADD COLUMN {col} {col_type}")
                    )
    except Exception as e:  # never block startup on a best-effort migration
        print(f"[MIGRATION] ensure_court_columns skipped: {e}")


def ensure_feedback_columns() -> None:
    """Add the Google-review funnel column to an existing `feedbacks` table.

    `create_all` builds the table fresh with every column, so this only matters
    on a deploy where `feedbacks` already exists from an earlier version.
    Best-effort + idempotent, same as the other ensure_* helpers. Existing rows
    get NULL, which correctly reads as "never tapped the Google CTA".
    """
    needed = {
        "google_cta_clicked_at": "DATETIME" if _is_sqlite else "TIMESTAMP",
    }
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "feedbacks" not in insp.get_table_names():
                return  # create_all builds it fresh with all columns
            existing = {c["name"] for c in insp.get_columns("feedbacks")}
            for col, col_type in needed.items():
                if col not in existing:
                    conn.execute(
                        text(f"ALTER TABLE feedbacks ADD COLUMN {col} {col_type}")
                    )
    except Exception as e:  # never block startup on a best-effort migration
        print(f"[MIGRATION] ensure_feedback_columns skipped: {e}")


def ensure_hk_columns() -> None:
    """Add `done_by_name` to existing `hk_tasks` and `hk_recurring` tables
    (create_all never ALTERs existing tables). Best-effort + idempotent."""
    targets = {
        "hk_tasks": {"done_by_name": "VARCHAR"},
        "hk_recurring": {"done_by_name": "VARCHAR"},
    }
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            tables = set(insp.get_table_names())
            for table, needed in targets.items():
                if table not in tables:
                    continue  # create_all will build it fresh with all columns
                existing = {c["name"] for c in insp.get_columns(table)}
                for col, col_type in needed.items():
                    if col not in existing:
                        conn.execute(
                            text(f"ALTER TABLE {table} ADD COLUMN {col} {col_type}")
                        )
    except Exception as e:
        print(f"[MIGRATION] ensure_hk_columns skipped: {e}")



def ensure_device_token_columns() -> None:
    """Add newly-introduced columns to an existing `device_tokens` table.

    `create_all` builds the table fresh with every column, so this only matters
    on a deploy where the table already exists from an earlier version.
    Best-effort + idempotent, same as the other ensure_* helpers.
    """
    needed = {
        "user_type": "VARCHAR",
        "user_id": "INTEGER",
        "email": "VARCHAR",
        "role": "VARCHAR",
        "court_id": "INTEGER",
        "outlet_id": "INTEGER",
        "platform": "VARCHAR",
        "app_version": "VARCHAR",
        "last_seen_at": "DATETIME" if _is_sqlite else "TIMESTAMP",
    }
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "device_tokens" not in insp.get_table_names():
                return  # create_all builds it fresh with all columns
            existing = {c["name"] for c in insp.get_columns("device_tokens")}
            for col, col_type in needed.items():
                if col not in existing:
                    conn.execute(
                        text(f"ALTER TABLE device_tokens ADD COLUMN {col} {col_type}")
                    )
    except Exception as e:
        print(f"[MIGRATION] ensure_device_token_columns skipped: {e}")
