# Tasks — Role Split + Maintenance Ticket Restructure

> Status: **DRAFT for review**. Derived from `requirements.md` + `design.md`.
> Each phase is a reviewable PR. Do NOT start a phase until the previous one is
> reviewed. Backend phases deploy independently of the app build.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done

---

## Phase 1 — Roles & access control (backend)
- [ ] Add role constants + `org` to `Manager` and `Staff` models.
- [ ] `ensure_manager_columns()` / extend `ensure_staff_columns()` for `org`
      (additive, idempotent, dialect-aware).
- [ ] Boot backfill: `manager@etl.com` → `crownest_head` (idempotent).
- [ ] `CurrentUser`: `is_management`, `is_ops_head`, `is_maintenance`,
      `maintenance_role`, `org`; keep `is_etl_manager` as alias of
      `is_management`.
- [ ] New guards: `require_management`, `require_ops_head`, `require_maintenance`
      (leave `require_etl_manager` as alias).
- [ ] Verify every existing `require_etl_manager` call still behaves (management
      = full access) — no regression for current accounts.
- [ ] Tests (TestClient): legacy account still full-access; a
      `crownest_head`/`azimuth_management`/`crownest_ops_head` gets full access;
      maintenance roles are correctly restricted.

## Phase 2 — Account administration (backend + admin API)
- [ ] Generalise `managers.py`: create account with `role` (any of 5) + `org` +
      `zone` (court_id for maintenance-head); Manager vs Staff row by role.
- [ ] Reuse set-password magic-link for new accounts (both tables).
- [ ] Generalise list / deactivate / reactivate across roles + tables; keep the
      last-active-management guardrail.
- [ ] Tests: create each role; only management can call; maintenance accounts
      cannot self-create.

## Phase 3 — Maintenance ticket model + raise/triage (backend)
- [ ] Add ticket columns (scope, raised_by_*, is_urgent, target_teams JSON,
      mentions JSON, triage_status, last_reminder_at, escalated_2d/4d).
- [ ] `ensure_maintenance_columns()` (additive/idempotent).
- [ ] `POST /maintenance/` — ops-head raise (scope/targets/mentions/urgent);
      outlet raise → triage (no targets, lands with ops head).
- [ ] `PUT /maintenance/{id}/route` — ops-head sets targets/mentions/scope.
- [ ] Widen assign/resolve to targeted maintenance role(s) + management.
- [ ] `GET /maintenance` visibility: maintenance role → target/mention only;
      management → all (+ zone filter).
- [ ] Tests: raise/triage/route/resolve happy paths + visibility isolation.

## Phase 4 — Notifications & reminders (backend)
- [ ] Notice model: `target_roles` JSON, `recipient_manager_id`, audience
      `"role"`; `ensure_notice_columns()`.
- [ ] `push_targeting._tokens_for_roles` + extend `resolve_notice_targets`;
      mirror in `notices.py::_scoped_query`.
- [ ] `create_notice` gains `target_roles` / `recipient_manager_id`.
- [ ] Wire raise/route notifications per matrix (immediate + management-tier
      once for azimuth-target; mentions immediate).
- [ ] Scheduler: `maintenance_reminders` (6h, 09:00–21:00 IST, OPEN only,
      stops on close) + `maintenance_escalations` (2d azimuth / 4d crownest,
      once each, OPEN only).
- [ ] Tests: targeting resolves across both tables; quiet-hours honoured;
      escalation thresholds + once-only; no leak to non-targeted roles.

## Phase 5 — Frontend: role screens + routing
- [ ] Auth state carries `role` (+ `org`); router redirects for 5 roles.
- [ ] `maintenance_home_screen` (tickets list + detail + resolve/assign +
      Settings) — on existing theme.
- [ ] `crownest_maintenance_head`: embed existing attendance (mark + view).
- [ ] `flutter analyze` clean.

## Phase 6 — Frontend: ops-head raise/triage + ticket redesign
- [ ] Raise flow (scope toggle, outlet picker, target multi-select, mention
      picker, urgent).
- [ ] Ops-head triage view (pending outlet-raised → route).
- [ ] Ticket detail redesign (targets, mentions, technician-or-head, timeline).

## Phase 7 — Frontend: roster badge + admin screen
- [ ] Roster/calendar shows `crownest_maintenance_head` with "Maintenance Head"
      badge; `azimuth_maintenance` excluded from attendance.
- [ ] Generalise "Manage Accounts" screen: create + role picker (5) + zone +
      org; management-only.
- [ ] `flutter analyze` clean; smoke test each role's landing + core flow.

## Phase 8 — Verification & release
- [ ] End-to-end (TestClient) across roles + ticket lifecycle + notifications.
- [ ] Manual smoke on device for each new role (theme, flows).
- [ ] Migration verified on a Postgres-like DB (columns + backfill idempotent).
- [ ] Ship backend; build + distribute app via testing tracks.

---

## Sequencing notes
- Phases 1–4 are **backend-only** and can be merged + deployed without an app
  update (new screens simply aren't reachable yet).
- Phases 5–7 need an app build; distribute via internal/closed testing.
- Keep the legacy `etl_manager` alias until all accounts are reassigned, then
  optionally retire it in a later cleanup.
