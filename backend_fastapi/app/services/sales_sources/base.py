"""Pluggable POS sales-source adapters.

Each POS integration (Petpooja `generic_get_orders`, Petpooja `get_sales_data`,
Royal POS, ...) implements one :class:`SalesSourceAdapter`. An adapter's only
job is to **fetch and normalize** — it returns a list of :class:`NormalizedOrder`
and performs **no database writes**. That keeps adapters pure and unit-testable
against captured JSON, and keeps all persistence/`DailySaleCache` logic in one
place (``petpooja_service.sync_outlet_for_dates``).

Add a new source in three steps:
    1. subclass :class:`SalesSourceAdapter`, set ``source_key``, implement
       ``fetch_normalized_orders``;
    2. ``register(MyAdapter())`` (usually at import time in the module);
    3. import the module from ``sales_sources/__init__.py`` so it registers.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import date, datetime
from typing import TYPE_CHECKING, Dict, List

if TYPE_CHECKING:  # avoid a runtime import cycle (models import database, etc.)
    from ...models.sale import Outlet


@dataclass
class NormalizedOrder:
    """A single revenue-counting bill, source-agnostic.

    Adapters must emit **only** orders that should count towards revenue
    (voided/failed bills are filtered out inside the adapter). The persistence
    layer sums every ``NormalizedOrder`` it receives, so this dataclass is the
    single contract between "how we fetched it" and "how the app reports it".

    Fields:
        external_ref: the source's own unique id for the bill, as a **string**
            (Petpooja generic ``orderID``, Petpooja sales_data ``Receipt number``,
            etc.). Uniqueness is scoped per ``(outlet, source)`` — see the
            ``UNIQUE(outlet_id, source, external_ref)`` constraint on
            ``sales_orders`` — so per-outlet sequential receipt numbers are fine.
        business_date: the operational day the bill belongs to (already
            cutoff/midnight-adjusted by the adapter).
        created_on: the exact bill timestamp (best-effort; falls back to
            midnight of ``business_date`` when the source omits a time).
        total_amount: the final settled amount for the bill.
        status: source-reported status string, kept for audit/reconciliation
            (e.g. ``"completed"``, ``"Success"``). Not used for filtering here —
            adapters already dropped non-counting bills.
    """

    external_ref: str
    business_date: date
    created_on: datetime
    total_amount: float
    status: str = "completed"


class SalesSourceAdapter(ABC):
    """Base class for every POS sales source."""

    #: unique key stored in ``Outlet.pos_source`` to select this adapter.
    source_key: str = ""

    @abstractmethod
    async def fetch_normalized_orders(
        self,
        outlet: "Outlet",
        api_fetch_dates: List[date],
        cutoff_hour: int = 0,
    ) -> List[NormalizedOrder]:
        """Fetch orders for ``outlet`` covering ``api_fetch_dates`` and return
        them normalized.

        Args:
            outlet: the outlet to sync (carries per-outlet creds + ``rest_id``).
            api_fetch_dates: the deep-sync window (typically ``[T, T-1, T-2]``).
                Range-based sources may fetch ``[min..max]`` in one call.
            cutoff_hour: the court's overnight ``day_cutoff_hour`` (0-11). Sources
                that only report calendar dates use it to shift post-midnight
                bills to the previous operational day. Sources that already
                report the operational day (Petpooja generic) ignore it.
        """
        raise NotImplementedError


# ── registry ──────────────────────────────────────────────────────────────────
_REGISTRY: Dict[str, SalesSourceAdapter] = {}

# The source assumed for any outlet that predates the ``pos_source`` column.
DEFAULT_SOURCE = "petpooja_generic"


def register(adapter: SalesSourceAdapter) -> SalesSourceAdapter:
    """Register an adapter instance under its ``source_key``."""
    if not adapter.source_key:
        raise ValueError(f"{type(adapter).__name__} must set a non-empty source_key")
    _REGISTRY[adapter.source_key] = adapter
    return adapter


def get_adapter(pos_source: str | None) -> SalesSourceAdapter:
    """Return the adapter for ``pos_source`` (falling back to the default).

    Importing this module's package (``sales_sources``) registers all bundled
    adapters, so callers just do ``from ..sales_sources import get_adapter``.
    """
    key = (pos_source or DEFAULT_SOURCE).strip() or DEFAULT_SOURCE
    try:
        return _REGISTRY[key]
    except KeyError:
        raise KeyError(
            f"No sales-source adapter registered for pos_source={key!r}. "
            f"Known sources: {sorted(_REGISTRY)}"
        )


def registered_sources() -> List[str]:
    return sorted(_REGISTRY)
