# Role Split + Maintenance Ticket Restructure — Requirements

> Status: **DRAFT for review** · Owner: ETL · Last updated: 2026-09

This document is the locked functional blueprint. It is the single source of
truth for the design (`design.md`) and tasks (`tasks.md`). Nothing here should
be implemented until it is confirmed.

---

## 0. Context

The company operates in two orgs:

- **Azimuth** — builds the trucks / kiosks and does their maintenance.
- **Crownest** — runs court operations ("ops") and expansion.

**"Eat Truck Love" (ETL)** is the brand for the **zones**; a **zone = one court**
(e.g. *Central 50*, *Bennett*) — NOT a group of courts.

Today a single `etl_manager` role has full, unrestricted access. This feature
splits that into **five ETL-side roles** across the two orgs and introduces a
richer maintenance-ticket + notification model.

---

## 1. Roles

### 1.1 New roles

| # | Role key | Org | Table | Access | Ticket power | Attendance |
|---|----------|-----|-------|--------|--------------|------------|
| 1 | `azimuth_management` | Azimuth | Manager | **Full** company-wide (todays etl_manager) | view + escalation notices | — |
| 2 | `azimuth_maintenance` | Azimuth | Staff | **Narrow**: only its tickets + Settings | resolve/close + assign technician | — |
| 3 | `crownest_ops_head` | Crownest | Manager | **Full** company-wide | **RAISE** + tag/divert + view | — |
| 4 | `crownest_head` | Crownest | Manager | **Full** company-wide | view + escalation notices | — |
| 5 | `crownest_maintenance_head` | Crownest | Staff | **Narrow**: only its tickets + Settings + **own attendance** | resolve/close + assign technician | **Yes** (like etl_staff) |

- "**Ops head**" and "**ops manager**" are the same role = `crownest_ops_head`.
- The three **management** roles (`azimuth_management`, `crownest_ops_head`,
  `crownest_head`) all get **identical full access** to everything today's
  `etl_manager` sees (all zones/outlets/sales/etc). Their only differences are
  notification behaviour and that **only** `crownest_ops_head` can raise tickets.
- The two **maintenance** roles are worker accounts with a narrow view.

### 1.2 Existing roles (unchanged)
`outlet_manager`, `outlet_staff`, `etl_staff` behave as today, except for the
new ticket-triage flow (see §3.4).

### 1.3 Technicians are NOT accounts
A maintenance head can assign a **technician (name + phone)** on a ticket
(reusing the existing `technician_name` / `technician_phone`). If none is
assigned, the ticket shows the **head's own name + phone**.

### 1.4 Zones & multiplicity
- `azimuth_maintenance` — **single** account (stays single even as zones grow).
- `crownest_maintenance_head` — **may become multiple, one per zone** in future.
  Each is tied to a zone (court). Design must not hard-code "exactly one".

### 1.5 Migration of existing accounts
- The current live `etl_manager` (`manager@etl.com`) becomes **`crownest_head`**.
- Legacy `etl_manager` / `manager` role values keep **full access** during
  transition (treated as management) so nothing breaks on deploy; accounts are
  then reassigned to precise roles via the admin screen.

---

## 2. Account administration

- **Only the three management roles** may create/assign accounts.
- The **maintenance accounts are NOT self-serviceable** — they can only be
  created by a management role.
- The existing "Manage ETL Managers" screen is generalised to **create an
  account + assign any of the 5 roles** (+ zone where the role needs one).
  Activation reuses the existing set-password magic-link flow (creator never
  handles a password).

---

## 3. Maintenance tickets

### 3.1 Ticket scope (type)
- **General** — court-level work (e.g. early-day missing/pending items for the
  whole court or azimuth-set outlets). No specific outlet.
- **Outlet-specific** — tied to one outlet, chosen from a picker showing that
  court's outlets.

### 3.2 Targets (flexible / future-proof)
A ticket may be targeted to **`azimuth_maintenance`, `crownest_maintenance_head`,
or BOTH** (a task may need both teams to contribute). The data model must allow
one or many targets, not a single fixed one.

### 3.3 Mentions
The raiser may **mention** additional recipients who should also be notified —
either a **role** or a **specific individual account**. A mentioned party is
always notified immediately (see §4), even if they are not a target.

### 3.4 Who raises, and triage
- `crownest_ops_head` raises directly and sets the target(s)/mentions.
- `outlet_manager` / `outlet_staff` raise as today, but the ticket first lands
  with `crownest_ops_head` (**triage**). The ops head then sets target(s)
  /divert. (Outlet-raised tickets are not auto-assigned to a maintenance team.)

### 3.5 Lifecycle (unchanged)
`RAISED → ASSIGNED → RESOLVED → CLOSED | DISPUTED`, incl. the existing 24h
verification window and auto-close. Resolve/close/assign are now performed by
the **targeted maintenance role(s)** (not only managers).

### 3.6 Ticket visibility
- `azimuth_maintenance` / `crownest_maintenance_head` — see **only** tickets
  where they are a **target or a mention**.
- The three management roles — see **all** tickets (filterable by zone).

---

## 4. Notifications & reminders (LOCKED)

Terminology: "**management tier**" = `azimuth_management` **and** `crownest_head`
(they behave identically for notifications). `crownest_ops_head` is the raiser
and is not separately notified for tickets it raises.

### 4.1 6-hour reminder (assignee only)
- Sent **only to the ticket's targeted maintenance role(s)**.
- Repeats **every 6 hours while the ticket is OPEN** (not CLOSED).
- **Only between 09:00–21:00 IST** (quiet hours 21:00–09:00 — never disturb).
- Stops immediately when the ticket closes.

### 4.2 Initial + escalation matrix

| Recipient | Target includes **`azimuth_maintenance`** | Target is **only `crownest_maintenance_head`** |
|-----------|-------------------------------------------|------------------------------------------------|
| Targeted maintenance role (assignee) | Immediate + 6h reminder | Immediate + 6h reminder |
| Management tier (`azimuth_management` + `crownest_head`) | **Immediate (once)** + **2-day** "still open" escalation | **No immediate** → **4-day** "still open" escalation only |
| Mentioned party (role/individual) | Immediate (always) | Immediate (always) |

- Escalations fire **only if the ticket is still OPEN** at 2 / 4 days, and each
  fires **once**.
- If **both** teams are targeted, the **azimuth rule** applies (immediate to
  management tier + 2-day escalation).
- **Quiet hours (09:00–21:00) apply ONLY to the 6h reminder.** Immediate and
  escalation notices may be sent any time.
- **Urgent + mention** override: an urgent ticket that mentions
  `azimuth_maintenance` notifies them immediately regardless of target.

### 4.3 Delivery
All notifications use the existing pipeline: persisted in-app Notice + SSE live
refresh + FCM push. Targeting is extended to resolve **by role** (see design).

---

## 5. Frontend / UI

> **Theme rule:** all new/redesigned screens must stay **within the existing app
> theme** (colours, typography, components) — no visual divergence.

### 5.1 New role screens
- **`azimuth_maintenance`** — simple: Home = list of tickets assigned/mentioned
  to them (with the existing resolve/assign-technician actions, plus new
  target/mention info) + a Settings page. Nothing else. Light redesign OK.
- **`crownest_maintenance_head`** — same tickets home + Settings + **own
  attendance** (identical to how `etl_staff` marks attendance).

### 5.2 Ops-head raise-ticket flow
- Choose scope (general / outlet-specific); outlet picker for outlet-specific.
- Select target(s): `azimuth_maintenance` and/or `crownest_maintenance_head`.
- Mention picker (roles and/or individuals).
- Priority incl. **urgent**.
- Clean UI, on theme.

### 5.3 Ticket UI redesign
- Outlet-side raise + the ops-head triage view + ticket detail (targets,
  mentions, technician-or-head contact, status, timeline). On theme.

### 5.4 Roster / calendar
- `crownest_maintenance_head` appears in the **existing roster + calendar** that
  managers view (same as staff), with a **"Maintenance Head" badge**.

### 5.5 Admin (account management)
- Generalised "Manage Accounts" screen: create account + assign any of the 5
  roles (+ zone where needed). Only management roles can open it.

---

## 6. Out of scope (for now)
- Per-team separate technician assignment on a single multi-target ticket
  (v1 keeps one technician assignment per ticket; note as future).
- Cloudflare/Jio networking fix (tracked separately).
- Any change to sales / onboarding / feedback modules.

---

## 7. Open confirmations
1. Modelling `azimuth_maintenance` + `crownest_maintenance_head` as **Staff**
   rows (Manager = full-access management; Staff = narrow worker) — see design.
2. Whether the management tier for an azimuth-target ticket should be notified
   for **outlet-raised-then-triaged** tickets at raise time or only at triage.
