// lib/features/staff/presentation/view_roster_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../home/presentation/home_providers.dart';
import '../../../app/dio_provider.dart'; // baseUrl for selfie images

// ─── Premium Palette ─────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _danger = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
const _cardBg = Color(0xFFFAFAFA);

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _formatTime(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '';
  try {
    return DateFormat('hh:mm a').format(DateTime.parse(isoString).toLocal());
  } catch (_) {
    return '';
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String? _fullSelfieUrl(dynamic raw) {
  if (raw == null || raw.toString().isEmpty) return null;
  final p = raw.toString();
  final path = p.startsWith('/') ? p.substring(1) : p;
  return '$baseUrl/$path';
}

class ViewRosterScreen extends ConsumerStatefulWidget {
  const ViewRosterScreen({super.key});

  @override
  ConsumerState<ViewRosterScreen> createState() => _ViewRosterScreenState();
}

class _ViewRosterScreenState extends ConsumerState<ViewRosterScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  DateTime get _selectedDate =>
      ref.watch(selectedRosterDateProvider) ?? DateTime.now();

  void _setDate(DateTime d) {
    HapticFeedback.selectionClick();
    final today = DateTime.now();
    // Never allow the future.
    final clamped = d.isAfter(today) ? today : d;
    ref.read(selectedRosterDateProvider.notifier).setDate(clamped);
    _animCtrl
      ..reset()
      ..forward();
  }

  Future<void> _pickDate() async {
    final current = ref.read(selectedRosterDateProvider) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _ok,
            onPrimary: _black,
            surface: Color(0xFF1A1A1A),
            onSurface: _white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) _setDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final rosterState = ref.watch(dailyRosterProvider);
    final selected = _selectedDate;
    final isToday = _sameDay(selected, DateTime.now());

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── Immersive Dark Header ───
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _white.withOpacity(0.08),
                            shape: BoxShape.circle,
                            border: Border.all(color: _white.withOpacity(0.12)),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: _white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        'DAILY ROSTER',
                        style: GoogleFonts.antonSc(
                          fontSize: 30,
                          color: _white,
                          letterSpacing: 0.5,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // ─── Date Navigator ───
                  _DateNavigator(
                    selected: selected,
                    isToday: isToday,
                    onPrev: () =>
                        _setDate(selected.subtract(const Duration(days: 1))),
                    onNext: isToday
                        ? null
                        : () =>
                              _setDate(selected.add(const Duration(days: 1))),
                    onTapLabel: _pickDate,
                  ),
                ],
              ),
            ),

            // ─── Premium White Canvas ───
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                ),
                child: rosterState.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: _black),
                  ),
                  error: (err, _) => _RosterError(
                    onRetry: () => ref.invalidate(dailyRosterProvider),
                  ),
                  data: (data) {
                    final total = (data['total_staff'] ?? 0) as int;
                    final present = (data['present_count'] ?? 0) as int;
                    final absent = total - present;
                    final rawList = (data['staff_list'] as List?) ?? [];

                    // Present staff first, then absent — both alphabetical.
                    final staffList = [...rawList]
                      ..sort((a, b) {
                        final pa = (a['status'] ?? '').toString() == 'present';
                        final pb = (b['status'] ?? '').toString() == 'present';
                        if (pa != pb) return pa ? -1 : 1;
                        return (a['name'] ?? '').toString().compareTo(
                          (b['name'] ?? '').toString(),
                        );
                      });

                    return FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: RefreshIndicator(
                          color: _black,
                          backgroundColor: _white,
                          strokeWidth: 2,
                          onRefresh: () async {
                            HapticFeedback.mediumImpact();
                            ref.invalidate(dailyRosterProvider);
                            await Future.delayed(
                              const Duration(milliseconds: 600),
                            );
                          },
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              24,
                              32,
                              24,
                              MediaQuery.of(context).padding.bottom + 40,
                            ),
                            children: [
                              _RosterSummaryCard(
                                present: present,
                                absent: absent,
                                total: total,
                              ),
                              const SizedBox(height: 32),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Staff Overview',
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: _black,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  Text(
                                    '$present / $total in',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _grey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (staffList.isEmpty)
                                _EmptyStaff()
                              else
                                ...staffList.map((s) {
                                  final isPresent =
                                      (s['status'] ?? '').toString() ==
                                      'present';
                                  return _StaffCard(
                                    name: (s['name'] ?? 'Unknown').toString(),
                                    isPresent: isPresent,
                                    checkInStr: _formatTime(
                                      s['check_in_time']?.toString(),
                                    ),
                                    checkOutStr: _formatTime(
                                      s['check_out_time']?.toString(),
                                    ),
                                    selfieUrl: _fullSelfieUrl(s['selfie_url']),
                                    onTap: isPresent
                                        ? () => _showStaffDetail(context, s)
                                        : null,
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStaffDetail(BuildContext context, Map<dynamic, dynamic> s) {
    HapticFeedback.selectionClick();
    final selfieUrl = _fullSelfieUrl(s['selfie_url']);
    final checkIn = _formatTime(s['check_in_time']?.toString());
    final checkOut = _formatTime(s['check_out_time']?.toString());

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 24),
              // Big selfie
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _ok.withOpacity(0.3), width: 3),
                ),
                child: ClipOval(
                  child: selfieUrl != null
                      ? Image.network(
                          selfieUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            size: 56,
                            color: _grey,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          size: 56,
                          color: _grey,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                (s['name'] ?? 'Unknown').toString(),
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _black,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _ok.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Present',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _ok,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _DetailTile(
                      icon: Icons.login_rounded,
                      label: 'Checked In',
                      value: checkIn.isEmpty ? '--' : checkIn,
                      color: _ok,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _DetailTile(
                      icon: Icons.logout_rounded,
                      label: 'Checked Out',
                      value: checkOut.isEmpty ? 'On shift' : checkOut,
                      color: checkOut.isEmpty ? _grey : _blue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Date Navigator ────────────────────────────────────────────────────────

class _DateNavigator extends StatelessWidget {
  final DateTime selected;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onTapLabel;

  const _DateNavigator({
    required this.selected,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onTapLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = isToday ? 'Today' : DateFormat('EEE, d MMM').format(selected);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          _navArrow(Icons.chevron_left_rounded, onPrev),
          Expanded(
            child: GestureDetector(
              onTap: onTapLabel,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: _grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _navArrow(Icons.chevron_right_rounded, onNext),
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? _white.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 22,
          color: enabled ? _white : _white.withOpacity(0.2),
        ),
      ),
    );
  }
}

// ─── Summary Card (present ring + counts) ────────────────────────────────────

class _RosterSummaryCard extends StatelessWidget {
  final int present;
  final int absent;
  final int total;
  const _RosterSummaryCard({
    required this.present,
    required this.absent,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : present / total;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Ring
          SizedBox(
            width: 96,
            height: 96,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 8,
                      backgroundColor: _white.withOpacity(0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(_ok),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(value * 100).round()}%',
                        style: GoogleFonts.antonSc(
                          fontSize: 26,
                          color: _white,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        'present',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: Colors.white54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _miniCount('Checked In', present, _ok),
                const SizedBox(height: 10),
                _miniCount('Absent', absent, _danger),
                const SizedBox(height: 10),
                _miniCount('Total Staff', total, _blue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCount(String label, int n, Color c) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 10),
      Text(
        '$n',
        style: GoogleFonts.antonSc(fontSize: 18, color: _white, height: 1.0),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: Colors.white60,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

// ─── Staff Card ──────────────────────────────────────────────────────────────

class _StaffCard extends StatelessWidget {
  final String name;
  final bool isPresent;
  final String checkInStr;
  final String checkOutStr;
  final String? selfieUrl;
  final VoidCallback? onTap;

  const _StaffCard({
    required this.name,
    required this.isPresent,
    required this.checkInStr,
    required this.checkOutStr,
    this.selfieUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isPresent ? _ok.withOpacity(0.25) : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isPresent ? _ok.withOpacity(0.1) : Colors.grey.shade100,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isPresent ? _ok.withOpacity(0.2) : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: (selfieUrl != null && isPresent)
                    ? Image.network(
                        selfieUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallback(),
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _ok,
                                  ),
                                ),
                              ),
                      )
                    : _fallback(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _black,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isPresent)
                    Row(
                      children: [
                        const Icon(
                          Icons.login_rounded,
                          size: 12,
                          color: _ok,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          checkInStr.isEmpty ? '--' : checkInStr,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (checkOutStr.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.logout_rounded,
                            size: 12,
                            color: _blue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            checkOutStr,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    Text(
                      'No check-in record',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _danger.withOpacity(0.8),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            // Status pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isPresent ? _ok.withOpacity(0.1) : _danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isPresent ? _ok : _danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPresent
                        ? (checkOutStr.isEmpty ? 'On shift' : 'Done')
                        : 'Absent',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isPresent ? _ok : _danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Icon(
    Icons.person_rounded,
    size: 26,
    color: isPresent ? _ok.withOpacity(0.6) : _grey.withOpacity(0.4),
  );
}

// ─── Detail tile (in bottom sheet) ───────────────────────────────────────────

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withOpacity(0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 10),
        Text(
          value,
          style: GoogleFonts.antonSc(fontSize: 22, color: _black, height: 1.0),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: _grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ─── Empty + Error ───────────────────────────────────────────────────────────

class _EmptyStaff extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Column(
      children: [
        Icon(Icons.group_off_rounded, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          'No staff members found.',
          style: GoogleFonts.inter(color: _grey, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
}

class _RosterError extends StatelessWidget {
  final VoidCallback onRetry;
  const _RosterError({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, size: 44, color: _grey),
        const SizedBox(height: 14),
        Text(
          'Data Sync Failed',
          style: GoogleFonts.inter(
            color: _danger,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            decoration: BoxDecoration(
              color: _black,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _white,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
