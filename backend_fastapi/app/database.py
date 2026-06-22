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
        }
    else:
        types = {
            "check_out_time": "TIMESTAMP",
            "check_out_lat": "DOUBLE PRECISION",
            "check_out_lng": "DOUBLE PRECISION",
            "check_out_address": "VARCHAR",
            "check_out_photo_url": "VARCHAR",
        }
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "attendance" not in insp.get_table_names():
                return  # create_all will build it fresh with all columns
            existing = {c["name"] for c in insp.get_columns("attendance")}
            for col, col_type in types.items():
                if col not in existing:
                    conn.execute(
                        text(f"ALTER TABLE attendance ADD COLUMN {col} {col_type}")
                    )
    except Exception as e:  # never block startup on a best-effort migration
        print(f"[MIGRATION] ensure_attendance_columns skipped: {e}")


def ensure_outlet_columns() -> None:
    """Add per-outlet Petpooja credential columns to an existing `outlets`
    table (create_all never ALTERs existing tables). Best-effort + idempotent."""
    needed = {
        "pp_app_key": "VARCHAR",
        "pp_app_secret": "VARCHAR",
        "pp_access_token": "VARCHAR",
        "pp_cookie": "VARCHAR",
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


def ensure_staff_columns() -> None:
    """Add profile columns (phone, photo_url) to an existing `staff` table.
    Best-effort + idempotent."""
    needed = {"phone": "VARCHAR", "photo_url": "VARCHAR"}
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