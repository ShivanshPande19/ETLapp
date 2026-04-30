// lib/features/music/presentation/music_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/music_notifier.dart';
import '../domain/music_models.dart';

// ─── Palette (identical to complaints_screen & maintenance_screen) ─────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
const _purple = Color(0xFFA78BFA);
const _spotify = Color(0xFF1DB954);
const _card = Color(0xFFF5F5F5);

// ─── Root ────────────────────────────────────────────────────────────────────
class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});
  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicNotifierProvider);
    final bottom = MediaQuery.of(context).padding.bottom + 92.0;

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(state),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: _buildBody(state, bottom),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(MusicState state) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Music',
                    style: GoogleFonts.antonSc(
                      fontSize: 30,
                      color: _white,
                      letterSpacing: -.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Spotify Connect · Manager only',
                    style: GoogleFonts.inter(fontSize: 11, color: _grey),
                  ),
                ],
              ),
            ),
            if (state.isAuthenticated)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _spotify.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _spotify.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, color: _spotify, size: 7),
                    const SizedBox(width: 5),
                    Text(
                      'Connected',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _spotify,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            _iconBtn(
              Icons.refresh_rounded,
              () => ref.read(musicNotifierProvider.notifier).refresh(),
            ),
          ],
        ),

        // Court selector — only shown when authenticated
        if (state.isAuthenticated) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              _courtTab('All', null, state.selectedCourtId),
              const SizedBox(width: 6),
              _courtTab('Court 1', 1, state.selectedCourtId),
              const SizedBox(width: 6),
              _courtTab('Court 2', 2, state.selectedCourtId),
              const SizedBox(width: 6),
              _courtTab('Court 3', 3, state.selectedCourtId),
            ],
          ),
        ],

        const SizedBox(height: 18),
      ],
    ),
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _white.withOpacity(0.08)),
      ),
      child: Icon(icon, size: 18, color: _grey),
    ),
  );

  Widget _courtTab(String label, int? courtId, int? selected) {
    final sel = selected == courtId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(musicNotifierProvider.notifier).selectCourt(courtId);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _white : _white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: sel ? _black : _grey,
            ),
          ),
        ),
      ),
    );
  }

  // ── Body Router ─────────────────────────────────────────────────────────────
  Widget _buildBody(MusicState state, double navClearance) {
    if (state.status == MusicStatus.loading) {
      return const Center(
        child: CircularProgressIndicator(color: _black, strokeWidth: 2),
      );
    }
    if (state.status == MusicStatus.error) {
      return _ErrorState(
        message: state.error ?? 'Unknown error',
        onRetry: () => ref.read(musicNotifierProvider.notifier).refresh(),
      );
    }
    if (!state.isAuthenticated) {
      return _SpotifyConnectState(
        onConnect: () async {
          final url = await ref
              .read(musicNotifierProvider.notifier)
              .getAuthUrl();
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      );
    }
    return _Dashboard(state: state, navClearance: navClearance);
  }
}

// ─── Spotify Connect Splash ───────────────────────────────────────────────────
class _SpotifyConnectState extends StatelessWidget {
  final VoidCallback onConnect;
  const _SpotifyConnectState({required this.onConnect});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _spotify.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: _spotify,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Connect Spotify',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _black,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Link your Spotify account to control\nmusic across all court tablets.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: _grey, height: 1.5),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: onConnect,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _spotify,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.open_in_new_rounded,
                      color: _white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Connect with Spotify',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Main Dashboard ───────────────────────────────────────────────────────────
class _Dashboard extends ConsumerWidget {
  final MusicState state;
  final double navClearance;
  const _Dashboard({required this.state, required this.navClearance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, navClearance),
      children: [
        // ── Now Playing ──────────────────────────────────────────
        _NowPlayingCard(state: state),
        const SizedBox(height: 20),

        // ── Playlists ────────────────────────────────────────────
        Text(
          'Playlists',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _black,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 10),
        _PlaylistsRow(state: state),
        const SizedBox(height: 20),

        // ── Court Devices ────────────────────────────────────────
        Text(
          'Court Devices',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _black,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Link each court tablet to control music independently.',
          style: GoogleFonts.inter(fontSize: 12, color: _grey),
        ),
        const SizedBox(height: 10),
        ...state.courtDevices.map(
          (c) => _CourtDeviceTile(
            courtDevice: c,
            availableDevices: state.devices,
            onLink: (deviceId, deviceName) => ref
                .read(musicNotifierProvider.notifier)
                .linkDevice(
                  courtId: c.courtId,
                  deviceId: deviceId,
                  deviceName: deviceName,
                ),
          ),
        ),

        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Pull to refresh  ·  auto-refresh 5s',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _black.withOpacity(0.25),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Now Playing Card (dark themed) ──────────────────────────────────────────
class _NowPlayingCard extends ConsumerWidget {
  final MusicState state;
  const _NowPlayingCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.playback?.track;
    final isPlaying = state.playback?.isPlaying ?? false;
    final volume = (state.playback?.device?.volumePercent ?? 50).toDouble();
    final notifier = ref.read(musicNotifierProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + device name
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _spotify.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'NOW PLAYING',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _spotify,
                    letterSpacing: .8,
                  ),
                ),
              ),
              if (state.playback?.device != null) ...[
                const Spacer(),
                const Icon(Icons.speaker_rounded, size: 13, color: _grey),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    state.playback!.device!.name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: _grey),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // Album art + track info
          Row(
            children: [
              _AlbumArt(url: track?.albumArtUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.title ?? 'Nothing playing',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _white,
                        letterSpacing: -.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track != null ? track.artist : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, color: _grey),
                    ),
                    if (track != null)
                      Text(
                        track.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _grey.withOpacity(0.6),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Progress bar + timestamps
          if (track != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: track.progressFraction,
                backgroundColor: _white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(_spotify),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  track.progressFormatted,
                  style: GoogleFonts.inter(fontSize: 10, color: _grey),
                ),
                Text(
                  track.durationFormatted,
                  style: GoogleFonts.inter(fontSize: 10, color: _grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Shuffle
              _CtrlBtn(
                icon: Icons.shuffle_rounded,
                active: state.playback?.shuffle ?? false,
                onTap: () => notifier.toggleShuffle(),
              ),
              // Previous
              _CtrlBtn(
                icon: Icons.skip_previous_rounded,
                onTap: () => notifier.skipPrevious(),
                size: 22,
              ),
              // Play / Pause — big button
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  notifier.togglePlayPause();
                },
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: _white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: _black,
                    size: 30,
                  ),
                ),
              ),
              // Next
              _CtrlBtn(
                icon: Icons.skip_next_rounded,
                onTap: () => notifier.skipNext(),
                size: 22,
              ),
              // Repeat (display only — no backend method yet)
              _CtrlBtn(
                icon: Icons.repeat_rounded,
                active: (state.playback?.repeat ?? 'off') != 'off',
                onTap: () {}, // wired up when backend ready
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Volume slider
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, size: 16, color: _grey),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: _white,
                    inactiveTrackColor: _white.withOpacity(0.15),
                    thumbColor: _white,
                    overlayColor: _white.withOpacity(0.1),
                  ),
                  child: Slider(
                    value: volume.clamp(0, 100),
                    min: 0,
                    max: 100,
                    onChangeEnd: (v) => notifier.setVolume(v.round()),
                    onChanged: (_) {},
                  ),
                ),
              ),
              const Icon(Icons.volume_up_rounded, size: 16, color: _grey),
            ],
          ),
        ],
      ),
    );
  }
}

// small control button inside the dark Now Playing card
class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool active;
  const _CtrlBtn({
    required this.icon,
    required this.onTap,
    this.size = 20,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      onTap();
    },
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: active ? _white.withOpacity(0.12) : _white.withOpacity(0.06),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: active ? _white : _grey, size: size),
    ),
  );
}

// ─── Playlists Horizontal Row ─────────────────────────────────────────────────
class _PlaylistsRow extends ConsumerWidget {
  final MusicState state;
  const _PlaylistsRow({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.playlists.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(Icons.queue_music_rounded, color: _grey, size: 32),
            const SizedBox(height: 8),
            Text(
              'No playlists found',
              style: GoogleFonts.inter(fontSize: 13, color: _grey),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 136,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: state.playlists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final pl = state.playlists[i];
          return _PlaylistCard(
            playlist: pl,
            onTap: () => ref
                .read(musicNotifierProvider.notifier)
                .playPlaylist(pl), // ← passes full SpotifyPlaylist object
          );
        },
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final SpotifyPlaylist playlist;
  final VoidCallback onTap;
  const _PlaylistCard({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      onTap();
    },
    child: Container(
      width: 104,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover art
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: playlist.imageUrl != null
                ? Image.network(
                    playlist.imageUrl!,
                    width: 84,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imgPlaceholder(),
                  )
                : _imgPlaceholder(),
          ),
          const SizedBox(height: 7),
          Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _black,
            ),
          ),
          Text(
            '${playlist.trackCount} tracks',
            style: GoogleFonts.inter(fontSize: 10, color: _grey),
          ),
        ],
      ),
    ),
  );

  Widget _imgPlaceholder() => Container(
    width: 84,
    height: 64,
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.music_note_rounded, color: _grey, size: 26),
  );
}

// ─── Court Device Tile ────────────────────────────────────────────────────────
class _CourtDeviceTile extends StatelessWidget {
  final CourtDevice courtDevice;
  final List<SpotifyDevice> availableDevices;
  final void Function(String deviceId, String deviceName) onLink;
  const _CourtDeviceTile({
    required this.courtDevice,
    required this.availableDevices,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final linked = courtDevice.isLinked;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: linked ? _ok.withOpacity(0.25) : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: linked ? _ok.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.tablet_rounded,
              size: 20,
              color: linked ? _ok : _grey,
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courtDevice.courtName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _black,
                  ),
                ),
                Text(
                  linked ? (courtDevice.deviceName ?? '') : 'No device linked',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: linked ? _ok : _grey,
                  ),
                ),
              ],
            ),
          ),

          // Link / Change button
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _showDevicePicker(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                linked ? 'Change' : 'Link',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDevicePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select device for ${courtDevice.courtName}',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _black,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(height: 12),

            if (availableDevices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Icon(Icons.speaker_outlined, size: 36, color: _grey),
                    const SizedBox(height: 8),
                    Text(
                      'No Spotify devices found.\nOpen Spotify on the court tablet first.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _grey,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...availableDevices.map(
                (d) => GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onLink(d.deviceId, d.name);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: d.isActive
                          ? _ok.withOpacity(0.05)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: d.isActive
                            ? _ok.withOpacity(0.25)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          d.type.toLowerCase() == 'tablet'
                              ? Icons.tablet_rounded
                              : Icons.speaker_rounded,
                          color: d.isActive ? _ok : _grey,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.name,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _black,
                                ),
                              ),
                              Text(
                                d.type,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: _grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (d.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _ok.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Active',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _ok,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Album Art ────────────────────────────────────────────────────────────────
class _AlbumArt extends StatelessWidget {
  final String? url;
  const _AlbumArt({this.url});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: url != null
        ? Image.network(
            url!,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        : _placeholder(),
  );

  Widget _placeholder() => Container(
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      color: _white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.music_note_rounded, color: _grey, size: 32),
  );
}

// ─── Error State ──────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: _grey),
          const SizedBox(height: 12),
          Text(
            'Could not connect',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: _grey, height: 1.5),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: _black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
