import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart'; // Naya package import
import '../data/music_repository.dart';
import 'music_models.dart';

enum MusicStatus { idle, loading, loaded, error }

class MusicState {
  final MusicStatus status;
  final bool isAuthenticated;
  final PlaybackState? playback;
  final List<SpotifyPlaylist> playlists;
  final List<SpotifyDevice> devices;
  final List<CourtDevice> courtDevices;
  final int? selectedCourtId;
  final String? error;

  const MusicState({
    this.status = MusicStatus.idle,
    this.isAuthenticated = false,
    this.playback,
    this.playlists = const [],
    this.devices = const [],
    this.courtDevices = const [],
    this.selectedCourtId,
    this.error,
  });

  MusicState copyWith({
    MusicStatus? status,
    bool? isAuthenticated,
    PlaybackState? playback,
    List<SpotifyPlaylist>? playlists,
    List<SpotifyDevice>? devices,
    List<CourtDevice>? courtDevices,
    int? selectedCourtId,
    String? error,
  }) => MusicState(
    status: status ?? this.status,
    isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    playback: playback ?? this.playback,
    playlists: playlists ?? this.playlists,
    devices: devices ?? this.devices,
    courtDevices: courtDevices ?? this.courtDevices,
    selectedCourtId: selectedCourtId ?? this.selectedCourtId,
    error: error ?? this.error,
  );
}

class MusicNotifier extends Notifier<MusicState> {
  Timer? _pollTimer;
  Timer? _authTimer; // Login ka wait karne ke liye naya timer

  @override
  MusicState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _authTimer?.cancel();
    });
    _init();
    return const MusicState(status: MusicStatus.loading);
  }

  Future<void> _init() async {
    final repo = ref.read(musicRepositoryProvider);
    try {
      final authed = await repo.getAuthStatus();
      if (!authed) {
        state = state.copyWith(
          status: MusicStatus.loaded,
          isAuthenticated: false,
        );
        return;
      }

      final results = await Future.wait([
        repo.getPlaybackState(
          courtId: state.selectedCourtId,
        ), // CourtId pass kiya
        repo.getPlaylists(),
        repo.getDevices(),
        repo.getCourtDevices(),
      ]);

      state = MusicState(
        status: MusicStatus.loaded,
        isAuthenticated: true,
        playback: results[0] as PlaybackState,
        playlists: results[1] as List<SpotifyPlaylist>,
        devices: results[2] as List<SpotifyDevice>,
        courtDevices: results[3] as List<CourtDevice>,
        selectedCourtId: state.selectedCourtId, // state maintain rakhne ke liye
      );

      _startPolling();
    } catch (e) {
      state = state.copyWith(status: MusicStatus.error, error: e.toString());
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!state.isAuthenticated) return;
      try {
        final playback = await ref
            .read(musicRepositoryProvider)
            .getPlaybackState(
              courtId: state.selectedCourtId,
            ); // CourtId pass kiya
        state = state.copyWith(playback: playback);
      } catch (_) {}
    });
  }

  // NAYA: URL Launcher ka use karke Spotify Login flow
  Future<void> connectSpotify() async {
    try {
      final urlString = await ref.read(musicRepositoryProvider).getAuthUrl();
      final url = Uri.parse(urlString);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);

        // Har 3 second mein backend se pucho ki kya manager ne login kar liya?
        _authTimer?.cancel();
        _authTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
          final isAuth = await ref
              .read(musicRepositoryProvider)
              .getAuthStatus();

          if (isAuth) {
            timer.cancel(); // Login success hote hi timer band karo
            state = state.copyWith(
              status: MusicStatus.loading,
              isAuthenticated: true,
            );
            await _init(); // Data fetch karna shuru karo
          }
        });
      } else {
        state = state.copyWith(error: "Could not open Spotify Login URL");
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> togglePlayPause() async {
    final repo = ref.read(musicRepositoryProvider);
    final playing = state.playback?.isPlaying ?? false;
    final courtId = state.selectedCourtId;

    // Optimistic update
    if (state.playback != null) {
      state = state.copyWith(
        playback: PlaybackState(
          isPlaying: !playing,
          track: state.playback!.track,
          device: state.playback!.device,
          shuffle: state.playback!.shuffle,
          repeat: state.playback!.repeat,
        ),
      );
    }

    try {
      if (playing) {
        await repo.pause(courtId: courtId);
      } else {
        await repo.play(courtId: courtId);
      }
    } catch (e) {
      // Revert on failure
      if (state.playback != null) {
        state = state.copyWith(
          playback: PlaybackState(
            isPlaying: playing,
            track: state.playback!.track,
            device: state.playback!.device,
            shuffle: state.playback!.shuffle,
            repeat: state.playback!.repeat,
          ),
          error: e.toString(),
        );
      }
    }
  }

  Future<void> skipNext() async {
    await ref
        .read(musicRepositoryProvider)
        .skipNext(courtId: state.selectedCourtId);
    await Future.delayed(const Duration(milliseconds: 500));
    await _refreshPlayback();
  }

  Future<void> skipPrevious() async {
    await ref
        .read(musicRepositoryProvider)
        .skipPrevious(courtId: state.selectedCourtId);
    await Future.delayed(const Duration(milliseconds: 500));
    await _refreshPlayback();
  }

  Future<void> setVolume(int volume) async {
    await ref
        .read(musicRepositoryProvider)
        .setVolume(volume, courtId: state.selectedCourtId);
  }

  Future<void> toggleShuffle() async {
    final newState = !(state.playback?.shuffle ?? false);
    await ref
        .read(musicRepositoryProvider)
        .toggleShuffle(newState, courtId: state.selectedCourtId);
    await _refreshPlayback();
  }

  // NAYA: Repeat cycle toggle karne ke liye function
  Future<void> toggleRepeat() async {
    final currentState = state.playback?.repeat ?? 'off';
    String nextState;
    if (currentState == 'off') {
      nextState = 'context'; // repeat playlist
    } else if (currentState == 'context') {
      nextState = 'track'; // repeat single song
    } else {
      nextState = 'off'; // turn off repeat
    }

    await ref
        .read(musicRepositoryProvider)
        .toggleRepeat(nextState, courtId: state.selectedCourtId);
    await _refreshPlayback();
  }

  Future<void> playPlaylist(SpotifyPlaylist playlist) async {
    await ref
        .read(musicRepositoryProvider)
        .play(courtId: state.selectedCourtId, playlistUri: playlist.uri);
    await Future.delayed(const Duration(milliseconds: 800));
    await _refreshPlayback();
  }

  // UPDATE: Jab naya court select ho, tabhi us court ka music fetch ho jaye
  void selectCourt(int? courtId) {
    state = state.copyWith(selectedCourtId: courtId);
    _refreshPlayback();
  }

  Future<void> linkDevice({
    required int courtId,
    required String deviceId,
    required String deviceName,
  }) async {
    await ref
        .read(musicRepositoryProvider)
        .linkDevice(
          courtId: courtId,
          deviceId: deviceId,
          deviceName: deviceName,
        );
    final courtDevices = await ref
        .read(musicRepositoryProvider)
        .getCourtDevices();
    state = state.copyWith(courtDevices: courtDevices);
  }

  Future<void> _refreshPlayback() async {
    try {
      final p = await ref
          .read(musicRepositoryProvider)
          .getPlaybackState(
            courtId: state.selectedCourtId,
          ); // CourtId pass kiya
      state = state.copyWith(playback: p);
    } catch (_) {}
  }

  Future<void> refresh() => _init();
}

final musicNotifierProvider = NotifierProvider<MusicNotifier, MusicState>(
  () => MusicNotifier(),
);
