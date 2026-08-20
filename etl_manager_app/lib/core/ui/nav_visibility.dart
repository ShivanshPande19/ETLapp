// lib/core/ui/nav_visibility.dart
//
// Whether the floating bottom nav bar (ShellScreen) is currently shown.
//
// It floats OVER the screen content, so any bottom sheet opened from within a
// shell screen would be partially covered by it. Screens that open a bottom
// sheet (e.g. the outlet switcher) flip this to false while the sheet is up so
// the nav bar slides away and the sheet gets the full height — then restore it.

import 'package:flutter_riverpod/flutter_riverpod.dart';

final navBarVisibleProvider = StateProvider<bool>((ref) => true);
