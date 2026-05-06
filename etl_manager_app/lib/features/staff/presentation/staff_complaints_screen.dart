// lib/features/staff/presentation/staff_complaints_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../complaints/domain/complaint_model.dart';
import '../../complaints/data/complaints_repository.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFE5A000);
const _danger = Color(0xFFFF4444);
const _red = Color(0xFFD02128);
const _border = Color(0xFFE5E5E5);

// ─── Provider ─────────────────────────────────────────────────────────────────
final _complaintsListProvider = FutureProvider.autoDispose
    .family<List<ComplaintModel>, int>((ref, courtId) async {
      final repo = ref.read(complaintsRepoProvider);
      final open = await repo.getComplaints(courtId: courtId, status: 'open');
      final resolved = await repo.getComplaints(
        courtId: courtId,
        status: 'resolved',
      );
      final all = [...open, ...resolved];
      all.sort((a, b) {
        final aT = a.createdAt ?? DateTime(2000);
        final bT = b.createdAt ?? DateTime(2000);
        return bT.compareTo(aT);
      });
      return all;
    });

// ─── Screen ───────────────────────────────────────────────────────────────────
class StaffComplaintsScreen extends ConsumerStatefulWidget {
  final int courtId;
  final String courtName;
  const StaffComplaintsScreen({
    super.key,
    required this.courtId,
    required this.courtName,
  });
  @override
  ConsumerState<StaffComplaintsScreen> createState() =>
      _StaffComplaintsScreenState();
}

class _StaffComplaintsScreenState extends ConsumerState<StaffComplaintsScreen>
    with TickerProviderStateMixin {
  // ── Entry animations ────────────────────────────────────────────────────────
  late final AnimationController _fadeCtrl; // screen fade-in
  late final AnimationController _heroCtrl; // header slide-up
  late final AnimationController _listCtrl; // list stagger
  late final Animation<double> _fadeAnim;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  // ── Filter-switch animation ──────────────────────────────────────────────────
  late final AnimationController _contentCtrl; // content cross-fade

  final ScrollController _scrollCtrl = ScrollController();
  String _filter = 'all';

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
    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));

    // Entry sequence
    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _heroCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _listCtrl.forward();
    });
    _contentCtrl.value = 1.0; // start visible
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _heroCtrl.dispose();
    _listCtrl.dispose();
    _contentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Filter switch: fade-out → change → re-stagger → fade-in ────────────────
  Future<void> _switchFilter(String next) async {
    if (next == _filter) return;
    HapticFeedback.selectionClick();

    await _contentCtrl.reverse(); // fade list out

    if (_scrollCtrl.hasClients && _scrollCtrl.offset > 0) {
      _scrollCtrl.jumpTo(0);
    }

    setState(() => _filter = next);

    _listCtrl
      ..reset()
      ..forward(); // re-stagger cards

    _contentCtrl.forward(); // fade list back in
  }

  Future<void> _refresh() async {
    HapticFeedback.mediumImpact();
    if (_scrollCtrl.hasClients && _scrollCtrl.offset > 0) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    _listCtrl.reset();
    ref.invalidate(_complaintsListProvider(widget.courtId));
    await ref
        .read(_complaintsListProvider(widget.courtId).future)
        .catchError((_) => <ComplaintModel>[]);
    if (mounted) _listCtrl.forward();
  }

  Animation<double> _itemAnim(int i) => CurvedAnimation(
    parent: _listCtrl,
    curve: Interval(
      (i * 0.08).clamp(0.0, 0.7),
      ((i * 0.08) + 0.4).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_complaintsListProvider(widget.courtId));

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── DARK HEADER ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back row
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                              color: _white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Court name fades in with hero
                        FadeTransition(
                          opacity: _heroFade,
                          child: Text(
                            widget.courtName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _white.withOpacity(0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Big title slides up
                    FadeTransition(
                      opacity: _heroFade,
                      child: SlideTransition(
                        position: _heroSlide,
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.antonSc(
                              fontSize: 42,
                              height: 0.95,
                              letterSpacing: -0.5,
                            ),
                            children: const [
                              TextSpan(
                                text: 'C',
                                style: TextStyle(color: _red),
                              ),
                              TextSpan(
                                text: 'OMPLAINTS',
                                style: TextStyle(color: _white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Filter chips — slide in with hero
                    FadeTransition(
                      opacity: _heroFade,
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, 0.15),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: _heroCtrl,
                                curve: const Interval(
                                  0.3,
                                  1.0,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                            ),
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'All',
                              active: _filter == 'all',
                              onTap: () => _switchFilter('all'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Open',
                              active: _filter == 'open',
                              color: _danger,
                              onTap: () => _switchFilter('open'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Resolved',
                              active: _filter == 'resolved',
                              color: _ok,
                              onTap: () => _switchFilter('resolved'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── WHITE LIST AREA ──────────────────────────────────────────
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  // Cross-fade wrapper on filter switch
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _contentCtrl,
                      curve: Curves.easeOutCubic,
                    ),
                    child: async.when(
                      loading: () => _LoadingList(),
                      error: (e, _) => _CenteredMsg(
                        icon: Icons.wifi_off_rounded,
                        iconColor: _danger,
                        title: 'Could not load',
                        subtitle: 'Pull down to retry',
                        action: TextButton(
                          onPressed: _refresh,
                          child: Text(
                            'Retry',
                            style: GoogleFonts.inter(
                              color: _danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      data: (all) {
                        final filtered = _filter == 'all'
                            ? all
                            : all.where((c) => c.status == _filter).toList();

                        if (filtered.isEmpty) {
                          return _CenteredMsg(
                            icon: _filter == 'open'
                                ? Icons.check_circle_rounded
                                : Icons.inbox_rounded,
                            iconColor: _filter == 'open' ? _ok : _grey,
                            title: _filter == 'open'
                                ? 'No open complaints'
                                : 'No complaints found',
                            subtitle: _filter == 'open'
                                ? 'All clear for this court 🎉'
                                : 'Pull down to refresh',
                          );
                        }

                        return RefreshIndicator(
                          color: _black,
                          backgroundColor: _white,
                          strokeWidth: 2,
                          displacement: 40,
                          onRefresh: _refresh,
                          child: ListView.separated(
                            controller: _scrollCtrl,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              20,
                              20,
                              20,
                              MediaQuery.of(context).padding.bottom + 100,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final c = filtered[i];
                              return _ComplaintCard(
                                complaint: c,
                                anim: _itemAnim(i),
                                onTap: () => _showDetail(context, c),
                              );
                            },
                          ),
                        );
                      },
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

  void _showDetail(BuildContext context, ComplaintModel c) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true, // ← shell ke upar render
      barrierColor: Colors.black.withOpacity(0.55), // ← peeche sab dark
      builder: (_) => _ComplaintDetailSheet(complaint: c),
    );
  }
}

// ─── Complaint Card ────────────────────────────────────────────────────────────
class _ComplaintCard extends StatefulWidget {
  final ComplaintModel complaint;
  final Animation<double> anim;
  final VoidCallback onTap;
  const _ComplaintCard({
    required this.complaint,
    required this.anim,
    required this.onTap,
  });
  @override
  State<_ComplaintCard> createState() => _ComplaintCardState();
}

class _ComplaintCardState extends State<_ComplaintCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    final isOpen = c.status == 'open';
    final color = isOpen ? _danger : _ok;

    return FadeTransition(
      opacity: widget.anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(widget.anim),
        child: GestureDetector(
          onTapDown: (_) {
            HapticFeedback.selectionClick();
            setState(() => _pressed = true);
          },
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isOpen ? _danger.withOpacity(0.25) : _border,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category icon
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      _categoryIcon(c.category),
                      size: 18,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _categoryLabel(c.category),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: color.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                isOpen ? 'Open' : 'Resolved',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.description,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _grey,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 11,
                              color: _grey.withOpacity(0.7),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              c.createdAt != null
                                  ? _formatTime(c.createdAt!)
                                  : 'Unknown time',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: _grey.withOpacity(0.7),
                              ),
                            ),
                            if (!isOpen && c.resolvedAt != null) ...[
                              const SizedBox(width: 10),
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 11,
                                color: _ok.withOpacity(0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Resolved ${_formatTime(c.resolvedAt!)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _ok.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Chevron
                  Padding(
                    padding: const EdgeInsets.only(top: 12, left: 4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _grey.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Detail Bottom Sheet ───────────────────────────────────────────────────────
class _ComplaintDetailSheet extends StatefulWidget {
  final ComplaintModel complaint;
  const _ComplaintDetailSheet({required this.complaint});
  @override
  State<_ComplaintDetailSheet> createState() => _ComplaintDetailSheetState();
}

class _ComplaintDetailSheetState extends State<_ComplaintDetailSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheetCtrl;
  late final Animation<double> _sheetFade;

  @override
  void initState() {
    super.initState();
    _sheetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _sheetFade = CurvedAnimation(
      parent: _sheetCtrl,
      curve: Curves.easeOutCubic,
    );
    // Small delay so sheet itself finishes its drag-up motion first
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _sheetCtrl.forward();
    });
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    final isOpen = c.status == 'open';
    final color = isOpen ? _danger : _ok;

    return Container(
      decoration: const BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // All sheet content fades + slides up together
          FadeTransition(
            opacity: _sheetFade,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(_sheetFade),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category + status row
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          _categoryIcon(c.category),
                          size: 20,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _categoryLabel(c.category),
                              style: GoogleFonts.antonSc(
                                fontSize: 20,
                                color: _black,
                                letterSpacing: 0.2,
                              ),
                            ),
                            Text(
                              'Court ${c.courtId} · #${c.id}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Animated status badge — pulses if open
                      _StatusBadge(isOpen: isOpen, color: color),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Description
                  Text(
                    'DESCRIPTION',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      c.description.isEmpty
                          ? 'No description provided.'
                          : c.description,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: _black,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Timeline — each row staggers in
                  Text(
                    'TIMELINE',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  _StagRow(
                    ctrl: _sheetCtrl,
                    index: 0,
                    child: _TimelineRow(
                      icon: Icons.flag_rounded,
                      iconColor: _danger,
                      label: 'Registered',
                      value: c.createdAt != null
                          ? _formatDateTime(c.createdAt!)
                          : 'Unknown',
                    ),
                  ),

                  if (!isOpen && c.resolvedAt != null) ...[
                    const SizedBox(height: 10),
                    _StagRow(
                      ctrl: _sheetCtrl,
                      index: 1,
                      child: _TimelineRow(
                        icon: Icons.check_circle_rounded,
                        iconColor: _ok,
                        label: 'Resolved',
                        value: _formatDateTime(c.resolvedAt!),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _StagRow(
                      ctrl: _sheetCtrl,
                      index: 2,
                      child: _TimelineRow(
                        icon: Icons.timer_outlined,
                        iconColor: _warn,
                        label: 'Time to resolve',
                        value: _duration(c.createdAt!, c.resolvedAt!),
                      ),
                    ),
                  ],

                  if (isOpen) ...[
                    const SizedBox(height: 10),
                    _StagRow(
                      ctrl: _sheetCtrl,
                      index: 1,
                      child: _TimelineRow(
                        icon: Icons.timer_outlined,
                        iconColor: _warn,
                        label: 'Pending since',
                        value: c.createdAt != null
                            ? _duration(c.createdAt!, DateTime.now())
                            : '—',
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Close button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _black,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          'Close',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
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
        ],
      ),
    );
  }
}

// ─── Status Badge with pulse if open ─────────────────────────────────────────
class _StatusBadge extends StatefulWidget {
  final bool isOpen;
  final Color color;
  const _StatusBadge({required this.isOpen, required this.color});
  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    if (widget.isOpen) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.color.withOpacity(0.3)),
      ),
      child: Text(
        widget.isOpen ? 'Open' : 'Resolved',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: widget.color,
        ),
      ),
    ),
  );
}

// ─── Sheet stagger row helper ─────────────────────────────────────────────────
class _StagRow extends StatelessWidget {
  final AnimationController ctrl;
  final int index;
  final Widget child;
  const _StagRow({
    required this.ctrl,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: ctrl,
      curve: Interval(
        (0.15 + index * 0.12).clamp(0.0, 0.85),
        (0.55 + index * 0.12).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.04, 0),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }
}

// ─── Filter Chip ──────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.color = _white,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color : _white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? color : _white.withOpacity(0.18)),
      ),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 180),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active
              ? (color == _white ? _black : _white)
              : _white.withOpacity(0.7),
        ),
        child: Text(label),
      ),
    ),
  );
}

// ─── Loading list (shimmer) ────────────────────────────────────────────────────
class _LoadingList extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
    itemCount: 5,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, __) => const _SkeletonCard(height: 90),
  );
}

// ─── Centered message ─────────────────────────────────────────────────────────
class _CenteredMsg extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final Widget? action;
  const _CenteredMsg({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.antonSc(
              fontSize: 18,
              color: _black,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 13, color: _grey),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────
class _SkeletonCard extends StatefulWidget {
  final double height;
  const _SkeletonCard({required this.height});
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Color.lerp(
          const Color(0xFFF0F0F0),
          const Color(0xFFE0E0E0),
          _anim.value,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  );
}

// ─── Timeline Row ─────────────────────────────────────────────────────────────
class _TimelineRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label, value;
  const _TimelineRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.10),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 15, color: iconColor),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: _grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      Text(
        value,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _black,
        ),
      ),
    ],
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
IconData _categoryIcon(String cat) => switch (cat.toLowerCase()) {
  'cleanliness' || 'cleaning' => Icons.cleaning_services_rounded,
  'food' || 'hygiene' => Icons.restaurant_rounded,
  'maintenance' => Icons.build_rounded,
  'staff' || 'behaviour' => Icons.person_rounded,
  'billing' || 'payment' => Icons.receipt_long_rounded,
  'noise' => Icons.volume_up_rounded,
  'security' => Icons.security_rounded,
  _ => Icons.report_problem_rounded,
};

String _categoryLabel(String cat) => cat.isEmpty
    ? 'General'
    : cat[0].toUpperCase() + cat.substring(1).toLowerCase();

String _formatTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays}d ago';
}

String _formatDateTime(DateTime dt) {
  const months = [
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
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]}, $h:$min';
}

String _duration(DateTime from, DateTime to) {
  final diff = to.difference(from);
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24)
    return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  return '${diff.inDays}d ${diff.inHours.remainder(24)}h';
}
