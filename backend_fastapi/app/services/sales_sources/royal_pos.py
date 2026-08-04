"""Adapter #3 — Royal POS (stub).

Royal POS outlets are on a completely different API from Petpooja. This stub
reserves the ``pos_source`` key and documents the contract; implement
``fetch_normalized_orders`` once Royal's API docs/credentials are available
(see PROGRESS_MULTISOURCE.md, Phase 3).

Because ``get_adapter`` resolves lazily and ``sync_outlet_for_dates`` guards
each outlet in its own try/except, an outlet accidentally set to this source
will log the NotImplementedError and be skipped — it will never crash the sync
for the other outlets.
"""

from __future__ import annotations

from datetime import date
from typing import List

from .base import NormalizedOrder, SalesSourceAdapter, register


class RoyalPosAdapter(SalesSourceAdapter):
    source_key = "royal_pos"

    async def fetch_normalized_orders(
        self,
        outlet,
        api_fetch_dates: List[date],
        cutoff_hour: int = 0,
    ) -> List[NormalizedOrder]:
        raise NotImplementedError(
            "Royal POS adapter is not implemented yet (Phase 3). "
            f"Cannot sync outlet id={getattr(outlet, 'id', '?')} "
            f"(rest_id={getattr(outlet, 'rest_id', '?')}) via royal_pos."
        )


register(RoyalPosAdapter())
