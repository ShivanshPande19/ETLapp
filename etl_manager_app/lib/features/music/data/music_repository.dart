import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/music_models.dart';

class MusicRepository {
  final Dio _dio;

  MusicRepository(this._dio);

  Future<bool> getAuthStatus() async {
    final res = await _dio.get('/music/auth/status');
    return res.data['is_authenticated'] ?? false;
  }

  Future<String> getAuthUrl() async {
    final res = await _dio.get('/music/auth/url');
    return res.data['auth_url'];
  }

  // Yahan ab optional courtId parameter add ho gaya hai
  Future<PlaybackState> getPlaybackState({int? courtId}) async {
    final res = await _dio.get(
      '/music/playback',
      queryParameters: {if (courtId != null) 'court_id': courtId},
    );
    return PlaybackState.fromJson(res.data);
  }

  Future<void> play({int? courtId, String? playlistUri}) async {
    await _dio.post(
      '/music/play',
      data: {
        if (courtId != null) 'court_id': courtId,
        if (playlistUri != null) 'playlist_uri': playlistUri,
      },
    );
  }

  Future<void> pause({int? courtId}) async {
    await _dio.post(
      '/music/pause',
      data: {if (courtId != null) 'court_id': courtId},
    );
  }

  Future<void> skipNext({int? courtId}) async {
    await _dio.post(
      '/music/next',
      data: {if (courtId != null) 'court_id': courtId},
    );
  }

  Future<void> skipPrevious({int? courtId}) async {
    await _dio.post(
      '/music/previous',
      data: {if (courtId != null) 'court_id': courtId},
    );
  }

  Future<void> setVolume(int volume, {int? courtId}) async {
    await _dio.post(
      '/music/volume',
      data: {if (courtId != null) 'court_id': courtId, 'volume': volume},
    );
  }

  Future<void> toggleShuffle(bool state, {int? courtId}) async {
    await _dio.post(
      '/music/shuffle',
      data: {if (courtId != null) 'court_id': courtId, 'state': state},
    );
  }

  // Naya function jo error resolve karega
  Future<void> toggleRepeat(String state, {int? courtId}) async {
    await _dio.post(
      '/music/repeat',
      data: {if (courtId != null) 'court_id': courtId, 'state': state},
    );
  }

  Future<List<SpotifyPlaylist>> getPlaylists() async {
    final res = await _dio.get('/music/playlists');
    return (res.data['playlists'] as List)
        .map((j) => SpotifyPlaylist.fromJson(j))
        .toList();
  }

  Future<List<SpotifyDevice>> getDevices() async {
    final res = await _dio.get('/music/devices');
    return (res.data['devices'] as List)
        .map((j) => SpotifyDevice.fromJson(j))
        .toList();
  }

  Future<void> linkDevice({
    required int courtId,
    required String deviceId,
    required String deviceName,
  }) async {
    await _dio.post(
      '/music/link-device',
      data: {
        'court_id': courtId,
        'device_id': deviceId,
        'device_name': deviceName,
      },
    );
  }

  Future<List<CourtDevice>> getCourtDevices() async {
    final res = await _dio.get('/music/court-devices');
    return (res.data['court_devices'] as List)
        .map((j) => CourtDevice.fromJson(j))
        .toList();
  }
}

// Provider jisme existing API client inject ho raha hai
final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return MusicRepository(dio);
});
