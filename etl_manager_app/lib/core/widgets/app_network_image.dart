// lib/core/widgets/app_network_image.dart
//
// Cached, flicker-free network image used across the app for proof photos
// (housekeeping, maintenance) and any volume-served media.
//
// Why: plain `Image.network` re-fetches/re-decodes whenever the widget tree
// rebuilds (e.g. the manager screen auto-refreshes every 30s), which causes a
// visible placeholder flash + jank. `CachedNetworkImage` keeps the decoded
// image in memory and on disk, so once loaded it paints instantly with a soft
// fade — and survives app restarts.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../network/api_client.dart';

class AppNetworkImage extends StatelessWidget {
  /// Stored path or URL (relative `uploads/...` or absolute http(s)).
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? background;
  final Color accent;

  /// Cap decoded width in memory (use the on-screen pixel size * devicePixelRatio
  /// for thumbnails to keep memory low). Null = full resolution.
  final int? memCacheWidth;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.background,
    this.accent = Colors.white,
    this.memCacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(url);
    final bg = background ?? Colors.white.withOpacity(0.06);

    Widget child;
    if (resolved == null) {
      child = _box(bg, Icons.image_not_supported_rounded);
    } else {
      child = CachedNetworkImage(
        imageUrl: resolved,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memCacheWidth,
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 80),
        placeholder: (_, __) => Container(
          width: width,
          height: height,
          color: bg,
          child: Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: accent.withOpacity(0.6),
              ),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _box(bg, Icons.broken_image_rounded),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  Widget _box(Color bg, IconData icon) => Container(
    width: width,
    height: height,
    color: bg,
    child: Icon(icon, size: 18, color: accent.withOpacity(0.5)),
  );
}
