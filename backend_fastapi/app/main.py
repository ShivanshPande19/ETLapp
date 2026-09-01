# app/main.py

import asyncio
import logging
import os
import shutil
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, UploadFile, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from sqlalchemy import text
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from .core.config import settings, INSECURE_DEFAULT_SECRET
from .database import get_db
from .api.deps import get_current_user, CurrentUser, require_etl_manager

from .api.routes import auth, dashboard, sales, courts
from .api.routes import housekeeping
from .api.routes import housekeeping as _hk_routes
from .api.routes import feedback
from .api.routes import maintenance
from .api.routes import staff
from .api.routes import events
from .api.routes import roster
from .api.routes import attendance
from .api.routes import onboarding
from .api.routes import notices
from .api.routes import devices
from .api.routes import legal
from .api.routes import outlets as outlets_routes
from .api.routes import managers as managers_routes

from .models import sale as _sale_models
from .models import housekeeping as _hk_models
from .models import feedback as _complaint_models
from .models import maintenance as _maintenance_models
from .models import manager as _manager_models
from .models import staff as _staff_models
from .models import attendance as _attendance_models
from .models import onboarding as _onboarding_models
from .models import notice as _notice_models
from .models import device_token as _device_token_models
from .models import outlet_membership as _outlet_membership_models

from .services import fcm_service
from .services.scheduler_service import start_scheduler, stop_scheduler


# ─── Logging ──────────────────────────────────────────────────────────────────
# Without a configured root handler, Python falls back to `logging.lastResort`,
# which only emits WARNING and above. Every logger.info() in the app was being
# silently dropped — including the "email sent" line in email_service.py and the
# "push delivered" line in fcm_service.py, i.e. exactly the lines you need to
# confirm a delivery actually happened.
#
# force=True because uvicorn installs its own handlers first; without it
# basicConfig() is a no-op under `uvicorn app.main:app`.
logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s:     %(name)s | %(message)s",
    force=True,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    from .database import Base, engine, ensure_attendance_columns, ensure_outlet_columns, ensure_staff_columns, ensure_hk_columns, ensure_court_columns, ensure_notice_columns, ensure_device_token_columns, ensure_feedback_columns, backfill_sales_orders, backfill_outlet_memberships

    Base.metadata.create_all(bind=engine)
    print("[DB] All tables verified / created ✓")

    # ✅ Add any newly-introduced columns to existing tables (check-out fields)
    ensure_attendance_columns()
    print("[DB] Attendance schema ensured ✓")

    # ✅ Add per-outlet Petpooja credential columns + pos_source if missing
    ensure_outlet_columns()
    print("[DB] Outlet schema ensured ✓")

    # ✅ Seed the multi-source sales_orders table from the legacy petpooja_orders
    # backup (idempotent). Runs after create_all built sales_orders.
    backfill_sales_orders()
    print("[DB] sales_orders backfill ensured ✓")

    # ✅ Add staff profile columns (phone, photo_url) if missing
    ensure_staff_columns()
    print("[DB] Staff schema ensured ✓")

    # ✅ Add court geofencing columns (latitude, longitude, geofence_radius,
    #    address) + the per-court google_review_url
    ensure_court_columns()
    print("[DB] Court schema ensured ✓")

    # ✅ Add the Google-review CTA tracking column to feedbacks if missing
    ensure_feedback_columns()
    print("[DB] Feedback schema ensured ✓")

    # ✅ Add notice outlet_id column if missing
    ensure_notice_columns()
    print("[DB] Notice schema ensured ✓")

    # ✅ Add housekeeping done_by_name columns if missing
    ensure_hk_columns()
    print("[DB] Housekeeping schema ensured ✓")

    # ✅ Add FCM device-token columns if the table predates them
    ensure_device_token_columns()
    print("[DB] Device token schema ensured ✓")

    # ✅ Multi-outlet ownership: seed outlet_memberships from the legacy
    #    Manager.outlet_id (idempotent). The table itself is created by
    #    create_all above; this just backfills one owner-membership per
    #    existing outlet_manager so nothing changes for current accounts.
    backfill_outlet_memberships()
    print("[DB] Outlet memberships backfill ensured ✓")

    _hk_routes._main_loop = asyncio.get_event_loop()
    events._main_loop = asyncio.get_event_loop()
    # Push is fired from sync route handlers running in worker threads, so it
    # needs the loop reference just like SSE does.
    fcm_service._main_loop = asyncio.get_event_loop()
    print("[SSE] Event loop captured ✓")

    if fcm_service.is_configured():
        print("[FCM] Push notifications enabled ✓")
    else:
        print("[FCM] Push disabled — FIREBASE_PROJECT_ID / FIREBASE_CREDENTIALS_JSON not set")

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
# Origins come from settings.ALLOWED_ORIGINS (comma-separated env var); empty
# => wildcard "*", which is safe for the native app (no Origin header, no
# cookies). allow_credentials is forced off whenever we're on wildcard.
_allowed = settings.allowed_origins_list
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed,
    allow_credentials=_allowed != ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.UPLOAD_DIR), name="uploads")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/health/config", include_in_schema=False)
def health_config(user: CurrentUser = Depends(require_etl_manager)):
    """Read-only production-readiness check (ETL-manager only).

    Returns ONLY booleans / non-sensitive values so it can be shared safely —
    never the actual SECRET_KEY, DATABASE_URL or PUBLIC_BASE_URL. Lets an admin
    confirm the Railway ops setup (secret, debug, Postgres, uploads volume,
    email) in one call instead of digging through the dashboard.
    """
    from .database import engine

    upload_dir = settings.UPLOAD_DIR

    # Is the upload dir actually writable? (best-effort probe)
    upload_writable = False
    try:
        os.makedirs(upload_dir, exist_ok=True)
        _probe = os.path.join(upload_dir, ".write_probe")
        with open(_probe, "w") as _f:
            _f.write("ok")
        os.remove(_probe)
        upload_writable = True
    except Exception:
        upload_writable = False

    # Does the upload dir live on the mounted Railway volume?
    volume_path = os.getenv("RAILWAY_VOLUME_MOUNT_PATH")
    on_volume = bool(volume_path) and os.path.abspath(upload_dir).startswith(
        os.path.abspath(volume_path)
    )

    return {
        "on_railway": bool(os.getenv("RAILWAY_ENVIRONMENT_NAME")),
        "debug": settings.DEBUG,
        # false == secure (a strong SECRET_KEY env is set)
        "secret_key_is_default": settings.SECRET_KEY == INSECURE_DEFAULT_SECRET,
        "db_dialect": engine.dialect.name,          # "postgresql" or "sqlite"
        "using_postgres": engine.dialect.name.startswith("postgre"),
        "upload_dir": upload_dir,
        "upload_dir_writable": upload_writable,
        "railway_volume_mount_path": volume_path,
        "uploads_on_railway_volume": on_volume,
        "public_base_url_set": bool(settings.PUBLIC_BASE_URL),
        "resend_email_configured": bool(settings.RESEND_API_KEY),
        "fcm_push_configured": fcm_service.is_configured(),
    }


# ─── PRINTED QR SHORT LINK ───────────────────────────────────────────────────
#
# The per-court feedback QRs produced by generate_qr.py encode `/c/{court_id}`
# — a deliberately short path, because fewer characters => a lower-density QR
# => a far more reliable scan from a printed standee in bad light.
#
# That path had NO route, so every printed QR resolved to a 404. This is the
# missing hop. Keep it dumb (no DB hit): /feedback/portal already validates the
# court and renders a proper 404 for an unknown/inactive one.
#
# Do NOT change this path or old printed QRs stop working — they are physically
# out in the world and cannot be reprinted cheaply.

@app.get("/c/{court_id}", include_in_schema=False)
def court_qr_shortlink(court_id: int):
    """Redirect a scanned court QR to the customer feedback portal."""
    return RedirectResponse(
        url=f"/feedback/portal?court_id={court_id}",
        status_code=status.HTTP_302_FOUND,
    )


# ─── SAFE OUTLETS ROUTE (explicit columns only — no phone/PII leak) ──────────

@app.get("/outlets/")
def get_all_outlets_safe(
    db: Session = Depends(get_db),
    # SECURITY (P0-2): outlet list must not be public. Any authenticated
    # employee may read it (managers/staff resolve outlet names from it);
    # anonymous access is now blocked.
    user: CurrentUser = Depends(get_current_user),
):
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
app.include_router(roster.router,       prefix="/roster",       tags=["Roster"])
app.include_router(attendance.router,   prefix="/attendance",   tags=["Attendance"])
app.include_router(onboarding.router,   prefix="/onboarding",   tags=["Onboarding"])
app.include_router(feedback.router,     prefix="/feedback",     tags=["Feedback"])
app.include_router(notices.router,      prefix="/notices",      tags=["Notices"])
app.include_router(devices.router,      prefix="/devices",      tags=["Devices"])
app.include_router(legal.router,                                tags=["Legal"])
# Multi-outlet ownership: switcher list + manage-access CRUD. Sub-paths only
# (/outlets/mine, /outlets/{id}/managers); the bare GET /outlets/ list stays
# defined inline above.
app.include_router(outlets_routes.router, prefix="/outlets",    tags=["Outlets"])
# ETL-manager account administration (create/list/deactivate other ETL managers).
app.include_router(managers_routes.router, prefix="/managers",  tags=["Managers"])
