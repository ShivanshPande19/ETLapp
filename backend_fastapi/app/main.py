# app/main.py

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .core.config import settings
from .api.routes import auth, dashboard, sales, courts
from .api.routes import housekeeping

# Importing the models registers them with SQLAlchemy's Base registry
# so Base.metadata.create_all() below knows about every table.
from .models import housekeeping as _hk_models  # noqa


# ─── Startup / Shutdown ───────────────────────────────────────────────────────
# lifespan replaces the old @app.on_event("startup") pattern.
# create_all() is idempotent — it only creates tables that don't exist yet,
# so it's safe to run every boot.

@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── Startup ──────────────────────────────────────────────────────────────
    from .database import Base, engine          # noqa
    Base.metadata.create_all(bind=engine)
    print(f"[DB] All tables verified / created  ✓")
    yield
    # ── Shutdown ─────────────────────────────────────────────────────────────
    # (add connection-pool disposal here if you ever switch to async SQLAlchemy)


# ─── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    debug=settings.DEBUG,
    lifespan=lifespan,
)


# ─── Middleware ───────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Routes ───────────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {"status": "ok"}


app.include_router(auth.router,         prefix="/auth",         tags=["Auth"])
app.include_router(dashboard.router,    prefix="/dashboard",    tags=["Dashboard"])
app.include_router(sales.router,        prefix="/sales",        tags=["Sales"])
app.include_router(courts.router,       prefix="/courts",       tags=["Courts"])
app.include_router(housekeeping.router, prefix="/housekeeping", tags=["Housekeeping"])
