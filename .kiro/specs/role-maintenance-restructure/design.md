# Design — Role Split + Maintenance Ticket Restructure

> Status: **DRAFT for review**. Implements `requirements.md`. Aligns with the
> existing architecture (no Alembic — additive `ensure_*` migrations; roles as
> string columns on `managers`/`staff`; notices via `notice_service` +
> `push_targeting`; APScheduler jobs).

---

## 1. Guiding decisions

- **Manager table = full-access management roles; Staff table = narrow worker
  roles.** This mirrors the current split and keeps `login_manager` (which
  already checks both tables) working unchanged.
  - Manager roles: `azimuth_management`, `crownest_ops_head`, `crownest_head`
    (+ legacy `etl_manager`/`manager`, `outlet_manager`).
  - Staff roles: `azimuth_maintenance`, `crownest_maintenance_head`
    (+ legacy `etl_staff`, `outlet_staff`).
- **Target/mention by ROLE (and optional individual)** — decouples ticket
  routing from which table an account lives in and is future-proof for multiple
  `crownest_maintenance_head` accounts.
- **Additive, idempotent migrations** only; every legacy account keeps working
  on deploy.

---

## 2. Data model changes

### 2.1 `managers` (Manager)
- `role` — now one of: `azimuth_management` | `crownest_ops_head` |
  `crownest_head` (+ legacy `etl_manager`/`manager`, `outlet_manager`).
- `org` (new, nullable String) — `"azimuth"` | `"crownest"` (management/maint
  accounts). Purely informational/labels; access is by role.

### 2.2 `staff` (Staff)
- `role` — add `azimuth_maintenance` | `crownest_maintenance_head`.
- `org` (new, nullable String).
- Reuse existing `court_id` as the **zone** for `crownest_maintenance_head`
  (nullable for `azimuth_maintenance`, which is company-wide + single).
- Reuse existing attendance columns/flow for `crownest_maintenance_head`.

### 2.3 `maintenance_issues` (MaintenanceIssue) — new columns
| Column | Type | Meaning |
|--------|------|---------|
| `scope` | String default `"outlet"` | `"general"` (court-level) or `"outlet"` |
| `raised_by_role` | String | role key of the raiser |
| `raised_by_id` | Integer | account id of the raiser |
| `raised_by_table` | String | `"manager"` \| `"staff"` |
| `is_urgent` | Boolean default false | urgent flag |
| `target_teams` | Text (JSON list) | e.g. `["azimuth_maintenance"]` or both |
| `mentions` | Text (JSON list) | items `{"kind":"role"\|"user","value":...}` |
| `triage_status` | String default `"pending"` for outlet-raised, `"routed"` when ops head sets targets | drives the triage queue |
| `last_reminder_at` | DateTime null | last 6h reminder sent |
| `escalated_2d` | Boolean default false | 2-day escalation fired |
| `escalated_4d` | Boolean default false | 4-day escalation fired |

- `outlet_id` = 0/null for `scope="general"`; existing `court_id`/`court_name`
  still set. (Keep NOT NULL constraints satisfied with a sentinel 0 + empty
  name for general, or relax to nullable via `ensure_*` — decide in impl;
  prefer sentinel 0 to avoid a NOT NULL migration.)
- Technician: keep existing `technician_name`/`technician_phone` (v1 single).
  Display logic: for each targeted team, show the assigned technician if set,
  else that team's head account name+phone.

### 2.4 `notices` (Notice) — new targeting
Current targeting is `audience=manager`(etl vs outlet by `outlet_id`) or
`audience=staff`(one recipient). Add **role-based** targeting:
- `target_roles` (new, Text JSON list) — when set, the notice is delivered to
  **all active accounts (manager or staff) holding any of these roles**.
- `recipient_manager_id` (new, Integer null) — optional single-manager target
  (parallel to `recipient_staff_id`) for individual mentions of a manager.
- `audience` gains value `"role"` for role-scoped notices.

All new columns are additive + nullable → idempotent `ensure_notice_columns()`.

---

## 3. Access control (`api/deps.py`)

Extend `CurrentUser` with clear capability properties (single source of truth):

```
MANAGEMENT_ROLES   = {"azimuth_management","crownest_ops_head","crownest_head",
                      "etl_manager","manager"}   # legacy = full access
MAINTENANCE_ROLES  = {"azimuth_maintenance","crownest_maintenance_head"}

is_management        -> role in MANAGEMENT_ROLES        (full company-wide access)
is_ops_head          -> role == "crownest_ops_head"     (can raise tickets)
is_maintenance       -> role in MAINTENANCE_ROLES
maintenance_role     -> the role key (for target/visibility matching)
org                  -> "azimuth" | "crownest" | None
```

- Keep `is_etl_manager` as an **alias of `is_management`** so existing routes
  keep compiling; migrate call-sites gradually.
- `require_etl_manager` → `require_management` (full-access gate). New gates:
  `require_ops_head`, `require_maintenance`.
- Login/JWT unchanged (still `sub`=email). Role/org resolved fresh from DB in
  `get_current_user`, same as today.

---

## 4. Notification / reminder engine

### 4.1 Role-based targeting (`push_targeting.py`)
Add `_tokens_for_roles(db, roles)` — joins device tokens against **both**
`managers` and `staff` live rows filtered by `role in roles` + `is_active`.
Extend `resolve_notice_targets`:
- `audience == "role"` → union of `_tokens_for_roles(target_roles)` +
  (`recipient_manager_id` token if set) + (`recipient_staff_id` token if set).
- Existing manager/staff branches unchanged.

Mirror the same scoping in `notices.py::_scoped_query` so a role-holder can open
what they were pushed (a manager/staff sees a `audience=role` notice iff their
role is in `target_roles`, or they are the named recipient).

### 4.2 `notice_service.create_notice`
Add optional params: `target_roles: list[str] | None`, `recipient_manager_id`.
No behavioural change for existing callers.

### 4.3 Ticket raise → notifications (`maintenance.py`)
On raise/triage-route (when targets are set):
1. Immediate notice to each **targeted maintenance role** (`audience=role`).
2. Immediate notice to each **mention** (role or individual).
3. If target includes `azimuth_maintenance` (or both): immediate **once** to the
   management tier (`target_roles=["azimuth_management","crownest_head"]`).
4. Urgent + mention azimuth → covered by (2).
- Outlet-raised tickets: on raise, notify **only `crownest_ops_head`** (triage
  queue). The above (1–3) run when the ops head routes/targets it.

### 4.4 Reminders + escalations (`scheduler_service.py`)
Two new cron jobs (IST timezone already configured):
- **`maintenance_reminders`** — runs hourly; for each **OPEN** ticket with
  target teams, if `now` is within **09:00–21:00 IST** and
  `last_reminder_at` is null or ≥6h ago → send a reminder notice to the
  target maintenance role(s) (ticket id + description), set `last_reminder_at`.
- **`maintenance_escalations`** — runs hourly; for each **OPEN** ticket:
  - target includes `azimuth_maintenance` & age ≥ 2d & not `escalated_2d`
    → notify management tier "still open after 2 days", set flag.
  - target is only `crownest_maintenance_head` & age ≥ 4d & not `escalated_4d`
    → notify management tier "still open after 4 days", set flag.
- "OPEN" = status not in {CLOSED}. (RESOLVED still has the 24h window;
  reminders should stop at RESOLVED — treat OPEN as status in
  {RAISED, ASSIGNED, DISPUTED}.)

---

## 5. API changes (`maintenance.py`, `managers.py`)

### 5.1 Maintenance
- `POST /maintenance/` — allow `crownest_ops_head` to raise with
  `scope`, `outlet_id?`, `target_teams`, `mentions`, `is_urgent`.
  Outlet users keep raising (triage: no targets, lands with ops head).
- `PUT /maintenance/{id}/route` (new, ops-head only) — set `target_teams` /
  `mentions` / scope for a triaged ticket; fires §4.3 notifications.
- `PUT /maintenance/{id}/assign|resolve|verify` — permission widened:
  assign/resolve allowed for **targeted maintenance role(s)** and management;
  verify stays with the raiser/outlet (and ops head for ops-raised).
- `GET /maintenance` — visibility per §3.6:
  - maintenance role → tickets where its role ∈ `target_teams` OR mentioned.
  - management → all (existing court/outlet filters, + zone filter).

### 5.2 Accounts (`managers.py` → generalise)
- New create endpoint accepting `role` (any of the 5) + `org` + `zone`
  (court_id) where applicable. Management-only.
  - Manager-table roles → create a `Manager` row (as today).
  - Staff-table maintenance roles → create a `Staff` row (set-password link
    reused; attendance applies only to `crownest_maintenance_head`).
- List/deactivate/reactivate generalised across both tables + roles.
- Keep the last-active-management guardrail (can't lock everyone out).

### 5.3 Roster / attendance
- `crownest_maintenance_head` is a Staff row → already flows into roster/
  attendance queries. Add a **role→badge** field in the roster response so the
  UI can show the "Maintenance Head" badge. `azimuth_maintenance` (no
  attendance) is **excluded** from attendance/roster queries.

---

## 6. Frontend

### 6.1 Routing (`app/router.dart`)
- Add role-aware redirects for the 5 roles (mirror existing per-role logic):
  - management roles → the existing full manager home (`/home`).
  - `azimuth_maintenance` → new `/maintenance-home` (staff-style shell).
  - `crownest_maintenance_head` → new `/maintenance-home` + attendance route.
- Auth state already carries `role`; add `org` if needed.

### 6.2 New screens (on existing theme)
- `features/maintenance/presentation/maintenance_home_screen.dart` — assigned
  tickets list + open ticket detail (resolve/assign-technician) + Settings.
- Reuse existing ticket detail widgets; add target/mention/technician display.
- `crownest_maintenance_head` gets the existing attendance widgets embedded.

### 6.3 Ops-head raise flow + ticket redesign
- Raise sheet/screen: scope toggle, outlet picker (reuse courts/outlets data),
  target multi-select, mention picker, urgent toggle.
- Triage view for ops head (pending outlet-raised tickets → route).
- Ticket detail redesign (targets, mentions, technician-or-head, timeline).

### 6.4 Admin
- Generalise `manage_etl_managers_screen.dart` → create account + role picker
  (5 roles) + zone picker (for maintenance-head) + org.

### 6.5 Theme
- Reuse `core/theme/app_theme.dart` tokens + existing shared widgets; no new
  design language.

---

## 7. Migration plan (boot, idempotent)
1. `ensure` new columns: `managers.org`, `staff.org`, maintenance columns,
   notice columns (all additive/nullable).
2. Backfill: set `manager@etl.com` → `crownest_head`, `org="crownest"`
   (idempotent; only if still legacy). Other legacy `etl_manager`/`manager`
   accounts keep full access via the `MANAGEMENT_ROLES` alias until reassigned.
3. No destructive changes; SQLite (dev) + Postgres (prod) both handled like the
   existing `ensure_*` helpers.

---

## 8. Rollout
- **Backend** deploys via Railway (roles, model, notifications) — safe/additive.
- **Frontend** ships in the next app build; distributed via the testing tracks.
- The two maintenance-head accounts are created by a management role via the
  admin screen after deploy.

---

## 9. Risks / decisions to confirm during build
- General-scope tickets with `outlet_id=0` sentinel vs relaxing NOT NULL.
- Widening resolve/assign to staff-table maintenance roles (permission tests).
- JSON-in-text columns for `target_teams`/`mentions`/`target_roles` on both
  dialects (store as JSON string; parse defensively).
- Attendance UI reuse for a Staff account that also has a tickets home.
