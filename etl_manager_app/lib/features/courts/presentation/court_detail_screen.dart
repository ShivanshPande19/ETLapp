// lib/features/courts/presentation/court_detail_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/courts_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../staff/data/housekeeping_repository.dart';
import '../../staff/domain/housekeeping_models.dart';

// ✅ api_client (dioProvider) + maintenance model + feedback model
import '../../../core/network/api_client.dart';
import '../../maintenance/domain/maintenance_notifier.dart'
    show MaintenanceIssueModel;
import '../../feedbacks/domain/etl_feedback_notifier.dart'
    show EtlFeedbackModel;

// ✅ Shared loading polish: animated shimmer skeleton + mount entrance fade
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/appear_fade.dart';

// ─── Palette (matches app exactly) ───────────────────────────────────────────

const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
const _purple = Color(0xFFA78BFA);

// ─── Court-scoped Providers ───────────────────────────────────────────────────

final _courtSalesProvider = FutureProvider.autoDispose
    .family<SalesSummary, int>((ref, id) async {
      return ref
          .read(salesRepositoryProvider)
          .getSalesSummary(courtId: id, period: 'yesterday');
    });

final _courtFeedbackProvider = FutureProvider.autoDispose
    .family<List<EtlFeedbackModel>, int>((ref, id) async {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/feedback/court/$id');
      return (res.data as List? ?? [])
          .map((e) => EtlFeedbackModel.fromJson(e as Map<String, dynamic>))
          .toList();
    });

// ✅ NEW: New backend format {items: [...]} + JWT-authenticated dio
final _courtMaintenanceProvider = FutureProvider.autoDispose
    .family<List<MaintenanceIssueModel>, int>((ref, id) async {
      final dio = ref.read(dioProvider);
      final res = await dio.get(
        '/maintenance',
        queryParameters: {'court_id': id, 'limit': 100, 'offset': 0},
      );
      return (res.data['items'] as List? ?? [])
          .map((e) => MaintenanceIssueModel.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final _courtHkProvider = FutureProvider.autoDispose.family<List<_HkShift>, int>(
  (ref, id) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    try {
      final status = await ref
          .read(housekeepingRepoProvider)
          .getFullStatus(date: today);
      if (status == null) return [];
      final court = status.courts.where((c) => c.courtId == id).toList();
      if (court.isEmpty) return [];
      return court.first.shifts.map((s) {
        return _HkShift(
          label: s.shiftName,
          time: s.timeRange,
          done: s.done,
          total: s.total,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  },
);

class _HkShift {
  final String label, time;
  final int done, total;
  const _HkShift({
    required this.label,
    required this.time,
    required this.done,
    required this.total,
  });
  double get pct => total == 0 ? 0.0 : done / total;
  bool get isComplete => total > 0 && done == total;
  bool get isEmpty => total == 0;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class CourtDetailScreen extends ConsumerStatefulWidget {
  final Court court;
  const CourtDetailScreen({super.key, required this.court});

  @override
  ConsumerState<CourtDetailScreen> createState() => _CourtDetailScreenState();
}

class _CourtDetailScreenState extends ConsumerState<CourtDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _invalidateAll();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _invalidateAll() {
    ref.invalidate(_courtSalesProvider(widget.court.id));
    ref.invalidate(_courtFeedbackProvider(widget.court.id));
    ref.invalidate(_courtMaintenanceProvider(widget.court.id));
    ref.invalidate(_courtHkProvider(widget.court.id));
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(_courtSalesProvider(widget.court.id));
    final feedbackAsync = ref.watch(
      _courtFeedbackProvider(widget.court.id),
    );
    final maintenanceAsync = ref.watch(
      _courtMaintenanceProvider(widget.court.id),
    );
    final hkAsync = ref.watch(_courtHkProvider(widget.court.id));

    final feedbackCount =
        feedbackAsync.whenData((l) => l.length).value ?? 0;

    // ✅ FIX: "Open" = anything not CLOSED (new status system)
    final openMaintenance =
        maintenanceAsync
            .whenData((l) => l.where((i) => i.status != 'CLOSED').length)
            .value ??
        0;

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (dark) ────────────────────────────────
              _buildHeader(feedbackCount, openMaintenance),

              // ── White card area ──────────────────────────────
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: RefreshIndicator(
                    color: _black,
                    backgroundColor: _white,
                    onRefresh: () async => _invalidateAll(),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        24,
                        20,
                        MediaQuery.of(context).padding.bottom + 100,
                      ),
                      children: [
                        // ── Sales ──────────────────────────────
                        _sectionTitle('Sales · Yesterday'),
                        const SizedBox(height: 10),
                        salesAsync.when(
                          loading: () => _skeletonCard(100),
                          error: (_, __) => _errorCard('Sales unavailable'),
                          data: (s) => AppearFade(
                            child: _SalesCard(summary: s, fmt: _fmt),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Housekeeping ───────────────────────
                        _sectionTitle('Housekeeping · Today'),
                        const SizedBox(height: 10),
                        hkAsync.when(
                          loading: () => _skeletonCard(120),
                          error: (_, __) =>
                              _errorCard('Housekeeping unavailable'),
                          data: (rows) => AppearFade(
                            delayMs: 60,
                            child: rows.isEmpty
                                ? _emptyCard(
                                    Icons.cleaning_services_rounded,
                                    'No housekeeping data',
                                  )
                                : _HkCard(rows: rows),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Feedbacks ──────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionTitle('Feedbacks'),
                            if (feedbackCount > 0)
                              _badge('$feedbackCount total', _blue),
                          ],
                        ),
                        const SizedBox(height: 10),
                        feedbackAsync.when(
                          loading: () => _skeletonCard(110),
                          error: (_, __) =>
                              _errorCard('Feedbacks unavailable'),
                          data: (list) => AppearFade(
                            delayMs: 120,
                            child: list.isEmpty
                                ? _emptyCard(
                                    Icons.reviews_outlined,
                                    'No feedback for this court yet',
                                  )
                                : _FeedbackSection(items: list),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Maintenance (read-only summary) ────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionTitle('Maintenance'),
                            if (openMaintenance > 0)
                              _badge('$openMaintenance open', _warn),
                          ],
                        ),
                        const SizedBox(height: 10),
                        maintenanceAsync.when(
                          loading: () => _skeletonCard(110),
                          error: (_, __) =>
                              _errorCard('Maintenance unavailable'),
                          data: (list) => AppearFade(
                            delayMs: 180,
                            child: list.isEmpty
                                ? _emptyCard(
                                    Icons.build_outlined,
                                    'No maintenance issues for this court',
                                  )
                                : _MaintenanceSection(items: list),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Pull to refresh  ·  auto-refresh 30s',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _black.withOpacity(0.25),
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
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(int feedbackCount, int openMaintenance) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back + refresh row
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _white.withOpacity(0.08)),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 15,
                    color: _grey,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _invalidateAll();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _white.withOpacity(0.08)),
                  ),
                  child: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: _grey,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Court name — antonSc matches app style
          Text(
            widget.court.name.toUpperCase(),
            style: GoogleFonts.antonSc(
              fontSize: 34,
              color: _white,
              letterSpacing: -0.5,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 6),

          // Location + status row
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 12, color: _grey),
              const SizedBox(width: 4),
              Text(
                widget.court.location,
                style: GoogleFonts.inter(fontSize: 12, color: _grey),
              ),
              const SizedBox(width: 10),
              _StatusDot(status: widget.court.isActive ? 'Active' : 'Inactive'),
            ],
          ),

          const SizedBox(height: 16),

          // Quick stat pills row
          Row(
            children: [
              _QuickPill(
                label: 'Feedbacks',
                value: '$feedbackCount',
                color: _blue,
              ),
              const SizedBox(width: 8),
              _QuickPill(
                label: 'Open Issues',
                value: '$openMaintenance',
                color: openMaintenance > 0 ? _warn : _ok,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Utility widgets ───────────────────────────────────────────────────────
  Widget _sectionTitle(String t) => Text(
    t,
    style: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: _black,
      letterSpacing: -0.2,
    ),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  // Animated shimmer placeholder (light variant — this area sits on the white
  // card). Structured shapes read as "content loading" instead of a dead grey
  // block, and the sweeping highlight makes the wait feel alive/premium.
  Widget _skeletonCard(double h) => Shimmer.light(
    child: SizedBox(
      height: h,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 34, radius: 10)),
              SizedBox(width: 14),
              Expanded(child: SkeletonBox(height: 34, radius: 10)),
              SizedBox(width: 14),
              Expanded(child: SkeletonBox(height: 34, radius: 10)),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(height: 12, radius: 6),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 150, height: 12, radius: 6),
          ),
          const Spacer(),
        ],
      ),
    ),
  );

  Widget _errorCard(String msg) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _danger.withOpacity(0.15), width: 1.5),
    ),
    child: Row(
      children: [
        const Icon(Icons.wifi_off_rounded, size: 16, color: _grey),
        const SizedBox(width: 8),
        Text(msg, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
      ],
    ),
  );

  Widget _emptyCard(IconData icon, String msg) => Container(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE8E8E6)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: _grey.withOpacity(0.5)),
        const SizedBox(width: 8),
        Text(msg, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
      ],
    ),
  );
}

// ─── Quick Pill (header) ──────────────────────────────────────────────────────

class _QuickPill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _QuickPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: _white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _white.withOpacity(0.08)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.antonSc(fontSize: 18, color: color, height: 1.0),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: _grey)),
      ],
    ),
  );
}

// ─── Status Dot ───────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final active = status.toLowerCase() == 'active';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? _ok : _danger,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          status,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: active ? _ok : _danger,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Sales Card ───────────────────────────────────────────────────────────────

class _SalesCard extends StatelessWidget {
  final SalesSummary summary;
  final String Function(double) fmt;
  const _SalesCard({required this.summary, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return _AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat row
          Row(
            children: [
              _StatBox(
                label: 'Revenue',
                value: '₹${fmt(summary.totalSales)}',
                icon: Icons.currency_rupee_rounded,
                color: _ok,
              ),
              _vDiv(),
              _StatBox(
                label: 'Bills',
                value: '${summary.totalBills}',
                icon: Icons.receipt_long_rounded,
                color: _blue,
              ),
              _vDiv(),
              _StatBox(
                label: 'Avg Bill',
                value: '₹${fmt(summary.avgBillValue)}',
                icon: Icons.bar_chart_rounded,
                color: _warn,
              ),
            ],
          ),
          // Vendor breakdown
          if (summary.vendors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.grey.shade100, height: 1),
            const SizedBox(height: 12),
            ...summary.vendors.map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.vendorName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _black,
                            ),
                          ),
                          Text(
                            v.sourceSystem,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${fmt(v.totalSales)}',
                          style: GoogleFonts.antonSc(
                            fontSize: 16,
                            color: _black,
                            height: 1.0,
                          ),
                        ),
                        Text(
                          '${v.billCount} bills',
                          style: GoogleFonts.inter(fontSize: 11, color: _grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vDiv() => Container(
    width: 1,
    height: 40,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: Colors.grey.shade100,
  );
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.antonSc(fontSize: 20, color: _black, height: 1.0),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ─── Housekeeping Card ────────────────────────────────────────────────────────

class _HkCard extends StatelessWidget {
  final List<_HkShift> rows;
  const _HkCard({required this.rows});

  @override
  Widget build(BuildContext context) => _AppCard(
    child: Column(
      children: rows.asMap().entries.map((e) {
        final i = e.key;
        final row = e.value;
        return Column(
          children: [
            if (i != 0) ...[
              Divider(color: Colors.grey.shade100, height: 1),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                // Shift label + time
                SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _black,
                        ),
                      ),
                      Text(
                        row.time,
                        style: GoogleFonts.inter(fontSize: 11, color: _grey),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (row.isEmpty)
                  Text(
                    '—',
                    style: GoogleFonts.inter(fontSize: 12, color: _grey),
                  )
                else ...[
                  Text(
                    '${row.done}/${row.total}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: row.isComplete ? _ok : _warn,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 90,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: row.pct,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          row.isComplete ? _ok : _warn,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
        );
      }).toList(),
    ),
  );
}

// ─── Maintenance Section (read-only summary) ─────────────────────────────────
// ✅ NEW: New status system, actions Maintenance tab mein hote hain

class _MaintenanceSection extends StatelessWidget {
  final List<MaintenanceIssueModel> items;
  const _MaintenanceSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final newCount = items
        .where((i) => i.status == 'RAISED' || i.status == 'DISPUTED')
        .length;
    final active = items
        .where((i) => i.status == 'ASSIGNED' || i.status == 'RESOLVED')
        .length;
    final closed = items.where((i) => i.status == 'CLOSED').length;

    // Open tickets pehle, closed last
    final sorted = [...items]
      ..sort((a, b) {
        if (a.status == 'CLOSED' && b.status != 'CLOSED') return 1;
        if (a.status != 'CLOSED' && b.status == 'CLOSED') return -1;
        return (b.createdAt ?? DateTime(2000)).compareTo(
          a.createdAt ?? DateTime(2000),
        );
      });

    return Column(
      children: [
        _SummaryBar(
          total: items.length,
          open: newCount,
          inProg: active,
          resolved: closed,
        ),
        const SizedBox(height: 10),
        ...sorted
            .take(5)
            .map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MaintenanceTile(item: i),
              ),
            ),
        if (sorted.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${sorted.length - 5} more in Maintenance tab',
              style: GoogleFonts.inter(fontSize: 12, color: _grey),
            ),
          ),
      ],
    );
  }
}

class _MStatusMeta {
  final String label;
  final Color color;
  const _MStatusMeta(this.label, this.color);
}

_MStatusMeta _mStatusMeta(String s) => switch (s) {
  'RAISED' => const _MStatusMeta('Raised', _warn),
  'ASSIGNED' => const _MStatusMeta('Assigned', _blue),
  'RESOLVED' => const _MStatusMeta('Verify', _purple),
  'CLOSED' => const _MStatusMeta('Closed', _ok),
  'DISPUTED' => const _MStatusMeta('Disputed', _danger),
  _ => const _MStatusMeta('Unknown', _grey),
};

String _mTypeEmoji(String t) => switch (t) {
  'electrical' => '⚡',
  'plumbing' => '🔧',
  'furniture' => '🪑',
  'cleaning' => '🧹',
  _ => '📋',
};

class _MaintenanceTile extends StatelessWidget {
  final MaintenanceIssueModel item;
  const _MaintenanceTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final st = _mStatusMeta(item.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: st.color.withOpacity(0.2), width: 1.5),
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: st.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(
                _mTypeEmoji(item.issueType),
                style: const TextStyle(fontSize: 19),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.outletName}  ·  ${_fmtTime(item.createdAt)}',
                  style: GoogleFonts.inter(fontSize: 11, color: _grey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: st.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              st.label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: st.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Bar (matches app exactly) ───────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int total, open, inProg, resolved;
  const _SummaryBar({
    required this.total,
    required this.open,
    required this.inProg,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _black,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        _Stat('Total', '$total', _white),
        _vDiv(),
        _Stat('Open', '$open', _danger),
        _vDiv(),
        _Stat('Progress', '$inProg', _warn),
        _vDiv(),
        _Stat('Resolved', '$resolved', _ok),
      ],
    ),
  );

  Widget _vDiv() => Container(
    width: 1,
    height: 34,
    color: _white.withOpacity(0.1),
    margin: const EdgeInsets.symmetric(horizontal: 8),
  );
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: GoogleFonts.antonSc(fontSize: 20, color: color, height: 1.0),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: _grey,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

// ─── Feedback Section (court-level, premium) ─────────────────────────────────

Color _ratingColor(int? r) {
  if (r == null) return _grey;
  if (r >= 4) return _ok;
  if (r == 3) return _warn;
  return _danger;
}

class _FeedbackSection extends StatelessWidget {
  final List<EtlFeedbackModel> items;
  const _FeedbackSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final rated = items
        .map((f) => f.outletRating ?? f.courtRating)
        .whereType<int>()
        .toList();
    final avg = rated.isEmpty
        ? 0.0
        : rated.reduce((a, b) => a + b) / rated.length;
    final five = items
        .where((f) => f.outletRating == 5 || f.courtRating == 5)
        .length;
    final one = items
        .where((f) => f.outletRating == 1 || f.courtRating == 1)
        .length;

    final sorted = [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final visible = sorted.take(5).toList();

    return Column(
      children: [
        // Premium dark summary bar
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _black,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _Stat('Total', '${items.length}', _white),
              _fbDiv(),
              _Stat('Avg', avg > 0 ? avg.toStringAsFixed(1) : '—', _warn),
              _fbDiv(),
              _Stat('5★', '$five', _ok),
              _fbDiv(),
              _Stat('1★', '$one', _danger),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...visible.map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FeedbackTile(item: f),
          ),
        ),
        if (sorted.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${sorted.length - 5} more in Feedbacks tab',
              style: GoogleFonts.inter(fontSize: 12, color: _grey),
            ),
          ),
      ],
    );
  }

  Widget _fbDiv() => Container(
    width: 1,
    height: 34,
    color: _white.withOpacity(0.1),
    margin: const EdgeInsets.symmetric(horizontal: 8),
  );
}

class _FeedbackTile extends StatelessWidget {
  final EtlFeedbackModel item;
  const _FeedbackTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final rating = item.outletRating ?? item.courtRating;
    final rColor = _ratingColor(rating);
    final comment =
        (item.outletComments != null &&
            item.outletComments!.trim().isNotEmpty)
        ? item.outletComments!
        : (item.courtComments != null &&
              item.courtComments!.trim().isNotEmpty)
        ? item.courtComments!
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: rColor.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                  color: rColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    item.customerName.isNotEmpty
                        ? item.customerName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.antonSc(fontSize: 16, color: rColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.customerName,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _fmtTime(item.createdAt),
                      style: GoogleFonts.inter(fontSize: 12, color: _grey),
                    ),
                  ],
                ),
              ),
              if (rating != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: rColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 13, color: rColor),
                      const SizedBox(width: 3),
                      Text(
                        '$rating',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: rColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (comment != null) ...[
            const SizedBox(height: 10),
            Divider(color: Colors.grey.shade100, height: 1),
            const SizedBox(height: 10),
            Text(
              '"$comment"',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: _black,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── App Card ─────────────────────────────────────────────────────────────────

class _AppCard extends StatelessWidget {
  final Widget child;
  const _AppCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE8E8E6)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

// ─── Helper classes ───────────────────────────────────────────────────────────

String _fmtTime(DateTime? dt) {
  if (dt == null) return '—';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${dt.day} ${_months[dt.month]}';
}

const _months = [
  '',
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
