// lib/app/biometric_gate.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/auth/domain/auth_notifier.dart';
import '../core/services/biometric_service.dart';

class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key});

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate> {
  bool _checking = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Build ke baad check karo — initState mein context.go() nahi chalega
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _failed = false;
    });

    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('biometric_lock') ?? false;

    if (!biometricEnabled) {
      // Biometric off hai — seedha destination pe bhejo
      _navigate();
      return;
    }

    final available = await BiometricService.isAvailable();
    if (!available) {
      // Device mein biometric nahi — seedha bhejo
      _navigate();
      return;
    }

    final passed = await BiometricService.authenticate();
    if (passed) {
      _navigate();
    } else {
      // Authentication fail — retry screen dikhao
      if (mounted)
        setState(() {
          _checking = false;
          _failed = true;
        });
    }
  }

  void _navigate() {
    if (!mounted) return;
    final authState = ref.read(authNotifierProvider);
    if (authState.isStaff) {
      context.go('/staff/home');
    } else {
      context.go('/home');
    }
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

  // ── Checking state — spinner ─────────────────────────────────────────────
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

  // ── Failed state — retry button ──────────────────────────────────────────
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
        // Retry button
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
