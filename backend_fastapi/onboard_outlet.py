"""One-off, idempotent outlet onboarding script.

Replicates the "approve application" flow (create Outlet + outlet-manager login
+ set-password email) but ALSO sets `pos_source` and the court's
`day_cutoff_hour` — the pieces needed to onboard a `get_sales_data`
(Petpooja flavour B) outlet like Coffee Vault.

Nothing sensitive is hard-coded: all creds and owner details come from
environment variables, so this file is safe to commit. Safe to re-run (guarded
on rest_id / owner email / existing application).

RUN (from backend_fastapi/, with prod DATABASE_URL already in the environment):

    OUTLET_REST_ID=r6h4cd0k2sfi \
    OUTLET_NAME="Coffee Vault" \
    OUTLET_COURT_NAME="Central 50" \
    OUTLET_POS_SOURCE=petpooja_salesdata \
    COURT_CUTOFF_HOUR=5 \
    OUTLET_PP_APP_KEY=xxx \
    OUTLET_PP_APP_SECRET=xxx \
    OUTLET_PP_ACCESS_TOKEN=xxx \
    OWNER_NAME="CV Owner" \
    OWNER_EMAIL="owner@example.com" \
    OWNER_PHONE="9999999999" \
    SYNC_DAYS=3 \
    python onboard_outlet.py

Notes:
- COURT_CUTOFF_HOUR is set on the COURT, which is shared with the attendance
  system. Set SET_CUTOFF=0 to skip changing it.
- SYNC_DAYS>0 runs a live sync for the last N days and prints the resulting
  DailySaleCache — this is the end-to-end validation of the adapter against the
  real POS response. Set SYNC_DAYS=0 to skip (the scheduler will sync later).
"""

import asyncio
import os
import secrets
import sys
from datetime import date, datetime, timedelta

# Import app modules (run from backend_fastapi/ so `app` is importable).
from app.database import SessionLocal, ensure_outlet_columns
from app.models.sale import Court, Outlet, DailySaleCache
from app.models.manager import Manager
from app.models.onboarding import OutletApplication
from app.core.security import create_token, hash_password
from app.core.config import settings
from app.services.email_service import send_email
from app.services.petpooja_service import sync_outlet_for_dates
from app.api.routes.onboarding import _set_password_email_html, _SET_PW_EXPIRY_MIN


def _env(name: str, default: str = "") -> str:
    return (os.environ.get(name, default) or "").strip()


def _require(name: str) -> str:
    v = _env(name)
    if not v:
        print(f"[ERROR] Missing required env var: {name}")
        sys.exit(1)
    return v


async def main() -> None:
    rest_id = _require("OUTLET_REST_ID")
    outlet_name = _require("OUTLET_NAME")
    court_name = _env("OUTLET_COURT_NAME", "Central 50")
    pos_source = _env("OUTLET_POS_SOURCE", "petpooja_generic")
    owner_name = _require("OWNER_NAME")
    owner_email = _require("OWNER_EMAIL").lower()
    owner_phone = _env("OWNER_PHONE")

    pp_app_key = _env("OUTLET_PP_APP_KEY") or None
    pp_app_secret = _env("OUTLET_PP_APP_SECRET") or None
    pp_access_token = _env("OUTLET_PP_ACCESS_TOKEN") or None
    pp_cookie = _env("OUTLET_PP_COOKIE") or None

    set_cutoff = _env("SET_CUTOFF", "1") == "1"
    cutoff_hour = int(_env("COURT_CUTOFF_HOUR", "5") or "5")
    sync_days = int(_env("SYNC_DAYS", "3") or "3")

    # pos_source column may not exist yet if the app hasn't booted post-deploy.
    ensure_outlet_columns()

    db = SessionLocal()
    try:
        # ── 1. Court ────────────────────────────────────────────────────────
        court = (
            db.query(Court)
            .filter(Court.name == court_name, Court.is_active == 1)
            .first()
        )
        if not court:
            print(f"[ERROR] Active court named {court_name!r} not found. "
                  f"Create it first (POST /courts/) or set OUTLET_COURT_NAME.")
            sys.exit(1)
        print(f"[COURT] {court.name} (id={court.id}) cutoff={court.day_cutoff_hour}")

        if set_cutoff and court.day_cutoff_hour != cutoff_hour:
            old = court.day_cutoff_hour
            court.day_cutoff_hour = cutoff_hour
            db.commit()
            print(f"[COURT] day_cutoff_hour {old} -> {cutoff_hour} "
                  f"(NOTE: this also affects ATTENDANCE grouping for this court)")

        # ── 2. Outlet (guard on rest_id) ────────────────────────────────────
        outlet = db.query(Outlet).filter(Outlet.rest_id == rest_id).first()
        if outlet:
            print(f"[OUTLET] exists id={outlet.id} — updating creds/pos_source")
            outlet.vendor_name = outlet_name
            outlet.court_id = court.id
            outlet.is_active = 1
            if pp_app_key:
                outlet.pp_app_key = pp_app_key
            if pp_app_secret:
                outlet.pp_app_secret = pp_app_secret
            if pp_access_token:
                outlet.pp_access_token = pp_access_token
            if pp_cookie:
                outlet.pp_cookie = pp_cookie
            outlet.pos_source = pos_source
        else:
            outlet = Outlet(
                court_id=court.id,
                vendor_name=outlet_name,
                rest_id=rest_id,
                is_active=1,
                pp_app_key=pp_app_key,
                pp_app_secret=pp_app_secret,
                pp_access_token=pp_access_token,
                pp_cookie=pp_cookie,
                pos_source=pos_source,
            )
            db.add(outlet)
            print(f"[OUTLET] creating {outlet_name!r} rest_id={rest_id} "
                  f"pos_source={pos_source}")
        db.commit()
        db.refresh(outlet)
        print(f"[OUTLET] id={outlet.id} pos_source={outlet.pos_source} "
              f"has_creds={bool(outlet.pp_app_key)}")

        # ── 3. Outlet-manager login (guard on email) ────────────────────────
        manager = db.query(Manager).filter(Manager.email == owner_email).first()
        manager_created = False
        if manager:
            print(f"[MANAGER] exists id={manager.id} email={manager.email} "
                  f"outlet_id={manager.outlet_id} — leaving password as-is")
            if manager.outlet_id != outlet.id:
                print(f"[MANAGER] WARNING: linked to outlet {manager.outlet_id}, "
                      f"not {outlet.id}. Not changing.")
        else:
            manager = Manager(
                name=owner_name,
                email=owner_email,
                hashed_password=hash_password(secrets.token_urlsafe(24)),
                role="outlet_manager",
                outlet_id=outlet.id,
                is_active=True,
            )
            db.add(manager)
            db.commit()
            db.refresh(manager)
            manager_created = True
            print(f"[MANAGER] created id={manager.id} email={manager.email}")

        # ── 4. Audit application row (so ETL app shows owner info) ───────────
        existing_app = (
            db.query(OutletApplication)
            .filter(OutletApplication.created_outlet_id == outlet.id)
            .first()
        )
        if not existing_app:
            approw = OutletApplication(
                court_id=court.id,
                outlet_name=outlet_name,
                owner_name=owner_name,
                owner_phone=owner_phone,
                owner_email=owner_email,
                status="approved",
                created_outlet_id=outlet.id,
                reviewed_at=datetime.utcnow(),
            )
            db.add(approw)
            db.commit()
            print(f"[APPLICATION] created approved audit row id={approw.id}")
        else:
            print(f"[APPLICATION] exists id={existing_app.id} — skipping")

        # ── 5. Set-password link + email (only for a freshly created login) ──
        token = create_token(
            {"sub": manager.email, "purpose": "set_password", "mid": manager.id},
            _SET_PW_EXPIRY_MIN,
        )
        base = (settings.PUBLIC_BASE_URL or "").rstrip("/")
        link = f"{base}/auth/set-password?token={token}"
        if manager_created:
            sent = await send_email(
                to=manager.email,
                subject="Welcome to ETL — set your password",
                html=_set_password_email_html(owner_name, outlet_name, link),
            )
            print(f"[EMAIL] set-password email sent={sent}")
        print(f"[LINK] set-password (valid 7 days):\n  {link}")

        # ── 6. Live sync validation ─────────────────────────────────────────
        if sync_days > 0:
            today = date.today()
            dates = [today - timedelta(days=i) for i in range(sync_days)]
            print(f"[SYNC] running live sync for {len(dates)} days via "
                  f"{outlet.pos_source} adapter...")
            affected = await sync_outlet_for_dates(db, outlet, dates)
            print(f"[SYNC] affected business dates: {sorted(str(d) for d in affected)}")
            rows = (
                db.query(DailySaleCache)
                .filter(DailySaleCache.outlet_id == outlet.id)
                .order_by(DailySaleCache.sale_date.desc())
                .limit(sync_days + 2)
                .all()
            )
            print("[SYNC] DailySaleCache (recent):")
            for r in rows:
                print(f"   {r.sale_date}  sales={r.total_sales}  bills={r.bill_count}"
                      f"  avg={r.avg_bill}")
            if not rows:
                print("[SYNC] No cache rows — check creds / rest_id / date range / "
                      "that the adapter parsed the response (wrapper key 'Records').")

        print("\n[DONE] Onboarding complete for", outlet_name)
    finally:
        db.close()


if __name__ == "__main__":
    asyncio.run(main())
