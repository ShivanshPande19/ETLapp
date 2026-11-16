"""Team tasks: who takes part, who sees what, the lifecycle, proof of work,
notifications and reminders.

The rules under test are the ones the product decisions fixed:
  • heads (Azimuth Management, Crownest Head, Crownest Ops Head) give tasks to
    each other and to the field tier (Zone Manager, Crownest Maintenance Head);
    the field tier (incl. Azimuth Maintenance) gives tasks to the Crownest Ops
    Head only; ETL staff and outlet accounts take no part at all
  • a task is visible ONLY to its two people — not even to management
  • a completed task is DONE at once, and the assigner may reopen it
  • proof of work is on by default and enforced by the server
"""
import datetime as dt

import pytest

from conftest import make_user, seed_court
from app.models.manager import Manager
from app.models.notice import Notice
from app.models.staff import Staff
from app.models.team_task import TeamTask, TeamTaskEvent
from app.services import team_task_service as svc

PHOTO = "uploads/team_tasks/task_abc.jpg"


# ─── Seeding ─────────────────────────────────────────────────────────────────

def _mgr(db, name, role, active=True):
    m = Manager(name=name, email=f"{name.lower().replace(' ', '')}@m.test",
                hashed_password="x", role=role, is_active=active)
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


def _stf(db, name, role="etl_staff", court_id=None, active=True, zone=None):
    s = Staff(name=name, email=f"{name.lower().replace(' ', '')}@s.test",
              hashed_password="x", role=role, court_id=court_id,
              zone_court_ids=zone, is_active=active)
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def _as(row, user_type):
    """The CurrentUser for a seeded row."""
    return make_user(row.role, uid=row.id, user_type=user_type, name=row.name,
                     email=row.email, court_id=getattr(row, "court_id", None))


@pytest.fixture()
def act(client_factory):
    """`act(user)` -> a client that always acts as THAT user.

    conftest's factory keeps ONE "current user" shared by every client it has
    handed out, so with two clients alive at once both would act as whoever was
    created last. These tests constantly alternate between the giver and the
    doer, so each call re-binds the identity first.
    """
    class _Actor:
        def __init__(self, user):
            self._user = user

        def get(self, *a, **k):
            return client_factory(self._user).get(*a, **k)

        def post(self, *a, **k):
            return client_factory(self._user).post(*a, **k)

    return _Actor


@pytest.fixture()
def team(db):
    """A realistic slice of the org. Note head.id == staff.id == 1 on purpose:
    the two tables' ids overlap in production, and nothing may confuse them."""
    court = seed_court(db, "Bennett University")
    head = _mgr(db, "Asha Head", "crownest_head")
    ops = _mgr(db, "Omar Ops", "crownest_ops_head")
    azimuth = _mgr(db, "Zara Azimuth", "azimuth_management")
    owner = _mgr(db, "Vik Vendor", "outlet_manager")
    # `staff` is the first staff-table row (id 1): the zone manager.
    staff = _stf(db, "Manu Zone", "crownest_zone_manager", court_id=court.id,
                 zone=f"[{court.id}]")
    maint = _stf(db, "Mo Maint", "crownest_maintenance_head", court_id=court.id)
    etl = _stf(db, "Evan Etl", "etl_staff", court_id=court.id)
    amaint = _stf(db, "Ari Azmaint", "azimuth_maintenance", court_id=court.id)
    ostaff = _stf(db, "Olly Outlet", "outlet_staff")
    assert head.id == staff.id == 1
    return dict(court=court, head=head, ops=ops, azimuth=azimuth, owner=owner,
                staff=staff, zone=staff, maint=maint, etl=etl, amaint=amaint,
                ostaff=ostaff)


def _give(client, assignee_key, **over):
    body = {"title": "Check the freezer", "assignee": assignee_key}
    body.update(over)
    return client.post("/tasks/", json=body)


def _notices_for(db, task_id):
    return db.query(Notice).filter(Notice.route == f"/tasks/{task_id}").all()


# ─── Who takes part ──────────────────────────────────────────────────────────

@pytest.mark.parametrize("who,utype", [
    ("owner", "manager"), ("ostaff", "staff"), ("etl", "staff"),
])
def test_outlet_accounts_and_etl_staff_are_shut_out_of_every_endpoint(
        act, team, who, utype):
    c = act(_as(team[who], utype))
    assert c.get("/tasks/").status_code == 403
    assert c.get("/tasks/people").status_code == 403
    assert c.get("/tasks/summary").status_code == 403
    assert c.get("/tasks/1").status_code == 403
    assert _give(c, "manager:1").status_code == 403
    assert c.post("/tasks/1/complete", json={}).status_code == 403


@pytest.mark.parametrize("who,utype", [
    ("head", "manager"), ("ops", "manager"), ("azimuth", "manager"),
    ("zone", "staff"), ("maint", "staff"), ("amaint", "staff"),
])
def test_heads_and_the_field_tier_can_use_tasks(act, team, who, utype):
    c = act(_as(team[who], utype))
    assert c.get("/tasks/").status_code == 200
    assert c.get("/tasks/people").status_code == 200


def test_a_head_can_pick_any_head_or_field_person_but_never_staff_or_vendors(act, db, team):
    _mgr(db, "Gone Head", "crownest_head", active=False)
    people = act(_as(team["head"], "manager")).get("/tasks/people").json()
    names = [p["name"] for p in people]
    assert set(names) == {"Omar Ops", "Zara Azimuth", "Manu Zone", "Mo Maint", "Ari Azmaint"}
    for absent in ["Asha Head", "Vik Vendor", "Olly Outlet", "Evan Etl", "Gone Head"]:
        assert absent not in names, absent
    assert names[0] == "Omar Ops"                 # heads first
    assert set(people[0]) == {"key", "name", "role", "role_label", "zone"}
    zone = next(p for p in people if p["name"] == "Manu Zone")
    assert zone["role_label"] == "Zone Head" and zone["zone"] == "Bennett University"


@pytest.mark.parametrize("who", ["zone", "maint", "amaint"])
def test_the_field_tier_can_only_pick_the_ops_head(act, team, who):
    people = act(_as(team[who], "staff")).get("/tasks/people").json()
    assert [p["name"] for p in people] == ["Omar Ops"]


@pytest.mark.parametrize("who", ["zone", "maint", "amaint"])
def test_the_field_tier_can_give_tasks_to_the_ops_head_and_nobody_else(act, db, team, who):
    c = act(_as(team[who], "staff"))
    ok = _give(c, f"manager:{team['ops'].id}")
    assert ok.status_code == 201 and ok.json()["assignee"]["name"] == "Omar Ops"
    other_field = "maint" if who == "zone" else "zone"
    for key in [f"manager:{team['head'].id}", f"manager:{team['azimuth'].id}",
                f"staff:{team[other_field].id}"]:
        r = _give(c, key)
        assert r.status_code == 403 and "Ops Head" in r.json()["detail"], key
    assert db.query(TeamTask).count() == 1


def test_heads_give_tasks_to_each_other_and_down_to_the_field(act, team):
    for giver, utype in [("head", "manager"), ("ops", "manager"), ("azimuth", "manager")]:
        c = act(_as(team[giver], utype))
        for to, ttype in [("head", "manager"), ("ops", "manager"), ("azimuth", "manager"),
                          ("zone", "staff"), ("maint", "staff"), ("amaint", "staff")]:
            if to == giver:
                continue
            assert _give(c, f"{ttype}:{team[to].id}").status_code == 201, (giver, to)


def test_nobody_can_give_a_task_to_etl_staff(act, db, team):
    c = act(_as(team["head"], "manager"))
    assert _give(c, f"staff:{team['etl'].id}").status_code == 400
    assert db.query(TeamTask).count() == 0


def test_same_numeric_id_in_the_other_table_is_a_different_person(act, team):
    """manager#1 (head) is excluded from their own directory, but staff#1 is not."""
    c = act(_as(team["head"], "manager"))
    keys = [p["key"] for p in c.get("/tasks/people").json()]
    assert "manager:1" not in keys and "staff:1" in keys


# ─── Giving a task ───────────────────────────────────────────────────────────

def test_zone_head_to_ops_and_head_to_ops(act, team):
    up = _give(act(_as(team["zone"], "staff")), f"manager:{team['ops'].id}")
    assert up.status_code == 201
    assert up.json()["assignee"]["name"] == "Omar Ops"
    assert up.json()["assigner"]["role_label"] == "Zone Head"

    across = _give(act(_as(team["head"], "manager")), f"manager:{team['ops'].id}")
    assert across.status_code == 201
    assert across.json()["status"] == "ASSIGNED"
    assert across.json()["proof_required"] is True          # ON by default


@pytest.mark.parametrize("assignee,detail", [
    ("manager:1", "yourself"),                 # self
    ("manager:999", "can't be assigned"),      # nobody
    ("nonsense", "Choose who"),                # malformed
    ("outlet:1", "Choose who"),                # unknown kind
])
def test_bad_assignees_are_rejected(act, team, assignee, detail):
    r = _give(act(_as(team["head"], "manager")), assignee)
    assert r.status_code == 400 and detail in r.json()["detail"]


def test_cannot_assign_to_a_vendor_or_a_deactivated_account(act, db, team):
    c = act(_as(team["head"], "manager"))
    assert _give(c, f"manager:{team['owner'].id}").status_code == 400
    assert _give(c, f"staff:{team['ostaff'].id}").status_code == 400
    team["ops"].is_active = False
    db.commit()
    assert _give(c, f"manager:{team['ops'].id}").status_code == 400
    assert db.query(TeamTask).count() == 0


def test_title_priority_zone_and_deadline_are_validated(act, team):
    c = act(_as(team["head"], "manager"))
    key = f"manager:{team['ops'].id}"
    assert _give(c, key, title="   ").status_code == 422
    assert _give(c, key, priority="asap").status_code == 422
    assert _give(c, key, court_id=9999).status_code == 400
    past = (dt.datetime.utcnow() - dt.timedelta(hours=1)).isoformat() + "Z"
    assert _give(c, key, due_at=past).status_code == 400

    ok = _give(c, key, title="  Fix the sign  ", priority="urgent",
               court_id=team["court"].id, proof_required=False,
               due_at="2099-01-01T10:00:00+05:30")
    assert ok.status_code == 201
    t = ok.json()
    assert t["title"] == "Fix the sign" and t["priority"] == "urgent"
    assert t["court_name"] == "Bennett University" and t["proof_required"] is False
    assert t["due_at"] == "2099-01-01T04:30:00Z"            # stored + returned as UTC


def test_assigning_notifies_only_the_assignee_with_a_deep_link(act, db, team):
    r = _give(act(_as(team["head"], "manager")), f"staff:{team['staff'].id}")
    tid = r.json()["id"]
    notices = _notices_for(db, tid)
    assert len(notices) == 1
    n = notices[0]
    assert n.type == "task_assigned" and n.audience == "role"
    assert n.recipient_staff_id == team["staff"].id and n.recipient_manager_id is None
    assert n.title == "New task from Asha Head" and "Check the freezer" in n.body

    # The assignee can open it from the inbox, route included…
    inbox = act(_as(team["staff"], "staff")).get("/notices/").json()["notices"]
    assert [x["route"] for x in inbox] == [f"/tasks/{tid}"]
    # …and manager#1, who shares the numeric id, sees nothing of it.
    assert act(_as(team["head"], "manager")).get("/notices/").json()["notices"] == []
    assert act(_as(team["ops"], "manager")).get("/notices/").json()["notices"] == []


# ─── Visibility: the two people, nobody else ─────────────────────────────────

def test_a_task_is_invisible_to_everyone_but_its_two_people(act, team):
    tid = _give(act(_as(team["head"], "manager")),
                f"manager:{team['ops'].id}").json()["id"]

    for who, utype in [("azimuth", "manager"), ("zone", "staff"), ("maint", "staff")]:
        c = act(_as(team[who], utype))
        assert c.get(f"/tasks/{tid}").status_code == 404, who
        assert c.get("/tasks/?box=mine&status=all").json()["tasks"] == [], who
        assert c.get("/tasks/?box=sent&status=all").json()["tasks"] == [], who
        assert c.post(f"/tasks/{tid}/comments", json={"note": "hi"}).status_code == 404, who
        assert c.post(f"/tasks/{tid}/complete", json={"photos": [PHOTO]}).status_code == 404, who
        assert c.post(f"/tasks/{tid}/cancel", json={}).status_code == 404, who
        assert c.get("/tasks/summary").json() == {
            "mine_open": 0, "mine_overdue": 0, "sent_open": 0, "sent_overdue": 0}, who

    assert act(_as(team["head"], "manager")).get(f"/tasks/{tid}").status_code == 200
    assert act(_as(team["ops"], "manager")).get(f"/tasks/{tid}").status_code == 200


def test_task_for_staff_1_is_not_visible_to_manager_1(act, team):
    """Overlapping ids across the two tables must never widen visibility."""
    tid = _give(act(_as(team["ops"], "manager")), "staff:1").json()["id"]
    assert act(_as(team["staff"], "staff")).get(f"/tasks/{tid}").status_code == 200
    assert act(_as(team["head"], "manager")).get(f"/tasks/{tid}").status_code == 404


# ─── Lifecycle ───────────────────────────────────────────────────────────────

def test_full_flow_seen_start_complete(act, db, team):
    giver = _as(team["head"], "manager")
    doer = _as(team["staff"], "staff")
    tid = _give(act(giver), "staff:1").json()["id"]

    t = act(doer).get(f"/tasks/{tid}").json()
    assert (t["i_am_assignee"], t["can_start"], t["can_complete"]) == (True, True, True)
    assert (t["can_reopen"], t["can_cancel"]) == (False, False)
    assert t["seen_at"] is None                              # a plain GET does not mark seen

    assert act(doer).post(f"/tasks/{tid}/seen").json()["seen_at"] is not None
    assert act(giver).post(f"/tasks/{tid}/seen").status_code == 200   # no-op
    started = act(doer).post(f"/tasks/{tid}/start").json()
    assert started["status"] == "IN_PROGRESS" and started["can_start"] is False

    done = act(doer).post(
        f"/tasks/{tid}/complete", json={"note": " all clean ", "photos": [PHOTO, PHOTO]}
    ).json()
    assert done["status"] == "DONE" and done["completion_note"] == "all clean"
    assert done["proof_photos"] == [PHOTO]                   # de-duplicated
    assert done["can_complete"] is False
    assert [e["kind"] for e in done["events"]] == ["created", "seen", "started", "completed"]
    assert done["events"][-1]["photos"] == [PHOTO] and done["events"][-1]["mine"] is True

    kinds = sorted(n.type for n in _notices_for(db, tid))
    assert kinds == ["task_assigned", "task_completed"]
    completed = next(n for n in _notices_for(db, tid) if n.type == "task_completed")
    assert completed.recipient_manager_id == team["head"].id
    assert "Manu Zone completed" in completed.body and "Proof attached" in completed.body

    view = act(giver).get(f"/tasks/{tid}").json()
    assert (view["i_am_assigner"], view["can_reopen"], view["can_cancel"]) == (True, True, False)


def test_only_the_assignee_starts_or_completes_and_only_the_assigner_reopens_or_cancels(
        act, team):
    giver = act(_as(team["head"], "manager"))
    tid = _give(giver, "staff:1").json()["id"]
    assert giver.post(f"/tasks/{tid}/start").status_code == 403
    assert giver.post(f"/tasks/{tid}/complete", json={"photos": [PHOTO]}).status_code == 403

    doer = act(_as(team["staff"], "staff"))
    assert doer.post(f"/tasks/{tid}/cancel", json={}).status_code == 403
    assert doer.post(f"/tasks/{tid}/complete", json={"photos": [PHOTO]}).status_code == 200
    assert doer.post(f"/tasks/{tid}/reopen", json={"note": "no"}).status_code == 403


def test_proof_is_enforced_when_required(act, team):
    giver = act(_as(team["head"], "manager"))
    tid = _give(giver, "staff:1").json()["id"]
    doer = act(_as(team["staff"], "staff"))

    r = doer.post(f"/tasks/{tid}/complete", json={"note": "done"})
    assert r.status_code == 400 and "proof photo is required" in r.json()["detail"]
    assert doer.get(f"/tasks/{tid}").json()["status"] == "ASSIGNED"

    for bad in ["https://evil.example/x.jpg", "uploads/maintenance/x.jpg",
                "uploads/team_tasks/../../etc/passwd"]:
        assert doer.post(f"/tasks/{tid}/complete", json={"photos": [bad]}).status_code == 400, bad
    too_many = [f"uploads/team_tasks/p{i}.jpg" for i in range(7)]
    assert doer.post(f"/tasks/{tid}/complete", json={"photos": too_many}).status_code == 400

    assert doer.post(f"/tasks/{tid}/complete", json={"photos": [PHOTO]}).status_code == 200


def test_assigner_can_switch_proof_off(act, team):
    tid = _give(act(_as(team["head"], "manager")), "staff:1",
                proof_required=False).json()["id"]
    done = act(_as(team["staff"], "staff")).post(f"/tasks/{tid}/complete", json={})
    assert done.status_code == 200 and done.json()["status"] == "DONE"
    assert done.json()["proof_photos"] == []


def test_reopen_sends_it_back_with_a_reason_and_keeps_the_old_proof_in_history(
        act, db, team):
    giver = act(_as(team["head"], "manager"))
    tid = _give(giver, "staff:1").json()["id"]
    doer = act(_as(team["staff"], "staff"))

    assert giver.post(f"/tasks/{tid}/reopen", json={"note": "x"}).status_code == 409   # not done yet
    doer.post(f"/tasks/{tid}/complete", json={"photos": [PHOTO], "note": "v1"})
    assert giver.post(f"/tasks/{tid}/reopen", json={"note": "  "}).status_code == 422  # reason needed

    back = giver.post(f"/tasks/{tid}/reopen", json={"note": "Shelf still dirty"}).json()
    assert back["status"] == "ASSIGNED" and back["reopen_count"] == 1
    assert back["proof_photos"] == [] and back["completion_note"] is None
    assert back["completed_at"] is None
    history = {e["kind"]: e for e in back["events"]}
    assert history["completed"]["photos"] == [PHOTO]         # rejected proof is not lost
    assert history["reopened"]["note"] == "Shelf still dirty"

    n = next(x for x in _notices_for(db, tid) if x.type == "task_reopened")
    assert n.recipient_staff_id == 1 and "Shelf still dirty" in n.body

    again = doer.post(f"/tasks/{tid}/complete", json={"photos": [PHOTO]})
    assert again.status_code == 200 and again.json()["status"] == "DONE"


def test_cancel_and_the_state_guards(act, db, team):
    giver = act(_as(team["head"], "manager"))
    doer = act(_as(team["staff"], "staff"))

    tid = _give(giver, "staff:1").json()["id"]
    gone = giver.post(f"/tasks/{tid}/cancel", json={"note": "not needed"}).json()
    assert gone["status"] == "CANCELLED" and gone["can_comment"] is False
    assert any(n.type == "task_cancelled" for n in _notices_for(db, tid))
    # nothing moves a cancelled task
    assert doer.post(f"/tasks/{tid}/start").status_code == 409
    assert doer.post(f"/tasks/{tid}/complete", json={"photos": [PHOTO]}).status_code == 409
    assert giver.post(f"/tasks/{tid}/cancel", json={}).status_code == 409
    assert giver.post(f"/tasks/{tid}/reopen", json={"note": "x"}).status_code == 409
    assert doer.post(f"/tasks/{tid}/comments", json={"note": "?"}).status_code == 409

    tid2 = _give(giver, "staff:1").json()["id"]
    doer.post(f"/tasks/{tid2}/complete", json={"photos": [PHOTO]})
    assert doer.post(f"/tasks/{tid2}/complete", json={"photos": [PHOTO]}).status_code == 409  # double tap
    assert doer.post(f"/tasks/{tid2}/start").status_code == 409
    assert giver.post(f"/tasks/{tid2}/cancel", json={}).status_code == 409                    # done ≠ cancellable
    assert sum(1 for n in _notices_for(db, tid2) if n.type == "task_completed") == 1


def test_comments_go_to_the_other_person(act, db, team):
    giver = act(_as(team["head"], "manager"))
    tid = _give(giver, "staff:1").json()["id"]
    doer = act(_as(team["staff"], "staff"))

    assert doer.post(f"/tasks/{tid}/comments", json={"note": ""}).status_code == 422
    r = doer.post(f"/tasks/{tid}/comments", json={"note": "Which freezer?"}).json()
    assert r["events"][-1]["kind"] == "comment" and r["events"][-1]["note"] == "Which freezer?"
    giver.post(f"/tasks/{tid}/comments", json={"note": "The big one"})

    comments = [n for n in _notices_for(db, tid) if n.type == "task_comment"]
    assert len(comments) == 2
    to_giver = next(n for n in comments if n.recipient_manager_id == team["head"].id)
    to_doer = next(n for n in comments if n.recipient_staff_id == 1)
    assert to_giver.title == "Manu Zone commented" and "Which freezer?" in to_giver.body
    assert to_doer.title == "Asha Head commented"


# ─── Lists and counts ────────────────────────────────────────────────────────

def test_boxes_filters_order_and_counts(act, db, team):
    head = _as(team["head"], "manager")
    ops = _as(team["ops"], "manager")
    key = f"manager:{team['ops'].id}"
    c = act(head)
    later = _give(c, key, title="later", due_at="2099-06-01T00:00:00Z").json()["id"]
    sooner = _give(c, key, title="sooner", due_at="2099-01-01T00:00:00Z").json()["id"]
    nodue = _give(c, key, title="no deadline", priority="urgent").json()["id"]
    done = _give(c, key, title="done one", proof_required=False).json()["id"]
    act(ops).post(f"/tasks/{done}/complete", json={})
    # one already overdue (deadline set directly: the API refuses past deadlines)
    late = _give(act(head), key, title="late").json()["id"]
    db.query(TeamTask).filter(TeamTask.id == late).update(
        {"due_at": dt.datetime.utcnow() - dt.timedelta(hours=3)})
    db.commit()

    mine = act(ops).get("/tasks/?box=mine&status=open").json()
    assert [t["title"] for t in mine["tasks"]] == ["late", "sooner", "later", "no deadline"]
    assert [t["is_overdue"] for t in mine["tasks"]] == [True, False, False, False]
    assert mine["summary"] == {"mine_open": 4, "mine_overdue": 1, "sent_open": 0, "sent_overdue": 0}

    assert [t["title"] for t in act(ops).get("/tasks/?box=mine&status=done").json()["tasks"]] == ["done one"]
    assert len(act(ops).get("/tasks/?box=mine&status=all").json()["tasks"]) == 5
    assert act(ops).get("/tasks/?box=sent&status=all").json()["tasks"] == []

    sent = act(head).get("/tasks/?box=sent&status=open").json()
    assert len(sent["tasks"]) == 4
    assert sent["summary"] == {"mine_open": 0, "mine_overdue": 0, "sent_open": 4, "sent_overdue": 1}
    assert act(head).get("/tasks/summary").json() == sent["summary"]

    page = act(ops).get("/tasks/?box=mine&status=open&limit=2&offset=0").json()
    assert len(page["tasks"]) == 2 and page["has_more"] is True
    last = act(ops).get("/tasks/?box=mine&status=open&limit=2&offset=2").json()
    assert len(last["tasks"]) == 2 and last["has_more"] is False
    assert act(ops).get("/tasks/?box=everyone").status_code == 422
    assert {later, sooner, nodue, late} == {t["id"] for t in mine["tasks"]}


# ─── Reminders ───────────────────────────────────────────────────────────────

def test_reminders_fire_once_each(act, db, team):
    c = act(_as(team["head"], "manager"))
    now = dt.datetime(2030, 1, 1, 12, 0, 0)
    soon = _give(c, "staff:1", title="soon", due_at="2099-01-01T00:00:00Z").json()["id"]
    far = _give(c, "staff:1", title="far", due_at="2099-01-01T00:00:00Z").json()["id"]
    late = _give(c, "staff:1", title="late", due_at="2099-01-01T00:00:00Z").json()["id"]
    done = _give(c, "staff:1", title="done", due_at="2099-01-01T00:00:00Z",
                 proof_required=False).json()["id"]
    act(_as(team["staff"], "staff")).post(f"/tasks/{done}/complete", json={})
    for tid, due in [(soon, now + dt.timedelta(minutes=90)), (far, now + dt.timedelta(hours=5)),
                     (late, now - dt.timedelta(hours=1)), (done, now - dt.timedelta(hours=1))]:
        db.query(TeamTask).filter(TeamTask.id == tid).update({"due_at": due})
    db.commit()

    assert svc.run_task_reminders(db, now) == {"due_soon": 1, "overdue": 1}

    def kinds(tid):
        return sorted(n.type for n in _notices_for(db, tid) if n.type in ("task_due_soon", "task_overdue"))

    assert kinds(soon) == ["task_due_soon"]
    assert kinds(far) == []                                  # not within the window yet
    assert kinds(late) == ["task_overdue", "task_overdue"]   # the doer AND the giver
    assert kinds(done) == []                                 # finished work is never chased
    overdue = [n for n in _notices_for(db, late) if n.type == "task_overdue"]
    assert {(n.recipient_staff_id, n.recipient_manager_id) for n in overdue} == {
        (1, None), (None, team["head"].id)}

    # a second pass an hour later sends nothing new for the same tasks…
    assert svc.run_task_reminders(db, now + dt.timedelta(minutes=15)) == {"due_soon": 0, "overdue": 0}
    # …and when "soon" finally slips past its deadline it gets its one overdue notice
    assert svc.run_task_reminders(db, now + dt.timedelta(hours=2)) == {"due_soon": 0, "overdue": 1}
    assert kinds(soon) == ["task_due_soon", "task_overdue", "task_overdue"]


# ─── Photo upload ────────────────────────────────────────────────────────────

def test_upload_returns_a_path_complete_accepts(act, team, tmp_path, monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "UPLOAD_DIR", str(tmp_path))
    doer = act(_as(team["staff"], "staff"))
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 64
    r = doer.post("/tasks/upload-photo", files={"photo": ("p.png", png, "image/png")})
    assert r.status_code == 201
    path = r.json()["photo_url"]
    assert path.startswith("uploads/team_tasks/task_") and path.endswith(".png")
    assert (tmp_path / "team_tasks" / path.rsplit("/", 1)[1]).exists()

    tid = _give(act(_as(team["head"], "manager")), "staff:1").json()["id"]
    assert doer.post(f"/tasks/{tid}/complete", json={"photos": [path]}).status_code == 200

    bad = doer.post("/tasks/upload-photo", files={"photo": ("p.txt", b"hi", "text/plain")})
    assert bad.status_code == 400
    owner = act(_as(team["owner"], "manager"))
    assert owner.post("/tasks/upload-photo",
                      files={"photo": ("p.png", png, "image/png")}).status_code == 403


# ─── Regression guards for what this feature touched elsewhere ───────────────

def test_other_notices_still_have_no_route(act, db):
    from conftest import seed_notice
    seed_notice(db, title="plain")
    n = act(make_user("etl_manager")).get("/notices/").json()["notices"][0]
    assert n["title"] == "plain" and n["route"] is None


def test_push_payload_route_defaults_to_the_inbox(db, monkeypatch):
    """A notice without its own screen still deep-links to /notices; a task
    notice deep-links to the task."""
    from app.services import notice_service

    sent = []
    monkeypatch.setattr(notice_service, "resolve_notice_targets", lambda db, n: ["tok"])
    monkeypatch.setattr(notice_service.fcm_service, "fire_push",
                        lambda factory: sent.append(factory))
    captured = {}

    async def _fake_send(tokens, *, title, body, data, badge=None):
        captured.setdefault("routes", []).append(data["route"])

    monkeypatch.setattr(notice_service, "_send_and_prune", _fake_send)

    notice_service.create_notice(db, audience="manager", type="early_logout", title="A")
    notice_service.create_notice(db, audience="role", type="task_assigned", title="B",
                                 recipient_manager_id=None, route="/tasks/7")
    import asyncio
    for factory in sent:
        asyncio.run(factory())
    assert captured["routes"] == ["/notices", "/tasks/7"]


def test_registering_the_same_token_twice_at_once_does_not_500(act, db, monkeypatch):
    """Sign-in and token-refresh can both register the same new token together.
    The second insert used to hit the UNIQUE index and surface as a 500."""
    from app.api.routes import devices as devices_routes
    from app.models.device_token import DeviceToken

    user = make_user("crownest_head", uid=5)
    c = act(user)

    # Simulate the race: the lookup says "no row" although one was just inserted.
    db.add(DeviceToken(user_type="manager", user_id=99, fcm_token="fcm-token-0001",
                       platform="ios", is_active=True))
    db.commit()
    real_query = db.query
    state = {"first": True}

    def racing_query(*a, **k):
        q = real_query(*a, **k)
        if a and a[0] is DeviceToken and state["first"]:
            state["first"] = False

            class _Blind:
                def filter(self, *_a, **_k):
                    return self

                def first(self):
                    return None
            return _Blind()
        return q

    monkeypatch.setattr(db, "query", racing_query)
    r = c.post("/devices/register", json={"fcm_token": "fcm-token-0001", "platform": "ios"})
    assert r.status_code == 200, r.text
    assert r.json()["transferred"] is True
    rows = real_query(DeviceToken).filter(DeviceToken.fcm_token == "fcm-token-0001").all()
    assert len(rows) == 1 and (rows[0].user_type, rows[0].user_id) == ("manager", 5)
    assert devices_routes is not None
