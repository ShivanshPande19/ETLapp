# app/core/geo.py
"""Geospatial helpers for attendance geofencing."""

import math


def distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two lat/lng points in metres (Haversine).

    Accurate enough for short distances (a few km) which is all geofencing
    needs. Matches the result of Flutter's `Geolocator.distanceBetween` so the
    client-side pre-check and server-side enforcement stay consistent.
    """
    earth_radius_m = 6371000.0  # mean Earth radius

    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)

    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return earth_radius_m * c


# Cap on how much GPS-accuracy slack we allow on top of the geofence radius, so
# a poor fix doesn't let someone mark attendance from far away.
MAX_ACCURACY_BUFFER_M = 75.0

# Fallback radius used when a court has a location set but no explicit radius.
DEFAULT_GEOFENCE_RADIUS_M = 150
