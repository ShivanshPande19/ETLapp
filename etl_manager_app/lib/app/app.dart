import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/badge_service.dart';
import '../core/services/push_service.dart';
import '../core/theme/app_theme.dart';
import '../features/notices/domain/notices_notifier.dart';
import 'router.dart';

/// Lets PushService show an in-app banner from outside the widget tree (an
/// Android foreground push has no BuildContext of its own).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class ETLApp extends ConsumerStatefulWidget {
  const ETLApp({super.key});

  @override
  ConsumerState<ETLApp> createState() => _ETLAppState();
}

class _ETLAppState extends ConsumerState<ETLApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Give PushService a way to navigate and to surface foreground pushes.
    //
    // Done here rather than inside PushService so that push_service.dart never
    // imports router.dart — router.dart -> biometric_gate.dart -> push_service
    // would otherwise be a circular import.
    //
    // Note this only ATTACHES the callbacks; a tap that arrived during cold
    // start stays parked until BiometricGate calls openGate(), because the
    // router's redirect swallows any navigation before auth is resolved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushServiceProvider).attachNavigator(
        (route) => ref.read(routerProvider).go(route),
        _showBanner,
      );
      // Sync the app-icon badge to the real unread count on launch.
      _syncBadge();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On resume, re-sync the app-icon badge to the real unread count. This is
    // the key fix for the badge getting "stuck" — opening/returning to the app
    // now always reflects reality (and drops to 0 once notices are read).
    if (state == AppLifecycleState.resumed) {
      _syncBadge();
    }
  }

  void _syncBadge() {
    // Force a re-fetch of the unread count; the ref.listen in build() pushes
    // the resolved value onto the app-icon badge. Kept decoupled so nothing
    // else (notifier / push service) needs to know about the badge.
    ref.invalidate(unreadCountProvider);
  }

  void _showBanner(String title, String? body, String route) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1C1C1C),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (body != null && body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),
          ],
        ),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: const Color(0xFFD02128),
          onPressed: () => ref.read(routerProvider).go(route),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Single source of truth for the app-icon badge: whenever the unread count
    // resolves (on read/push/SSE/open — each of which invalidates the provider)
    // mirror it onto the launcher badge. Fixes the badge getting stuck.
    ref.listen(unreadCountProvider, (prev, next) {
      next.whenData((count) => BadgeService.setCount(count));
    });

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ETL Manager',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.dark,
      routerConfig: router,
      // Clamp the system text scale. The UI is dense and number-heavy with
      // large fixed font sizes (big ₹ hero figures, headers). A very large
      // accessibility font setting would otherwise overflow those layouts.
      // We still honour scaling up to 1.3x for readability.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
