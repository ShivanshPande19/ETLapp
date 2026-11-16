#!/usr/bin/env python
"""Retire The Chatpata Affair BU and onboard The Chatpata Affair (Sec-1).

    DRY RUN (default):  python scripts/retire_bu_and_add_sec1.py
    APPLY:              python scripts/retire_bu_and_add_sec1.py --apply

Needs DATABASE_URL (or PROD_DB_URL) pointing at the Postgres you want to change.

WHAT IT DOES
  1. Adds the `closed_on` column if it is missing (same DDL the app runs at
     boot, so running this before or after the deploy is equivalent).
  2. Marks BU closed on its last trading day and RETIRES its `rest_id`.
  3. Creates the "Sec-1 Noida" zone.
  4. Creates "The Chatpata Affair (Sec-1)" in it, owner left blank.

WHY BU's rest_id HAS TO CHANGE
  `outlets.rest_id` carries a UNIQUE constraint, which does not care about
  is_active or closed_on. BU holds '1' and the new outlet needs '1' — Royal POS
  numbers restaurant_id per BRAND, so both are legitimately "1", told apart by
  the brand_id in pp_app_key. Marking BU closed does NOT free the value; only
  changing or deleting it does, and deleting the row would take its sales
  history with it.

  Changing it is safe: `rest_id` is only ever used as the POS API lookup key.
  Sales history is keyed on `outlet_id`, so nothing is re-pointed, and a closed
  outlet is skipped by the sync anyway, so the value is never read again.

  The original id stays legible in the retired value, and the brand_id in
  pp_app_key is left untouched, so this is reversible by hand if BU reopens.

IDEMPOTENT: re-running changes nothing. Everything is one transaction.
"""
import argparse
import datetime as dt
import os
import sys
import uuid

from sqlalchemy import create_engine, text

# ─── What we are changing ────────────────────────────────────────────────────
BU_OUTLET_ID = 18
BU_LAST_TRADING_DAY = dt.date(2026, 10, 3)   # last daily_sale_cache row
BU_RETIRED_REST_ID = "1-retired-2026-10-03"  # frees '1' for the new outlet

NEW_COURT_NAME = "Sec-1 Noida"
# Matches Central 50 and Bennett University, both 5: activity before 5am still
# belongs to the day the shift started, so a 1am close-out does not land on the
# next business day. Change this if Sec-1 keeps different hours.
NEW_COURT_CUTOFF_HOUR = 5
ETL_MANAGER_ID = 1                            # manager@etl.com, as the others

NEW_OUTLET_NAME = "The Chatpata Affair (Sec-1)"
NEW_REST_ID = "1"            # Royal POS restaurant_id
NEW_BRAND_ID = "thech722"    # Royal POS brand_id -> pp_app_key
NEW_POS_SOURCE = "royal_pos"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="actually write; without it this only prints the plan")
    args = ap.parse_args()

    url = os.environ.get("PROD_DB_URL") or os.environ.get("DATABASE_URL")
    if not url:
        print("ERROR: set PROD_DB_URL (or DATABASE_URL) first.")
        return 2
    if url.startswith("sqlite"):
        print(f"ERROR: refusing to run against SQLite ({url}). Point at Postgres.")
        return 2
    engine = create_engine(url.replace("postgresql://", "postgresql+psycopg2://"))

    with engine.begin() as c:
        # ── 0. the column ────────────────────────────────────────────────────
        has_col = c.execute(text("""
            select 1 from information_schema.columns
             where table_name='outlets' and column_name='closed_on'
        """)).scalar()
        if has_col:
            print("[0/4] closed_on column: already present")
        else:
            print("[0/4] closed_on column: MISSING -> will add (DATE, nullable)")
            if args.apply:
                c.execute(text("ALTER TABLE outlets ADD COLUMN closed_on DATE"))

        # ── 1. BU ────────────────────────────────────────────────────────────
        bu = c.execute(text("""
            select id, vendor_name, rest_id, pp_app_key, is_active
              from outlets where id=:i
        """), {"i": BU_OUTLET_ID}).fetchone()
        if not bu:
            print(f"ABORT: outlet {BU_OUTLET_ID} not found. Nothing written.")
            return 1
        if "chatpata" not in (bu[1] or "").lower():
            print(f"ABORT: outlet {BU_OUTLET_ID} is '{bu[1]}', not a Chatpata "
                  "outlet. Refusing to touch the wrong row.")
            return 1

        days, first, last, total = c.execute(text("""
            select count(*), min(sale_date), max(sale_date), coalesce(sum(total_sales),0)
              from daily_sale_cache where outlet_id=:i
        """), {"i": BU_OUTLET_ID}).fetchone()
        print(f"[1/4] BU '{bu[1]}': rest_id='{bu[2]}' brand='{bu[3]}' "
              f"is_active={bu[4]}")
        print(f"      history to PRESERVE: {days} days, {first} -> {last}, "
              f"Rs {float(total):,.0f}")
        print(f"      -> closed_on = {BU_LAST_TRADING_DAY}")
        print(f"      -> rest_id   = '{BU_RETIRED_REST_ID}' (frees '{NEW_REST_ID}')")
        print("      -> is_active stays 1, so every history path keeps working")
        if args.apply:
            c.execute(text("""
                update outlets set closed_on=:d, rest_id=:r where id=:i
            """), {"d": BU_LAST_TRADING_DAY, "r": BU_RETIRED_REST_ID,
                   "i": BU_OUTLET_ID})

        # ── 2. the zone ──────────────────────────────────────────────────────
        court_id = c.execute(text(
            "select id from courts where lower(name)=lower(:n)"
        ), {"n": NEW_COURT_NAME}).scalar()
        if court_id:
            print(f"[2/4] zone '{NEW_COURT_NAME}': exists (id={court_id})")
        else:
            print(f"[2/4] zone '{NEW_COURT_NAME}': will create "
                  f"(day_cutoff_hour={NEW_COURT_CUTOFF_HOUR}, no geofence yet)")
            if args.apply:
                court_id = c.execute(text("""
                    INSERT INTO courts (court_uid, name, manager_id, is_active,
                                        created_at, geofence_radius, day_cutoff_hour)
                    VALUES (:u, :n, :m, 1, now(), 150, :cut) RETURNING id
                """), {"u": uuid.uuid4().hex[:12].upper(), "n": NEW_COURT_NAME,
                       "m": ETL_MANAGER_ID, "cut": NEW_COURT_CUTOFF_HOUR}).scalar()
                print(f"      created id={court_id}")

        # ── 3. the outlet ────────────────────────────────────────────────────
        clash = c.execute(text(
            "select id, vendor_name from outlets where rest_id=:r"
        ), {"r": NEW_REST_ID}).fetchone()
        existing = c.execute(text("""
            select id from outlets
             where rest_id=:r and pos_source=:p and coalesce(pp_app_key,'')=:k
        """), {"r": NEW_REST_ID, "p": NEW_POS_SOURCE, "k": NEW_BRAND_ID}).fetchone()

        if existing:
            print(f"[3/4] outlet '{NEW_OUTLET_NAME}': exists (id={existing[0]})")
        elif clash and args.apply:
            print(f"ABORT: rest_id '{NEW_REST_ID}' still held by outlet "
                  f"{clash[0]} ('{clash[1]}'). Nothing written.")
            return 1
        else:
            print(f"[3/4] outlet '{NEW_OUTLET_NAME}': will create "
                  f"(rest_id='{NEW_REST_ID}', brand='{NEW_BRAND_ID}', "
                  f"pos={NEW_POS_SOURCE}, owner BLANK)")
            if args.apply:
                oid = c.execute(text("""
                    INSERT INTO outlets (court_id, vendor_name, rest_id, is_active,
                                         created_at, pp_app_key, pos_source)
                    VALUES (:c, :v, :r, 1, now(), :k, :p) RETURNING id
                """), {"c": court_id, "v": NEW_OUTLET_NAME, "r": NEW_REST_ID,
                       "k": NEW_BRAND_ID, "p": NEW_POS_SOURCE}).scalar()
                print(f"      created id={oid}")

        if not args.apply:
            print("\n[4/4] DRY RUN — nothing was written. "
                  "Re-run with --apply to perform it.")
            return 0

    # ── 4. verify, on a fresh connection ────────────────────────────────────
    with engine.connect() as c:
        print("\n[4/4] verification")
        r = c.execute(text("""
            select id, vendor_name, rest_id, pp_app_key, is_active, closed_on
              from outlets where id=:i
        """), {"i": BU_OUTLET_ID}).fetchone()
        print("  BU now:", r)
        d, f, l, t = c.execute(text("""
            select count(*), min(sale_date), max(sale_date), coalesce(sum(total_sales),0)
              from daily_sale_cache where outlet_id=:i
        """), {"i": BU_OUTLET_ID}).fetchone()
        print(f"  BU history INTACT: {d} days, {f} -> {l}, Rs {float(t):,.0f}")
        print(f"\n  '{NEW_COURT_NAME}':")
        for row in c.execute(text("""
            select c.id, c.name, c.day_cutoff_hour, o.id, o.vendor_name,
                   o.rest_id, o.pp_app_key, o.pos_source
              from courts c left join outlets o on o.court_id=c.id
             where lower(c.name)=lower(:n)
        """), {"n": NEW_COURT_NAME}):
            print("   ", row)
        print("\n  all royal_pos outlets:")
        for row in c.execute(text("""
            select o.id, c.name, o.vendor_name, o.rest_id, o.pp_app_key, o.closed_on
              from outlets o join courts c on c.id=o.court_id
             where o.pos_source='royal_pos' order by o.id
        """)):
            print("   ", row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
