# app/database.py
# ─────────────────────────────────────────────────────────────────────────────
# Single source of truth for SQLAlchemy setup.
# Exports: Base, engine, SessionLocal, get_db
# ─────────────────────────────────────────────────────────────────────────────

import os
import shutil
import pathlib
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# ── Try to read DATABASE_URL from your config ─────────────────────────────────
try:
    from .core.config import settings
    DATABASE_URL: str = settings.DATABASE_URL
except Exception:
    DATABASE_URL = None

# ── Setup Database Path (Railway Volume vs Local) ─────────────────────────────
# Railway variable: DB_FILE_PATH=/app/data/etl.db
db_file_env = os.getenv("DB_FILE_PATH")

if db_file_env:
    # Running on Railway with a volume
    _db_file = pathlib.Path(db_file_env)
    DATABASE_URL = f"sqlite:///{_db_file}"
elif not DATABASE_URL:
    # Local fallback if nothing is set
    _db_file = pathlib.Path(__file__).parent / "etl.db"
    DATABASE_URL = f"sqlite:///{_db_file}"
else:
    # Fallback for Postgres or other DBs (no local file)
    _db_file = None

# ── PERMANENT FIX LOGIC (Seed DB) ─────────────────────────────────────────────
if DATABASE_URL.startswith("sqlite") and _db_file:
    # Find seed file whether it's in backend_fastapi/app/ or backend_fastapi/
    _seed_path_app = pathlib.Path(__file__).parent / "seed_etl.db"
    _seed_path_root = pathlib.Path(__file__).parent.parent / "seed_etl.db"
    
    actual_seed = None
    if _seed_path_app.exists():
        actual_seed = _seed_path_app
    elif _seed_path_root.exists():
        actual_seed = _seed_path_root
        
    # If the destination volume DB doesn't exist but we have a seed file, copy it!
    if actual_seed and not _db_file.exists():
        _db_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(actual_seed, _db_file)
        print(f"🚀 DATABASE INITIALIZED: Copied real data from {actual_seed} to permanent volume {_db_file}")

# ── Engine ────────────────────────────────────────────────────────────────────
# connect_args only needed for SQLite (disables the single-thread check so
# FastAPI's thread-pool workers can all share the same connection).
_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(
    DATABASE_URL,
    connect_args=_connect_args,
    # Pool tweaks — safe defaults for both SQLite and Postgres
    pool_pre_ping=True,   # auto-reconnect on stale connections
    echo=False,           # set True to print every SQL statement (debug only)
)

# ── Session factory ───────────────────────────────────────────────────────────
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# ── Base ──────────────────────────────────────────────────────────────────────
# All ORM models inherit from this. Importing a model file registers it here,
# so Base.metadata.create_all(bind=engine) in main.py creates its table.
Base = declarative_base()


# ── Dependency ────────────────────────────────────────────────────────────────
def get_db():
    """
    FastAPI dependency — yields a DB session per request and closes it after.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()