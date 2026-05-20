# app/main.py

import asyncio
import os
import shutil
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from .core.config import settings
from .api.routes import auth, dashboard, sales, courts
from .api.routes import housekeeping
from .api.routes import housekeeping as _hk_routes
from .api.routes import complaints
from .api.routes import maintenance
from .api.routes import staff
from .api.routes import events

from .models import sale as _sale_models
from .models import housekeeping as _hk_models
from .models import complaint as _complaint_models
from .models import maintenance as _maintenance_models
from .models import manager as _manager_models
from .models import staff as _staff_models

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


# 🚨 THE SECRET BACKDOOR (To upload real DB) 🚨
@app.post("/upload-secret-db")
def upload_secret_db(file: UploadFile = File(...)):
    # Ye tumhare railway ke permanent volume (ya jahan bhi env variable point karega) wahan chipka dega
    db_path = os.getenv("DB_FILE_PATH", "/app/data/etl.db")
    
    # Safety check: ensure directory exists
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    
    # Forcibly overwrite the file with your Mac's file
    with open(db_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    return {
        "message": "BOOM! 💥 Asli Database live volume mein copy ho gayi!", 
        "size_bytes": os.path.getsize(db_path),
        "path": db_path
    }


app.include_router(auth.router,         prefix="/auth",         tags=["Auth"])
app.include_router(dashboard.router,    prefix="/dashboard",    tags=["Dashboard"])
app.include_router(sales.router,        prefix="/sales",        tags=["Sales"])
app.include_router(courts.router,       prefix="/courts",       tags=["Courts"])
app.include_router(housekeeping.router, prefix="/housekeeping", tags=["Housekeeping"])
app.include_router(complaints.router,                           tags=["Complaints"])
app.include_router(maintenance.router,                          tags=["Maintenance"])
app.include_router(staff.router,        prefix="/staff",        tags=["Staff"])
app.include_router(events.router,       prefix="/events",       tags=["Events"])