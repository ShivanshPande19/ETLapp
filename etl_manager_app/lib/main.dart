import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/services/biometric_guard.dart'; // ✅ Add karo
import 'core/services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // ✅ Add karo (SharedPrefs ke liye zaroori)

  // Firebase — needed before any FirebaseMessaging call.
  //
  // No `options:` argument on purpose: on Android and iOS the native SDK reads
  // android/app/google-services.json and ios/Runner/GoogleService-Info.plist
  // automatically, so there is no generated firebase_options.dart to keep in
  // sync. (Run `flutterfire configure` and pass
  // `options: DefaultFirebaseOptions.currentPlatform` only if web/desktop
  // support is added later — those platforms have no native config file.)
  //
  // Wrapped because a missing/!invalid config must not stop the app booting:
  // in-app notices and SSE work fine without push.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[PUSH] Firebase init failed — push disabled: $e');
  }

  runApp(
    const ProviderScope(
      child: BiometricGuard(
        // ✅ Wrap karo
        child: ETLApp(),
      ),
    ),
  );
}
