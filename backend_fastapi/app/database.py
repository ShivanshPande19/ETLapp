import os
import pathlib
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import declarative_base, sessionmaker

# 🚀 BULLETPROOF LOGIC: Railway khud ek hidden variable deta hai. 
# Agar wo variable hai, toh hum cloud par hain. Warna Mac par hain!
if os.getenv("RAILWAY_ENVIRONMENT_NAME"):
    db_path = "/app/data/etl.db"
else:
    db_path = "app/etl.db"

_db_file = pathlib.Path(db_path)

# Ensure folder exists safely
_db_file.parent.mkdir(parents=True, exist_ok=True)

DATABASE_URL = f"sqlite:///{_db_file}"

_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

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
    created `attendance` table. This adds any missing check-out columns
    (SQLite supports `ALTER TABLE ... ADD COLUMN`). Safe to run on every boot.
    """
    needed = {
        "check_out_time": "DATETIME",
        "check_out_lat": "FLOAT",
        "check_out_lng": "FLOAT",
        "check_out_address": "VARCHAR",
        "check_out_photo_url": "VARCHAR",
    }
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            if "attendance" not in insp.get_table_names():
                return  # create_all will build it fresh with all columns
            existing = {c["name"] for c in insp.get_columns("attendance")}
            for col, col_type in needed.items():
                if col not in existing:
                    conn.execute(
                        text(f"ALTER TABLE attendance ADD COLUMN {col} {col_type}")
                    )
    except Exception as e:  # never block startup on a best-effort migration
        print(f"[MIGRATION] ensure_attendance_columns skipped: {e}")