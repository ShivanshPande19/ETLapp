"""FCM payload shape + the cross-file contracts that make a banner appear.

Regression cover for: "in-app bell counts go up, but no OS banner arrives when
the app is closed."

The bell is fed by the /notices REST API, so it keeps working even when push is
completely broken — which is why this failure was invisible from inside the app.
Three things have to hold for the OS itself to draw a banner, and each of them
lives in a different file, so each is pinned here:

  1. The message must carry a `notification` block. A data-only message is
     handed to the app instead of the OS, and a closed app draws nothing.
  2. Android: the channel id must be one the app actually created, at
     IMPORTANCE_HIGH. An id Android doesn't know is dropped on API 26+, and a
     channel at IMPORTANCE_DEFAULT shows in the status bar without peeking.
  3. iOS: the alert must be sent as a real alert push (apns-push-type), at
     priority 10.
"""
import pathlib
import re

import pytest

from app.services import fcm_service
from app.services.notice_service import _ANDROID_CHANNEL_ID

_REPO = pathlib.Path(__file__).resolve().parents[2]
_APP = _REPO / "etl_manager_app"
_MANIFEST = _APP / "android/app/src/main/AndroidManifest.xml"
_MAIN_ACTIVITY = (
    _APP / "android/app/src/main/kotlin/com/example/etl_manager_app/MainActivity.kt"
)
_RELEASE_ENTITLEMENTS = _APP / "ios/Runner/Runner.entitlements"
_DEBUG_ENTITLEMENTS = _APP / "ios/Runner/RunnerDebug.entitlements"


def _msg(**kw):
    defaults = dict(
        token="tok",
        title="Title",
        body="Body",
        data={"type": "early_logout", "route": "/notices"},
        android_channel_id=_ANDROID_CHANNEL_ID,
    )
    defaults.update(kw)
    return fcm_service._build_message(**defaults)["message"]


# ─── 1. The OS must be the one drawing it ────────────────────────────────────

def test_message_carries_a_notification_block():
    """Without this the payload is data-only and a closed app shows nothing."""
    notif = _msg()["notification"]
    assert notif["title"] == "Title"
    assert notif["body"] == "Body"


def test_body_is_never_null():
    """FCM rejects a null body; an empty string is the valid 'no body' form."""
    assert _msg(body=None)["notification"]["body"] == ""


def test_data_values_are_all_strings():
    """FCM 400s on non-string data values, and the error is opaque."""
    data = _msg(data={"type": "x", "notice_id": 7, "outlet_id": None})["data"]
    assert data == {"type": "x", "notice_id": "7"}  # None dropped, int stringified
    assert all(isinstance(v, str) for v in data.values())


# ─── 2. Android: channel contract across three files ─────────────────────────

def test_channel_id_is_sent_on_the_android_notification():
    assert _msg()["android"]["notification"]["channel_id"] == _ANDROID_CHANNEL_ID


def test_android_priority_is_high():
    assert _msg()["android"]["priority"] == "high"


def test_send_push_default_channel_matches_notice_service():
    """The default argument and the only caller must not drift apart."""
    import inspect

    default = inspect.signature(fcm_service.send_push).parameters[
        "android_channel_id"
    ].default
    assert default == _ANDROID_CHANNEL_ID


@pytest.mark.skipif(not _MANIFEST.exists(), reason="Flutter app not in this checkout")
def test_manifest_default_channel_matches_the_backend():
    m = re.search(
        r'default_notification_channel_id"\s*\n?\s*android:value="([^"]+)"',
        _MANIFEST.read_text(),
    )
    assert m, "default_notification_channel_id not found in AndroidManifest.xml"
    assert m.group(1) == _ANDROID_CHANNEL_ID


@pytest.mark.skipif(
    not _MAIN_ACTIVITY.exists(), reason="Flutter app not in this checkout"
)
def test_app_actually_creates_that_channel_at_high_importance():
    """A channel the app never creates is auto-made at IMPORTANCE_DEFAULT, which
    never peeks — status bar only, no banner. This is the original bug."""
    src = _MAIN_ACTIVITY.read_text()
    assert f'"{_ANDROID_CHANNEL_ID}"' in src, (
        f"MainActivity does not create the {_ANDROID_CHANNEL_ID} channel"
    )
    assert "IMPORTANCE_HIGH" in src, "channel must be IMPORTANCE_HIGH to show a banner"
    assert "createNotificationChannel" in src


# ─── 3. iOS: alert push, and the right APNs environment ──────────────────────

def test_apns_is_sent_as_a_high_priority_alert():
    headers = _msg()["apns"]["headers"]
    assert headers["apns-priority"] == "10"
    assert headers["apns-push-type"] == "alert"


def test_apns_payload_has_a_sound():
    assert _msg()["apns"]["payload"]["aps"]["sound"] == "default"


@pytest.mark.skipif(
    not _RELEASE_ENTITLEMENTS.exists(), reason="Flutter app not in this checkout"
)
def test_release_build_uses_the_production_apns_environment():
    """A store build signed with a distribution profile gets PRODUCTION APNs
    tokens. Shipping `development` here means every production send is rejected
    by APNs with BadDeviceToken — no banner, while the in-app bell (REST) still
    works. That was the iOS half of this bug."""
    assert "<string>production</string>" in _RELEASE_ENTITLEMENTS.read_text()


@pytest.mark.skipif(
    not _DEBUG_ENTITLEMENTS.exists(), reason="Flutter app not in this checkout"
)
def test_debug_build_keeps_the_development_apns_environment():
    """Debug/Profile are signed with a development profile, so they must stay on
    the sandbox — otherwise we'd simply move the breakage to local builds."""
    assert "<string>development</string>" in _DEBUG_ENTITLEMENTS.read_text()


# ─── Badge ───────────────────────────────────────────────────────────────────

def test_badge_is_sent_to_both_platforms_when_known():
    m = _msg(badge=4)
    assert m["apns"]["payload"]["aps"]["badge"] == 4
    assert m["android"]["notification"]["notification_count"] == 4


def test_badge_is_omitted_when_unknown():
    """A role-audience notice fans out to many people, so no single count is
    meaningful; the app recomputes it from /notices/unread-count instead."""
    m = _msg(badge=None)
    assert "badge" not in m["apns"]["payload"]["aps"]
    assert "notification_count" not in m["android"]["notification"]


def test_negative_badge_is_clamped_to_zero():
    assert _msg(badge=-3)["apns"]["payload"]["aps"]["badge"] == 0
