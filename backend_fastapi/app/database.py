# app/database.py
# ─────────────────────────────────────────────────────────────────────────────
# Single source of truth for SQLAlchemy setup.
# Exports: Base, engine, SessionLocal, get_db
#
# DATABASE_URL is read from your .env via app/core/config.py (settings).
# Default fallback: SQLite file at backend_fastapi/app/etl.db
# To use PostgreSQL later: set DATABASE_URL=postgresql://user:pass@host/dbname
# ─────────────────────────────────────────────────────────────────────────────

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# ── Try to read DATABASE_URL from your config ─────────────────────────────────
# If config import fails (e.g., missing env), fall back to a local SQLite file.
try:
    from .core.config import settings
    DATABASE_URL: str = settings.DATABASE_URL
except Exception:
    import os, pathlib
    _db_file = pathlib.Path(__file__).parent / "etl.db"
    DATABASE_URL = f"sqlite:///{_db_file}"

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

    Usage in a route:
        from app.database import get_db
        def my_route(db: Session = Depends(get_db)): ...
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
