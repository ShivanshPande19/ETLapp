// lib/features/courts/presentation/location_picker_screen.dart
//
// Reusable map-based location + geofence picker (OpenStreetMap via flutter_map).
// Returns a [PickedLocation] to the caller via Navigator.pop.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);

/// Result returned by [LocationPickerScreen].
class PickedLocation {
  final double latitude;
  final double longitude;
  final int radius; // metres
  final String? address;

  const PickedLocation({
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.address,
  });
}

class LocationPickerScreen extends StatefulWidget {
  /// Pre-fill when editing an existing court's location.
  final double? initialLat;
  final double? initialLng;
  final int? initialRadius;
  final String courtName;

  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialRadius,
    this.courtName = 'Court',
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final Dio _geoDio = Dio(
    BaseOptions(
      // Free OpenStreetMap services — usage policy requires a UA / Referer.
      headers: {'User-Agent': 'ETL_Manager_App/1.0'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  // Fallback center (Sector 50, Noida-ish) used only if nothing else is known.
  static const LatLng _fallbackCenter = LatLng(28.5709, 77.3609);

  late LatLng _center;
  double _radius = 150;
  String? _address;
  bool _resolvingAddress = false;
  bool _searching = false;
  bool _locating = false;
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    _radius = (widget.initialRadius ?? 150).toDouble();
    if (widget.initialLat != null && widget.initialLng != null) {
      _center = LatLng(widget.initialLat!, widget.initialLng!);
      _reverseGeocode(_center);
    } else {
      _center = _fallbackCenter;
      // Try to jump to the device's current location on open.
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToMyLocation());
    }
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ── Geocoding (OpenStreetMap Nominatim, free) ──────────────────────────────

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _resolvingAddress = true);
    try {
      final res = await _geoDio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': point.latitude,
          'lon': point.longitude,
          'format': 'json',
        },
      );
      final data = res.data;
      final name = (data is Map) ? data['display_name'] as String? : null;
      if (mounted) {
        setState(() => _address = name);
      }
    } catch (_) {
      // Address is best-effort only; coords are what matters.
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final res = await _geoDio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {'q': q, 'format': 'json', 'limit': 1},
      );
      final list = res.data;
      if (list is List && list.isNotEmpty) {
        final first = list.first as Map;
        final lat = double.tryParse(first['lat'].toString());
        final lon = double.tryParse(first['lon'].toString());
        if (lat != null && lon != null) {
          final target = LatLng(lat, lon);
          _mapController.move(target, 16);
          setState(() {
            _center = target;
            _address = first['display_name'] as String?;
          });
        }
      } else if (mounted) {
        _snack('No results for "$q"');
      }
    } catch (_) {
      if (mounted) _snack('Search failed. Check your internet.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── Device location ─────────────────────────────────────────────────────────

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Location services are off.');
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final target = LatLng(pos.latitude, pos.longitude);
      _mapController.move(target, 17);
      setState(() => _center = target);
      _reverseGeocode(target);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onMapMoved(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (!hasGesture) return;
    // Debounce reverse geocoding while the user is panning.
    _addressDebounce?.cancel();
    _addressDebounce = Timer(const Duration(milliseconds: 600), () {
      _reverseGeocode(_center);
    });
    setState(() {}); // refresh circle position + coord readout
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _black,
      ),
    );
  }

  void _confirm() {
    HapticFeedback.selectionClick();
    Navigator.pop(
      context,
      PickedLocation(
        latitude: _center.latitude,
        longitude: _center.longitude,
        radius: _radius.round(),
        address: _address,
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _black,
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: _onMapMoved,
              onTap: (_, point) {
                _mapController.move(point, _mapController.camera.zoom);
                setState(() => _center = point);
                _reverseGeocode(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.etl.manager_app',
                maxZoom: 19,
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radius,
                    useRadiusInMeter: true,
                    color: _red.withOpacity(0.15),
                    borderColor: _red,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            ],
          ),

          // Fixed center pin (the selected point is always the map center)
          IgnorePointer(
            child: Center(
              child: Padding(
                // lift the icon so its tip points at the exact center
                padding: const EdgeInsets.only(bottom: 36),
                child: Icon(
                  Icons.location_on,
                  color: _red,
                  size: 44,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 8),
                  ],
                ),
              ),
            ),
          ),

          // Top: back + search
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _circleBtn(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        style: GoogleFonts.inter(fontSize: 14, color: _black),
                        decoration: InputDecoration(
                          hintText: 'Search e.g. Sector 50, Noida',
                          hintStyle:
                              GoogleFonts.inter(fontSize: 14, color: _grey),
                          prefixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _black,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.search_rounded,
                                  color: _grey, size: 20),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // "My location" button
          Positioned(
            right: 16,
            bottom: 250,
            child: _circleBtn(
              icon: _locating ? Icons.hourglass_top_rounded : Icons.my_location_rounded,
              onTap: _locating ? null : _goToMyLocation,
            ),
          ),

          // Bottom sheet: address + radius + confirm
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                MediaQuery.of(context).padding.bottom + 18,
              ),
              decoration: const BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.courtName,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _grey,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 16, color: _red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _resolvingAddress
                              ? 'Locating address…'
                              : (_address ??
                                  '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Geofence radius',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _black,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_radius.round()} m',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _red,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _red,
                      thumbColor: _red,
                      inactiveTrackColor: const Color(0xFFE5E5E5),
                      overlayColor: _red.withOpacity(0.15),
                    ),
                    child: Slider(
                      value: _radius,
                      min: 50,
                      max: 500,
                      divisions: 45,
                      onChanged: (v) => setState(() => _radius = v),
                    ),
                  ),
                  Text(
                    'Staff must be within this circle to mark attendance. '
                    'Drag the map so the pin sits on the court entrance.',
                    style: GoogleFonts.inter(fontSize: 11, color: _grey),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _confirm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _black,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Confirm location',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10),
          ],
        ),
        child: Icon(icon, color: _black, size: 20),
      ),
    );
  }
}
