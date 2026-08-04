# Multi-Source POS Sales Ingestion — Progress Log

> Purpose: pluggable architecture so ETL can ingest sales from **multiple POS
> systems** (Petpooja `generic_get_orders`, Petpooja `get_sales_data`, and later
> Royal POS) without special-casing the whole codebase per source.
> **Hard constraint:** the Flutter UI and the `DailySaleCache` contract must stay
> **exactly identical** — this work only changes *how* orders are fetched and
> stored, never what the app reads.

Branch: `feat/multisource-sales-adapters`

---

## Why (background)

- **The Momo Box (`yk4ou3en`)** works on ETL's integration account
  (`app_key uvw0th4nksi97o1bgqp35zjxr6e2may8`) via the `generic_get_orders`
  endpoint (JSON body + `Cookie: PETPOOJA_API=...`). This is the flow the app
  already uses today.
- **Coffee Vault (`r6h4cd0k2sfi`)** is mapped under a *different* Petpooja
  integration account and only responds on the `get_sales_data` endpoint
  (query params, no cookie). Cross-combinations fail (`code 103` / `GN_105`).
  So we cannot force it onto the existing flow without Petpooja re-mapping it
  (which they'd charge for) — hence a **second adapter**.
- **Royal POS outlets** are coming and use a completely different API — a third
  adapter, stubbed now.

### Two Petpooja "flavours"

| | Flavour A (generic) | Flavour B (sales_data) |
|---|---|---|
| endpoint | `/V1/thirdparty/generic_get_orders/` | `/V1/orders/get_sales_data/` |
| auth | JSON body + `Cookie: PETPOOJA_API` | query params, no cookie |
| business-date | **already correct** (`order_date` per bill groups post-midnight bills to the previous operational day) | **calendar date only** → app must apply a cutoff |
| id | global `orderID` (int) | per-outlet `Receipt number` (sequential → collides across outlets) |
| amount | `total` | `Net sale` |
| filter | all orders counted | keep `Transaction status=SALE` **and** `order_status=Success` |

Business-date rule for flavour B: a bill's calendar `Receipt Date` is shifted to
the **previous day** when its `Transaction Time` hour is `< Court.day_cutoff_hour`
(the same overnight cutoff the attendance system already uses). That fixes the
"Coffee Vault raat ke bills galat din" problem.

---

## Design decisions

1. **New table `sales_orders`** (surrogate `id` PK) instead of PK surgery on the
   live `petpooja_orders` table.
   Columns: `id, outlet_id, source, external_ref (VARCHAR), business_date,
   created_on, total_amount, status`. **UNIQUE(outlet_id, source, external_ref)**.
   The composite key is what lets flavour B's per-outlet receipt numbers coexist
   without collision. `petpooja_orders` is **kept as a frozen backup** (drop
   manually later once confident) — expand → migrate → contract.

2. **`Outlet.pos_source`** VARCHAR, default `'petpooja_generic'`. Selects the
   adapter. Existing outlets automatically get the generic flow → zero behaviour
   change for Momo Box.

3. **Adapter pattern** in `app/services/sales_sources/`:
   - `base.py` — `NormalizedOrder` dataclass + `SalesSourceAdapter` ABC +
     `register`/`get_adapter` registry.
   - Adapters are **pure**: fetch + normalize only, **no DB writes**, so they're
     unit-testable against captured JSON.
   - `sync_outlet_for_dates` picks the adapter by `outlet.pos_source`, gets
     `list[NormalizedOrder]`, upserts into `sales_orders`, then recomputes
     `DailySaleCache` with the **unchanged** logic/shape.

4. **`DailySaleCache` unchanged** = the UI-safety guarantee. The UI reads only
   `DailySaleCache`, never the order tables, so as long as the cache recompute
   produces the same numbers, the app is byte-for-byte identical.

5. **One-time idempotent backfill** `petpooja_orders → sales_orders`
   (`source='petpooja_generic'`, `order_id → external_ref`), using
   `ON CONFLICT DO NOTHING` / `INSERT OR IGNORE` so it's safe to run on every
   boot and order-independent w.r.t. the first new sync.

---

## Status

### Done
- [x] Branch + this log
- [x] Read exact current state of every file being touched

### Done in this PR (Phase 1) ✅
- [x] `sales_sources/base.py` (ABC + NormalizedOrder + registry)
- [x] `SalesOrder` model + `Outlet.pos_source`
- [x] `pos_source` in `ensure_outlet_columns()` + NULL backfill + `backfill_sales_orders()`
      wired into `main.py` lifespan (idempotent, dialect-aware)
- [x] `petpooja_generic.py` adapter (existing logic moved, behaviour identical)
- [x] `petpooja_salesdata.py` adapter (flavour B — Coffee Vault; needs live wrapper-key validation)
- [x] `royal_pos.py` stub (raises NotImplementedError; sync skips gracefully)
- [x] `sync_outlet_for_dates` made source-agnostic (picks adapter, upserts `sales_orders`,
      recomputes `DailySaleCache` with UNCHANGED shape)
- [x] Flutter: revenue/month providers rethrow on error (was silently `0.0`); home cards
      show "—" on error instead of a misleading ₹0; Dio timeouts 10s→30s in both dio files
- [x] Verified: 25/25 checks (adapters vs captured JSON, cutoff, sync end-to-end, cache
      totals, backfill idempotency, composite-key collision, royal skip) + full app boots
      via TestClient (lifespan create_all + backfill + ensure_* all clean)

### Remaining (later phases — blocked / not in this PR)
- **Phase 2 — Coffee Vault go-live:** NOT blocked on Petpooja (no remap needed).
  The adapter uses the outlet's own per-outlet creds — the exact `get_sales_data`
  creds already proven to return this outlet's sales during investigation
  (`srd2neaq…` set, kept in `/projects/pp_probe2.py`, NOT in the repo). Go-live is
  pure data/config:
    1. store those creds on the Coffee Vault outlet row
       (`pp_app_key` / `pp_app_secret` / `pp_access_token`);
    2. set `pos_source = 'petpooja_salesdata'`;
    3. set the court's `day_cutoff_hour` (~5-6) for correct night-bill attribution.
  Response wrapper key is **confirmed = `Records`** (validated via `pp_probe2.py`
  which parsed live data). Field names confirmed: `Net sale`, `Receipt number`,
  `Receipt Date`, `Transaction Time`, `Transaction status`, `order_status`.

  **Onboarding tooling (added):**
  - The onboarding API (`ApproveRequest` + `POST /applications/{id}/approve`) now
    accepts an optional `pos_source` (default `petpooja_generic`), so future
    salesdata/royal outlets onboard through the normal flow.
  - `onboard_outlet.py` — idempotent, env-driven script that replicates the
    approve flow (Outlet + outlet-manager login + set-password email) AND sets
    `pos_source` + the court's `day_cutoff_hour`, then runs a live sync to verify.
    No secrets in the file (all via env vars). Run once on Railway to onboard
    Coffee Vault. Coffee Vault decisions: same court "Central 50",
    `day_cutoff_hour = 5`, owner login = yes.
- **Phase 3 — Royal POS:** implement `royal_pos.py` once their API docs/creds
  are available.

### Parked (unrelated, remembered so we don't lose them)
- Set Central 50 `google_review_url` (needs Google Business Place ID + manager token).
- Jio IPv6 issue → custom domain + Cloudflare.
- Prod courts id=2 "test court" & id=3 "test court 2" still active — deactivate.
- **Security (rotate creds):** Petpooja creds for both accounts were shared in
  chat during investigation — rotate them.

---

## How to resume
1. `git checkout feat/multisource-sales-adapters`
2. Re-read this file top-to-bottom.
3. Check the "In progress" checklist above for the next unchecked item.
