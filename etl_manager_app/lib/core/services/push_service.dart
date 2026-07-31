// lib/core/services/push_service.dart
//
// FCM push notifications.
//
// Deliberately modelled on core/services/sse_service.dart: a Provider holding a
// Ref, which invalidates the same Riverpod providers when something arrives. The
// two are COMPLEMENTARY, not alternatives:
//
//   SSE  — works only while the app is open. Instant, cheap, already wired.
//   Push — reaches the device when the app is backgrounded or killed.
//
// When both deliver the same event the result is two identical provider
// invalidations, which is harmless (the second refetch hits the same data).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/feedbacks/domain/court_feedback_notifier.dart';
import '../../features/feedbacks/domain/etl_feedback_notifier.dart';
import '../../features/feedbacks/domain/feedback_notifier.dart';
import '../../features/home/presentation/home_providers.dart';
import '../../features/maintenance/domain/maintenance_notifier.dart';
import '../../features/notices/domain/notices_notifier.dart';
import '../../features/notifications/data/device_token_repository.dart';

/// Called with the route a tapped notification wants to open.
typedef PushNavigator = void Function(String route);

/// Shows an in-app banner for a push that arrived while the app is foregrounded.
typedef PushBannerHandler = void Function(String title, String? body, String route);

/// Handles a push that arrives while the app is in the background or terminated.
///
/// MUST be a top-level function and MUST carry the `vm:entry-point` pragma —
/// Flutter spins up a brand-new isolate for it, so tree-shaking would otherwise
/// remove it in release builds.
///
/// Nothing is done here on purpose. The native FCM SDK already draws the
/// notification from the `notification` block of the payload, and this isolate
/// has no access to the running app's Riverpod container, so there is no UI to
/// update. The provider refresh happens when the app is resumed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[PUSH] background message: ${message.messageId}');
}

class PushService {
  final Ref _ref;

  PushService(this._ref);

  PushNavigator? _navigator;
  PushBannerHandler? _banner;

  /// A tapped notification's route, parked until the app is ready to show it.
  String? _pendingRoute;

  /// False until the biometric gate has released and the user is on a real
  /// screen. Navigating before that fights the router's redirect (which pins
  /// everything to `/` while auth status is unknown) and would be swallowed.
  bool _gateOpen = false;

  bool _initialised = false;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Wired once from ETLApp so taps can navigate. Does NOT flush a pending
  /// route — the biometric gate decides when it is safe to navigate.
  void attachNavigator(PushNavigator navigator, PushBannerHandler banner) {
    _navigator = navigator;
    _banner = banner;
  }

  /// Called by BiometricGate once the user has landed on their home screen.
  /// Releases any notification tap that arrived during cold start.
  void openGate() {
    _gateOpen = true;
    _tryNavigate();
  }

  /// Ask for permission, register this device, and start listening.
  ///
  /// Safe to call more than once — the listeners are only attached on the first
  /// call, while the token is re-registered every time (which is what we want
  /// after a re-login on the same device).
  Future<void> initialise() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Android 13+ needs the runtime POST_NOTIFICATIONS grant; iOS needs the
      // APNs authorisation prompt. One call covers both.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[PUSH] permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // Nothing more to do — but DON'T return before registering listeners on
        // a later call, since the user can enable notifications in Settings and
        // come back without a cold start.
        debugPrint('[PUSH] notifications denied by user');
      }

      // iOS only: make the system draw the banner even in the foreground, so
      // Android is the only platform that needs the in-app fallback below.
      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      await registerToken();

      if (!_initialised) {
        _initialised = true;

        // A refreshed token is a NEW identity for this device — re-register or
        // pushes silently stop arriving. Fires independently of login.
        _subs.add(
          messaging.onTokenRefresh.listen((token) {
            debugPrint('[PUSH] token refreshed');
            _ref
                .read(deviceTokenRepositoryProvider)
                .register(fcmToken: token, platform: _platform());
          }),
        );

        // App open when the push lands.
        _subs.add(FirebaseMessaging.onMessage.listen(_onForegroundMessage));

        // User tapped a notification while the app was backgrounded.
        _subs.add(
          FirebaseMessaging.onMessageOpenedApp.listen((m) {
            debugPrint('[PUSH] opened from background: ${m.messageId}');
            _handleTap(m);
          }),
        );

        // App was fully terminated and launched BY the notification.
        final initial = await messaging.getInitialMessage();
        if (initial != null) {
          debugPrint('[PUSH] cold start from notification: ${initial.messageId}');
          _handleTap(initial);
        }
      }
    } catch (e) {
      // Firebase not configured, no Play Services, simulator without APNs —
      // none of these should break the app. Notices + SSE keep working.
      debugPrint('[PUSH] initialise failed (push disabled): $e');
    }
  }

  /// Send this device's token to the backend, bound to the signed-in user.
  Future<void> registerToken() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // iOS: getToken() cannot succeed until APNs has handed us a device token.
      // On a slow first launch that takes a moment; without this guard the call
      // throws and push silently never registers.
      if (Platform.isIOS) {
        final apns = await messaging.getAPNSToken();
        if (apns == null) {
          debugPrint('[PUSH] APNs token not ready — retrying in 3s');
          Future.delayed(const Duration(seconds: 3), registerToken);
          return;
        }
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[PUSH] no FCM token available');
        return;
      }

      final ok = await _ref
          .read(deviceTokenRepositoryProvider)
          .register(fcmToken: token, platform: _platform());
      debugPrint('[PUSH] device registered: $ok');
    } catch (e) {
      debugPrint('[PUSH] registerToken failed: $e');
    }
  }

  /// Unregister this device, then drop the local token.
  ///
  /// MUST be awaited BEFORE TokenStorage.clearAll() — the unregister call needs
  /// the JWT that clearAll() wipes.
  Future<void> unregister() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _ref
          .read(deviceTokenRepositoryProvider)
          .unregister(fcmToken: token);

      // Force a brand-new token next sign-in. Belt-and-braces on top of the
      // backend's ownership transfer: on a shared device this guarantees the
      // next user cannot inherit this token at all.
      await FirebaseMessaging.instance.deleteToken();
      debugPrint('[PUSH] device unregistered');
    } catch (e) {
      debugPrint('[PUSH] unregister failed: $e');
    }
  }

  // ─── Handlers ──────────────────────────────────────────────────────────────

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('[PUSH] foreground: ${message.notification?.title}');

    // Same refresh the SSE layer performs — keeps badges and lists live.
    _refreshFor(message);

    // Android draws nothing for a foregrounded app, so surface it in-app.
    // iOS already showed a system banner (see setForegroundNotificationPresentationOptions).
    if (Platform.isAndroid) {
      final n = message.notification;
      if (n?.title != null) {
        _banner?.call(n!.title!, n.body, _routeFor(message));
      }
    }
  }

  void _handleTap(RemoteMessage message) {
    _refreshFor(message);
    _pendingRoute = _routeFor(message);
    _tryNavigate();
  }

  void _tryNavigate() {
    final route = _pendingRoute;
    if (route == null) return;
    if (!_gateOpen || _navigator == null) {
      debugPrint('[PUSH] navigation parked until the app is ready: $route');
      return;
    }
    _pendingRoute = null;
    debugPrint('[PUSH] navigating to $route');
    _navigator!(route);
  }

  /// Where a notification should take the user. The backend sends an explicit
  /// `route` in the data payload; anything unknown falls back to the notices
  /// inbox, which is always safe because every push has a Notice behind it.
  String _routeFor(RemoteMessage message) {
    final route = message.data['route'];
    if (route is String && route.startsWith('/')) return route;
    return '/notices';
  }

  /// Mirrors SSEService._handleEvent so a push and an SSE ping leave the app in
  /// the same state. Keyed off the notice `type` the backend puts in `data`.
  void _refreshFor(RemoteMessage message) {
    // Every push is backed by a Notice row, so these two are always stale.
    _ref.invalidate(noticesNotifierProvider);
    _ref.invalidate(unreadCountProvider);

    final type = (message.data['type'] ?? '').toString();

    if (type.startsWith('maintenance')) {
      _ref.invalidate(maintenanceNotifierProvider);
      _ref.invalidate(homeMaintenanceProvider);
    }

    if (type.startsWith('feedback')) {
      _ref.invalidate(etlFeedbackNotifierProvider);
      _ref.invalidate(feedbackNotifierProvider);
      _ref.invalidate(courtFeedbackNotifierProvider);
      _ref.invalidate(homeFeedbacksProvider);
    }
  }

  String _platform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _initialised = false;
    _gateOpen = false;
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref);
  ref.onDispose(service.dispose);
  return service;
});
