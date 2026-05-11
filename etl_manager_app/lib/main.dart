import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/services/biometric_guard.dart'; // ✅ Add karo

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // ✅ Add karo (SharedPrefs ke liye zaroori)
  runApp(
    const ProviderScope(
      child: BiometricGuard(
        // ✅ Wrap karo
        child: ETLApp(),
      ),
    ),
  );
}
