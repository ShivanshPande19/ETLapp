"""Shared pytest fixtures for the ETLapp backend test suite.

These tests run against an in-memory SQLite DB and a *bare* FastAPI app that
mounts only the routers under test — the production lifespan (APScheduler,
FCM, on-boot Petpooja sync, backfills) is deliberately NOT started, so tests
are fast, isolated and have no external side-effects.

Auth is simulated by overriding `get_current_user`, so no real JWT/login is
needed; each test picks the acting identity via the `client_factory`.
"""
import os
import pathlib
import sys

# Make `import app...` work when pytest is run from anywhere.
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

# Config reads these at import time; set harmless test values up front.
os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./_pytest_ignore.db")

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db

# Import every model module so create_all() builds the full schema.
from app.models import (  # noqa: F401
    manager,
    staff,
    sale,
    attendance,
    feedback,
    outlet_membership,
    notice,
    device_token,
    maintenance,
    housekeeping,
    onboarding,
    vendor,
)
from app.api.deps import CurrentUser, get_current_user

# One shared in-memory engine for the whole session; each test gets a fresh
# schema (create_all in the fixture, drop_all after).
_engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
_Session = sessionmaker(bind=_engine, autoflush=False, autocommit=False)


@pytest.fixture()
def db():
    Base.metadata.create_all(bind=_engine)
    session = _Session()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=_engine)


@pytest.fixture()
def client_factory(db):
    """Return `make(user) -> TestClient`.

    The returned client has `get_db` bound to the test session and
    `get_current_user` bound to the given `CurrentUser`.
    """
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.routes import feedback as feedback_routes
    from app.api.routes import outlets as outlet_routes
    from app.api.routes import notices as notice_routes

    app = FastAPI()
    app.include_router(feedback_routes.router, prefix="/feedback")
    app.include_router(outlet_routes.router, prefix="/outlets")
    app.include_router(notice_routes.router, prefix="/notices")

    def _override_db():
        yield db

    _holder = {"user": None}

    def _override_user():
        return _holder["user"]

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = _override_user

    def _make(user: CurrentUser) -> TestClient:
        _holder["user"] = user
        return TestClient(app)

    return _make


# ─── Seeding helpers ─────────────────────────────────────────────────────────

def make_user(role, uid=1, court_id=None, outlet_id=None, outlet_ids=None,
              user_type="manager", email="u@test.com", name="User"):
    return CurrentUser(
        id=uid, name=name, email=email, role=role,
        court_id=court_id, outlet_id=outlet_id, outlet_ids=outlet_ids,
        user_type=user_type,
    )


def seed_court(db, name="Court A"):
    from app.models.sale import Court
    c = Court(name=name, is_active=1)
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


def seed_outlet(db, court_id, vendor_name="Vendor", rest_id=None):
    from app.models.sale import Outlet
    o = Outlet(
        court_id=court_id,
        vendor_name=vendor_name,
        rest_id=rest_id or f"rest-{vendor_name}",
        is_active=1,
        pos_source="petpooja_generic",
    )
    db.add(o)
    db.commit()
    db.refresh(o)
    return o


def seed_manager(db, role="outlet_manager", email=None, outlet_id=None):
    from app.models.manager import Manager
    m = Manager(
        name="Mgr",
        email=email or f"mgr-{role}@test.com",
        hashed_password="x",
        role=role,
        outlet_id=outlet_id,
        is_active=True,
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


def seed_membership(db, manager_id, outlet_id, membership_role="owner"):
    from app.models.outlet_membership import OutletMembership
    mem = OutletMembership(
        manager_id=manager_id, outlet_id=outlet_id, membership_role=membership_role
    )
    db.add(mem)
    db.commit()
    db.refresh(mem)
    return mem


def seed_feedback(db, court_id, outlet_id=None, court_rating=None, outlet_rating=None):
    from app.models.feedback import Feedback
    f = Feedback(
        court_id=court_id,
        outlet_id=outlet_id,
        customer_name="Cust",
        customer_phone="9999999999",
        court_rating=court_rating,
        outlet_rating=outlet_rating,
        source="qr",
    )
    db.add(f)
    db.commit()
    db.refresh(f)
    return f



def seed_notice(db, audience="manager", type_="generic", title="Notice",
                body="body", court_id=None, outlet_id=None,
                recipient_staff_id=None, is_read=False, created_at=None):
    from app.models.notice import Notice
    n = Notice(
        audience=audience,
        type=type_,
        title=title,
        body=body,
        court_id=court_id,
        outlet_id=outlet_id,
        recipient_staff_id=recipient_staff_id,
        is_read=is_read,
    )
    db.add(n)
    db.commit()
    db.refresh(n)
    if created_at is not None:
        # override the server-default timestamp for date-filter tests
        n.created_at = created_at
        db.commit()
        db.refresh(n)
    return n
