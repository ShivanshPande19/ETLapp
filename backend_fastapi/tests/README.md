# Backend test suite

Fast, isolated pytest suite for the FastAPI backend. Runs against an in-memory
SQLite DB and a bare app that mounts only the routers under test — the
production lifespan (APScheduler, FCM, on-boot Petpooja sync, backfills) is
never started, so there are no external side-effects.

## Run

```bash
cd backend_fastapi
python -m venv .venv-test && source .venv-test/bin/activate   # first time
pip install -r requirements.txt pytest
python -m pytest tests/ -q
```

## What it covers

| File | Validates |
|------|-----------|
| `test_roles.py` | `CurrentUser` role/tenancy logic — legacy `manager`/`staff` count as ETL identities (mirrors the Flutter `auth_notifier` fix); `can_access_outlet` membership gate. |
| `test_attendance_unique.py` | One attendance row per staff per business day — the double-check-in guard (unique constraint), incl. NULL-business_date legacy rows staying distinct. |
| `test_feedback_scoping.py` | `/feedback/my-court(+/analytics)` works for ETL managers (across all courts / a single `?court_id=`), stays locked for ETL staff; `/feedback/court/{id}` is ETL-manager-only. |
| `test_delete_outlet.py` | `delete_outlet` deactivates a now-membershipless owner (no zombie login) but keeps a multi-outlet owner active; ETL-manager-only. |

## ⚠️ Depends on the QA fix PRs

These tests assert the behaviour introduced by PRs **#99** (attendance unique
constraint), **#101** (delete_outlet cleanup, `/feedback/my-court` for
managers) and the role helpers in **#99**. Run them on a branch/`main` that has
those merged — otherwise the attendance, my-court and delete-outlet tests will
(correctly) fail.
