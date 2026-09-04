"""Sales-source adapter registry.

Importing this package registers every bundled adapter (side effect of importing
each module), so callers only need::

    from ..sales_sources import get_adapter, NormalizedOrder
"""

from .base import (  # noqa: F401
    NormalizedOrder,
    SalesSourceAdapter,
    DEFAULT_SOURCE,
    get_adapter,
    register,
    registered_sources,
)

# Import concrete adapters so their `register(...)` calls run.
from . import petpooja_generic  # noqa: F401,E402
from . import petpooja_salesdata  # noqa: F401,E402
from . import royal_pos  # noqa: F401,E402
from . import rista_pos  # noqa: F401,E402
