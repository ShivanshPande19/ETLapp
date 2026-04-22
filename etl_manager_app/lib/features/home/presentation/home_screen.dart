import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/token_storage.dart';
import '../../courts/domain/courts_notifier.dart';
import '../../sales/domain/sales_notifier.dart';

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _lightGrey = Color(0xFFF2F2F2);
const _border = Color(0xFF1A1A1A);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  String _managerName = 'Manager';
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();
    _loadName();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    final name = await TokenStorage.getManagerName();
    if (name != null && mounted) setState(() => _managerName = name);
  }

  @override
  Widget build(BuildContext context) {
    final salesState = ref.watch(salesNotifierProvider);
    final courtsAsync = ref.watch(courtsNotifierProvider);

    final totalSales = salesState.summary?.totalSales ?? 0.0;
    final totalCourts = courtsAsync.whenData((c) => c.length).value ?? 0;
    final isLoadingSales = salesState.status == SalesLoadStatus.loading;
    final isLoadingCourts = courtsAsync is AsyncLoading;

    return Scaffold(
      backgroundColor: _white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: RefreshIndicator(
            color: _black,
            strokeWidth: 2,
            backgroundColor: _white,
            onRefresh: () async {
              ref
                  .read(salesNotifierProvider.notifier)
                  .fetchSummary(allCourts: true);
              ref.read(courtsNotifierProvider.notifier).fetchCourts();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top Row ──────────────────────────────────────
                  _TopRow(managerName: _managerName),
                  const SizedBox(height: 8),

                  // ── Display Heading ──────────────────────────────
                  Text(
                    'ETL FOOD\nCOURT',
                    style: GoogleFonts.antonSc(
                      fontSize: 54,
                      color: _black,
                      height: 0.95,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Bento Row 1: Revenue + Courts ────────────────
                  SizedBox(
                    height: 120,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 55,
                          child: _OutlineCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Revenue',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: _grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                isLoadingSales
                                    ? const _Skeleton(width: 100, height: 32)
                                    : Text(
                                        '₹${_fmt(totalSales)}',
                                        style: GoogleFonts.antonSc(
                                          fontSize: 30,
                                          color: _black,
                                          height: 1,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 45,
                          child: _FilledCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Courts',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.white60,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                isLoadingCourts
                                    ? const _Skeleton(
                                        width: 70,
                                        height: 28,
                                        dark: true,
                                      )
                                    : Text(
                                        '$totalCourts Active',
                                        style: GoogleFonts.antonSc(
                                          fontSize: 24,
                                          color: _white,
                                          height: 1,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Sales card ───────────────────────────────────
                  _OutlineCard(
                    height: 86,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: SizedBox(
                            height: 46,
                            child: CustomPaint(
                              painter: _SparklinePainter(color: _black),
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 46,
                          color: _border.withOpacity(0.12),
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Total Sales',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 3),
                              isLoadingSales
                                  ? const _Skeleton(width: 80, height: 24)
                                  : Text(
                                      '₹${_fmt(totalSales)}',
                                      style: GoogleFonts.antonSc(
                                        fontSize: 26,
                                        color: _black,
                                        height: 1,
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Bento Row 2: Complaints + Maintenance ────────
                  SizedBox(
                    height: 100,
                    child: Row(
                      children: [
                        // Complaints
                        Expanded(
                          child: _OutlineCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Complaints',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: _grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 11,
                                      color: _grey,
                                    ),
                                  ],
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '3',
                                      style: GoogleFonts.antonSc(
                                        fontSize: 32,
                                        color: _black,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text(
                                        'open',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _grey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Maintenance
                        Expanded(
                          child: _FilledCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Maintenance',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 11,
                                      color: Colors.white.withOpacity(0.4),
                                    ),
                                  ],
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '2',
                                      style: GoogleFonts.antonSc(
                                        fontSize: 32,
                                        color: _white,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text(
                                        'pending',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.white60,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Housekeeping Progress Card ───────────────────
                  _OutlineCard(
                    height: 90,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Housekeeping',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '8 / 12 zones',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _black,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: 8 / 12,
                            minHeight: 8,
                            backgroundColor: _lightGrey,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              _black,
                            ),
                          ),
                        ),
                        Text(
                          '4 zones pending',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _grey,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Courts Section ───────────────────────────────
                  _SectionHeader(title: 'Courts', onViewAll: () {}),
                  const SizedBox(height: 12),
                  courtsAsync.when(
                    loading: () => Column(
                      children: List.generate(
                        3,
                        (_) => const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: _Skeleton(width: double.infinity, height: 72),
                        ),
                      ),
                    ),
                    error: (_, __) =>
                        const _ErrorRow(message: 'Could not load courts'),
                    data: (courts) => Column(
                      children: courts
                          .map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _CourtRow(court: c),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Now Playing ──────────────────────────────────
                  _SectionHeader(title: 'Now Playing', onViewAll: null),
                  const SizedBox(height: 12),
                  const _NowPlayingCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Top Row ───────────────────────────────────────────────────────────────────

class _TopRow extends StatelessWidget {
  final String managerName;
  const _TopRow({required this.managerName});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Hi, $managerName',
          style: GoogleFonts.inter(
            fontSize: 15,
            color: _grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: _black,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_rounded, color: _white, size: 20),
        ),
      ],
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;
  const _SectionHeader({required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _black,
            letterSpacing: -0.3,
          ),
        ),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: Text(
              'View All',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: _grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Outline Card ──────────────────────────────────────────────────────────────

class _OutlineCard extends StatelessWidget {
  final Widget child;
  final double? height;
  const _OutlineCard({required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 1.5),
      ),
      child: child,
    );
  }
}

// ── Filled Card ───────────────────────────────────────────────────────────────

class _FilledCard extends StatelessWidget {
  final Widget child;
  final double? height;
  const _FilledCard({required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

// ── Court Row ─────────────────────────────────────────────────────────────────

class _CourtRow extends StatelessWidget {
  final dynamic court;
  const _CourtRow({required this.court});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _lightGrey,
              shape: BoxShape.circle,
              border: Border.all(color: _border.withOpacity(0.12)),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: _black,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  court.name ?? 'Court',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  court.location ?? 'Food Court',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _grey,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _black,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Active',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Now Playing Card ──────────────────────────────────────────────────────────

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: _white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Background Playlist',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Now Playing',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white54,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.skip_previous_rounded,
            color: Colors.white.withOpacity(0.5),
            size: 24,
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.pause_circle_filled_rounded,
            color: _white,
            size: 32,
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.skip_next_rounded,
            color: Colors.white.withOpacity(0.5),
            size: 24,
          ),
        ],
      ),
    );
  }
}

// ── Sparkline Painter ─────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final Color color;
  const _SparklinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const pts = [0.55, 0.40, 0.65, 0.30, 0.70, 0.45, 0.35, 0.60, 0.50, 0.75];
    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = (i / (pts.length - 1)) * size.width;
      final y = size.height - (pts[i] * size.height);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  final double width;
  final double height;
  final bool dark;
  const _Skeleton({
    required this.width,
    required this.height,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.15) : _lightGrey,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

// ── Error Row ─────────────────────────────────────────────────────────────────

class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Text(message, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
        ],
      ),
    );
  }
}
