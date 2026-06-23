// lib/core/storage/photo_upload_service.dart
//
// Replaces the old Cloudinary flow. Photos are now:
//   1. Compressed (flutter_image_compress)
//   2. Watermarked with location + time (image package, baked-in / tamper-proof)
//   3. Uploaded as multipart to the backend, which stores them on the Railway
//      volume (UPLOAD_DIR) and returns a relative `uploads/...` path.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class PhotoUploadService {
  // ── Public API ──────────────────────────────────────────────────────────

  /// Compress + stamp a location/time watermark, then upload a housekeeping
  /// proof photo. Returns the stored relative path (e.g.
  /// `uploads/housekeeping/xyz.jpg`) or null on failure.
  static Future<String?> uploadHousekeepingPhoto({
    required Dio dio,
    required File photo,
    String? addressLine,
    double? lat,
    double? lng,
  }) async {
    try {
      final stamped = await _compressAndWatermark(
        photo,
        addressLine: addressLine,
        lat: lat,
        lng: lng,
      );
      return await _upload(dio, stamped, '/housekeeping/upload-photo');
    } catch (e) {
      debugPrint('uploadHousekeepingPhoto error: $e');
      return null;
    }
  }

  /// Compress + upload a maintenance proof photo (no watermark).
  static Future<String?> uploadMaintenancePhoto({
    required Dio dio,
    required File photo,
  }) async {
    try {
      final compressed = await _compress(photo);
      return await _upload(dio, compressed, '/maintenance/upload-photo');
    } catch (e) {
      debugPrint('uploadMaintenancePhoto error: $e');
      return null;
    }
  }

  /// Best-effort reverse geocode (OpenStreetMap Nominatim). Falls back to
  /// formatted coordinates if the lookup fails or times out.
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final geoDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          headers: {'User-Agent': 'ETL_Manager_App/1.0'},
        ),
      );
      final res = await geoDio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'format': 'json',
          'zoom': 18,
        },
      );
      final name = res.data is Map ? res.data['display_name'] : null;
      if (name is String && name.trim().isNotEmpty) return name.trim();
    } catch (e) {
      debugPrint('reverseGeocode error: $e');
    }
    return 'Lat ${lat.toStringAsFixed(5)}, Lng ${lng.toStringAsFixed(5)}';
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  static Future<String?> _upload(Dio dio, File file, String path) async {
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
    });
    final res = await dio.post(path, data: form);
    if (res.statusCode == 200 || res.statusCode == 201) {
      final url = res.data is Map ? res.data['photo_url'] : null;
      return url as String?;
    }
    return null;
  }

  // ── Compression ─────────────────────────────────────────────────────────

  static Future<File> _compress(File file) async {
    final dir = await getTemporaryDirectory();
    final target =
        '${dir.path}/cmp_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      target,
      quality: 72,
      minWidth: 1280,
      minHeight: 720,
    );
    return result == null ? file : File(result.path);
  }

  // ── Watermark ─────────────────────────────────────────────────────────────

  static Future<File> _compressAndWatermark(
    File file, {
    String? addressLine,
    double? lat,
    double? lng,
  }) async {
    final compressed = await _compress(file);

    try {
      final bytes = await compressed.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return compressed;

      decoded = img.bakeOrientation(decoded);

      final lines = _watermarkLines(
        addressLine: addressLine,
        lat: lat,
        lng: lng,
      );
      _drawWatermark(decoded, lines);

      final out = img.encodeJpg(decoded, quality: 82);
      final dir = await getTemporaryDirectory();
      final stampedPath =
          '${dir.path}/wm_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final stampedFile = File(stampedPath);
      await stampedFile.writeAsBytes(out);
      return stampedFile;
    } catch (e) {
      debugPrint('watermark error (using compressed): $e');
      return compressed;
    }
  }

  static List<String> _watermarkLines({
    String? addressLine,
    double? lat,
    double? lng,
  }) {
    final now = DateTime.now();
    final ts = DateFormat('dd MMM yyyy   hh:mm a').format(now);

    final lines = <String>[ts];

    final addr = addressLine?.trim();
    if (addr != null && addr.isNotEmpty) {
      lines.addAll(_wrap(addr, 42, maxLines: 2));
    } else if (lat != null && lng != null) {
      lines.add('Lat ${lat.toStringAsFixed(5)}   Lng ${lng.toStringAsFixed(5)}');
    }
    return lines;
  }

  static List<String> _wrap(String text, int maxChars, {int maxLines = 2}) {
    final words = text.split(RegExp(r'\s+'));
    final out = <String>[];
    var current = '';
    for (final w in words) {
      final candidate = current.isEmpty ? w : '$current $w';
      if (candidate.length > maxChars) {
        if (current.isNotEmpty) out.add(current);
        current = w;
        if (out.length == maxLines - 1) break;
      } else {
        current = candidate;
      }
    }
    if (out.length < maxLines && current.isNotEmpty) out.add(current);
    if (out.length == maxLines && current.isNotEmpty && !out.contains(current)) {
      // truncate the last line with ellipsis if more text remains
      var last = out[maxLines - 1];
      if (last.length > maxChars - 1) last = last.substring(0, maxChars - 1);
      out[maxLines - 1] = '$last...';
    }
    return out.isEmpty ? [text] : out;
  }

  static void _drawWatermark(img.Image image, List<String> lines) {
    if (lines.isEmpty) return;

    final font = img.arial48;
    const lineHeight = 54;
    const padX = 24;
    const padY = 18;

    final bandHeight = (lines.length * lineHeight) + (padY * 2);
    final bandTop = image.height - bandHeight;

    // Semi-transparent dark caption bar across the bottom.
    img.fillRect(
      image,
      x1: 0,
      y1: bandTop < 0 ? 0 : bandTop,
      x2: image.width,
      y2: image.height,
      color: img.ColorRgba8(0, 0, 0, 145),
    );

    // Thin red accent line (brand colour) above the bar.
    img.fillRect(
      image,
      x1: 0,
      y1: bandTop < 0 ? 0 : bandTop,
      x2: image.width,
      y2: (bandTop < 0 ? 0 : bandTop) + 4,
      color: img.ColorRgb8(208, 33, 40),
    );

    var y = (bandTop < 0 ? 0 : bandTop) + padY;
    for (final line in lines) {
      img.drawString(
        image,
        line,
        font: font,
        x: padX,
        y: y,
        color: img.ColorRgb8(255, 255, 255),
      );
      y += lineHeight;
    }
  }
}
