import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

const _kCloudName = 'dooyogcqj';
const _kUploadPreset = 'etl_unsigned';

class HousekeepingStorageService {
  static final _cloudinary = CloudinaryPublic(
    _kCloudName,
    _kUploadPreset,
    cache: false,
  );

  // ── Compress before upload ─────────────────────────────────────────────────
  static Future<File> _compress(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70, // 70% quality — good enough for proof photos
      minWidth: 1280,
      minHeight: 720,
    );

    if (result == null) {
      debugPrint('⚠️ Compression failed, using original file');
      return file;
    }

    final originalSize = await file.length();
    final compressedSize = await result.length();
    debugPrint(
      '🗜️  Compressed: ${(originalSize / 1024 / 1024).toStringAsFixed(1)} MB'
      ' → ${(compressedSize / 1024 / 1024).toStringAsFixed(1)} MB',
    );

    return File(result.path);
  }

  static Future<String?> uploadTaskPhoto({
    required File photo,
    required int courtId,
    required String shift,
    required String date,
    required String taskId,
  }) async {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('☁️  CLOUDINARY UPLOAD ATTEMPT');
    debugPrint('  Cloud Name   : $_kCloudName');
    debugPrint('  Upload Preset: $_kUploadPreset');
    debugPrint(
      '  File Size    : ${(await photo.length() / 1024 / 1024).toStringAsFixed(1)} MB',
    );

    try {
      // Compress first
      final compressed = await _compress(photo);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final publicId = '${taskId}_$timestamp';
      final folder = 'housekeeping/court_$courtId/$shift/$date';

      debugPrint('📤 Sending to Cloudinary...');

      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          compressed.path,
          folder: folder,
          publicId: publicId,
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      debugPrint('✅ SUCCESS: ${response.secureUrl}');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return response.secureUrl;
    } on CloudinaryException catch (e) {
      debugPrint('❌ CloudinaryException: ${e.message}');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return null;
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return null;
    }
  }

  static Future<String?> uploadWeeklyPhoto({
    required File photo,
    required int courtId,
    required String date,
  }) async => uploadTaskPhoto(
    photo: photo,
    courtId: courtId,
    shift: 'weekly',
    date: date,
    taskId: 'flags_washing',
  );

  static Future<String?> uploadMonthlyPhoto({
    required File photo,
    required int courtId,
    required String date,
  }) async => uploadTaskPhoto(
    photo: photo,
    courtId: courtId,
    shift: 'monthly',
    date: date,
    taskId: 'fire_safety_audit',
  );
}
