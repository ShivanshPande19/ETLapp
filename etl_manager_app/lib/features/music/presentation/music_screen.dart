import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/music_notifier.dart';
import '../domain/music_models.dart';

class MusicScreen extends ConsumerWidget {
  const MusicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicNotifierProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: switch (state.status) {
          MusicStatus.loading => const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          MusicStatus.error => _ErrorView(
              message: state.error ?? 'Unknown error',
              onRetry: () =>
                  ref.read(musicNotifierProvider.notifier).refresh(),
            ),
          _ => state.isAuthenticated
              ? _MusicDashboard(state: state)
              : _SpotifyConnectView(
                  onConnect: () async {
                    final url = await ref
                        .read(musicNotifierProvider.notifier)
                        .getAuthUrl();
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
        },
      ),
    );
  }
}

// ── Spotify Connect splash ────────────────────────────────────────────────────

class _SpotifyConnectView extends StatelessWidget {
  final VoidCallback onConnect;
  const _SpotifyConnectView({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.music_note_rounded,
                  color: Color(0xFF1DB954), size: 40),
            ),
            const SizedBox(height: 24),
            const Text(
              'Connect Spotify',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Link your Spotify account to control\nmusic across all court tablets.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConnect,
                icon:  const Icon(Icons.open_in_new, size: 18),
                label: const Text('Connect with Spotify'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main music dashboard ──────────────────────────────────────────────────────

class _MusicDashboard extends ConsumerWidget {
  final MusicState state;
  const _MusicDashboard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Music Control',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Manager only · Spotify Connect',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Color(0xFF1DB954), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Connected',
                      style: TextStyle(
                        color: Color(0xFF1DB954),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          _CourtSelector(state: state),
          const SizedBox(height: 20),
          _NowPlayingCard(state: state),
          const SizedBox(height: 20),
          _PlaylistSection(state: state),
          const SizedBox(height: 20),
          _DeviceLinkSection(state: state),
        ],
      ),
    );
  }
}

// ── Court selector ────────────────────────────────────────────────────────────

class _CourtSelector extends ConsumerWidget {
  final MusicState state;
  const _CourtSelector({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = [
      {'id': null, 'name': 'All'},
      {'id': 1,    'name': 'ETL'},
      {'id': 2,    'name': 'Court 2'},
      {'id': 3,    'name': 'Court 3'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Controlling',
          style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: courts.map((c) {
              final selected = state.selectedCourtId == c['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => ref
                      .read(musicNotifierProvider.notifier)
                      .selectCourt(c['id'] as int?),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      c['name'] as String,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Now Playing card ──────────────────────────────────────────────────────────

class _NowPlayingCard extends ConsumerWidget {
  final MusicState state;
  const _NowPlayingCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track     = state.playback?.track;
    final isPlaying = state.playback?.isPlaying ?? false;
    final notifier  = ref.read(musicNotifierProvider.notifier);
    final volume    = (state.playback?.device?.volumePercent ?? 50).toDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.2),
            AppTheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NOW PLAYING',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),

          // Album art + info
          Row(
            children: [
              _AlbumArt(url: track?.albumArtUrl),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.title ?? 'Nothing playing',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track?.artist ?? 'Play a playlist to start',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track?.album ?? '',
                      style: const TextStyle(
                          color: AppTheme.textFaint, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Shuffle
              IconButton(
                onPressed: notifier.toggleShuffle,
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: (state.playback?.shuffle ?? false)
                      ? AppTheme.primary
                      : AppTheme.textFaint,
                  size: 20,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Progress bar
          if (track != null) ...[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:  const RoundSliderThumbShape(
                    enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12),
                activeTrackColor:   AppTheme.primary,
                inactiveTrackColor: AppTheme.border,
                thumbColor:         AppTheme.primary,
                overlayColor: AppTheme.primary.withOpacity(0.2),
              ),
              child: Slider(
                value: track.progressFraction.clamp(0.0, 1.0),
                onChanged: (_) {},
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(track.progressFormatted,
                      style: const TextStyle(
                          color: AppTheme.textFaint, fontSize: 11)),
                  Text(track.durationFormatted,
                      style: const TextStyle(
                          color: AppTheme.textFaint, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlButton(
                  icon: Icons.skip_previous_rounded,
                  onTap: notifier.skipPrevious,
                  size: 28),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: notifier.togglePlayPause,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color:  AppTheme.primary,
                    shape:  BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:      AppTheme.primary.withOpacity(0.4),
                        blurRadius: 16,
                        offset:     const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size:  32,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              _ControlButton(
                  icon: Icons.skip_next_rounded,
                  onTap: notifier.skipNext,
                  size: 28),
            ],
          ),

          const SizedBox(height: 16),

          // Volume
          Row(
            children: [
              const Icon(Icons.volume_down_rounded,
                  color: AppTheme.textFaint, size: 18),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight:        2,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5),
                    activeTrackColor:   AppTheme.textSecondary,
                    inactiveTrackColor: AppTheme.border,
                    thumbColor:         AppTheme.textPrimary,
                  ),
                  child: Slider(
                    value:    volume,
                    min:      0,
                    max:      100,
                    onChanged: (v) => notifier.setVolume(v.round()),
                  ),
                ),
              ),
              const Icon(Icons.volume_up_rounded,
                  color: AppTheme.textFaint, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Playlist section ──────────────────────────────────────────────────────────

class _PlaylistSection extends ConsumerWidget {
  final MusicState state;
  const _PlaylistSection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Playlists',
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (state.playlists.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No playlists found',
                  style: TextStyle(color: AppTheme.textFaint)),
            ),
          )
        else
          ...state.playlists.map(
            (p) => _PlaylistTile(
              playlist: p,
              onTap: () => ref
                  .read(musicNotifierProvider.notifier)
                  .playPlaylist(p),
            ),
          ),
      ],
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final SpotifyPlaylist playlist;
  final VoidCallback    onTap;
  const _PlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin:   const EdgeInsets.only(bottom: 10),
        padding:  const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:  AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.queue_music_rounded,
                  color: AppTheme.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${playlist.trackCount} tracks',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.play_circle_outline_rounded,
                color: AppTheme.primary, size: 28),
          ],
        ),
      ),
    );
  }
}

// ── Device link section ───────────────────────────────────────────────────────

class _DeviceLinkSection extends ConsumerWidget {
  final MusicState state;
  const _DeviceLinkSection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Court Devices',
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Link each court tablet to control its music independently.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...state.courtDevices.map(
          (c) => _CourtDeviceTile(
            courtDevice:      c,
            availableDevices: state.devices,
            onLink: (deviceId, deviceName) =>
                ref.read(musicNotifierProvider.notifier).linkDevice(
                      courtId:    c.courtId,
                      deviceId:   deviceId,
                      deviceName: deviceName,
                    ),
          ),
        ),
      ],
    );
  }
}

class _CourtDeviceTile extends StatelessWidget {
  final CourtDevice             courtDevice;
  final List<SpotifyDevice>     availableDevices;
  final void Function(String, String) onLink;
  const _CourtDeviceTile({
    required this.courtDevice,
    required this.availableDevices,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: courtDevice.isLinked
              ? AppTheme.primary.withOpacity(0.4)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: courtDevice.isLinked
                  ? AppTheme.success
                  : AppTheme.textFaint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(courtDevice.courtName,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(
                  courtDevice.isLinked
                      ? courtDevice.deviceName!
                      : 'No device linked',
                  style: TextStyle(
                    color: courtDevice.isLinked
                        ? AppTheme.primary
                        : AppTheme.textFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showDevicePicker(context),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
            ),
            child: Text(
              courtDevice.isLinked ? 'Change' : 'Link',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _showDevicePicker(BuildContext context) {
    showModalBottomSheet(
      context:         context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select device for ${courtDevice.courtName}',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (availableDevices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No Spotify devices found.\nOpen Spotify on the court tablet first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              ...availableDevices.map(
                (d) => ListTile(
                  leading: Icon(
                    d.type.toLowerCase() == 'tablet'
                        ? Icons.tablet_rounded
                        : Icons.speaker_rounded,
                    color: d.isActive
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                  title: Text(d.name,
                      style: const TextStyle(
                          color: AppTheme.textPrimary)),
                  subtitle: Text(d.type,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12)),
                  trailing: d.isActive
                      ? const Icon(Icons.circle,
                          color: AppTheme.success, size: 10)
                      : null,
                  onTap: () {
                    onLink(d.deviceId, d.name);
                    Navigator.pop(context);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _AlbumArt extends StatelessWidget {
  final String? url;
  const _AlbumArt({this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url != null
          ? Image.network(url!,
              width: 72, height: 72, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder())
          : _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.music_note_rounded,
            color: AppTheme.textFaint, size: 32),
      );
}

class _ControlButton extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  final double       size;
  const _ControlButton(
      {required this.icon, required this.onTap, required this.size});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size + 16, height: size + 16,
        decoration: BoxDecoration(
          color:  AppTheme.surface,
          shape:  BoxShape.circle,
          border: Border.all(color: AppTheme.border),
        ),
        child: Icon(icon, color: AppTheme.textPrimary, size: size),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.textFaint, size: 48),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}