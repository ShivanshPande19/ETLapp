import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/music_models.dart';
import 'music_mock_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Set to false when real Spotify backend is ready
const bool _useMock = true;
// ─────────────────────────────────────────────────────────────────────────────

class MusicRepository {
  Future<bool> getAuthStatus() async {
    if (_useMock) { await _delay(); return true; }
    throw UnimplementedError();
  }

  Future<String> getAuthUrl() async {
    if (_useMock) return 'https://accounts.spotify.com/';
    throw UnimplementedError();
  }

  Future<PlaybackState> getPlaybackState() async {
    if (_useMock) {
      await _delay(ms: 300);
      return MusicMockData.playbackState();
    }
    throw UnimplementedError();
  }

  Future<void> play({int? courtId, String? playlistUri}) async {
    if (_useMock) { await _delay(ms: 200); return; }
    throw UnimplementedError();
  }

  Future<void> pause({int? courtId}) async {
    if (_useMock) { await _delay(ms: 200); return; }
    throw UnimplementedError();
  }

  Future<void> skipNext({int? courtId}) async {
    if (_useMock) { await _delay(ms: 200); return; }
    throw UnimplementedError();
  }

  Future<void> skipPrevious({int? courtId}) async {
    if (_useMock) { await _delay(ms: 200); return; }
    throw UnimplementedError();
  }

  Future<void> setVolume(int volume, {int? courtId}) async {
    if (_useMock) { await _delay(ms: 100); return; }
    throw UnimplementedError();
  }

  Future<void> toggleShuffle(bool state, {int? courtId}) async {
    if (_useMock) { await _delay(ms: 100); return; }
    throw UnimplementedError();
  }

  Future<List<SpotifyPlaylist>> getPlaylists() async {
    if (_useMock) {
      await _delay();
      return MusicMockData.playlists;
    }
    throw UnimplementedError();
  }

  Future<List<SpotifyDevice>> getDevices() async {
    if (_useMock) {
      await _delay();
      return MusicMockData.devices;
    }
    throw UnimplementedError();
  }

  Future<void> linkDevice({
    required int    courtId,
    required String deviceId,
    required String deviceName,
  }) async {
    if (_useMock) { await _delay(ms: 300); return; }
    throw UnimplementedError();
  }

  Future<List<CourtDevice>> getCourtDevices() async {
    if (_useMock) {
      await _delay();
      return MusicMockData.courtDevices;
    }
    throw UnimplementedError();
  }

  Future<void> _delay({int ms = 500}) =>
      Future.delayed(Duration(milliseconds: ms));
}

final musicRepositoryProvider = Provider((ref) => MusicRepository());