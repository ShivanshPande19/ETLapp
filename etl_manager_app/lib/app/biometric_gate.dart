// lib/app/biometric_gate.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/auth/domain/auth_notifier.dart';
import '../core/services/biometric_service.dart';
import '../core/services/push_service.dart'; // ✅ FCM import
import '../core/services/sse_service.dart'; // ✅ SSE import

class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key});

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final authState = ref.read(authNotifierProvider);

    print('[BIOMETRIC] managerEmail: ${authState.managerEmail}');
    print('[BIOMETRIC] role: ${authState.role}');

    final key = 'biometric_lock_${authState.managerEmail ?? 'default'}';
    final biometricEnabled = prefs.getBool(key) ?? false;

    print('[BIOMETRIC] key: $key');
    print('[BIOMETRIC] enabled: $biometricEnabled');
    print('[BIOMETRIC] ALL PREFS KEYS: ${prefs.getKeys()}');

    if (!biometricEnabled) {
      _navigate();
      return;
    }

    final available = await BiometricService.isAvailable();
    if (!available) {
      _navigate();
      return;
    }

    final passed = await BiometricService.authenticate();
    if (passed) {
      _navigate();
    } else {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  void _navigate() {
    if (!mounted) return;
    final authState = ref.read(authNotifierProvider);

    // ✅ SSE connect — login ke baad ek baar
    ref.read(sseServiceProvider).connect();

    // ✅ FCM — permission + register this device against the signed-in user.
    // Fire-and-forget: a push failure must never delay or block sign-in.
    final push = ref.read(pushServiceProvider);
    push.initialise();

    print('[BIOMETRIC] Navigating — isStaff: ${authState.isStaff}');
    if (authState.isStaff) {
      context.go('/staff/home');
    } else {
      context.go('/home');
    }

    // Release any notification tap that arrived while the app was starting.
    // Must come AFTER the go() above: the router's redirect pins everything to
    // '/' until auth is resolved, so an earlier navigation would be discarded.
    push.openGate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: Center(child: _checking ? _buildChecking() : _buildFailed()),
      ),
    );
  }

  Widget _buildChecking() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: const Icon(
            Icons.fingerprint_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Verifying Identity',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Please authenticate to continue',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _buildFailed() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFF4444).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFF4444).withOpacity(0.3)),
          ),
          child: const Icon(
            Icons.lock_rounded,
            color: Color(0xFFFF4444),
            size: 32,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Authentication Failed',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Could not verify your identity',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
        ),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: _check,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.fingerprint_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Try Again',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
