// lib/features/staff/presentation/mark_attendance_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../home/presentation/home_providers.dart';

const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _ok = Color(0xFF22C55E);

class MarkAttendanceScreen extends ConsumerStatefulWidget {
  const MarkAttendanceScreen({super.key});

  @override
  ConsumerState<MarkAttendanceScreen> createState() =>
      _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen> {
  CameraController? _cameraController;
  Position? _currentPosition;
  bool _isInitializing = true;
  bool _isCapturing = false;
  String _errorMsg = '';

  // ── Geofence state ──────────────────────────────────────────────────────────
  bool _hasGeofence = false; // court has a location configured
  bool _withinZone = true; // staff currently inside the allowed circle
  bool _checkingZone = false;
  String? _courtName;
  double? _courtLat;
  double? _courtLng;
  int _radius = 150;
  double _accuracyBuffer = 75;
  double? _distanceFromCourt; // metres

  @override
  void initState() {
    super.initState();
    _initializeCameraAndLocation();
  }

  Future<void> _fetchGeofence() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/attendance/geofence');
      final data = res.data;
      if (data is Map && data['has_geofence'] == true) {
        _hasGeofence = true;
        _courtName = data['court_name'] as String?;
        _courtLat = (data['latitude'] as num?)?.toDouble();
        _courtLng = (data['longitude'] as num?)?.toDouble();
        _radius = (data['geofence_radius'] as num?)?.toInt() ?? 150;
        _accuracyBuffer = (data['accuracy_buffer'] as num?)?.toDouble() ?? 75;
      } else {
        _hasGeofence = false;
      }
    } catch (_) {
      // If we can't fetch the geofence, don't block the user client-side —
      // the server still enforces it on submit.
      _hasGeofence = false;
    }
  }

  /// Recompute whether the current position is inside the court's circle.
  void _evaluateZone() {
    if (!_hasGeofence ||
        _currentPosition == null ||
        _courtLat == null ||
        _courtLng == null) {
      _withinZone = true;
      _distanceFromCourt = null;
      return;
    }
    final dist = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _courtLat!,
      _courtLng!,
    );
    final allowed = _radius +
        (_currentPosition!.accuracy.clamp(0, _accuracyBuffer));
    _distanceFromCourt = dist;
    _withinZone = dist <= allowed;
  }

  Future<void> _refreshLocation() async {
    setState(() => _checkingZone = true);
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _evaluateZone();
    } catch (_) {
      // keep previous position
    } finally {
      if (mounted) setState(() => _checkingZone = false);
    }
  }

  Future<void> _initializeCameraAndLocation() async {
    try {
      // 1. Get Location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied)
          throw Exception('Location permission denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 1b. Fetch this staff's court geofence and evaluate the zone.
      await _fetchGeofence();
      _evaluateZone();

      // 2. Initialize Front Camera securely
      final cameras = await availableCameras();

      // ✅ FIX: Check if cameras list is empty before accessing it
      if (cameras.isEmpty) {
        throw Exception('No cameras found on this device.');
      }

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () =>
            cameras.first, // Safe now because we checked isEmpty above
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.toString();
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing)
      return;

    // 🚫 Geofence gate — block capture if outside the court's allowed circle.
    if (_hasGeofence && !_withinZone) {
      HapticFeedback.heavyImpact();
      final d = _distanceFromCourt;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            d != null
                ? 'You are ~${d.round()} m from ${_courtName ?? 'the court'}. '
                    'Move within $_radius m to mark attendance.'
                : 'You are outside the attendance zone.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    // 🚫 Mock / fake-GPS gate.
    if (_currentPosition?.isMocked == true) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mock location detected. Turn off any fake-GPS app and try again.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _isCapturing = true);
    HapticFeedback.heavyImpact();

    try {
      final XFile image = await _cameraController!.takePicture();

      // Return image path and location back to Home Screen
      if (mounted) {
        Navigator.pop(context, {
          'image_path': image.path,
          'latitude': _currentPosition?.latitude,
          'longitude': _currentPosition?.longitude,
          'accuracy': _currentPosition?.accuracy,
          'is_mocked': _currentPosition?.isMocked ?? false,
        });
      }
    } catch (e) {
      debugPrint("Error taking picture: $e");
      setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: _black,
        body: Center(child: CircularProgressIndicator(color: _white)),
      );
    }

    if (_errorMsg.isNotEmpty) {
      return Scaffold(
        backgroundColor: _black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Initialization Failed',
                  style: GoogleFonts.inter(
                    color: _white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMsg,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _white,
                    foregroundColor: _black,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final authState = ref.watch(authNotifierProvider);
    final staffName = authState.staffName ?? authState.managerName ?? 'Staff';
    // ✅ Real outlet name (no hardcoding). Null while loading / unknown.
    final outletName = ref.watch(currentOutletNameProvider).value;
    final now = DateTime.now();
    final timeString = DateFormat('dd MMM yyyy, hh:mm a').format(now);

    return Scaffold(
      backgroundColor: _black,
      body: Stack(
        children: [
          // 1. Full Screen Camera Preview
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: CameraPreview(_cameraController!),
          ),

          // 2. Safe Area Top Overlay (Back button)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _white,
                  size: 20,
                ),
              ),
            ),
          ),

          // 2b. Geofence status banner
          if (_hasGeofence)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 72,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (_withinZone ? _ok : const Color(0xFFEF4444))
                      .withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      _withinZone
                          ? Icons.check_circle_rounded
                          : Icons.location_off_rounded,
                      color: _white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _withinZone
                            ? 'Inside ${_courtName ?? 'court'} zone'
                            : 'Outside zone${_distanceFromCourt != null ? ' · ~${_distanceFromCourt!.round()} m away' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _checkingZone ? null : _refreshLocation,
                      child: _checkingZone
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _white,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded,
                              color: _white, size: 18),
                    ),
                  ],
                ),
              ),
            ),

          // 3. Watermark Overlay (Bottom)
          Positioned(
            bottom: 120,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _white.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: _ok,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'LIVE ATTENDANCE',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: _ok,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    staffName.toUpperCase(),
                    style: GoogleFonts.antonSc(
                      fontSize: 24,
                      color: _white,
                      letterSpacing: 1.0,
                    ),
                  ),
                  // ✅ Only show outlet name when we actually have it (no fake).
                  if (outletName != null && outletName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      outletName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        color: Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeString,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Lat: ${_currentPosition?.latitude.toStringAsFixed(5)}, Lng: ${_currentPosition?.longitude.toStringAsFixed(5)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 4. Shutter Button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePicture,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _isCapturing ? 64 : 76,
                  height: _isCapturing ? 64 : 76,
                  decoration: BoxDecoration(
                    color: (_hasGeofence && !_withinZone)
                        ? Colors.white38
                        : (_isCapturing ? Colors.grey : _white),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _black.withOpacity(0.2),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        border: Border.all(color: _black, width: 2),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
