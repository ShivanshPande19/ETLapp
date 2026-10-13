// lib/core/utils/app_version.dart
//
// The running build's version, read from the app bundle itself.
//
// Both settings screens used to hard-code this as `'1.0.3 (Phase 1)'`. By the
// time anyone noticed, the app had shipped 1.0.4 and was about to ship 1.0.5 —
// so the one screen a user checks to tell support "which version am I on?" was
// confidently wrong, in two places, in two files.
//
// Reading it from PackageInfo means it comes from the same `version:` line in
// pubspec.yaml that the store build is stamped with, so it cannot drift again.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// e.g. `"1.0.5 (8)"` — the marketing version with the build number, which is
/// what App Store Connect / Play Console show and what support needs to
/// identify an exact build.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final build = info.buildNumber;
  return build.isEmpty ? info.version : '${info.version} ($build)';
});
