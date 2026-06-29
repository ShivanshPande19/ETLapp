// lib/features/feedbacks/presentation/staff_court_feedback_screen.dart
//
// Premium court-feedback screen for ETL staff. Shows the venue/court voice
// (ratings + comments) for the staff's assigned court only.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/appear_fade.dart';

import '../domain/court_feedback_notifier.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFE5A000);
const _danger = Color(0xFFFF4444);
const _red = Color(0xFFD02128);
const _blue = Color(0xFF60A5FA);
const _border = Color(0xFFE9E9E9);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _relTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

Color _ratingColor(int r) {
  if (r >= 4) return _ok;
  if (r == 3) return _warn;
  return _danger;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class StaffCourtFeedbackScreen extends ConsumerStatefulWidget {
  final String courtName;
  const StaffCourtFeedbackScreen({super.key, required this.courtName});

  @override
  ConsumerState<StaffCourtFeedbackScreen> createState() =>
      _StaffCourtFeedbackScreenState();
}

class _StaffCourtFeedbackScreenState
    extends ConsumerState<StaffCourtFeedbackScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _heroCtrl;
  late final AnimationController _listCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  final ScrollController _scrollCtrl = ScrollController();

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
      duration: const Duration(milliseconds: 850),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));

    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _heroCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _listCtrl.forward();
    });

    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _fadeCtrl.dispose();
    _heroCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      ref.read(courtFeedbackNotifierProvider.notifier).loadMore();
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

  Future<void> _refresh() async {
    HapticFeedback.mediumImpact();
    await ref.read(courtFeedbackNotifierProvider.notifier).fetch(isRefresh: true);
    _listCtrl
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(courtFeedbackNotifierProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── DARK HEADER ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        FadeTransition(
                          opacity: _heroFade,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.stadium_rounded,
                                size: 14,
                                color: _blue,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.courtName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: _white.withOpacity(0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
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
                                text: 'OURT ',
                                style: TextStyle(color: _white),
                              ),
                              TextSpan(
                                text: 'V',
                                style: TextStyle(color: _red),
                              ),
                              TextSpan(
                                text: 'OICE',
                                style: TextStyle(color: _white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FadeTransition(
                      opacity: _heroFade,
                      child: Text(
                        'What guests say about your court',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── WHITE CANVAS ───────────────────────────────────────────
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                    child: RefreshIndicator(
                      color: _black,
                      backgroundColor: _white,
                      strokeWidth: 2,
                      onRefresh: _refresh,
                      child: async.when(
                        loading: () => const SkeletonList(
                          dark: false,
                          count: 6,
                          tileHeight: 92,
                        ),
                        error: (err, _) => _ErrorView(
                          message: err.toString(),
                          onRetry: _refresh,
                        ),
                        data: (data) => AppearFade(child: _buildContent(data)),
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

  Widget _buildContent(CourtFeedbackData data) {
    return ListView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        MediaQuery.of(context).padding.bottom + 110,
      ),
      children: [
        if (data.analytics != null) ...[
          _AnalyticsCard(analytics: data.analytics!),
          const SizedBox(height: 24),
        ],

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
        const SizedBox(height: 14),

        if (data.feedbacks.isEmpty)
          _EmptyState()
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
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FeedbackCard(feedback: e.value),
                ),
              ),
            );
          }),

        if (data.isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: _black, strokeWidth: 2),
              ),
            ),
          )
        else if (!data.hasMore && data.feedbacks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
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
          ),
      ],
    );
  }
}

// ─── Analytics Card ────────────────────────────────────────────────────────────

class _AnalyticsCard extends StatelessWidget {
  final CourtFeedbackAnalytics analytics;
  const _AnalyticsCard({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final avg = analytics.avgCourtRating;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stadium_rounded, size: 13, color: _blue),
                      const SizedBox(width: 5),
                      Text(
                        'Court Rating',
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
                    avg != null ? avg.toStringAsFixed(1) : '—',
                    style: GoogleFonts.antonSc(
                      fontSize: 46,
                      color: _white,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(5, (i) {
                      final filled = avg != null && i < avg.round();
                      return Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 15,
                        color: filled ? _warn : Colors.white24,
                      );
                    }),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
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
                    'this week',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.white38,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: _white.withOpacity(0.08)),
          const SizedBox(height: 16),
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
                icon: Icons.event_available_rounded,
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
    margin: const EdgeInsets.symmetric(horizontal: 8),
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
        const SizedBox(height: 2),
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

// ─── Feedback Card ──────────────────────────────────────────────────────────

class _FeedbackCard extends StatelessWidget {
  final CourtFeedbackModel feedback;
  const _FeedbackCard({required this.feedback});

  @override
  Widget build(BuildContext context) {
    final rating = feedback.courtRating ?? 0;
    final color = _ratingColor(rating);
    final initial = feedback.customerName.isNotEmpty
        ? feedback.customerName[0].toUpperCase()
        : 'G';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color,
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
                      feedback.customerName,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _relTime(feedback.createdAt),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 13, color: color),
                    const SizedBox(width: 3),
                    Text(
                      '$rating',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (feedback.hasComment) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                feedback.courtComments!,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF333333),
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Empty + Error ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rate_review_outlined,
              size: 32,
              color: _blue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No court reviews yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Guest feedback for your court will appear here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: _grey),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.wifi_off_rounded, size: 44, color: _danger),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Could not load',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _black,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: _grey),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.inter(
                color: _danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
