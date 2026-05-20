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
db_file_env = os.getenv("DB_FILE_PATH")

if db_file_env:
    _db_file = pathlib.Path(db_file_env)
    DATABASE_URL = f"sqlite:///{_db_file}"
else:
    _db_file = pathlib.Path(__file__).parent / "etl.db"
    DATABASE_URL = f"sqlite:///{_db_file}"

# ── 🚨 FORCE OVERWRITE LOGIC (Bypassing Railway UI & GitHub) ──────────────────
if DATABASE_URL.startswith("sqlite") and _db_file:
    print("🤖 AUTO-SYNC: Starting hard copy of seed database...")
    
    # Railway jab build karta hai toh poora repository in locations par hota hai
    possible_seed_paths = [
        pathlib.Path(__file__).parent / "seed_etl.db",                     # app/seed_etl.db
        pathlib.Path(__file__).parent.parent / "seed_etl.db",              # root/seed_etl.db
        pathlib.Path.cwd() / "seed_etl.db",                                # current dir/seed_etl.db
        pathlib.Path.cwd() / "app" / "seed_etl.db"
    ]
    
    actual_seed = None
    for path in possible_seed_paths:
        if path.exists():
            actual_seed = path
            break

    if actual_seed:
        # Hum bina check kiye purani khali file ko HAR BAAR overwrite karenge
        # Taaki tumhara real data 100% volume mein chala jaye
        _db_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(actual_seed, _db_file)
        print(f"🎯 SUCCESS: Forced copied real data from {actual_seed} to permanent volume {_db_file}")
    else:
        print("❌ ERROR: seed_etl.db could not be found anywhere in the repository build!")

# ── Engine ────────────────────────────────────────────────────────────────────
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