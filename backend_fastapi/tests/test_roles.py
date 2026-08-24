"""Role & tenancy logic on CurrentUser (mirrors the frontend auth_notifier)."""
from app.api.deps import CurrentUser


def _u(role, **kw):
    return CurrentUser(id=1, name="n", email="e@test.com", role=role, **kw)


def test_etl_manager_includes_legacy_manager():
    assert _u("etl_manager").is_etl_manager
    assert _u("manager").is_etl_manager  # legacy value must still count
    assert not _u("outlet_manager").is_etl_manager
    assert not _u("etl_staff").is_etl_manager


def test_etl_staff_includes_legacy_staff():
    assert _u("etl_staff").is_etl_staff
    assert _u("staff").is_etl_staff  # legacy value must still count
    assert not _u("outlet_staff").is_etl_staff


def test_outlet_user_detection():
    assert _u("outlet_manager").is_outlet_user
    assert _u("outlet_staff").is_outlet_user
    assert not _u("etl_manager").is_outlet_user
    assert not _u("etl_staff").is_outlet_user


def test_account_type_flags():
    assert _u("etl_manager", user_type="manager").is_manager_account
    assert _u("etl_staff", user_type="staff").is_staff_account


def test_can_access_outlet_tenancy():
    etl = _u("etl_manager")
    assert etl.can_access_outlet(99)  # ETL manager is unrestricted
    assert not etl.can_access_outlet(None)

    owner = _u("outlet_manager", outlet_ids=[5, 6])
    assert owner.can_access_outlet(5)
    assert owner.can_access_outlet(6)
    assert not owner.can_access_outlet(7)  # not a member
    assert not owner.can_access_outlet(None)


def test_outlet_ids_fallback_to_single_outlet():
    u = _u("outlet_manager", outlet_id=5)
    assert u.outlet_ids == [5]
    u2 = _u("outlet_manager")
    assert u2.outlet_ids == []
