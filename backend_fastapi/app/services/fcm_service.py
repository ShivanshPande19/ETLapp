# app/services/fcm_service.py
"""Push delivery via the FCM HTTP v1 API.

Deliberately NOT using `firebase-admin`. That package pulls in grpcio and
google-cloud-firestore, which is a heavy compiled dependency tree on the
python:3.10-slim base image, and we only need one endpoint. This module mirrors
the shape of `email_service.py` instead:

  • async, driven by the httpx client that is already a dependency
  • NEVER raises — a push failure must not break the flow that triggered it
  • no-ops gracefully when credentials are unset, so local dev and CI work
    without any Firebase setup at all

Config (see core/config.py):
  FIREBASE_PROJECT_ID       — e.g. "etl-manager"
  FIREBASE_CREDENTIALS_JSON — the service-account JSON, pasted as a single env
                              var (Railway has no secret-file mechanism)

Targeting is NOT decided here — see services/push_targeting.py. This module
just delivers to the exact token list it is handed.
"""

from __future__ import annotations

import asyncio
import json
import logging
import threading
import time
from typing import Any, Dict, Iterable, List, Optional, Tuple

import httpx

from ..core.config import settings

logger = logging.getLogger("fcm")

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

# FCM error codes that mean "this token is dead, stop sending to it".
# https://firebase.google.com/docs/cloud-messaging/send-message#rest_error_response
_DEAD_TOKEN_CODES = {"UNREGISTERED", "INVALID_ARGUMENT", "NOT_FOUND", "SENDER_ID_MISMATCH"}

# Cached OAuth2 credentials. google-auth is not thread-safe for refresh, so a
# lock guards it; the token is valid for ~1h and refreshed on demand.
_creds = None
_creds_lock = threading.Lock()
_creds_unavailable = False  # set once so we log the "not configured" line once

# Set from main.py lifespan, exactly like events._main_loop. Lets sync route
# handlers (which FastAPI runs in a worker thread) fire a push onto the loop.
_main_loop: Optional[asyncio.AbstractEventLoop] = None


def is_configured() -> bool:
    return bool(settings.FIREBASE_PROJECT_ID and settings.FIREBASE_CREDENTIALS_JSON)


# ─── OAuth2 access token ─────────────────────────────────────────────────────

def _load_credentials():
    """Build service-account credentials from the JSON env var. Cached."""
    global _creds, _creds_unavailable

    if _creds is not None:
        return _creds
    if _creds_unavailable:
        return None

    try:
        from google.oauth2 import service_account  # imported lazily
    except ImportError:
        _creds_unavailable = True
        logger.error(
            "[FCM] google-auth is not installed — push disabled. "
            "Add `google-auth` to requirements.txt."
        )
        return None

    raw = (settings.FIREBASE_CREDENTIALS_JSON or "").strip()
    if not raw:
        _creds_unavailable = True
        return None

    try:
        info = json.loads(raw)
    except json.JSONDecodeError as e:
        _creds_unavailable = True
        logger.error("[FCM] FIREBASE_CREDENTIALS_JSON is not valid JSON: %s", e)
        return None

    try:
        _creds = service_account.Credentials.from_service_account_info(
            info, scopes=[FCM_SCOPE]
        )
    except Exception as e:  # noqa: BLE001
        _creds_unavailable = True
        logger.error("[FCM] could not build service-account credentials: %s", e)
        return None

    return _creds


def _refresh_access_token_blocking() -> Optional[str]:
    """Refresh (if needed) and return the bearer token. Runs in a thread."""
    creds = _load_credentials()
    if creds is None:
        return None

    try:
        from google.auth.transport.requests import Request as GoogleRequest
    except ImportError:
        logger.error("[FCM] google-auth transport unavailable — push disabled.")
        return None

    with _creds_lock:
        try:
            if not creds.valid:
                creds.refresh(GoogleRequest())
            return creds.token
        except Exception as e:  # noqa: BLE001
            logger.error("[FCM] token refresh failed: %s", e)
            return None


async def _access_token() -> Optional[str]:
    """google-auth's refresh is synchronous — keep it off the event loop."""
    return await asyncio.to_thread(_refresh_access_token_blocking)


# ─── Sending ─────────────────────────────────────────────────────────────────

def _build_message(
    token: str,
    *,
    title: str,
    body: Optional[str],
    data: Optional[Dict[str, Any]],
    android_channel_id: str,
    badge: Optional[int] = None,
) -> Dict[str, Any]:
    """One FCM v1 message envelope.

    `data` values must all be strings — FCM rejects non-string values, and a
    silent 400 here is very hard to debug.

    `badge` is the recipient's REAL unread count. Previously this was hardcoded
    to 1, so the iOS app-icon badge got stuck showing "1" forever regardless of
    how many notices were unread and never reflected reads. When provided we
    send the exact count on both platforms (iOS `aps.badge`, Android
    `notification_count`); the client also clears it to 0 on open/read.
    """
    aps: Dict[str, Any] = {"sound": "default"}
    android_notif: Dict[str, Any] = {
        "channel_id": android_channel_id,
        # Lets a newer notice for the same thing replace the old one in the
        # tray instead of stacking duplicates.
        "tag": str((data or {}).get("type", "general")),
    }
    if badge is not None:
        b = max(0, int(badge))
        aps["badge"] = b
        android_notif["notification_count"] = b

    payload: Dict[str, Any] = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body or ""},
            "android": {
                "priority": "high",
                "notification": android_notif,
            },
            "apns": {
                "headers": {"apns-priority": "10"},
                "payload": {"aps": aps},
            },
        }
    }
    if data:
        payload["message"]["data"] = {str(k): str(v) for k, v in data.items() if v is not None}
    return payload


def _classify_error(resp_text: str) -> Tuple[bool, str]:
    """Return ``(token_is_dead, code)`` from an FCM error response body."""
    try:
        parsed = json.loads(resp_text)
    except Exception:  # noqa: BLE001
        return False, "UNPARSEABLE"

    err = parsed.get("error", {}) or {}
    code = err.get("status") or ""
    for detail in err.get("details", []) or []:
        if isinstance(detail, dict) and detail.get("errorCode"):
            code = detail["errorCode"]
            break
    return code in _DEAD_TOKEN_CODES, code or "UNKNOWN"


async def send_push(
    tokens: Iterable[str],
    *,
    title: str,
    body: Optional[str] = None,
    data: Optional[Dict[str, Any]] = None,
    android_channel_id: str = "etl_default",
    badge: Optional[int] = None,
) -> Tuple[int, List[str]]:
    """Deliver to every token. Returns ``(sent_count, dead_tokens)``.

    `dead_tokens` are tokens FCM rejected as permanently invalid; the caller
    should soft-disable them (see push_targeting.deactivate_tokens).

    Never raises.
    """
    token_list = list(dict.fromkeys(t for t in tokens if t))
    if not token_list:
        return 0, []

    if not is_configured():
        logger.warning(
            "[FCM] not configured (FIREBASE_PROJECT_ID / FIREBASE_CREDENTIALS_JSON) "
            "— skipping push to %d device(s): %s",
            len(token_list),
            title,
        )
        return 0, []

    access_token = await _access_token()
    if not access_token:
        return 0, []

    url = FCM_ENDPOINT.format(project_id=settings.FIREBASE_PROJECT_ID)
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; UTF-8",
    }

    sent = 0
    dead: List[str] = []

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:

            async def _one(tok: str) -> None:
                nonlocal sent
                try:
                    resp = await client.post(
                        url,
                        headers=headers,
                        json=_build_message(
                            tok,
                            title=title,
                            body=body,
                            data=data,
                            android_channel_id=android_channel_id,
                            badge=badge,
                        ),
                    )
                except Exception as e:  # noqa: BLE001 — one device must not fail the batch
                    logger.error("[FCM] transport error for one device: %s", e)
                    return

                if resp.status_code == 200:
                    sent += 1
                    return

                is_dead, code = _classify_error(resp.text)
                if is_dead:
                    dead.append(tok)
                    logger.info("[FCM] token dead (%s) — will be disabled", code)
                else:
                    logger.error(
                        "[FCM] send failed (%s/%s): %s",
                        resp.status_code,
                        code,
                        resp.text[:300],
                    )

            # Small fan-outs (a handful of devices per notice) — parallel is fine.
            await asyncio.gather(*(_one(t) for t in token_list))

    except Exception as e:  # noqa: BLE001 — push must never break the caller
        logger.error("[FCM] send_push exception: %s", e)
        return sent, dead

    logger.info("[FCM] '%s' → %d/%d delivered", title, sent, len(token_list))
    return sent, dead


# ─── Thread-safe fire-and-forget, mirroring events.fire_notify ────────────────

def fire_push(coro_factory) -> None:
    """Schedule a push coroutine on the main loop from ANY context.

    `create_notice` is called both from sync route handlers (which FastAPI runs
    in an AnyIO worker thread) and from async scheduler jobs. This mirrors
    `events.fire_notify` so both work identically.

    Takes a zero-arg callable returning a coroutine, so nothing is created
    unless there is a live loop to run it on (avoids "coroutine was never
    awaited" warnings when push is disabled).
    """
    global _main_loop
    try:
        if _main_loop is None or not _main_loop.is_running():
            return
        asyncio.run_coroutine_threadsafe(coro_factory(), _main_loop)
    except Exception as e:  # noqa: BLE001
        logger.error("[FCM] fire_push failed: %s", e)
