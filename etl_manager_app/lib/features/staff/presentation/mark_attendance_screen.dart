// lib/features/staff/presentation/mark_attendance_screen.dart
//
// Attendance capture: a selfie + a trustworthy location, handed back to the
// caller (see AttendanceFlow) which submits it.
//
// ─── WHAT WAS WRONG BEFORE ───────────────────────────────────────────────────
//  • `_initializeCameraAndLocation()` awaited location, then the geofence, then
//    the camera — all with NO timeout — while the whole screen rendered as a
//    bare black Scaffold with a spinner and no back button. One slow GPS fix
//    (normal indoors at the end of a shift) = a permanent dead end. This is
//    the "check-out pe black screen, loader ghumta rehta hai" bug.
//  • It took ONE coarse GPS fix and judged the geofence from it, so a fix with
//    a ±1 km error bar produced "you are outside your zone" while the person
//    stood inside it.
//  • It had no idea whether it was opened for check-in or check-out, so it
//    applied the geofence gate to BOTH — even though the backend deliberately
//    does not geofence check-out (blocking it strands someone who has already
//    left the premises, then the hourly sweep flags a false "forgot to check
//    out").
//  • It uploaded the raw camera JPEG; every other photo flow in the app
//    compresses first.
//
// ─── HOW IT WORKS NOW ────────────────────────────────────────────────────────
//  • Camera and location start TOGETHER, each with its own deadline, so the
//    preview appears while GPS is still converging.
//  • Location goes through AttendanceLocation, which waits for the error bar
//    to shrink and always finishes (fix or named failure) within 15 s.
//  • The error bar is shown live and gates the decision: a fix too coarse to
//    judge a geofence is never used to reject a check-in.
//  • Geofence gate applies to check-IN only, matching the backend.
//  • Check-OUT can be completed without a photo if the camera won't start.
//  • Back / Retry / Open-settings are reachable at every moment.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/photo_upload_service.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../home/presentation/home_providers.dart';
import '../data/attendance_location.dart';
import '../domain/attendance_flow.dart';

const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);

/// One of the staff's allowed check-in zones.
class _Zone {
  const _Zone({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radius,
  });

  final String? name;
  final double lat;
  final double lng;
  final int radius;
}

class MarkAttendanceScreen extends ConsumerStatefulWidget {
  const MarkAttendanceScreen({super.key, this.action = AttendanceAction.checkIn});

  final AttendanceAction action;

  @override
  ConsumerState<MarkAttendanceScreen> createState() =>
      _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen>
    with WidgetsBindingObserver {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _camera;
  bool _cameraStarting = true;
  String? _cameraError;
  bool _capturing = false;

  // ── Location ──────────────────────────────────────────────────────────────
  bool _locating = true;
  LocationFix? _fix;
  LocationFailure? _locFailure;

  // ── Geofence ──────────────────────────────────────────────────────────────
  final List<_Zone> _zones = [];
  bool _geofenceLoaded = false;
  _Zone? _nearestZone;
  double? _distanceToNearest;
  bool _withinZone = true;

  bool get _isCheckOut => widget.action == AttendanceAction.checkOut;

  /// The geofence is a check-IN rule only. The backend does the same: blocking
  /// check-out would strand anyone who has already walked out of the court.
  bool get _geofenceApplies => !_isCheckOut;

  /// Timers backing `_withDeadline`, cancelled when the screen goes away.
  final List<Timer> _deadlines = [];

  /// Bound a future that may never complete.
  ///
  /// `Future.timeout` is not used because its timer keeps running after the
  /// screen is disposed (which also trips "pending timers" in widget tests).
  /// These timers are owned here and cancelled in `dispose`.
  Future<T> _withDeadline<T>(Future<T> future, Duration limit, String what) {
    final completer = Completer<T>();
    final timer = Timer(limit, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(what, limit));
      }
    });
    _deadlines.add(timer);
    future.then(
      (v) {
        if (!completer.isCompleted) completer.complete(v);
      },
      onError: (Object e, StackTrace s) {
        if (!completer.isCompleted) completer.completeError(e, s);
      },
    ).whenComplete(() {
      timer.cancel();
      _deadlines.remove(timer);
    });
    return completer.future;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deliberately NOT awaited together: the camera must not wait for GPS.
    _startCamera();
    _acquireLocation();
    _loadGeofence();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _deadlines) {
      t.cancel();
    }
    _deadlines.clear();
    final cam = _camera;
    _camera = null;
    cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android reclaims the camera when the app goes to the background; without
    // this the preview comes back frozen/black on resume.
    if (state == AppLifecycleState.inactive) {
      final cam = _camera;
      _camera = null;
      cam?.dispose();
      if (mounted) setState(() => _cameraStarting = false);
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _startCamera();
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _startCamera() async {
    if (!mounted) return;
    setState(() {
      _cameraStarting = true;
      _cameraError = null;
    });
    try {
      final cameras = await _withDeadline(
        availableCameras(),
        const Duration(seconds: 8),
        'camera list',
      );
      if (cameras.isEmpty) throw Exception('No camera found on this device.');

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium, // small frames = fast capture + fast upload
        enableAudio: false,
      );
      await _withDeadline(
        controller.initialize(),
        const Duration(seconds: 12),
        'camera start',
      );

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraStarting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraStarting = false;
        _cameraError = _isCheckOut
            ? 'Camera could not start. You can still check out without a photo.'
            : 'Camera could not start. Close any other app using the camera, '
                'then tap retry.';
        debugPrint('attendance camera init failed: $e');
      });
    }
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _acquireLocation() async {
    if (!mounted) return;
    setState(() {
      _locating = true;
      _locFailure = null;
    });

    final outcome = await AttendanceLocation.acquire(
      // Live error bar, so the user watches it tighten instead of staring at a
      // spinner that might never end.
      onProgress: (fix) {
        if (!mounted) return;
        setState(() => _fix = fix);
        _evaluateZone();
      },
    );

    if (!mounted) return;
    setState(() {
      _locating = false;
      if (outcome.ok) {
        _fix = outcome.fix;
        _locFailure = null;
      } else {
        _locFailure = outcome.failure;
      }
    });
    _evaluateZone();
  }

  Future<void> _loadGeofence() async {
    try {
      final res = await ref.read(dioProvider).get('/attendance/geofence');
      final data = res.data;
      final parsed = <_Zone>[];
      if (data is Map && data['has_geofence'] == true) {
        // The backend always sends `zones` now; the flat single-zone shape is
        // still read as a fallback so an older backend keeps working.
        final raw = data['zones'];
        final entries = (raw is List && raw.isNotEmpty)
            ? raw.whereType<Map>().toList()
            : <Map>[data];
        for (final z in entries) {
          final lat = (z['latitude'] as num?)?.toDouble();
          final lng = (z['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          parsed.add(_Zone(
            name: z['court_name'] as String?,
            lat: lat,
            lng: lng,
            radius: (z['geofence_radius'] as num?)?.toInt() ?? 150,
          ));
        }
      }
      if (!mounted) return;
      setState(() {
        _zones
          ..clear()
          ..addAll(parsed);
        _geofenceLoaded = true;
      });
      _evaluateZone();
    } catch (_) {
      // Can't fetch it → don't block anyone client-side; the server still
      // enforces the geofence on submit.
      if (!mounted) return;
      setState(() => _geofenceLoaded = true);
    }
  }

  /// Decide inside/outside against the NEAREST assigned zone, using the fix's
  /// own error bar as slack (capped, so a bad fix can't buy unlimited range).
  void _evaluateZone() {
    final fix = _fix;
    if (_zones.isEmpty || fix == null) {
      if (!mounted) return;
      setState(() {
        _withinZone = true;
        _distanceToNearest = null;
        _nearestZone = null;
      });
      return;
    }

    final slack = fix.accuracy.clamp(0.0, AttendanceLocation.usableAccuracyM);
    double? nearestDist;
    _Zone? nearest;
    var within = false;

    for (final z in _zones) {
      final dist = Geolocator.distanceBetween(
        fix.latitude,
        fix.longitude,
        z.lat,
        z.lng,
      );
      if (nearestDist == null || dist < nearestDist) {
        nearestDist = dist;
        nearest = z;
      }
      // Inside ANY assigned zone is enough (a Zone Manager / Maintenance Head
      // covers several).
      if (dist <= z.radius + slack) within = true;
    }

    if (!mounted) return;
    setState(() {
      _withinZone = within;
      _distanceToNearest = nearestDist;
      _nearestZone = nearest;
    });
  }

  // ── Capture ───────────────────────────────────────────────────────────────

  /// Null when we're good to go, otherwise why the shutter is blocked.
  String? get _blockedReason {
    final fix = _fix;
    if (fix == null) {
      return _locating
          ? 'Getting your location…'
          : 'No location yet. Tap refresh to try again.';
    }
    if (fix.isMocked) {
      return 'Mock location detected. Turn off any fake-GPS app and try again.';
    }
    if (!_geofenceApplies) return null; // check-out: location is enough

    // Don't let a fast tap submit a check-in before we know which zones are
    // allowed — the server would just reject it with a geofence 403.
    if (!_geofenceLoaded) return 'Checking your zone…';

    // A fix this coarse cannot place anyone inside a ~150 m circle. Refusing to
    // DECIDE (instead of deciding "outside") is what stops the daily false
    // rejection.
    if (fix.isUnusable && _zones.isNotEmpty) {
      return 'GPS accuracy is only ${fix.accuracyLabel}. Tap refresh, or step '
          'near a window / outside so your zone can be confirmed.';
    }
    if (_zones.isNotEmpty && !_withinZone) {
      final d = _distanceToNearest;
      final name = _nearestZone?.name ?? 'your zone';
      return d != null
          ? 'You are ~${d.round()} m from $name. Move within '
              '${_nearestZone?.radius ?? 150} m to mark attendance.'
          : 'You are outside your attendance zone.';
    }
    return null;
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _capturing) return;

    final blocked = _blockedReason;
    if (blocked != null) {
      HapticFeedback.heavyImpact();
      _toast(blocked, isError: true);
      return;
    }

    setState(() => _capturing = true);
    HapticFeedback.heavyImpact();
    try {
      final shot = await cam.takePicture();
      // Compress before handing it over — this is the bulk of the old upload
      // wait (see PhotoUploadService.compressForUpload).
      String path = shot.path;
      try {
        final compressed =
            await PhotoUploadService.compressForUpload(File(shot.path));
        path = compressed.path;
      } catch (_) {
        // Keep the original — a slower upload beats a lost punch.
      }
      if (!mounted) return;
      _pop(imagePath: path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      _toast('Could not take the photo. Please try again.', isError: true);
    }
  }

  /// Check-out escape hatch: the backend accepts a photo-less check-out, so a
  /// dead camera must never trap someone in an open shift.
  void _checkOutWithoutPhoto() {
    final blocked = _blockedReason;
    if (blocked != null) {
      HapticFeedback.heavyImpact();
      _toast(blocked, isError: true);
      return;
    }
    HapticFeedback.mediumImpact();
    _pop(imagePath: null);
  }

  void _pop({required String? imagePath}) {
    final fix = _fix;
    if (fix == null) return;
    Navigator.pop(context, {
      'image_path': imagePath,
      'latitude': fix.latitude,
      'longitude': fix.longitude,
      'accuracy': fix.accuracy,
      'is_mocked': fix.isMocked,
    });
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? _danger : _ok,
          content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        ),
      );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // A hard location failure is the only full-screen stop, and it always
    // offers a way forward (retry / settings / back).
    if (_locFailure != null && _fix == null) {
      return _LocationBlockedView(
        failure: _locFailure!,
        onRetry: _acquireLocation,
      );
    }

    return Scaffold(
      backgroundColor: _black,
      body: Stack(
        children: [
          Positioned.fill(child: _preview()),

          // Top row: back button is ALWAYS present — the old screen hid it
          // during init, which is what made a slow GPS fix a dead end.
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Expanded(child: _statusBanner()),
              ],
            ),
          ),

          Positioned(bottom: 118, left: 20, right: 20, child: _watermarkCard()),
          Positioned(bottom: 24, left: 0, right: 0, child: _shutterRow()),
        ],
      ),
    );
  }

  Widget _preview() {
    final cam = _camera;
    if (cam != null && cam.value.isInitialized) {
      return CameraPreview(cam);
    }
    return ColoredBox(
      color: _black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_cameraStarting) ...[
              const CircularProgressIndicator(color: _white, strokeWidth: 2),
              const SizedBox(height: 16),
              Text(
                'Starting camera…',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
              ),
            ] else ...[
              const Icon(Icons.no_photography_rounded,
                  color: Colors.white38, size: 44),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Text(
                  _cameraError ?? 'Camera unavailable.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _startCamera,
                icon: const Icon(Icons.refresh_rounded, color: _white, size: 18),
                label: Text(
                  'Retry camera',
                  style: GoogleFonts.inter(color: _white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Live location + geofence state. This replaces the old all-or-nothing
  /// banner, so the user can see WHY the shutter is disabled.
  Widget _statusBanner() {
    final fix = _fix;
    final Color bg;
    final IconData icon;
    final String text;

    if (fix == null) {
      bg = _warn;
      icon = Icons.gps_not_fixed_rounded;
      text = _locating ? 'Locating you…' : 'No location yet';
    } else if (_geofenceApplies && _zones.isNotEmpty && fix.isUnusable) {
      bg = _warn;
      icon = Icons.gps_not_fixed_rounded;
      text = 'Weak GPS · ${fix.accuracyLabel}';
    } else if (_geofenceApplies && _zones.isNotEmpty && !_withinZone) {
      bg = _danger;
      icon = Icons.location_off_rounded;
      final d = _distanceToNearest;
      text = d != null
          ? 'Outside zone · ~${d.round()} m away'
          : 'Outside your zone';
    } else if (_zones.isNotEmpty && _withinZone) {
      bg = _ok;
      icon = Icons.check_circle_rounded;
      text = 'Inside ${_nearestZone?.name ?? 'zone'} · ${fix.accuracyLabel}';
    } else if (!_geofenceLoaded) {
      bg = _warn;
      icon = Icons.travel_explore_rounded;
      text = 'Checking your zone · ${fix.accuracyLabel}';
    } else {
      bg = _ok;
      icon = Icons.my_location_rounded;
      text = 'Location ready · ${fix.accuracyLabel}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: _white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: _white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            onTap: _locating ? null : _acquireLocation,
            child: _locating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: _white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _watermarkCard() {
    final auth = ref.watch(authNotifierProvider);
    final staffName = auth.staffName ?? auth.managerName ?? 'Staff';
    final outletName = ref.watch(currentOutletNameProvider).value;
    final timeString = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
    final fix = _fix;

    return Container(
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
                decoration: const BoxDecoration(color: _ok, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                _isCheckOut ? 'CHECK OUT' : 'CHECK IN',
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
          _MetaRow(icon: Icons.access_time_rounded, text: timeString),
          const SizedBox(height: 6),
          _MetaRow(
            icon: Icons.location_on_rounded,
            text: fix == null
                ? 'Waiting for GPS…'
                : 'Lat: ${fix.latitude.toStringAsFixed(5)}, '
                    'Lng: ${fix.longitude.toStringAsFixed(5)} · ${fix.accuracyLabel}',
          ),
        ],
      ),
    );
  }

  Widget _shutterRow() {
    final blocked = _blockedReason != null;
    final canShoot = _camera?.value.isInitialized == true && !_capturing;
    // Check-out only needs a location, so offer it even with no camera.
    final showNoPhotoOption =
        _isCheckOut && _camera == null && !_cameraStarting && _fix != null;

    return Column(
      children: [
        if (showNoPhotoOption) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ok,
                  foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _checkOutWithoutPhoto,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text(
                  'Check out without photo',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Center(
          child: GestureDetector(
            onTap: canShoot ? _capture : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _capturing ? 64 : 76,
              height: _capturing ? 64 : 76,
              decoration: BoxDecoration(
                color: (!canShoot || blocked)
                    ? Colors.white38
                    : (_capturing ? Colors.grey : _white),
                shape: BoxShape.circle,
                border: Border.all(color: _black.withOpacity(0.2), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: _black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: _capturing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _black,
                        ),
                      )
                    : Container(
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
      ],
    );
  }
}

// ─── Small pieces ────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: _white, size: 20),
      ),
    );
  }
}

/// Shown only when we have NO usable position at all. Always offers a way out,
/// which the old black-spinner screen did not.
class _LocationBlockedView extends StatelessWidget {
  const _LocationBlockedView({required this.failure, required this.onRetry});

  final LocationFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _RoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context),
                ),
              ),
              const Spacer(),
              const Icon(Icons.location_disabled_rounded,
                  color: _warn, size: 52),
              const SizedBox(height: 20),
              Text(
                'Location needed',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: _white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AttendanceLocation.messageFor(failure),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white60,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              if (AttendanceLocation.needsAppSettings(failure) ||
                  failure == LocationFailure.serviceDisabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () =>
                        AttendanceLocation.openSettingsFor(failure),
                    child: Text(
                      'Open settings',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _white,
                  foregroundColor: _black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onRetry,
                child: Text(
                  'Try again',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
