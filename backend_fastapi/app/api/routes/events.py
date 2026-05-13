# app/api/routes/events.py
from fastapi import APIRouter
from fastapi.responses import StreamingResponse
import asyncio
import json

router = APIRouter()

# court_id → list of queues
# court_id = 0 means manager (gets all events)
_clients: dict[int, list[asyncio.Queue]] = {}


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
async def event_stream(court_id: int = 0):
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