// lib/features/feedbacks/presentation/outlet_feedback_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/appear_fade.dart';

import '../domain/feedback_notifier.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
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

class OutletFeedbacksScreen extends ConsumerStatefulWidget {
  const OutletFeedbacksScreen({super.key});

  @override
  ConsumerState<OutletFeedbacksScreen> createState() =>
      _OutletFeedbacksScreenState();
}

class _OutletFeedbacksScreenState extends ConsumerState<OutletFeedbacksScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _listCtrl;
  late final Animation<double> _fadeAnim;

  // ✅ Drives infinite scroll — when the user nears the bottom we ask the
  // notifier for the next page.
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

  // Trigger the next page a little before hitting the very bottom for a
  // seamless feel. The notifier itself guards against duplicate/empty loads.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      ref.read(feedbackNotifierProvider.notifier).loadMore();
    }
  }

  Animation<double> _itemAnim(int i) => CurvedAnimation(
    parent: _listCtrl,
    curve: Interval(
      (i * 0.07).clamp(0.0, 0.7),
      ((i * 0.07) + 0.4).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ),
  );

  Future<void> _pickDate(FeedbackNotifier notifier, DateTime? current) async {
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
      _listCtrl
        ..reset()
        ..forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedbacksState = ref.watch(feedbackNotifierProvider);
    final notifier = ref.read(feedbackNotifierProvider.notifier);

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
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CUSTOMER VOICE',
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
                              // Date filter button
                              GestureDetector(
                                onTap: () =>
                                    _pickDate(notifier, data.selectedDate),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: data.selectedDate != null
                                        ? _accent
                                        : _white.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: data.selectedDate != null
                                          ? _accent
                                          : _white.withOpacity(0.1),
                                    ),
                                  ),
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
                                            _listCtrl
                                              ..reset()
                                              ..forward();
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
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Refresh button
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  notifier.fetchFeedbacks(isRefresh: true);
                                  _listCtrl
                                    ..reset()
                                    ..forward();
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
                      'FEEDBACKS',
                      style: GoogleFonts.antonSc(
                        fontSize: 42,
                        color: _white,
                        height: 1.0,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Real reviews from your customers',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white54,
                        fontWeight: FontWeight.w500,
                      ),
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
                      await notifier.fetchFeedbacks(isRefresh: true);
                      _listCtrl
                        ..reset()
                        ..forward();
                    },
                    child: feedbacksState.when(
                      loading: () => const SkeletonList(
                        dark: false,
                        count: 6,
                        tileHeight: 92,
                      ),
                      error: (err, _) => _ErrorView(
                        message: err.toString(),
                        onRetry: () => notifier.fetchFeedbacks(isRefresh: true),
                      ),
                      data: (data) =>
                          AppearFade(child: _buildContent(data, notifier)),
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

  Widget _buildContent(FeedbackData data, FeedbackNotifier notifier) {
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 100),
      children: [
        // ─── Analytics Card ───
        if (data.analytics != null) ...[
          _AnalyticsCard(analytics: data.analytics!),
          const SizedBox(height: 28),
        ],

        // ─── List header ───
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              data.selectedDate == null
                  ? 'All Reviews'
                  : 'Reviews for ${_formatDate(data.selectedDate!)}',
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
                // When more pages exist show a "20+" style hint, else the
                // exact loaded count.
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
          _EmptyState(hasDateFilter: data.selectedDate != null)
        else
          ...data.feedbacks.map((f) => _FeedbackCard(feedback: f)),

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
// Shows a spinner while the next page loads, or a subtle "all caught up" note
// once every review has been fetched.

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

    // Only show the end-of-list note when there is something to be at the end of.
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

// ─── Analytics Card ──────────────────────────────────────────────────────────

class _AnalyticsCard extends StatelessWidget {
  final FeedbackAnalytics analytics;
  const _AnalyticsCard({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final avg = analytics.avgOutletRating;
    final avgStr = avg != null ? avg.toStringAsFixed(1) : '—';
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
          // Top row: avg rating + wow
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Big rating number
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    avgStr,
                    style: GoogleFonts.antonSc(
                      fontSize: 56,
                      color: _white,
                      height: 1.0,
                    ),
                  ),
                  Row(
                    children: List.generate(5, (i) {
                      final filled = avg != null && i < avg.round();
                      return Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 16,
                        color: filled ? _warn : Colors.white24,
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Average Rating',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // WoW growth
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: wowColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: wowColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          analytics.isGrowing
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          size: 14,
                          color: wowColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          wowStr,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: wowColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'vs last week',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),
          Container(height: 1, color: _white.withOpacity(0.08)),
          const SizedBox(height: 16),

          // Bottom stats row
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
              _MiniStat(
                icon: Icons.calendar_today_rounded,
                label: 'This Week',
                value: '${analytics.thisWeekCount}',
                color: _ok,
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
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: _white.withOpacity(0.08),
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

// ─── Feedback Card ────────────────────────────────────────────────────────────

class _FeedbackCard extends StatefulWidget {
  final FeedbackModel feedback;
  const _FeedbackCard({required this.feedback});

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard>
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
    final rating = widget.feedback.outletRating ?? 0;
    final rColor = rating > 0 ? _ratingColor(rating) : _grey;
    final hasComment =
        widget.feedback.outletComments != null &&
        widget.feedback.outletComments!.isNotEmpty;

    return GestureDetector(
      onTap: hasComment ? _toggle : null,
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Container(
                    width: 44,
                    height: 44,
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
                        widget.feedback.customerName.isNotEmpty
                            ? widget.feedback.customerName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.antonSc(fontSize: 18, color: rColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Name + phone + time
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.feedback.customerName,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _black,
                            letterSpacing: -0.2,
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
                            const SizedBox(width: 4),
                            Text(
                              widget.feedback.customerPhoneMasked,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: _grey,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.access_time_rounded,
                              size: 11,
                              color: _grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _relTime(widget.feedback.createdAt),
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

                  // Rating badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: rColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: _white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating > 0 ? '$rating' : '—',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasComment) ...[
                        const SizedBox(height: 6),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 280),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: _grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ─── Star row ───
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
              child: Row(
                children: List.generate(5, (i) {
                  final filled = i < rating;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: filled ? 1.0 : 0.0),
                    duration: Duration(milliseconds: 200 + (i * 60)),
                    curve: Curves.easeOutBack,
                    builder: (_, v, __) => Transform.scale(
                      scale: 0.7 + (v * 0.3),
                      child: Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 22,
                        color: filled ? _warn : Colors.grey.shade300,
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ─── Expandable comment ───
            SizeTransition(
              sizeFactor: _expandAnim,
              child: hasComment
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.format_quote_rounded,
                              size: 16,
                              color: rColor.withOpacity(0.5),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.feedback.outletComments!,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  color: _black,
                                  height: 1.5,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasDateFilter;
  const _EmptyState({required this.hasDateFilter});

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
          hasDateFilter ? 'No reviews on this date' : 'No reviews yet',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasDateFilter
              ? 'Try a different date or clear the filter.'
              : 'Customer reviews will appear here after QR scans.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: _grey, height: 1.5),
        ),
      ],
    ),
  );
}

// ─── Error View ───────────────────────────────────────────────────────────────

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
