# app/api/routes/events.py
from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
import asyncio
import json
import logging

from ..deps import get_current_user, CurrentUser

logger = logging.getLogger("events")

router = APIRouter()

# court_id → list of queues
# court_id = 0 means manager (gets all events)
_clients: dict[int, list[asyncio.Queue]] = {}

# Main event loop — set in main.py lifespan. Lets sync route handlers (which run
# in a worker thread) push SSE events safely onto the async loop.
_main_loop: asyncio.AbstractEventLoop | None = None


def fire_notify(event: dict) -> None:
    """Thread-safe fire-and-forget SSE notify from a sync handler."""
    global _main_loop
    try:
        if _main_loop is None or not _main_loop.is_running():
            return
        asyncio.run_coroutine_threadsafe(notify_clients(event), _main_loop)
    except Exception as e:
        logger.warning("fire_notify failed: %s", e)


async def notify_clients(event: dict):
    court_id = event.get("court_id")

    # Sirf us court ke clients + managers (court_id=0)
    queues         = list(_clients.get(court_id, []))
    manager_queues = list(_clients.get(0, []))
    all_queues     = queues + manager_queues

    dead = []
    for q in all_queues:
        try:
            await q.put(event)
        except Exception:
            dead.append(q)

    # Dead clients cleanup
    for court, qlist in _clients.items():
        for q in dead:
            if q in qlist:
                qlist.remove(q)


@router.get("/stream")
async def event_stream(
    court_id: int = 0,
    # SECURITY (P1): this stream used to be fully anonymous — anyone could
    # subscribe to court_id=0 (the manager firehose) and watch live cross-tenant
    # activity, plus open unlimited connections. Now a valid login is required.
    # The Flutter SSE client already sends `Authorization: Bearer <token>`, so
    # this adds no client-side change. Channel routing below is intentionally
    # left as-is (payloads are only IDs; the app re-fetches via tenancy-scoped
    # endpoints), so existing real-time updates behave exactly as before.
    user: CurrentUser = Depends(get_current_user),
):
    queue: asyncio.Queue = asyncio.Queue()

    if court_id not in _clients:
        _clients[court_id] = []
    _clients[court_id].append(queue)

    async def generate():
        try:
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=20.0)
                    yield f"data: {json.dumps(event)}\n\n"
                except asyncio.TimeoutError:
                    yield ": ping\n\n"  # keep-alive
        except asyncio.CancelledError:
            if court_id in _clients and queue in _clients[court_id]:
                _clients[court_id].remove(queue)

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )