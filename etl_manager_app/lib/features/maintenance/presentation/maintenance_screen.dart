// lib/features/maintenance/presentation/maintenance_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/maintenance_notifier.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_notifier.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _blue = Color(0xFF3B82F6);
const _warn = Color(0xFFF59E0B);
const _purple = Color(0xFFA855F7);
const _red = Color(0xFFEF4444);
const _cardBg = Color(0xFFFAFAFA);

// ─── Status & Priority Meta ──────────────────────────────────────────────────

class _StatusMeta {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusMeta(this.label, this.color, this.icon);
}

_StatusMeta _statusMeta(String s) => switch (s) {
  'RAISED' => const _StatusMeta('Raised', _warn, Icons.error_outline_rounded),
  'ASSIGNED' => const _StatusMeta('Assigned', _blue, Icons.engineering_rounded),
  'RESOLVED' => const _StatusMeta(
    'Verify Fix',
    _purple,
    Icons.fact_check_rounded,
  ),
  'CLOSED' => const _StatusMeta('Closed', _ok, Icons.check_circle_rounded),
  'DISPUTED' => const _StatusMeta('Disputed', _red, Icons.gpp_bad_rounded),
  _ => const _StatusMeta('Unknown', _grey, Icons.help_outline_rounded),
};

class _PriorityMeta {
  final String label;
  final Color color;
  const _PriorityMeta(this.label, this.color);
}

_PriorityMeta _priorityMeta(String p) => switch (p) {
  'high' => const _PriorityMeta('HIGH', _red),
  'low' => const _PriorityMeta('LOW', Color(0xFF94A3B8)),
  _ => const _PriorityMeta('MED', _warn),
};

class _TypeMeta {
  final String emoji;
  final String label;
  const _TypeMeta(this.emoji, this.label);
}

_TypeMeta _typeMeta(String t) => switch (t) {
  'electrical' => const _TypeMeta('⚡', 'Electrical'),
  'plumbing' => const _TypeMeta('🔧', 'Plumbing'),
  'furniture' => const _TypeMeta('🪑', 'Furniture'),
  'cleaning' => const _TypeMeta('🧹', 'Deep Clean'),
  _ => const _TypeMeta('📋', 'Other'),
};

// ─── Time helpers ────────────────────────────────────────────────────────────

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _fmtDateTime(DateTime? d) {
  if (d == null) return '—';
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day} ${_months[d.month - 1]}, $h12:${d.minute.toString().padLeft(2, '0')} $ampm';
}

String _relTime(DateTime? d) {
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays}d ago';
}

String _fmtCountdown(Duration d) {
  if (d.inMinutes <= 0) return 'closing soon';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  return '${d.inMinutes}m';
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen>
    with TickerProviderStateMixin {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Action Req.', 'Open', 'Closed'];

  late final AnimationController _fadeCtrl;
  late final AnimationController _listCtrl;
  late final Animation<double> _fadeAnim;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _listCtrl.forward();
    });

    // ✅ Live countdown tick — RESOLVED tickets ka timer har minute update
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _fadeCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _switchFilter(String f) {
    if (f == _selectedFilter) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedFilter = f);
    _listCtrl
      ..reset()
      ..forward();
  }

  Animation<double> _itemAnim(int i) => CurvedAnimation(
    parent: _listCtrl,
    curve: Interval(
      (i * 0.07).clamp(0.0, 0.7),
      ((i * 0.07) + 0.4).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ),
  );

  void _showRaiseSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RaiseTicketSheet(),
    );
  }

  void _showDetailSheet(MaintenanceIssueModel issue, bool isManager) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _TicketDetailSheet(issueId: issue.id, isManager: isManager),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(maintenanceNotifierProvider);
    final authState = ref.watch(authNotifierProvider);

    final bool isOutletUser =
        authState.isOutletManager || authState.isOutletStaff;
    final bool isManager = authState.isEtlManager;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ───
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(isManager ? '/home' : '/outlet-home');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _white.withOpacity(0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: _white.withOpacity(0.1)),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: _white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isManager ? 'ALL COURTS' : 'YOUR OUTLET',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _grey,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'MAINTENANCE',
                            style: GoogleFonts.antonSc(
                              fontSize: 34,
                              color: _white,
                              height: 1.0,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref
                            .read(maintenanceNotifierProvider.notifier)
                            .refresh();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _white.withOpacity(0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: _white.withOpacity(0.1)),
                        ),
                        child: const Icon(
                          Icons.refresh_rounded,
                          color: _grey,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Summary stat bar (dark) ───
              state.maybeWhen(
                data: (issues) => Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                  child: _SummaryBar(issues: issues, isManager: isManager),
                ),
                orElse: () => const SizedBox(height: 8),
              ),

              // ─── Filter chips ───
              SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _filters.length,
                  itemBuilder: (context, i) {
                    final f = _filters[i];
                    final sel = _selectedFilter == f;
                    return GestureDetector(
                      onTap: () => _switchFilter(f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? _white : _white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          f,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            color: sel ? _black : _grey,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // ─── White canvas ───
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(36),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(36),
                    ),
                    child: RefreshIndicator(
                      color: _black,
                      backgroundColor: _white,
                      onRefresh: () => ref
                          .read(maintenanceNotifierProvider.notifier)
                          .refresh(),
                      child: state.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(
                            color: _black,
                            strokeWidth: 2,
                          ),
                        ),
                        error: (err, _) => _ErrorView(
                          message: err.toString(),
                          onRetry: () => ref
                              .read(maintenanceNotifierProvider.notifier)
                              .refresh(),
                        ),
                        data: (issues) {
                          final filtered = issues.where((i) {
                            switch (_selectedFilter) {
                              case 'Open':
                                return i.status != 'CLOSED';
                              case 'Closed':
                                return i.status == 'CLOSED';
                              case 'Action Req.':
                                return isManager
                                    ? (i.status == 'RAISED' ||
                                          i.status == 'DISPUTED')
                                    : (i.status == 'RESOLVED');
                              default:
                                return true;
                            }
                          }).toList();

                          if (filtered.isEmpty) {
                            return _EmptyView(
                              filter: _selectedFilter,
                              isOutletUser: isOutletUser,
                              onRaise: isOutletUser ? _showRaiseSheet : null,
                            );
                          }

                          return ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 140),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final issue = filtered[i];
                              final anim = _itemAnim(i);
                              return FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.08),
                                    end: Offset.zero,
                                  ).animate(anim),
                                  child: _TicketCard(
                                    issue: issue,
                                    isManager: isManager,
                                    onTap: () =>
                                        _showDetailSheet(issue, isManager),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // ─── FAB (outlet users only) ───
      floatingActionButton: isOutletUser
          ? Padding(
              padding: const EdgeInsets.only(bottom: 90),
              child: FloatingActionButton.extended(
                backgroundColor: _black,
                elevation: 8,
                onPressed: _showRaiseSheet,
                icon: const Icon(Icons.add_rounded, color: _white),
                label: Text(
                  'Raise Ticket',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: _white,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

// ─── Summary Bar ─────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final List<MaintenanceIssueModel> issues;
  final bool isManager;
  const _SummaryBar({required this.issues, required this.isManager});

  @override
  Widget build(BuildContext context) {
    final raised = issues.where((i) => i.status == 'RAISED').length;
    final inProgress = issues
        .where((i) => i.status == 'ASSIGNED' || i.status == 'RESOLVED')
        .length;
    final disputed = issues.where((i) => i.status == 'DISPUTED').length;
    final closed = issues.where((i) => i.status == 'CLOSED').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          _Stat('New', raised, _warn),
          _vDiv(),
          _Stat('Active', inProgress, _blue),
          _vDiv(),
          _Stat('Disputed', disputed, _red),
          _vDiv(),
          _Stat('Closed', closed, _ok),
        ],
      ),
    );
  }

  Widget _vDiv() => Container(
    width: 1,
    height: 30,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: _white.withOpacity(0.08),
  );
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Text(
            v.toInt().toString(),
            style: GoogleFonts.antonSc(fontSize: 20, color: color, height: 1.0),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: _grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ─── Ticket Card ─────────────────────────────────────────────────────────────

class _TicketCard extends StatelessWidget {
  final MaintenanceIssueModel issue;
  final bool isManager;
  final VoidCallback onTap;
  const _TicketCard({
    required this.issue,
    required this.isManager,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final st = _statusMeta(issue.status);
    final pr = _priorityMeta(issue.priority);
    final type = _typeMeta(issue.issueType);
    final countdown = issue.timeUntilAutoClose;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: st.color.withOpacity(0.25), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: st.color.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Row(
                children: [
                  // Status pill with glowing dot
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: st.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: st.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: st.color.withOpacity(0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          st.label.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: st.color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Priority flag
                  _PriorityFlag(meta: pr, isHigh: issue.priority == 'high'),
                  const Spacer(),
                  Text(
                    _relTime(issue.createdAt),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: _grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Center(
                      child: Text(
                        type.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.label,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _black,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          issue.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: _grey,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (issue.photoUrl != null) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        resolveMediaUrl(issue.photoUrl)!,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Footer: outlet/court + technician + countdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.storefront_rounded, size: 13, color: _grey),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      isManager
                          ? '${issue.outletName} · ${issue.courtName}'
                          : issue.outletName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _black.withOpacity(0.75),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (issue.status == 'RESOLVED' && countdown != null)
                    // ✅ Live countdown chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _purple.withOpacity(0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.hourglass_top_rounded,
                            size: 11,
                            color: _purple,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Auto-closes in ${_fmtCountdown(countdown)}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _purple,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (issue.status == 'ASSIGNED' &&
                      issue.technicianName != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.engineering_rounded,
                          size: 12,
                          color: _blue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          issue.technicianName!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _blue,
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
    );
  }
}

// ─── Priority Flag (pulses on HIGH) ──────────────────────────────────────────

class _PriorityFlag extends StatefulWidget {
  final _PriorityMeta meta;
  final bool isHigh;
  const _PriorityFlag({required this.meta, required this.isHigh});

  @override
  State<_PriorityFlag> createState() => _PriorityFlagState();
}

class _PriorityFlagState extends State<_PriorityFlag>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.isHigh) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: widget.meta.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_rounded, size: 10, color: widget.meta.color),
          const SizedBox(width: 3),
          Text(
            widget.meta.label,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: widget.meta.color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );

    if (_pulse == null) return chip;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 1.0,
        end: 0.55,
      ).animate(CurvedAnimation(parent: _pulse!, curve: Curves.easeInOut)),
      child: chip,
    );
  }
}

// ─── Raise Ticket Sheet ──────────────────────────────────────────────────────

class _RaiseTicketSheet extends ConsumerStatefulWidget {
  const _RaiseTicketSheet();
  @override
  ConsumerState<_RaiseTicketSheet> createState() => _RaiseTicketSheetState();
}

class _RaiseTicketSheetState extends ConsumerState<_RaiseTicketSheet> {
  String _type = 'electrical';
  String _priority = 'medium';
  final _descCtrl = TextEditingController();
  File? _photo;
  bool _loading = false;

  final Map<String, String> _types = {
    'electrical': '⚡ Electrical',
    'plumbing': '🔧 Plumbing',
    'furniture': '🪑 Furniture',
    'cleaning': '🧹 Deep Clean',
    'other': '📋 Other',
  };

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (x != null && mounted) setState(() => _photo = File(x.path));
  }

  Future<void> _submit() async {
    final desc = _descCtrl.text.trim();
    if (desc.length < 5) {
      _snack('Please describe the issue (min 5 characters).');
      return;
    }
    setState(() => _loading = true);
    final error = await ref
        .read(maintenanceNotifierProvider.notifier)
        .raiseTicket(
          issueType: _type,
          priority: _priority,
          description: desc,
          photo: _photo,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (error == null) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
    } else {
      _snack(error);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: _white)),
        backgroundColor: _black,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Raise New Ticket',
                style: GoogleFonts.antonSc(fontSize: 24, color: _black),
              ),
              const SizedBox(height: 22),

              _sectionLabel('ISSUE TYPE'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _types.entries.map((e) {
                  final sel = _type == e.key;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _type = e.key);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? _black : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        e.value,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? _white : _black,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              _sectionLabel('PRIORITY'),
              const SizedBox(height: 10),
              Row(
                children: ['low', 'medium', 'high'].map((p) {
                  final meta = _priorityMeta(p);
                  final sel = _priority == p;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _priority = p);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: EdgeInsets.only(right: p != 'high' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: sel
                              ? meta.color.withOpacity(0.12)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel ? meta.color : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flag_rounded,
                                size: 13,
                                color: sel ? meta.color : _grey,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                p[0].toUpperCase() + p.substring(1),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: sel ? meta.color : _grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              _sectionLabel('DESCRIPTION'),
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                maxLength: 1000,
                style: GoogleFonts.inter(color: _black, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Describe the issue in detail...',
                  hintStyle: GoogleFonts.inter(color: _grey),
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _black, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _sectionLabel('PHOTO PROOF (OPTIONAL)'),
              const SizedBox(height: 10),
              if (_photo == null)
                Row(
                  children: [
                    _photoBtn(
                      Icons.camera_alt_rounded,
                      'Camera',
                      () => _pickPhoto(ImageSource.camera),
                    ),
                    const SizedBox(width: 10),
                    _photoBtn(
                      Icons.photo_library_rounded,
                      'Gallery',
                      () => _pickPhoto(ImageSource.gallery),
                    ),
                  ],
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        _photo!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _photo = null),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _black.withOpacity(0.7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: _white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 26),

              GestureDetector(
                onTap: _loading ? null : _submit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _loading ? _grey : _black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: _white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Submit Ticket',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(
    t,
    style: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: _grey,
      letterSpacing: 1.0,
    ),
  );

  Widget _photoBtn(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: _black),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _black,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Ticket Detail Sheet (Timeline + Actions) ────────────────────────────────

class _TicketDetailSheet extends ConsumerStatefulWidget {
  final int issueId;
  final bool isManager;
  const _TicketDetailSheet({required this.issueId, required this.isManager});

  @override
  ConsumerState<_TicketDetailSheet> createState() => _TicketDetailSheetState();
}

class _TicketDetailSheetState extends ConsumerState<_TicketDetailSheet> {
  bool _loading = false;
  bool _showAssignForm = false;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _loading = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _loading = false);
    if (error == null) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: GoogleFonts.inter(color: _white)),
          backgroundColor: _black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _callTechnician(String phone) async {
    // Keep only digits and a leading '+' so spaces/dashes don't break the URI.
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    try {
      // Opens the phone dialer with the number pre-filled. On a dual-SIM phone
      // the native dialer shows the SIM chooser when the call is placed.
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the dialer ($cleaned).')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calling is not supported on this device.'),
          ),
        );
      }
    }
  }

  void _viewPhoto(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.network(resolveMediaUrl(url) ?? url))),
            Positioned(
              top: 50,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: _white,
                    size: 18,
                  ),
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
    // ✅ Live data — SSE/refresh pe sheet bhi update hoti hai
    final issues = ref.watch(maintenanceNotifierProvider).value ?? [];
    final matches = issues.where((i) => i.id == widget.issueId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final issue = matches.first;

    final st = _statusMeta(issue.status);
    final type = _typeMeta(issue.issueType);
    final pr = _priorityMeta(issue.priority);
    final countdown = issue.timeUntilAutoClose;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: st.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                      child: Text(
                        type.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${type.label} · #${issue.id}',
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: _black,
                          ),
                        ),
                        Text(
                          '${issue.outletName} · ${issue.courtName}',
                          style: GoogleFonts.inter(fontSize: 12, color: _grey),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: st.color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          st.label.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_rounded, size: 10, color: pr.color),
                          const SizedBox(width: 3),
                          Text(
                            pr.label,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: pr.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Description card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.description,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: _black,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline_rounded,
                          size: 13,
                          color: _grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Raised by ${issue.staffName}',
                          style: GoogleFonts.inter(fontSize: 12, color: _grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Photo proof
              if (issue.photoUrl != null) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _viewPhoto(issue.photoUrl!),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          resolveMediaUrl(issue.photoUrl)!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.open_in_full_rounded,
                                size: 11,
                                color: _white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'View',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: _white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Technician card with CALL button
              if (issue.technicianName != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _blue.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.engineering_rounded,
                          color: _blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              issue.technicianName!,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _black,
                              ),
                            ),
                            if (issue.technicianPhone != null)
                              Text(
                                issue.technicianPhone!,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: _grey,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (issue.technicianPhone != null)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            _callTechnician(issue.technicianPhone!);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: _ok,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_rounded,
                              color: _white,
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              // Countdown banner (RESOLVED state)
              if (issue.status == 'RESOLVED' && countdown != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _purple.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top_rounded,
                        color: _purple,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.isManager
                              ? 'Waiting for outlet verification — auto-closes in ${_fmtCountdown(countdown)}.'
                              : 'Verify within ${_fmtCountdown(countdown)} or this ticket auto-closes.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _purple,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ─── Timeline ───
              Text(
                'TIMELINE',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _grey,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              _Timeline(issue: issue),

              const SizedBox(height: 24),

              // ─── Actions ───
              ..._buildActions(issue),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(MaintenanceIssueModel issue) {
    final notifier = ref.read(maintenanceNotifierProvider.notifier);

    // Manager: assign on RAISED/DISPUTED
    if (widget.isManager &&
        (issue.status == 'RAISED' || issue.status == 'DISPUTED')) {
      if (!_showAssignForm) {
        return [
          _Btn(
            label: 'Assign Technician',
            color: _black,
            icon: Icons.engineering_rounded,
            loading: _loading,
            onTap: () => setState(() => _showAssignForm = true),
          ),
          const SizedBox(height: 10),
          _Btn(
            label: 'Mark Resolved Directly',
            color: _purple,
            icon: Icons.fact_check_rounded,
            loading: _loading,
            outlined: true,
            onTap: () => _run(() => notifier.markResolved(issue.id)),
          ),
        ];
      }
      return [
        _field(_nameCtrl, 'Technician Name', Icons.person_rounded),
        const SizedBox(height: 10),
        _field(
          _phoneCtrl,
          'Phone Number',
          Icons.phone_rounded,
          keyboard: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        _Btn(
          label: 'Confirm Assignment',
          color: _blue,
          icon: Icons.check_rounded,
          loading: _loading,
          onTap: () {
            if (_nameCtrl.text.trim().length < 2 ||
                _phoneCtrl.text.trim().length < 7) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Enter valid name & phone',
                    style: GoogleFonts.inter(color: _white),
                  ),
                  backgroundColor: _black,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            _run(
              () => notifier.assignTechnician(
                issue.id,
                _nameCtrl.text,
                _phoneCtrl.text,
              ),
            );
          },
        ),
      ];
    }

    // Manager: resolve on ASSIGNED
    if (widget.isManager && issue.status == 'ASSIGNED') {
      return [
        _Btn(
          label: 'Mark as Resolved',
          color: _purple,
          icon: Icons.fact_check_rounded,
          loading: _loading,
          onTap: () => _run(() => notifier.markResolved(issue.id)),
        ),
      ];
    }

    // Outlet: verify on RESOLVED
    if (!widget.isManager && issue.status == 'RESOLVED') {
      return [
        Text(
          'Is the issue actually fixed?',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _black,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Btn(
                label: 'No, Reopen',
                color: _red,
                icon: Icons.replay_rounded,
                loading: _loading,
                outlined: true,
                onTap: () => _run(() => notifier.verifyTicket(issue.id, false)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Btn(
                label: 'Yes, Close It',
                color: _ok,
                icon: Icons.check_circle_rounded,
                loading: _loading,
                onTap: () => _run(() => notifier.verifyTicket(issue.id, true)),
              ),
            ),
          ],
        ),
      ];
    }

    return [];
  }

  Widget _field(
    TextEditingController c,
    String hint,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
  }) => TextField(
    controller: c,
    keyboardType: keyboard,
    style: GoogleFonts.inter(color: _black, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: _grey, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: _grey),
      filled: true,
      fillColor: const Color(0xFFFAFAFA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _black, width: 1.5),
      ),
    ),
  );
}

// ─── Timeline Widget ─────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  final MaintenanceIssueModel issue;
  const _Timeline({required this.issue});

  @override
  Widget build(BuildContext context) {
    final steps = <(String, DateTime?, Color, bool)>[
      ('Ticket Raised', issue.createdAt, _warn, true),
      (
        issue.technicianName != null
            ? 'Assigned to ${issue.technicianName}'
            : 'Technician Assigned',
        issue.technicianName != null ? issue.updatedAt : null,
        _blue,
        issue.technicianName != null,
      ),
      (
        'Marked Resolved',
        issue.resolvedAt,
        _purple,
        issue.resolvedAt != null || issue.status == 'CLOSED',
      ),
      if (issue.status == 'DISPUTED')
        ('Disputed by Outlet', issue.updatedAt, _red, true)
      else
        ('Closed', issue.closedAt, _ok, issue.status == 'CLOSED'),
    ];

    return Column(
      children: steps.asMap().entries.map((entry) {
        final i = entry.key;
        final (label, time, color, done) = entry.value;
        final isLast = i == steps.length - 1;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + (i * 120)),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => Opacity(opacity: v, child: child),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: done ? color : Colors.grey.shade200,
                        shape: BoxShape.circle,
                        boxShadow: done
                            ? [
                                BoxShadow(
                                  color: color.withOpacity(0.4),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                      child: done
                          ? const Icon(
                              Icons.check_rounded,
                              size: 9,
                              color: _white,
                            )
                          : null,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: done
                              ? color.withOpacity(0.3)
                              : Colors.grey.shade200,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: done ? _black : _grey,
                          ),
                        ),
                        if (time != null)
                          Text(
                            _fmtDateTime(time),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Shared Button ───────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool loading;
  final bool outlined;
  final VoidCallback onTap;
  const _Btn({
    required this.label,
    required this.color,
    required this.icon,
    required this.loading,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading
        ? null
        : () {
            HapticFeedback.mediumImpact();
            onTap();
          },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: loading ? _grey : (outlined ? color.withOpacity(0.08) : color),
        borderRadius: BorderRadius.circular(15),
        border: outlined
            ? Border.all(color: color.withOpacity(0.3), width: 1.5)
            : null,
      ),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: _white, strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: outlined ? color : _white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: outlined ? color : _white,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}

// ─── Empty & Error states ────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final String filter;
  final bool isOutletUser;
  final VoidCallback? onRaise;
  const _EmptyView({
    required this.filter,
    required this.isOutletUser,
    this.onRaise,
  });

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.only(top: 70),
    children: [
      Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200, width: 2),
              ),
              child: const Icon(Icons.handyman_rounded, size: 44, color: _grey),
            ),
            const SizedBox(height: 20),
            Text(
              filter == 'All' ? 'No tickets yet' : 'No "$filter" tickets',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isOutletUser
                  ? 'Something broken? Raise a ticket below.'
                  : 'All clear — nothing needs attention.',
              style: GoogleFonts.inter(fontSize: 13, color: _grey),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(40, 70, 40, 0),
    children: [
      const Icon(Icons.wifi_off_rounded, size: 44, color: _grey),
      const SizedBox(height: 14),
      Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _black,
        ),
      ),
      const SizedBox(height: 18),
      Center(
        child: GestureDetector(
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
      ),
    ],
  );
}
