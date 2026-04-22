import '../domain/music_models.dart';

class MusicMockData {
  static final List<SpotifyPlaylist> playlists = [
    SpotifyPlaylist(
      playlistId:  '1',
      name:        'Chill Vibes',
      description: 'Relaxing beats for the food court',
      imageUrl:    null,
      trackCount:  24,
    ),
    SpotifyPlaylist(
      playlistId:  '2',
      name:        'Bollywood Hits',
      description: 'Top Bollywood tracks',
      imageUrl:    null,
      trackCount:  40,
    ),
    SpotifyPlaylist(
      playlistId:  '3',
      name:        'Evening Lounge',
      description: 'Smooth evening background music',
      imageUrl:    null,
      trackCount:  18,
    ),
    SpotifyPlaylist(
      playlistId:  '4',
      name:        'Morning Energy',
      description: 'Upbeat morning playlist',
      imageUrl:    null,
      trackCount:  32,
    ),
    SpotifyPlaylist(
      playlistId:  '5',
      name:        'Weekend Special',
      description: 'Party mix for weekends',
      imageUrl:    null,
      trackCount:  55,
    ),
  ];

  static final List<SpotifyDevice> devices = [
    SpotifyDevice(
      deviceId:      'device-court-1',
      name:          'ETL Food Court Tablet',
      type:          'Tablet',
      isActive:      true,
      volumePercent: 70,
    ),
    SpotifyDevice(
      deviceId:      'device-court-2',
      name:          'Court 2 Speaker',
      type:          'Speaker',
      isActive:      false,
      volumePercent: 55,
    ),
    SpotifyDevice(
      deviceId:      'device-court-3',
      name:          'Court 3 Tablet',
      type:          'Tablet',
      isActive:      false,
      volumePercent: 60,
    ),
  ];

  static final List<CourtDevice> courtDevices = [
    CourtDevice(
      courtId:    1,
      courtName:  'ETL Food Court',
      deviceId:   'device-court-1',
      deviceName: 'ETL Food Court Tablet',
      isLinked:   true,
    ),
    CourtDevice(
      courtId:    2,
      courtName:  'Court 2',
      deviceId:   null,
      deviceName: null,
      isLinked:   false,
    ),
    CourtDevice(
      courtId:    3,
      courtName:  'Court 3',
      deviceId:   null,
      deviceName: null,
      isLinked:   false,
    ),
  ];

  static PlaybackState playbackState({
    bool isPlaying  = true,
    int  progressMs = 67000,
  }) =>
      PlaybackState(
        isPlaying: isPlaying,
        shuffle:   false,
        repeat:    'off',
        device: SpotifyDevice(
          deviceId:      'device-court-1',
          name:          'ETL Food Court Tablet',
          type:          'Tablet',
          isActive:      true,
          volumePercent: 70,
        ),
        track: SpotifyTrack(
          trackId:      'track-001',
          title:        'Kesariya',
          artist:       'Arijit Singh',
          album:        'Brahmastra',
          albumArtUrl:  null,
          durationMs:   262000,
          progressMs:   progressMs,
          isPlaying:    isPlaying,
        ),
      );
}