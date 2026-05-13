# app/main.py

import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .core.config import settings
from .api.routes import auth, dashboard, sales, courts
from .api.routes import housekeeping
from .api.routes import housekeeping as _hk_routes  # ✅ loop capture ke liye
from .api.routes import complaints
from .api.routes import maintenance
from .api.routes import staff
from .api.routes import events                       # ✅ SSE events router

from .models import housekeeping    as _hk_models
from .models import complaint       as _complaint_models
from .models import maintenance     as _maintenance_models
from .models import manager         as _manager_models
from .models import staff           as _staff_models


@asynccontextmanager
async def lifespan(app: FastAPI):
    from .database import Base, engine
    Base.metadata.create_all(bind=engine)
    print("[DB] All tables verified / created  ✓")

    # ✅ Main event loop capture — SSE ke liye
    _hk_routes._main_loop = asyncio.get_event_loop()
    print("[SSE] Event loop captured ✓")

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
app.include_router(complaints.router,                           tags=["Complaints"])
app.include_router(maintenance.router,                          tags=["Maintenance"])
app.include_router(staff.router,        prefix="/staff",        tags=["Staff"])
app.include_router(events.router,       prefix="/events",       tags=["Events"])  # ✅