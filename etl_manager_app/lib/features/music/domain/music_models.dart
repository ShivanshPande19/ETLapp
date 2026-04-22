class SpotifyTrack {
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final String? albumArtUrl;
  final int durationMs;
  final int progressMs;
  final bool isPlaying;

  const SpotifyTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtUrl,
    required this.durationMs,
    required this.progressMs,
    required this.isPlaying,
  });

  factory SpotifyTrack.fromJson(Map<String, dynamic> j) => SpotifyTrack(
        trackId:      j['track_id'],
        title:        j['title'],
        artist:       j['artist'],
        album:        j['album'],
        albumArtUrl:  j['album_art_url'],
        durationMs:   j['duration_ms'],
        progressMs:   j['progress_ms'],
        isPlaying:    j['is_playing'],
      );

  String get progressFormatted => _fmt(progressMs);
  String get durationFormatted => _fmt(durationMs);
  double get progressFraction  =>
      durationMs > 0 ? progressMs / durationMs : 0.0;

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
           '${(s % 60).toString().padLeft(2, '0')}';
  }
}

class SpotifyDevice {
  final String deviceId;
  final String name;
  final String type;
  final bool   isActive;
  final int?   volumePercent;

  const SpotifyDevice({
    required this.deviceId,
    required this.name,
    required this.type,
    required this.isActive,
    this.volumePercent,
  });

  factory SpotifyDevice.fromJson(Map<String, dynamic> j) => SpotifyDevice(
        deviceId:      j['device_id'],
        name:          j['name'],
        type:          j['type'],
        isActive:      j['is_active'],
        volumePercent: j['volume_percent'],
      );
}

class PlaybackState {
  final bool           isPlaying;
  final SpotifyTrack?  track;
  final SpotifyDevice? device;
  final bool           shuffle;
  final String         repeat;

  const PlaybackState({
    required this.isPlaying,
    this.track,
    this.device,
    this.shuffle = false,
    this.repeat  = 'off',
  });

  factory PlaybackState.fromJson(Map<String, dynamic> j) => PlaybackState(
        isPlaying: j['is_playing'],
        track:     j['track']  != null
            ? SpotifyTrack.fromJson(j['track'])  : null,
        device:    j['device'] != null
            ? SpotifyDevice.fromJson(j['device']) : null,
        shuffle:   j['shuffle'] ?? false,
        repeat:    j['repeat']  ?? 'off',
      );
}

class SpotifyPlaylist {
  final String  playlistId;
  final String  name;
  final String? description;
  final String? imageUrl;
  final int     trackCount;

  const SpotifyPlaylist({
    required this.playlistId,
    required this.name,
    this.description,
    this.imageUrl,
    required this.trackCount,
  });

  String get uri => 'spotify:playlist:$playlistId';

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> j) => SpotifyPlaylist(
        playlistId:  j['playlist_id'],
        name:        j['name'],
        description: j['description'],
        imageUrl:    j['image_url'],
        trackCount:  j['track_count'],
      );
}

class CourtDevice {
  final int     courtId;
  final String  courtName;
  final String? deviceId;
  final String? deviceName;
  final bool    isLinked;

  const CourtDevice({
    required this.courtId,
    required this.courtName,
    this.deviceId,
    this.deviceName,
    required this.isLinked,
  });

  factory CourtDevice.fromJson(Map<String, dynamic> j) => CourtDevice(
        courtId:    j['court_id'],
        courtName:  j['court_name'],
        deviceId:   j['device_id'],
        deviceName: j['device_name'],
        isLinked:   j['is_linked'],
      );
}