# Multi-Outlet Ownership — Design & Ops Guide

**What this enables:** one owner (one login/email) can run **many outlets across
different courts** — e.g. *Coffee Vault* in **Central 50** and **Bennett** under a
single account — and can grant **limited co-managers** access to a specific
outlet. Built as **Option A: a junction table** (`outlet_memberships`).

> **Golden rule kept throughout:** a **single-outlet owner sees ZERO change** —
> same login, same screens, no switcher. New UI appears only for a genuine
> multi-outlet owner.

---

## 1. Data model

New table **`outlet_memberships`** (`app/models/outlet_membership.py`):

| column | meaning |
|--------|---------|
| `manager_id` | FK → `managers.id` |
| `outlet_id`  | FK → `outlets.id` |
| `membership_role` | `owner` or `manager` |
| unique | `(manager_id, outlet_id)` |

- Many-to-many: one manager ↔ many outlets, one outlet ↔ many managers.
- The legacy `Manager.outlet_id` column is retained as the **primary/default**
  outlet (backward compatibility + the default switcher selection). **Memberships
  are the single source of truth** for access.
- **Backfill** (`database.py::backfill_outlet_memberships`, run every boot,
  idempotent): every existing `outlet_manager` becomes `owner` of their current
  `Manager.outlet_id`. So on deploy, current accounts behave exactly as before.

## 2. Role matrix

| Capability | ETL manager | Owner (membership `owner`) | Co-manager (membership `manager`) | Outlet staff |
|---|---|---|---|---|
| See all courts / company totals | ✅ | — | — | — |
| Access an outlet's sales/feedback/maintenance/staff/roster | any | their outlets | outlets they're linked to | their one outlet |
| Switch between multiple outlets (app switcher) | — | ✅ (if >1) | ✅ (if >1) | — |
| **Add / remove co-managers** | ✅ | ✅ (own outlets) | ❌ | ❌ |
| Raise maintenance / add staff | — | ✅ (per selected outlet) | ✅ (per selected outlet) | raise only |

## 3. Tenancy scoping (server-enforced, extends the P0 work)

`CurrentUser` (`app/api/deps.py`) now exposes **`outlet_ids`** (the full set of
accessible outlets, resolved from memberships) plus `outlet_id` (primary). Every
tenancy check moved from `== user.outlet_id` to **membership set** logic. The
client can never widen its own scope:

- **Sales** (`routes/sales.py`): outlet user → a requested `outlet_id` must be in
  their set (else **403**); no selection → **aggregate across all their outlets**.
  ETL unrestricted. Service (`sales_service.py`) gained an `outlet_ids` param.
- **Feedback / Maintenance / Notices / Roster / Staff / Attendance calendar**:
  all use `outlet_id in user.outlet_ids`. Maintenance `list` + `raise` and staff
  `add` accept an optional `outlet_id` (which outlet to act on), always validated
  against membership.
- **Push targeting** (`services/push_targeting.py`): an outlet's notices now go to
  **every manager linked to it via membership** (owners + co-managers), never via
  the stale single column.

## 4. Onboarding behaviour (`routes/onboarding.py`)

Approving an application whose owner email **already exists**:
- **Before:** `409 "account already exists"` (blocked — couldn't reuse an owner).
- **Now:** the new outlet is **linked** to that existing account as another
  `owner` membership — **no new login, no password reset** — and the owner gets an
  "outlet added" email + push. A brand-new email still creates a login + set-
  password link as before. (An email belonging to a *non-outlet* account is still
  refused.)

## 5. New endpoints (`routes/outlets.py`, prefix `/outlets`)

| method | path | who | purpose |
|---|---|---|---|
| GET | `/outlets/mine` | any manager | outlets the caller can access (drives the switcher; `[]` for ETL/staff) |
| GET | `/outlets/{id}/managers` | owner / ETL | list managers linked to an outlet |
| POST | `/outlets/{id}/managers` | owner / ETL | invite a **limited** co-manager (new email → set-password link; existing → linked) |
| DELETE | `/outlets/{id}/managers/{managerId}` | owner / ETL | revoke a co-manager (cannot remove self or an owner) |

On revoke, the manager's primary `outlet_id` is **re-synced** to a remaining
membership (or null) so the revoke actually takes effect.

## 6. Frontend (`lib/features/outlets/`)

- **`data/outlets_repository.dart`** — `MyOutlet` / `OutletManager` models + calls.
- **`domain/outlet_providers.dart`**:
  - `myOutletsProvider` — `GET /outlets/mine` (empty for ETL/staff).
  - `selectedOutletIdProvider` — current outlet; **defaults to the primary
    outlet**, so single-outlet owners are unaffected.
  - `selectedOutletProvider`, `hasMultipleOutletsProvider`.
- **`presentation/outlet_switcher.dart`** — header dropdown that **renders nothing
  unless the owner has >1 outlet**. Placed in the outlet-home header.
- **`presentation/manage_access_screen.dart`** — owner-only: list / invite /
  remove co-managers. Reached from **Settings → Manage Access** (shown only when
  the caller owns the selected outlet).
- **Threading**: `home_providers` (dashboard/insights/roster/outlet-name),
  `outlet_sales_screen`, `feedback_notifier`, `maintenance_notifier`, and outlet
  `staff` add now follow `selectedOutletIdProvider` and refetch when it changes.

## 7. Verification done

Backend is **fully verified in-process (FastAPI TestClient)** — all green:
- Backfill creates owner membership for a legacy account.
- Owner aggregate vs specific outlet vs **foreign outlet → 403**.
- **Single-outlet owner behaves identically** (no aggregation surprises).
- Onboarding **links** existing owner (no duplicate login, no set-password) vs
  **creates** a new owner (with set-password link).
- Co-manager: added as `manager`, can read their outlet, **blocked** from other
  outlets and from managing access; owner revoke **fully** removes access.
- Cannot remove an owner; duplicate add → 409.

## 8. ⚠️ Before release

- **`flutter analyze` + a device build have NOT been run** (no Dart toolchain in
  the build environment). Please run `flutter analyze` and smoke-test the outlet
  screens (switcher, sales/feedback/maintenance following the switch, Manage
  Access add/remove) on a device before shipping the app binary.
- **Backend is deploy-ready** and backward-compatible: the new table is created +
  backfilled on boot; existing single-outlet accounts are unaffected.

## 9. How to onboard the Bennett Coffee Vault (the original example)

1. Owner applies (or ETL creates an application) for *Coffee Vault* at **Bennett**
   using the **same owner email** already used for Central 50.
2. ETL approves → the outlet is **linked** to the existing owner automatically.
3. Owner opens the app → an **outlet switcher** now appears in the header → they
   switch between *Central 50 · Coffee Vault* and *Bennett · Coffee Vault*; every
   screen (sales, feedback, maintenance, staff, roster) follows the selection.
