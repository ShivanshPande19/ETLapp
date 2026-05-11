// lib/core/services/biometric_guard.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'biometric_service.dart';

class BiometricGuard extends StatefulWidget {
  final Widget child;
  const BiometricGuard({super.key, required this.child});

  @override
  State<BiometricGuard> createState() => _BiometricGuardState();
}

class _BiometricGuardState extends State<BiometricGuard>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _checking = false;
  bool _authenticated =
      false; // ✅ Session flag — ek baar pass kiya toh dobara nahi

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // ✅ App background gaya — reset karo taaki wapas aane pe lock lage
      _authenticated = false;
    }
    if (state == AppLifecycleState.resumed && !_authenticated) {
      _checkLock();
    }
  }

  Future<void> _checkLock() async {
    if (_checking || _authenticated) return; // ✅ Already authenticated toh skip

    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('biometric_lock') ?? false;
    if (!isEnabled) {
      _authenticated = true; // Biometric off hai — seedha andar
      return;
    }

    setState(() {
      _locked = true;
      _checking = true;
    });

    final passed = await BiometricService.authenticate();

    if (mounted) {
      if (passed) {
        _authenticated = true; // ✅ Pass — session mein dobara nahi poochega
      }
      setState(() {
        _locked = !passed;
        _checking = false;
      });

      if (!passed) {
        await Future.delayed(const Duration(milliseconds: 300));
        SystemNavigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF080808),
          body: Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
