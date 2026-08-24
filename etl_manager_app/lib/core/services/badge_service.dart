// lib/core/services/badge_service.dart
//
// Thin wrapper over app_badge_plus for the app-icon (launcher) badge. Used to
// fix the badge getting "stuck": we set it to the REAL unread count and clear
// it (0) when the app is opened/resumed and when the notices inbox is read.
//
// Every call is best-effort — it checks support and never throws, so an
// unsupported launcher (many Android OEMs) or any platform hiccup can never
// break the flow that triggered it.
import 'package:app_badge_plus/app_badge_plus.dart';

class BadgeService {
  const BadgeService._();

  static Future<void> setCount(int count) async {
    try {
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(count < 0 ? 0 : count);
      }
    } catch (_) {
      // never throw
    }
  }

  static Future<void> clear() => setCount(0);
}
