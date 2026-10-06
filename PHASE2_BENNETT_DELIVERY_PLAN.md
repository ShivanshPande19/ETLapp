# Phase 2 — Bennett University In-House Food Delivery

> Design plan for adding an **in-house, multi-outlet food delivery system** to the
> existing ETL app, scoped to the **Bennett University** zone (court). Students
> order from multiple brands in one cart; we deliver university → hostel. This
> document is a plan/architecture proposal, not code.

---

## 1. Goal (in one line)

A student opens the app, browses every Bennett outlet's live menu, builds **one
cart across multiple outlets**, pays **once**, and we (a) split the money to each
outlet automatically, (b) get each outlet to prepare their part, (c) have a
delivery partner pick up (with proof) and deliver to the hostel (with proof),
and (d) handle every failure (out-of-stock / missing item / outlet offline) with
the correct **partial refund**.

---

## 2. Reuse — what already exists (we are NOT starting from zero)

The current app already gives us a lot of the delivery backbone for free:

| Existing capability | Reused for delivery as |
|---|---|
| **Courts / zones** (`Court`, Bennett University = court `id=4`) | The delivery zone; zone open/close + delivery config hang off this. |
| **Outlets** (`Outlet`, per-outlet `pos_source` = petpooja/rista/royal) | The brands students order from; each already has POS config. |
| **Multi-POS adapters** (`sales_sources/*`) | Later: push orders into the POS where the POS supports it. |
| **Roles / RBAC** (`deps.py` role taxonomy) | Add `student`, `delivery_partner`, `delivery_head`; outlet_manager extends. |
| **Outlet manager login** | Gets menu + online/offline + incoming-orders screens. |
| **Geofenced attendance + selfie** (`attendance.py`, `_enforce_geofence`, uploads) | Delivery partner shift + geofenced check-in; same photo/upload plumbing. |
| **FCM push** (`push_targeting.py`, `fcm_service`) | Order/assignment/ready/delivered notifications to all actors. |
| **Uploads** (`core/uploads.py`, `/uploads` static mount) | Pickup + handover proof photos. |
| **Notices** | In-app order updates / disputes. |

**New surfaces to build:** a **Student app** (browse/cart/pay/track), a
**Delivery partner app** (assigned orders + proof photos), a **Dispatcher
console** for the delivery head, and **menu/online-offline/incoming-orders** in
the existing outlet-manager app.

---

## 3. Actors & roles (extend `deps.py` taxonomy)

| Role | New? | Does what |
|---|---|---|
| `student` | NEW | Browse menus, cart, pay, track, rate, request refund. |
| `outlet_manager` | exists | Manage menu, toggle outlet/item online-offline + out-of-stock, accept/prepare/ready incoming orders. |
| `delivery_partner` | NEW (staff-like) | Shift (geofenced check-in), see assigned orders, pickup (photo), deliver (photo). |
| `delivery_head` (dispatcher) | NEW | Assign orders → partners, monitor load, **open/close the zone for delivery**, resolve disputes. |
| management / `crownest_zone_manager` | exists | Oversight dashboards (delivery sales, SLAs) — read-only, zone-scoped (zone manager already works this way). |

---

## 4. High-level architecture

```
  STUDENT APP ──┐                              ┌── OUTLET-MANAGER APP
  (browse,      │                              │   (menu, online/offline,
   cart, pay,   │        ETL BACKEND           │    incoming orders KDS-lite)
   track)       │   (FastAPI, same codebase)   │
                ▼                              ▼
        ┌────────────────────────────────────────────┐
        │  Delivery module                            │
        │  • menus / stock / outlet online-offline    │
        │  • cart → ONE order → N per-outlet suborders │
        │  • payment (split) + refunds                │
        │  • dispatch + delivery lifecycle            │
        │  • zone delivery config (open/close)        │
        └───────┬───────────────┬───────────────┬─────┘
                │               │               │
         Payment Aggregator   POS adapters     FCM / uploads
        (Razorpay Route /     (push where       (notifications,
         Cashfree Easy Split)  supported)        proof photos)
                                                │
  DELIVERY-PARTNER APP ◄── Dispatcher console (delivery_head) ──►
```

Everything lives in the **same backend/app** — delivery is a new module + new
screens, not a new product.

---

## 5. PROBLEM 1 — Payment: one checkout, money to each outlet

### 5.1 The core idea
A student's cart has items from (say) 3 outlets. They pay **once** for the grand
total. We must route **each outlet's share to that outlet**, keep our
**commission + delivery fee**, and still be able to **refund** a single item.

Doing this yourself (collecting into your account and paying outlets manually)
is both operationally painful **and** an RBI compliance problem — holding and
settling other merchants' money needs a payment-aggregator licence. The clean,
compliant way is to use a **split-settlement payment aggregator**, which does
the collect-split-settle for you.

### 5.2 Recommendation — Razorpay Route (primary) / Cashfree Easy Split (alt)
Both are built exactly for marketplaces: take **one** customer payment, split it
across **multiple linked seller accounts**, deduct your commission, and process
refunds/settlements automatically.

- **Razorpay Route** — collect one payment, create **transfers** to each outlet's
  **Linked Account**; supports transfer **reversals** for refunds, configurable
  settlement cycles, and a dashboard. ([Razorpay Route docs](https://razorpay.com/docs/payments/route/))
- **Cashfree Easy Split** — same model: collect, deduct commission, split to
  **vendors**, with built-in refund adjustment and flexible settlement schedules.
  ([Cashfree Easy Split docs](https://www.cashfree.com/docs/payments/split/overview))

**Recommendation: start with Razorpay Route** (largest ecosystem, simplest
Orders→Transfers API, strong Flutter/standard checkout support). Cashfree is a
drop-in alternative if pricing/onboarding favours it.
*(Both descriptions rephrased for licensing compliance.)*

### 5.3 One-time: onboard each outlet as a payout account
Each outlet becomes a **Linked Account** (Razorpay) / **Vendor** (Cashfree) with
its **KYC + bank details**. We store the mapping:

```
outlet_payout_accounts(outlet_id, provider, linked_account_id, kyc_status, active)
```

This is an onboarding step per outlet (the outlet owner provides bank + KYC
once). Until KYC is `activated`, that outlet can't be settled → keep it delivery-
disabled.

### 5.4 Checkout flow (single payment → auto split)
```
1. Student cart = items from outlets A, B, C.
2. Backend computes: subtotal_A, subtotal_B, subtotal_C,
   + delivery_fee + platform_commission + taxes  = GRAND TOTAL.
3. Create ONE payment order (Razorpay Order) for GRAND TOTAL, with the
   split instruction: transfer subtotal_A → A, subtotal_B → B, subtotal_C → C;
   platform keeps (commission + delivery_fee).
4. Student pays once (UPI/card) in the in-app checkout.
5. On "payment captured" webhook → each outlet's transfer is created/settled by
   the aggregator on its settlement cycle. We mark suborders PAID.
```
- **We never touch the raw money flow** — the aggregator holds & settles. We only
  instruct the split and read webhooks. (Compliance ✔, reconciliation ✔.)
- **Commission / delivery fee** is simply the portion NOT transferred to outlets.

### 5.5 Refunds (ties into Problem 3)
- Item/suborder refund → **partial refund** on the original payment for that
  amount **and** reverse (or reduce) that outlet's transfer. Both Razorpay Route
  and Cashfree Easy Split support refunds that adjust the vendor's settlement.
- We persist every refund (`refunds` table) with reason + gateway refund id +
  status, and reconcile against webhooks.

### 5.6 MDR / cost note
Payment-gateway MDR applies (UPI/cards). Build a small **commission + delivery
fee** into every order to cover MDR + delivery-partner payout + platform margin.
Confirm current MDR slabs with the chosen aggregator before going live.

---

## 6. PROBLEM 2 — Orders must reflect in each outlet's POS

### 6.1 The honest constraint
Our existing POS adapters are **read-only** (they *pull* completed sales for
`DailySaleCache`). **Pushing a new order INTO a POS is a different API and is
POS-specific.** Researched capability (Oct 2026):

| POS | Order-push into POS? | How |
|---|---|---|
| **Petpooja** | ✅ **Yes** | Online Ordering / Orders API — `POST /save_order` "push a new order into the Petpooja POS" (the same mechanism Swiggy/Zomato use); Stores API for store on/off + item stock. Auth: `access-token` header, per outlet. Must be enabled as an integration partner per outlet. |
| **Rista** | ✅ **Yes** | REST API `api.ristaapps.com/v1` with `sale` (orders), `catalog` (menu), `inventory` (stock) resources (JSON). Per-outlet API key required. |
| **Royal POS** | ⚠️ **Not confirmed (treat as no push)** | Only the read-only `get_completed_orders_item_wise_dynamic` endpoint is known. No public order-push API found (small POS, Swiftomatics). Must confirm with the vendor; until then, Royal outlets use the in-app fallback. |

So POS-push **cannot be a hard dependency** — Petpooja & Rista can receive pushed
orders; Royal (for now) cannot.

**Two operational prerequisites for push (Petpooja/Rista):**
1. **Partner enablement** — the online-ordering API must be enabled + credentials
   issued **per outlet** (like becoming a Swiggy/Zomato partner). One-time setup.
2. **Menu-ID mapping** — `save_order` references the POS's own item IDs, so for
   Petpooja/Rista outlets we **import the menu from the POS** (ids + prices) and
   students order against those ids. Royal outlets get a manual in-app menu.

### 6.2 Two-layer design (works for ALL outlets)
1. **Primary (universal): in-app order management.** The outlet-manager app gets
   an **"Incoming Orders" KDS-lite** screen: new order → push notification + sound
   → **Accept → Preparing → Ready**. This works for **every** outlet regardless of
   POS. This is the source of truth for the delivery order's kitchen state.
2. **Optional: POS push** where an API exists (Petpooja first), behind a
   per-outlet flag `pos_push_enabled`. When on, we also inject the order so the
   outlet's own POS/KDS, inventory and their reporting stay in sync.

### 6.3 Avoid double-counting with the existing sales sync
Our sales sync **pulls completed orders** from the POS into `DailySaleCache`. If a
delivery order is **also** pushed into the POS, it would be counted **twice**
(once as a delivery order in our DB, once via the POS pull).

**Refined by the POS research:**
- **Push outlets (Petpooja/Rista):** a pushed delivery order becomes a POS order,
  so the **existing sales sync already captures it** in `DailySaleCache` — POS is
  the single source of truth. Do **not** separately add these to delivery revenue
  (tag them so reporting doesn't double-count).
- **Non-push outlets (Royal):** the delivery order lives only in our system, so we
  **do** count its revenue from our own tables (`source = "etl_delivery"`).

So the double-count rule follows the push flag per outlet, not a blanket choice.

---

## 7. PROBLEM 3 — Ordering flow, state machine & refund scenarios

### 7.1 Order model: one order, per-outlet suborders, line items
```
delivery_order
  └── delivery_suborder (one per outlet)      ← accept/reject + settlement unit
        └── delivery_order_item (line items)  ← out-of-stock / refund unit
```

### 7.2 State machine
**Order:** `CREATED → PAID → CONFIRMED → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED → COMPLETED`
(+ `CANCELLED`, `PARTIALLY_REFUNDED`, `REFUNDED`).

**Suborder (per outlet):** `PENDING_ACCEPT → ACCEPTED → PREPARING → READY → PICKED_UP`
(or `REJECTED` → refund that outlet's amount).

### 7.3 Every scenario → what happens
| Scenario | Handling |
|---|---|
| Outlet is **offline** when ordering | Student can't add its items (menu shows "closed"); never enters cart. |
| Outlet **doesn't accept** within SLA (e.g. 2 min) | Auto-reject that suborder → **partial refund** of its amount; rest of order proceeds. |
| **Item out of stock** (outlet forgot to mark) — caught at accept | Outlet marks item unavailable → **item-level refund** to student; rest of suborder proceeds (or student is asked to confirm). |
| **Missing item caught at pickup** (delivery partner's photo check) | Partner flags discrepancy → dispatcher confirms → **item refund**; delivery continues with the rest. |
| **Whole outlet can't fulfil** | Reject suborder → refund its full amount; other outlets' items still delivered. |
| **Student cancels before any acceptance** | **Full refund.** |
| **Student cancels after preparing** | No refund (configurable) — food already made. |
| **Not delivered / wrong handover dispute** | Resolved via the **handover photo** (§8). |

### 7.4 Refund mechanics
All refunds go through the aggregator: **partial refund** on the original payment
for the exact item/suborder amount **+** reverse/reduce that outlet's transfer, so
the outlet isn't paid for what it didn't deliver. Every refund is logged and
reconciled against the aggregator's webhook.

---

## 8. PROBLEM 4 — Delivery: partner app + dispatcher + proof + zone control

### 8.1 Delivery partner app (role `delivery_partner`, modelled like staff)
- **Shift / attendance:** reuse the existing **geofenced check-in + selfie** — a
  partner must be on-shift inside the zone to receive orders.
- **Assigned orders list:** only orders the dispatcher assigned to them.
- **Pickup:** at the outlet, **MANDATORY photo** of all items on handover (proof
  that everything is present — kills "missing item" disputes). Marks `PICKED_UP`.
- **Deliver:** at the hostel, **MANDATORY handover photo** (proof of delivery —
  kills false "not delivered" claims). Marks `DELIVERED`.
- Optional later: live location for in-transit tracking.

### 8.2 Dispatcher console (role `delivery_head`)
- Live board of all zone orders (new / preparing / ready / out-for-delivery).
- **Assign** an order (or batch) → a specific delivery partner. (Manual now;
  distance/load auto-assign later.)
- **Open/Close the zone for delivery** — a zone-level switch. When **closed**
  (too many orders, too few partners), the **student app stops taking new
  delivery orders** ("Delivery paused, back soon") so load stays manageable.
- See every proof photo; resolve disputes/refunds.

### 8.3 Zone delivery config (hangs off the Court/zone)
```
zone_delivery_config(court_id, delivery_open, open_from, open_to,
                     max_active_orders, base_delivery_fee, ...)
```
Bennett University (court 4) gets one row. `delivery_open=false` → student app
blocks new orders instantly.

### 8.4 Proof photos
Both pickup and handover photos use the **existing uploads** pipeline and are
attached to the order, visible to dispatcher + management for any dispute.

---

## 9. Menu management (outlet-manager app)

New screens for the existing outlet-manager login:
- **Menu builder:** categories + items (name, price, veg/non-veg, description,
  photo). Per item: **in-stock / out-of-stock** toggle.
- **Online/Offline:** one switch to open/close the whole outlet for delivery.
- **Incoming Orders (KDS-lite):** accept / preparing / ready (Problem 2 §6.2).

**Menu source:** manual entry in-app is the **universal baseline** (works for
every POS). Optional later: import menu from Petpooja's menu API for Petpooja
outlets to save typing.

---

## 10. Data model additions (new tables)

```
students(id, name, phone, email, hostel, block, room, created_at)          -- or extend a generic users table
menu_categories(id, outlet_id, name, sort_order)
menu_items(id, outlet_id, category_id, name, price, is_veg, description,
           image_url, is_available, is_active)
outlet_delivery_profile(outlet_id, is_online, prep_time_min, pos_push_enabled)
zone_delivery_config(court_id, delivery_open, open_from, open_to,
                     max_active_orders, base_delivery_fee)

delivery_order(id, student_id, court_id, status, items_total, delivery_fee,
               commission, grand_total, payment_status, address_hostel,
               address_room, created_at, ...)
delivery_suborder(id, order_id, outlet_id, status, subtotal, pos_pushed,
                  pos_ref, transfer_id, settlement_status, rejected_reason)
delivery_order_item(id, suborder_id, menu_item_id, name_snapshot, qty,
                    unit_price, status[active|refunded], refund_id)

payments(id, order_id, provider, provider_order_id, provider_payment_id,
         amount, status)
refunds(id, order_id, suborder_id, item_id, amount, reason,
        provider_refund_id, status, created_at)
outlet_payout_accounts(id, outlet_id, provider, linked_account_id, kyc_status, active)

delivery_partner(id, name, phone, court_id, is_active, is_online)            -- staff-like
delivery_assignment(id, order_id, partner_id, assigned_by, status,
                    pickup_photo_url, picked_up_at,
                    handover_photo_url, delivered_at)
```
(Reuse `Court`, `Outlet`, existing manager/staff + roles.)

---

## 11. End-to-end lifecycle (the "proper flow")

```
STUDENT
  1. Opens app → zone = Bennett University.
     If zone_delivery_config.delivery_open = false → "Delivery paused."
  2. Browses outlets (only ONLINE outlets, only IN-STOCK items shown).
  3. Adds items from outlet A, B, C → one cart.
  4. Checkout: sees items + delivery fee + taxes = grand total.
  5. Pays ONCE (Razorpay checkout, UPI/card).

BACKEND (on payment captured)
  6. Create delivery_order (PAID) + 3 suborders (A,B,C) = PENDING_ACCEPT.
  7. Split instruction recorded: A→A acct, B→B acct, C→C acct, platform keeps
     commission + delivery fee (settled by aggregator on cycle).
  8. FCM → each outlet: "New order."  FCM → dispatcher: "New order to assign."

OUTLETS (each independently, on their Incoming-Orders screen)
  9. Accept (→ ACCEPTED → PREPARING). If an item is out of stock → mark it →
     item refund to student. If not accepted in SLA → auto-reject → refund that
     suborder. (POS push happens here if pos_push_enabled.)
 10. Mark Ready when done.

DISPATCHER (delivery_head)
 11. Assigns the order to an on-shift delivery partner (sees which outlets +
     pickup points). Can batch nearby orders.

DELIVERY PARTNER
 12. Goes to each outlet, collects items, takes MANDATORY pickup photo
     (all items present) → PICKED_UP. Discrepancy → flag → refund.
 13. Order → OUT_FOR_DELIVERY. Delivers to hostel/room.
 14. Takes MANDATORY handover photo → DELIVERED.

CLOSE-OUT
 15. Order → COMPLETED. Student can rate. Any dispute uses the two photos.
 16. Aggregator settles each outlet its share (minus refunds); platform keeps
     commission + delivery fee.
```

---

## 12. Notifications (reuse FCM)
- Student: order confirmed → preparing → out for delivery → delivered → refund.
- Outlet: new order (with sound), auto-reject warning near SLA.
- Delivery partner: new assignment, pickup/handover reminders.
- Dispatcher: new order to assign, SLA breaches, disputes.

---

## 13. Non-functionals
- **Security/scoping:** everything zone-scoped (reuse the zone-manager pattern);
  students only see their zone; outlets only their own orders; partners only
  their assignments.
- **Geofence/attendance:** reuse existing geofenced check-in for partners.
- **Idempotency & webhooks:** payment/refund/transfer webhooks must be
  idempotent and reconciled (never trust client success alone).
- **Audit:** every state change + photo + refund logged.

---

## 14. Phased rollout (ship value early, de-risk the hard parts)

| Phase | Scope | Why |
|---|---|---|
| **2.0** | Menus + outlet online/offline + out-of-stock + student browse (no ordering) | Foundation; outlets build menus; zero payment risk. |
| **2.1** | Cart + **single-outlet** order + **Razorpay** payment + outlet Incoming-Orders screen | Prove payment + order management on the simplest case. |
| **2.2** | **Multi-outlet** cart + **Route split** + refunds | The hard payment piece, once single-outlet is solid. |
| **2.3** | Delivery-partner app + dispatcher console + assignment + **proof photos** + **zone open/close** | The delivery operation. |
| **2.4** | POS push (Petpooja), live tracking, auto-assign, ratings, COD (if wanted) | Enhancements. |

---

## 15. Open decisions / questions (need your call before building)

1. **Merchant / compliance:** Who is the merchant-of-record for delivery — ETL
   (platform) with outlets as sub-merchants (Razorpay Route model)? Are outlets
   willing to do **KYC + bank linking** once? (Required for split settlement.)
2. **Commission + delivery fee model:** flat delivery fee? % commission per
   outlet? Who bears MDR? (Drives the split math.)
3. **POS push priority:** Do you want order-push into Petpooja from day one, or
   is the in-app Incoming-Orders screen enough initially (universal, no POS
   dependency)? Does Rista/Royal have an order-push API we can get creds for?
4. **Sales reporting:** should delivery revenue be a **separate stream** from
   dine-in POS sales (recommended), or merged? (Affects double-counting.)
5. **Student auth:** college email / phone OTP / both? Any restriction to Bennett
   students only?
6. **Payments extras:** Cash-on-delivery allowed? GST invoice per outlet needed?
7. **Delivery ops:** partner payout model (per-delivery / salary)? Max delivery
   radius = hostels only?

---

### Suggested first build (once §15 is answered)
Start with **Phase 2.0 + 2.1** on a feature branch:
menu + online/offline + student browse + **single-outlet** order with Razorpay +
the outlet Incoming-Orders screen. This proves the payment + order loop end-to-end
on the lowest-risk path, before we add the multi-outlet split and the delivery
operation.
