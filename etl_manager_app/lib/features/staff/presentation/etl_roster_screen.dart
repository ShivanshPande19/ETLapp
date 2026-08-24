// lib/features/staff/presentation/etl_roster_screen.dart
//
// ETL manager ke liye COURT-WISE staff attendance roster.
// Har court ka apna section (alag staff), ek overall summary, date navigator
// aur court filter chips. Data: GET /roster/etl.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../home/presentation/home_providers.dart';
import '../../../app/dio_provider.dart'; // baseUrl for selfie images
import '../../../core/widgets/skeleton.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _danger = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
const _red = Color(0xFFD02128);
const _cardBg = Color(0xFFFAFAFA);

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _formatTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    return DateFormat('hh:mm a').format(DateTime.parse(iso).toLocal());
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

// ─── Screen ───────────────────────────────────────────────────────────────────

class EtlRosterScreen extends ConsumerStatefulWidget {
  const EtlRosterScreen({super.key});

  @override
  ConsumerState<EtlRosterScreen> createState() => _EtlRosterScreenState();
}

class _EtlRosterScreenState extends ConsumerState<EtlRosterScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  // null => saare courts dikhao
  int? _focusedCourtId;

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
    final rosterState = ref.watch(etlRosterProvider);
    final selected = _selectedDate;
    final isToday = _sameDay(selected, DateTime.now());

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Dark header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
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
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.antonSc(
                                  fontSize: 28,
                                  letterSpacing: 0.5,
                                  height: 1.05,
                                ),
                                children: const [
                                  TextSpan(
                                    text: 'STAFF ',
                                    style: TextStyle(color: _white),
                                  ),
                                  TextSpan(
                                    text: 'ROSTER',
                                    style: TextStyle(color: _red),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Court-wise attendance',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _DateNavigator(
                    selected: selected,
                    isToday: isToday,
                    onPrev: () =>
                        _setDate(selected.subtract(const Duration(days: 1))),
                    onNext: isToday
                        ? null
                        : () => _setDate(selected.add(const Duration(days: 1))),
                    onTapLabel: _pickDate,
                  ),
                ],
              ),
            ),

            // ── White canvas ─────────────────────────────────────────
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                ),
                child: rosterState.when(
                  loading: () => const SkeletonList(
                    dark: false,
                    count: 5,
                    tileHeight: 78,
                    showTrailing: true,
                  ),
                  error: (err, _) => _RosterError(
                    onRetry: () => ref.invalidate(etlRosterProvider),
                  ),
                  data: (data) => _buildBody(data),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final totalStaff = (data['total_staff'] ?? 0) as int;
    final totalPresent = (data['total_present'] ?? 0) as int;
    final totalAbsent = totalStaff - totalPresent;

    final rawCourts = (data['courts'] as List?) ?? [];
    final courts = rawCourts
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();

    // Court filter (client-side)
    final visibleCourts = _focusedCourtId == null
        ? courts
        : courts.where((c) => (c['court_id'] as int?) == _focusedCourtId).toList();

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
            ref.invalidate(etlRosterProvider);
            await Future.delayed(const Duration(milliseconds: 600));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              24,
              30,
              24,
              MediaQuery.of(context).padding.bottom + 40,
            ),
            children: [
              _SummaryCard(
                present: totalPresent,
                absent: totalAbsent,
                total: totalStaff,
                courtCount: courts.length,
              ),
              const SizedBox(height: 24),

              if (courts.length > 1) ...[
                _CourtFilterChips(
                  courts: courts,
                  focusedCourtId: _focusedCourtId,
                  onSelect: (id) {
                    HapticFeedback.selectionClick();
                    setState(() => _focusedCourtId = id);
                  },
                ),
                const SizedBox(height: 22),
              ],

              if (courts.isEmpty)
                _EmptyState(
                  icon: Icons.location_city_rounded,
                  message: 'No courts found.',
                )
              else
                ...visibleCourts.map(
                  (court) => _CourtSection(
                    court: court,
                    onStaffTap: (s) => _showStaffDetail(context, s, court),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStaffDetail(
    BuildContext context,
    Map<String, dynamic> s,
    Map<String, dynamic> court,
  ) {
    HapticFeedback.selectionClick();
    final inPhoto = _fullSelfieUrl(s['check_in_photo_url'] ?? s['selfie_url']);
    final outPhoto = _fullSelfieUrl(s['check_out_photo_url']);
    final checkIn = _formatTime(s['check_in_time']?.toString());
    final checkOut = _formatTime(s['check_out_time']?.toString());
    final autoClosed = s['auto_closed'] == true;
    final earlyOut = s['early_checkout'] == true;

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
              Text(
                (s['name'] ?? 'Unknown').toString(),
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _black,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                (court['court_name'] ?? '').toString(),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _grey,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _AttendancePhoto(
                      photoUrl: inPhoto,
                      label: 'Checked In',
                      time: checkIn.isEmpty ? '--' : checkIn,
                      accent: _ok,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _AttendancePhoto(
                      photoUrl: outPhoto,
                      label: 'Checked Out',
                      time: checkOut.isEmpty ? 'On shift' : checkOut,
                      accent: checkOut.isEmpty ? _grey : _blue,
                      note: autoClosed
                          ? 'Auto-closed'
                          : (earlyOut ? 'Early' : null),
                      noteColor: autoClosed
                          ? const Color(0xFFEA580C)
                          : const Color(0xFFE5A000),
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

// ─── Date Navigator ─────────────────────────────────────────────────────────

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

// ─── Summary card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final int present;
  final int absent;
  final int total;
  final int courtCount;

  const _SummaryCard({
    required this.present,
    required this.absent,
    required this.total,
    required this.courtCount,
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
                const SizedBox(height: 9),
                _miniCount('Absent', absent, _danger),
                const SizedBox(height: 9),
                _miniCount('Total Staff', total, _blue),
                const SizedBox(height: 9),
                _miniCount('Courts', courtCount, Colors.white),
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

// ─── Court filter chips ─────────────────────────────────────────────────────

class _CourtFilterChips extends StatelessWidget {
  final List<Map<String, dynamic>> courts;
  final int? focusedCourtId;
  final void Function(int?) onSelect;

  const _CourtFilterChips({
    required this.courts,
    required this.focusedCourtId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _chip('All Courts', focusedCourtId == null, () => onSelect(null)),
          ...courts.map((c) {
            final id = c['court_id'] as int?;
            final name = (c['court_name'] ?? 'Court').toString();
            return _chip(name, focusedCourtId == id, () => onSelect(id));
          }),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? _black : _white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? _black : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? _white : _grey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Court section ──────────────────────────────────────────────────────────

class _CourtSection extends StatelessWidget {
  final Map<String, dynamic> court;
  final void Function(Map<String, dynamic>) onStaffTap;

  const _CourtSection({required this.court, required this.onStaffTap});

  @override
  Widget build(BuildContext context) {
    final name = (court['court_name'] ?? 'Court').toString();
    final present = (court['present_count'] ?? 0) as int;
    final total = (court['total_staff'] ?? 0) as int;
    final rawList = (court['staff_list'] as List?) ?? [];
    final staffList = rawList
        .whereType<Map>()
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
    final allPresent = total > 0 && present == total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Court header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.stadium_rounded,
                  size: 18,
                  color: _white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: _black,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: (allPresent ? _ok : _grey).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (allPresent ? _ok : Colors.grey.shade300),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  '$present / $total in',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: allPresent ? _ok : _grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (staffList.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: Text(
                  'No staff assigned to this court.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            ...staffList.map((s) {
              final isPresent = (s['status'] ?? '').toString() == 'present';
              final checkOut = _formatTime(s['check_out_time']?.toString());
              return _StaffCard(
                name: (s['name'] ?? 'Unknown').toString(),
                isPresent: isPresent,
                checkInStr: _formatTime(s['check_in_time']?.toString()),
                checkOutStr: checkOut,
                selfieUrl: _fullSelfieUrl(s['selfie_url']),
                onTap: isPresent ? () => onStaffTap(s) : null,
              );
            }),
        ],
      ),
    );
  }
}

// ─── Staff card ─────────────────────────────────────────────────────────────

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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPresent ? _ok.withOpacity(0.25) : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
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
                        const Icon(Icons.login_rounded, size: 12, color: _ok),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isPresent
                    ? _ok.withOpacity(0.1)
                    : _danger.withOpacity(0.08),
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
    size: 24,
    color: isPresent ? _ok.withOpacity(0.6) : _grey.withOpacity(0.4),
  );
}

// ─── Detail tile (bottom sheet) ─────────────────────────────────────────────

class _AttendancePhoto extends StatelessWidget {
  final String? photoUrl;
  final String label;
  final String time;
  final Color accent;
  final String? note;
  final Color? noteColor;

  const _AttendancePhoto({
    required this.photoUrl,
    required this.label,
    required this.time,
    required this.accent,
    this.note,
    this.noteColor,
  });

  void _openFull(BuildContext context) {
    if (photoUrl == null) return;
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(photoUrl!, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 50,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _openFull(context),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withOpacity(0.35), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: photoUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded,
                                size: 36, color: _grey),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.open_in_full_rounded,
                                size: 13, color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.no_photography_rounded,
                              size: 30, color: _grey.withOpacity(0.6)),
                          const SizedBox(height: 4),
                          Text('No photo',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: _grey)),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          time,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _black,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (noteColor ?? _grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              note!,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: noteColor ?? _grey,
              ),
            ),
          ),
        ],
      ],
    );
  }
}


// ─── Empty + Error ──────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Column(
      children: [
        Icon(icon, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          message,
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
                color: _white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
