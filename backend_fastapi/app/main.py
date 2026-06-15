# app/main.py

import asyncio
import os
import shutil
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, UploadFile, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from sqlalchemy import text
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from .core.config import settings
from .database import get_db

from .api.routes import auth, dashboard, sales, courts
from .api.routes import housekeeping
from .api.routes import housekeeping as _hk_routes
from .api.routes import feedback
from .api.routes import maintenance
from .api.routes import staff
from .api.routes import events
from .api.routes import music
from .api.routes import roster
from .api.routes import attendance

from .models import sale as _sale_models
from .models import housekeeping as _hk_models
from .models import feedback as _complaint_models
from .models import maintenance as _maintenance_models
from .models import manager as _manager_models
from .models import staff as _staff_models
from .models import attendance as _attendance_models

from .services.scheduler_service import start_scheduler, stop_scheduler


@asynccontextmanager
async def lifespan(app: FastAPI):
    from .database import Base, engine

    Base.metadata.create_all(bind=engine)
    print("[DB] All tables verified / created ✓")

    _hk_routes._main_loop = asyncio.get_event_loop()
    print("[SSE] Event loop captured ✓")

    start_scheduler()
    print("[AUTO SYNC] scheduler boot hook executed ✓")

    yield

    stop_scheduler()
    print("[AUTO SYNC] scheduler stopped")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    debug=settings.DEBUG,
    lifespan=lifespan,
)

# ✅ FIX #5/#6: register the SAME limiter the feedback router uses
app.state.limiter = feedback.limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ✅ CORS: '*' + allow_credentials=True is invalid/insecure.
# Use explicit origins from settings (add ALLOWED_ORIGINS in config).
_allowed = getattr(settings, "ALLOWED_ORIGINS", None) or ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed,
    allow_credentials=_allowed != ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")


@app.get("/health")
def health():
    return {"status": "ok"}


# ─── SAFE OUTLETS ROUTE (explicit columns only — no phone/PII leak) ──────────

@app.get("/outlets/")
def get_all_outlets_safe(db: Session = Depends(get_db)):
    """Fetch outlets with only the fields the client needs."""
    try:
        result = db.execute(
            text("SELECT id, vendor_name, court_id FROM outlets")
        ).mappings().all()
        return [dict(row) for row in result]
    except Exception as e1:
        try:
            result = db.execute(
                text("SELECT id, vendor_name, court_id FROM outlet")
            ).mappings().all()
            return [dict(row) for row in result]
        except Exception as e2:
            print(f"SQL Error fetching outlets: {e2}")
            return []


# ─── Routers ─────────────────────────────────────────────────────────────────

app.include_router(auth.router,         prefix="/auth",         tags=["Auth"])
app.include_router(dashboard.router,    prefix="/dashboard",    tags=["Dashboard"])
app.include_router(sales.router,        prefix="/sales",        tags=["Sales"])
app.include_router(courts.router,       prefix="/courts",       tags=["Courts"])
app.include_router(housekeeping.router, prefix="/housekeeping", tags=["Housekeeping"])
app.include_router(maintenance.router,                          tags=["Maintenance"])
app.include_router(staff.router,        prefix="/staff",        tags=["Staff"])
app.include_router(events.router,       prefix="/events",       tags=["Events"])
app.include_router(music.router,        prefix="/music",        tags=["Music"])
app.include_router(roster.router,       prefix="/roster",       tags=["Roster"])
app.include_router(attendance.router,   prefix="/attendance",   tags=["Attendance"])
app.include_router(feedback.router,     prefix="/feedback",     tags=["Feedback"])
