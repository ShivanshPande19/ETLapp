"""The "Operations - Office" role is Crownest Head under another name: wherever
the server treats `crownest_head` specially, it must treat `operations_office`
the same. These pin that parity so a future role list cannot forget it."""
from conftest import make_user, seed_notice

from app.api import deps
from app.api.routes import maintenance as maintenance_routes
from app.api.routes import managers as managers_routes
from app.services import push_targeting, scheduler_service
from app.services import team_task_service as tasks

NEW, TWIN = "operations_office", "crownest_head"


def test_it_is_in_every_role_list_crownest_head_is_in():
    lists = {
        "deps.MANAGEMENT_ROLES": deps.MANAGEMENT_ROLES,
        "push_targeting.ETL_MANAGER_ROLES": push_targeting.ETL_MANAGER_ROLES,
        "maintenance.MANAGEMENT_TIER_ROLES": maintenance_routes.MANAGEMENT_TIER_ROLES,
        "scheduler._MAINT_MGMT_TIER": scheduler_service._MAINT_MGMT_TIER,
        "managers._CREATABLE_ROLES": managers_routes._CREATABLE_ROLES,
        "managers._ORG_BY_ROLE": managers_routes._ORG_BY_ROLE,
        "tasks.HEAD_ROLES": tasks.HEAD_ROLES,
    }
    for name, roles in lists.items():
        assert TWIN in roles, f"{name} no longer lists {TWIN} — update this test"
        assert NEW in roles, f"{name} is missing {NEW}"


def test_same_table_org_and_access_flags_as_crownest_head():
    assert managers_routes._CREATABLE_ROLES[NEW] == managers_routes._CREATABLE_ROLES[TWIN] == "manager"
    assert managers_routes._ORG_BY_ROLE[NEW] == managers_routes._ORG_BY_ROLE[TWIN]
    assert managers_routes._ROLE_LABELS[NEW] == "Operations - Office"
    assert tasks.role_label(NEW) == "Operations - Office"

    a, b = make_user(NEW), make_user(TWIN)
    for flag in ["is_management", "is_etl_manager", "is_ops_head", "is_zone_manager",
                 "is_maintenance", "is_outlet_user", "is_etl_staff"]:
        assert getattr(a, flag) == getattr(b, flag), flag
    assert a.is_management is True and a.is_ops_head is False


def test_it_sees_the_management_inbox(client_factory, db):
    seed_notice(db, title="for management")
    r = client_factory(make_user(NEW)).get("/notices/")
    assert [n["title"] for n in r.json()["notices"]] == ["for management"]


def test_team_tasks_treat_it_as_a_head():
    for other in ["crownest_ops_head", "azimuth_management", TWIN,
                  "crownest_zone_manager", "crownest_maintenance_head", "azimuth_maintenance"]:
        assert tasks.can_assign(NEW, other), other
    assert tasks.can_assign("crownest_ops_head", NEW)
    assert not tasks.can_assign("crownest_zone_manager", NEW)   # field → Ops Head only
