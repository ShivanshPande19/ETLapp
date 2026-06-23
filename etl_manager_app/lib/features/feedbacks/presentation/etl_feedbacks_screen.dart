// lib/features/feedbacks/presentation/etl_feedbacks_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/etl_feedback_notifier.dart';
import '../../../core/widgets/skeleton.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
const _purple = Color(0xFFA78BFA);
const _accent = Color(0xFFDEFF9A);
const _cardBg = Color(0xFFFAFAFA);

// ─── Helpers ─────────────────────────────────────────────────────────────────

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

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

String _relTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return _formatDate(d);
}

Color _ratingColor(int r) {
  if (r >= 4) return _ok;
  if (r == 3) return _warn;
  return _danger;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class EtlFeedbacksScreen extends ConsumerStatefulWidget {
  const EtlFeedbacksScreen({super.key});

  @override
  ConsumerState<EtlFeedbacksScreen> createState() => _EtlFeedbacksScreenState();
}

class _EtlFeedbacksScreenState extends ConsumerState<EtlFeedbacksScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _listCtrl;
  late final Animation<double> _fadeAnim;

  // ✅ Drives infinite scroll for the (now paginated) ETL list.
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
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

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _fadeCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      ref.read(etlFeedbackNotifierProvider.notifier).loadMore();
    }
  }

  Animation<double> _itemAnim(int i) => CurvedAnimation(
    parent: _listCtrl,
    curve: Interval(
      (i * 0.06).clamp(0.0, 0.7),
      ((i * 0.06) + 0.4).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ),
  );

  void _restartListAnim() {
    _listCtrl
      ..reset()
      ..forward();
  }

  Future<void> _pickDate(
    EtlFeedbackNotifier notifier,
    DateTime? current,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            onPrimary: _black,
            surface: Color(0xFF1A1A1A),
            onSurface: _white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      HapticFeedback.selectionClick();
      notifier.setDateFilter(picked);
      _restartListAnim();
    }
  }

  void _showOutletSheet(
    BuildContext context,
    EtlFeedbackNotifier notifier,
    EtlFeedbackData data,
  ) {
    HapticFeedback.lightImpact();
    final filteredOutlets = data.selectedCourtId == null
        ? data.outlets
        : data.outlets.where((o) => o.courtId == data.selectedCourtId).toList();

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SafeArea(
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
                'Filter by Outlet',
                style: GoogleFonts.antonSc(
                  fontSize: 22,
                  color: _black,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),
              if (filteredOutlets.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No outlets for selected court.',
                      style: GoogleFonts.inter(color: _grey),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // All option
                      _OutletTile(
                        name: 'All Outlets',
                        icon: Icons.apps_rounded,
                        isSelected: data.selectedOutletId == null,
                        onTap: () {
                          notifier.setOutletFilter(null);
                          Navigator.of(context, rootNavigator: true).pop();
                          _restartListAnim();
                        },
                      ),
                      ...filteredOutlets.map(
                        (o) => _OutletTile(
                          name: o.name,
                          icon: Icons.storefront_rounded,
                          isSelected: data.selectedOutletId == o.id,
                          onTap: () {
                            notifier.setOutletFilter(o.id);
                            Navigator.of(context, rootNavigator: true).pop();
                            _restartListAnim();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedbacksState = ref.watch(etlFeedbackNotifierProvider);
    final notifier = ref.read(etlFeedbackNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // ─── Dark Header ───
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ETL MANAGER',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _grey,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                          ),
                        ),
                        feedbacksState.maybeWhen(
                          data: (data) => Row(
                            children: [
                              // Date filter
                              _HeaderBtn(
                                active: data.selectedDate != null,
                                activeColor: _accent,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.calendar_month_rounded,
                                      size: 14,
                                      color: data.selectedDate != null
                                          ? _black
                                          : _grey,
                                    ),
                                    if (data.selectedDate != null) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        _formatDate(data.selectedDate!),
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _black,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          notifier.setDateFilter(null);
                                          _restartListAnim();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: _black,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            size: 10,
                                            color: _white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                onTap: () =>
                                    _pickDate(notifier, data.selectedDate),
                              ),
                              const SizedBox(width: 8),
                              // Outlet filter
                              _HeaderBtn(
                                active: data.selectedOutletId != null,
                                activeColor: _blue,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.tune_rounded,
                                      size: 14,
                                      color: data.selectedOutletId != null
                                          ? _white
                                          : _grey,
                                    ),
                                    if (data.selectedOutletId != null) ...[
                                      const SizedBox(width: 5),
                                      Text(
                                        'Outlet',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _white,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                onTap: () =>
                                    _showOutletSheet(context, notifier, data),
                              ),
                              const SizedBox(width: 8),
                              // Refresh
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  notifier.fetchEtlData(isRefresh: true);
                                  _restartListAnim();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _white.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _white.withOpacity(0.1),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                    color: _grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'VENUE REVIEWS',
                      style: GoogleFonts.antonSc(
                        fontSize: 38,
                        color: _white,
                        height: 1.0,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'All courts · All outlets',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Court selector chips ───
                    feedbacksState.maybeWhen(
                      data: (data) => SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _CourtChip(
                              label: 'All Courts',
                              isSelected: data.selectedCourtId == null,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                notifier.setCourtFilter(null);
                                _restartListAnim();
                              },
                            ),
                            ...data.courts.map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: _CourtChip(
                                  label: c.name,
                                  isSelected: data.selectedCourtId == c.id,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    notifier.setCourtFilter(c.id);
                                    _restartListAnim();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      orElse: () => const SizedBox(height: 36),
                    ),
                  ],
                ),
              ),
            ),

            // ─── White Canvas ───
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(36),
                  ),
                  child: RefreshIndicator(
                    color: _black,
                    backgroundColor: _white,
                    strokeWidth: 2,
                    onRefresh: () async {
                      HapticFeedback.mediumImpact();
                      await notifier.fetchEtlData(isRefresh: true);
                      _restartListAnim();
                    },
                    child: feedbacksState.when(
                      loading: () => const SkeletonList(
                        dark: false,
                        count: 6,
                        tileHeight: 92,
                      ),
                      error: (err, _) => _ErrorView(
                        message: err.toString(),
                        onRetry: () => notifier.fetchEtlData(isRefresh: true),
                      ),
                      data: (data) => _buildContent(data),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(EtlFeedbackData data) {
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 100),
      children: [
        // ─── Analytics Card ───
        if (data.analytics != null) ...[
          _EtlAnalyticsCard(analytics: data.analytics!),
          const SizedBox(height: 28),
        ],

        // ─── List header ───
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Reviews',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: _black,
                letterSpacing: -0.3,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _black,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                data.hasMore
                    ? '${data.feedbacks.length}+'
                    : '${data.feedbacks.length}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ─── Feedback list ───
        if (data.feedbacks.isEmpty)
          _EmptyState(
            hasFilters:
                data.selectedCourtId != null ||
                data.selectedOutletId != null ||
                data.selectedDate != null,
          )
        else
          ...data.feedbacks.asMap().entries.map((e) {
            final anim = _itemAnim(e.key);
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(anim),
                child: _EtlFeedbackCard(
                  feedback: e.value,
                  courts: data.courts,
                  outlets: data.outlets,
                ),
              ),
            );
          }),

        // ─── Pagination footer ───
        _PaginationFooter(
          isLoadingMore: data.isLoadingMore,
          hasMore: data.hasMore,
          hasItems: data.feedbacks.isNotEmpty,
        ),
      ],
    );
  }
}

// ─── Pagination Footer ───────────────────────────────────────────────────────

class _PaginationFooter extends StatelessWidget {
  final bool isLoadingMore;
  final bool hasMore;
  final bool hasItems;
  const _PaginationFooter({
    required this.isLoadingMore,
    required this.hasMore,
    required this.hasItems,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(color: _black, strokeWidth: 2),
          ),
        ),
      );
    }

    if (!hasMore && hasItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            "You're all caught up",
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _grey,
            ),
          ),
        ),
      );
    }

    return const SizedBox(height: 8);
  }
}

// ─── ETL Analytics Card ───────────────────────────────────────────────────────

class _EtlAnalyticsCard extends StatelessWidget {
  final EtlFeedbackAnalytics analytics;
  const _EtlAnalyticsCard({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final courtAvg = analytics.avgCourtRating;
    final outletAvg = analytics.avgOutletRating;
    final wowStr = analytics.isGrowing
        ? '+${analytics.wowGrowth.toStringAsFixed(0)}%'
        : '${analytics.wowGrowth.toStringAsFixed(0)}%';
    final wowColor = analytics.isGrowing ? _ok : _danger;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top: dual ratings
          Row(
            children: [
              Expanded(
                child: _RatingBlock(
                  label: 'Court Rating',
                  icon: Icons.stadium_rounded,
                  color: _blue,
                  avg: courtAvg,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: _white.withOpacity(0.08),
              ),
              Expanded(
                child: _RatingBlock(
                  label: 'Outlet Rating',
                  icon: Icons.storefront_rounded,
                  color: _purple,
                  avg: outletAvg,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Container(height: 1, color: _white.withOpacity(0.08)),
          const SizedBox(height: 16),

          // Bottom stats
          Row(
            children: [
              _MiniStat(
                icon: Icons.reviews_rounded,
                label: 'Total',
                value: '${analytics.totalCount}',
                color: _blue,
              ),
              _vDiv(),
              _MiniStat(
                icon: Icons.star_rounded,
                label: '5 Stars',
                value: '${analytics.fiveStarCount}',
                color: _warn,
              ),
              _vDiv(),
              _MiniStat(
                icon: Icons.star_outline_rounded,
                label: '1 Star',
                value: '${analytics.oneStarCount}',
                color: _danger,
              ),
              _vDiv(),
              // WoW growth
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: wowColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        wowStr,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: wowColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'WoW',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: Colors.white38,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vDiv() => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: _white.withOpacity(0.08),
  );
}

class _RatingBlock extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double? avg;
  const _RatingBlock({
    required this.label,
    required this.icon,
    required this.color,
    this.avg,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        avg != null ? avg!.toStringAsFixed(1) : '—',
        style: GoogleFonts.antonSc(fontSize: 36, color: _white, height: 1.0),
      ),
      Row(
        children: List.generate(5, (i) {
          final filled = avg != null && i < avg!.round();
          return Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 13,
            color: filled ? _warn : Colors.white24,
          );
        }),
      ),
    ],
  );
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.antonSc(fontSize: 18, color: _white, height: 1.0),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ─── ETL Feedback Card ────────────────────────────────────────────────────────

class _EtlFeedbackCard extends StatefulWidget {
  final EtlFeedbackModel feedback;
  final List<SimpleCourt> courts;
  final List<SimpleOutlet> outlets;
  const _EtlFeedbackCard({
    required this.feedback,
    required this.courts,
    required this.outlets,
  });

  @override
  State<_EtlFeedbackCard> createState() => _EtlFeedbackCardState();
}

class _EtlFeedbackCardState extends State<_EtlFeedbackCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    _expanded ? _expandCtrl.forward() : _expandCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.feedback;

    // Resolve names
    final courtMatch = widget.courts.where((c) => c.id == f.courtId);
    final courtName = courtMatch.isNotEmpty
        ? courtMatch.first.name.toUpperCase()
        : 'UNKNOWN COURT';

    String outletName = '';
    if (f.outletId != null) {
      final outletMatch = widget.outlets.where((o) => o.id == f.outletId);
      outletName = outletMatch.isNotEmpty
          ? outletMatch.first.name.toUpperCase()
          : 'UNKNOWN OUTLET';
    }

    // Dominant rating for card color
    final dominantRating = f.outletRating ?? f.courtRating ?? 0;
    final rColor = dominantRating > 0 ? _ratingColor(dominantRating) : _grey;

    final hasAnyComment =
        (f.courtComments != null && f.courtComments!.isNotEmpty) ||
        (f.outletComments != null && f.outletComments!.isNotEmpty);

    return GestureDetector(
      onTap: hasAnyComment ? _toggle : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: rColor.withOpacity(0.2), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: rColor.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: customer + time + expand arrow
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: rColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: rColor.withOpacity(0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            f.customerName.isNotEmpty
                                ? f.customerName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.antonSc(
                              fontSize: 17,
                              color: rColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.customerName,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.phone_rounded,
                                  size: 11,
                                  color: _grey,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  f.customerPhoneMasked,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _grey,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 11,
                                  color: _grey,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _relTime(f.createdAt),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (hasAnyComment)
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 280),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: _grey,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Location badges
                  Row(
                    children: [
                      _LocationBadge(
                        icon: Icons.stadium_rounded,
                        label: courtName,
                        color: _blue,
                      ),
                      if (outletName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _LocationBadge(
                          icon: Icons.storefront_rounded,
                          label: outletName,
                          color: _purple,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Rating sections
                  if (f.hasCourtFeedback)
                    _RatingRow(
                      label: 'Court',
                      rating: f.courtRating!,
                      icon: Icons.stadium_rounded,
                    ),
                  if (f.hasCourtFeedback && f.hasOutletFeedback)
                    const SizedBox(height: 8),
                  if (f.hasOutletFeedback)
                    _RatingRow(
                      label: 'Outlet',
                      rating: f.outletRating!,
                      icon: Icons.storefront_rounded,
                    ),
                ],
              ),
            ),

            // ─── Expandable comments ───
            SizeTransition(
              sizeFactor: _expandAnim,
              child: hasAnyComment
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Column(
                        children: [
                          if (f.courtComments != null &&
                              f.courtComments!.isNotEmpty)
                            _CommentBlock(
                              label: 'Court Comment',
                              comment: f.courtComments!,
                              color: _blue,
                            ),
                          if (f.courtComments != null &&
                              f.courtComments!.isNotEmpty &&
                              f.outletComments != null &&
                              f.outletComments!.isNotEmpty)
                            const SizedBox(height: 8),
                          if (f.outletComments != null &&
                              f.outletComments!.isNotEmpty)
                            _CommentBlock(
                              label: 'Outlet Comment',
                              comment: f.outletComments!,
                              color: _purple,
                            ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small Widgets ────────────────────────────────────────────────────────────

class _RatingRow extends StatelessWidget {
  final String label;
  final int rating;
  final IconData icon;
  const _RatingRow({
    required this.label,
    required this.rating,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = _ratingColor(rating);
    return Row(
      children: [
        Icon(icon, size: 13, color: _grey),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: _grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        ...List.generate(
          5,
          (i) => Icon(
            i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16,
            color: i < rating ? _warn : Colors.grey.shade300,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$rating/5',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _LocationBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _CommentBlock extends StatelessWidget {
  final String label, comment;
  final Color color;
  const _CommentBlock({
    required this.label,
    required this.comment,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.format_quote_rounded,
              size: 13,
              color: color.withOpacity(0.6),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          comment,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: _black,
            height: 1.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    ),
  );
}

class _CourtChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _CourtChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? _accent : _white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          color: isSelected ? _black : _white,
        ),
      ),
    ),
  );
}

class _HeaderBtn extends StatelessWidget {
  final Widget child;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _HeaderBtn({
    required this.child,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? activeColor : _white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? activeColor : _white.withOpacity(0.1),
        ),
      ),
      child: child,
    ),
  );
}

class _OutletTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  const _OutletTile({
    required this.name,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSelected ? _black : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: isSelected ? _white : _grey),
    ),
    title: Text(
      name,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        color: isSelected ? _black : _grey,
      ),
    ),
    trailing: isSelected
        ? const Icon(Icons.check_circle_rounded, color: _ok, size: 20)
        : null,
    onTap: onTap,
  );
}

// ─── Empty & Error ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  const _EmptyState({required this.hasFilters});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 40),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _cardBg,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade200, width: 2),
          ),
          child: const Icon(Icons.rate_review_outlined, size: 48, color: _grey),
        ),
        const SizedBox(height: 20),
        Text(
          hasFilters ? 'No reviews match filters' : 'No reviews yet',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasFilters
              ? 'Try changing court, outlet or date filters.'
              : 'Customer reviews will appear here after QR scans.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: _grey, height: 1.5),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
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
      const SizedBox(height: 20),
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
