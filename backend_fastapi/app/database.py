import os
import pathlib
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# Sirf aur sirf live volume ya local path use karo, no copying!
db_file_env = os.getenv("DB_FILE_PATH", "/app/data/etl.db")
_db_file = pathlib.Path(db_file_env)

# Ensure folder exists
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