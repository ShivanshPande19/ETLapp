"""FCM badge: real unread count instead of the old hardcoded badge:1."""
import datetime as dt

from conftest import seed_notice
from app.services.fcm_service import _build_message
from app.services import notice_service
from app.models.notice import Notice

AUG24 = dt.datetime(2026, 8, 24, 12, 0, 0)


def test_build_message_omits_badge_when_none():
    msg = _build_message("tok", title="t", body="b", data=None,
                         android_channel_id="etl_default", badge=None)
    aps = msg["message"]["apns"]["payload"]["aps"]
    assert "badge" not in aps
    assert "notification_count" not in msg["message"]["android"]["notification"]


def test_build_message_sets_real_badge_both_platforms():
    msg = _build_message("tok", title="t", body="b", data={"type": "x"},
                         android_channel_id="etl_default", badge=5)
    assert msg["message"]["apns"]["payload"]["aps"]["badge"] == 5
    assert msg["message"]["android"]["notification"]["notification_count"] == 5


def test_build_message_badge_never_negative():
    msg = _build_message("tok", title="t", body=None, data=None,
                         android_channel_id="etl_default", badge=-3)
    assert msg["message"]["apns"]["payload"]["aps"]["badge"] == 0


def test_unread_badge_for_manager_scope(db):
    seed_notice(db, audience="manager", is_read=False, created_at=AUG24)
    seed_notice(db, audience="manager", is_read=False, created_at=AUG24)
    seed_notice(db, audience="manager", is_read=True, created_at=AUG24)
    # a staff notice must NOT count toward the manager badge
    seed_notice(db, audience="staff", recipient_staff_id=9, is_read=False,
                created_at=AUG24)
    latest = db.query(Notice).filter(
        Notice.audience == "manager", Notice.is_read == False).first()
    assert notice_service._unread_badge_for(db, latest) == 2


def test_unread_badge_for_staff_scope(db):
    seed_notice(db, audience="staff", recipient_staff_id=9, is_read=False,
                created_at=AUG24)
    seed_notice(db, audience="staff", recipient_staff_id=9, is_read=False,
                created_at=AUG24)
    seed_notice(db, audience="staff", recipient_staff_id=99, is_read=False,
                created_at=AUG24)  # different staff, excluded
    n = db.query(Notice).filter(Notice.recipient_staff_id == 9).first()
    assert notice_service._unread_badge_for(db, n) == 2
