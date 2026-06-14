// lib/features/staff/presentation/view_roster_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../home/presentation/home_providers.dart';
import '../../../app/dio_provider.dart'; // ✅ To get base URL for images

// ─── Premium Palette ─────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _danger = Color(0xFFEF4444);
const _cardBg = Color(0xFFFAFAFA);

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

  String _formatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rosterState = ref.watch(dailyRosterProvider);
    final todayStr = DateFormat('EEEE, MMM d').format(DateTime.now());

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── Immersive Dark Header ───
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Row(
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DAILY ROSTER',
                          style: GoogleFonts.antonSc(
                            fontSize: 32,
                            color: _white,
                            letterSpacing: 0.5,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 14,
                              color: _grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              todayStr,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
                  error: (err, _) => Center(
                    child: Text(
                      "Data Sync Failed",
                      style: GoogleFonts.inter(
                        color: _danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  data: (data) {
                    final total = data['total_staff'] as int;
                    final present = data['present_count'] as int;
                    final absent = total - present;
                    final staffList = data['staff_list'] as List;

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
                              const Duration(milliseconds: 800),
                            );
                          },
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              24,
                              40,
                              24,
                              MediaQuery.of(context).padding.bottom + 40,
                            ),
                            children: [
                              // ─── Summary Stats Grid ───
                              Row(
                                children: [
                                  Expanded(
                                    child: _SummaryStat(
                                      label: 'Checked In',
                                      count: present,
                                      color: _ok,
                                      icon: Icons.how_to_reg_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _SummaryStat(
                                      label: 'Absent',
                                      count: absent,
                                      color: _danger,
                                      icon: Icons.person_off_rounded,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 40),

                              // ─── List Header ───
                              Text(
                                'Staff Overview',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: _black,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ─── Staff List ───
                              if (staffList.isEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 60),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.group_off_rounded,
                                          size: 48,
                                          color: Colors.grey.shade300,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No staff members found.',
                                          style: GoogleFonts.inter(
                                            color: _grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ...staffList.map((s) {
                                  final isPresent =
                                      s['status'].toString().toLowerCase() ==
                                      'present';

                                  // ✅ Resolving Full Image URL from Backend
                                  String? fullImageUrl;
                                  if (s['selfie_url'] != null &&
                                      s['selfie_url'].isNotEmpty) {
                                    // Removing any leading slash to avoid double slashes
                                    final path =
                                        s['selfie_url'].toString().startsWith(
                                          '/',
                                        )
                                        ? s['selfie_url'].toString().substring(
                                            1,
                                          )
                                        : s['selfie_url'].toString();
                                    fullImageUrl = '$baseUrl/$path';
                                  }

                                  return _StaffCard(
                                    name: s['name'],
                                    isPresent: isPresent,
                                    timeStr: _formatTime(s['check_in_time']),
                                    selfieUrl: fullImageUrl,
                                  );
                                }).toList(),
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
}

// ─── Premium Summary Stat Component ───
class _SummaryStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SummaryStat({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                size: 16,
                color: color.withOpacity(0.4),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            count.toString(),
            style: GoogleFonts.antonSc(fontSize: 42, color: color, height: 1.0),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _black.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Premium Staff Member Card ───
class _StaffCard extends StatelessWidget {
  final String name;
  final bool isPresent;
  final String timeStr;
  final String? selfieUrl;

  const _StaffCard({
    required this.name,
    required this.isPresent,
    required this.timeStr,
    this.selfieUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isPresent ? _ok.withOpacity(0.3) : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isPresent
                ? _ok.withOpacity(0.05)
                : Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Real Photo Avatar ──
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isPresent ? _ok.withOpacity(0.1) : Colors.grey.shade100,
              shape: BoxShape.circle,
              border: Border.all(
                color: isPresent ? _ok.withOpacity(0.2) : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: (selfieUrl != null)
                  ? Image.network(
                      selfieUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallbackIcon(),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _ok,
                          ),
                        );
                      },
                    )
                  : _fallbackIcon(),
            ),
          ),
          const SizedBox(width: 16),

          // ── Name & Time Details ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _black,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                if (isPresent && timeStr.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: _grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeStr,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: _grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

          // ── Premium Status Badge ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isPresent ? _white : _cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isPresent
                    ? _ok.withOpacity(0.2)
                    : _danger.withOpacity(0.2),
              ),
              boxShadow: isPresent
                  ? [
                      BoxShadow(
                        color: _ok.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
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
                const SizedBox(width: 8),
                Text(
                  isPresent ? 'Online' : 'Offline',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isPresent ? _ok : _danger,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackIcon() => Icon(
    Icons.person_rounded,
    size: 28,
    color: isPresent ? _ok.withOpacity(0.6) : _grey.withOpacity(0.4),
  );
}
