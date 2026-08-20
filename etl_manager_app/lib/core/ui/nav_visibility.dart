// lib/core/ui/nav_visibility.dart
//
// Whether the floating bottom nav bar (ShellScreen) is currently shown.
//
// It floats OVER the screen content, so any bottom sheet opened from within a
// shell screen would be partially covered by it. Screens that open a bottom
// sheet (e.g. the outlet switcher) hide() it while the sheet is up so the nav
// bar slides away and the sheet gets the full height — then show() it again.
//
// Uses the Riverpod 3 Notifier API (StateProvider is no longer in the default
// export in v3), matching the rest of the app.

import 'package:flutter_riverpod/flutter_riverpod.dart';

class NavBarVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void show() => state = true;
  void hide() => state = false;
  void set(bool visible) => state = visible;
}

final navBarVisibleProvider =
    NotifierProvider<NavBarVisibilityNotifier, bool>(
  NavBarVisibilityNotifier.new,
);
