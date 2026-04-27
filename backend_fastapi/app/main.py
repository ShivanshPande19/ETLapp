# app/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .core.config import settings
from .api.routes import auth, dashboard, sales, courts
from .api.routes import housekeeping
from .api.routes import complaints                        # ← NEW

from .models import housekeeping as _hk_models            # noqa — registers HK models
from .models import complaint    as _complaint_models     # noqa — registers Complaint model   ← NEW


@asynccontextmanager
async def lifespan(app: FastAPI):
    from .database import Base, engine
    Base.metadata.create_all(bind=engine)
    print("[DB] All tables verified / created  ✓")
    yield


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    debug=settings.DEBUG,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}


app.include_router(auth.router,         prefix="/auth",         tags=["Auth"])
app.include_router(dashboard.router,    prefix="/dashboard",    tags=["Dashboard"])
app.include_router(sales.router,        prefix="/sales",        tags=["Sales"])
app.include_router(courts.router,       prefix="/courts",       tags=["Courts"])
app.include_router(housekeeping.router, prefix="/housekeeping", tags=["Housekeeping"])
app.include_router(complaints.router,   tags=["Complaints"])    # ← NEW (no prefix — /c/{id} must stay at root)
