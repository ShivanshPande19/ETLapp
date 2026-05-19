// lib/features/courts/presentation/court_detail_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/courts_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../complaints/data/complaints_repository.dart';
import '../../complaints/domain/complaint_model.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../maintenance/domain/maintenance_model.dart';
import '../../staff/data/housekeeping_repository.dart';
import '../../staff/domain/housekeeping_models.dart';

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
const _orange = Color(0xFFFB923C);

// ─── Court-scoped Providers ───────────────────────────────────────────────────

final _courtSalesProvider = FutureProvider.autoDispose
    .family<SalesSummary, int>((ref, id) async {
      return ref
          .read(salesRepositoryProvider)
          .getSalesSummary(courtId: id, period: 'yesterday');
    });

final _courtComplaintsProvider = FutureProvider.autoDispose
    .family<List<ComplaintModel>, int>((ref, id) async {
      return ref.read(complaintsRepoProvider).getComplaints(courtId: id);
    });

final _courtMaintenanceProvider = FutureProvider.autoDispose
    .family<List<MaintenanceIssue>, int>((ref, id) async {
      return ref.read(maintenanceRepoProvider).getIssues(courtId: id);
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
        final label = s.shift == Shift.morning
            ? 'Morning'
            : s.shift == Shift.day
            ? 'Day'
            : 'Night';
        final time = s.shift == Shift.morning
            ? '6 AM – 12 PM'
            : s.shift == Shift.day
            ? '12 PM – 4 PM'
            : '4 PM – 11 PM';
        return _HkShift(label: label, time: time, done: s.done, total: s.total);
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
    ref.invalidate(_courtComplaintsProvider(widget.court.id));
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
    final complaintsAsync = ref.watch(
      _courtComplaintsProvider(widget.court.id),
    );
    final maintenanceAsync = ref.watch(
      _courtMaintenanceProvider(widget.court.id),
    );
    final hkAsync = ref.watch(_courtHkProvider(widget.court.id));

    final openComplaints =
        complaintsAsync
            .whenData((l) => l.where((c) => c.status == 'open').length)
            .value ??
        0;
    final openMaintenance =
        maintenanceAsync
            .whenData((l) => l.where((i) => i.status == 'open').length)
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
              _buildHeader(openComplaints, openMaintenance),

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
                          data: (s) => _SalesCard(summary: s, fmt: _fmt),
                        ),
                        const SizedBox(height: 24),

                        // ── Housekeeping ───────────────────────
                        _sectionTitle('Housekeeping · Today'),
                        const SizedBox(height: 10),
                        hkAsync.when(
                          loading: () => _skeletonCard(120),
                          error: (_, __) =>
                              _errorCard('Housekeeping unavailable'),
                          data: (rows) => rows.isEmpty
                              ? _emptyCard(
                                  Icons.cleaning_services_rounded,
                                  'No housekeeping data',
                                )
                              : _HkCard(rows: rows),
                        ),
                        const SizedBox(height: 24),

                        // ── Complaints ─────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionTitle('Complaints'),
                            if (openComplaints > 0)
                              _badge('$openComplaints open', _danger),
                          ],
                        ),
                        const SizedBox(height: 10),
                        complaintsAsync.when(
                          loading: () => _skeletonCard(110),
                          error: (_, __) =>
                              _errorCard('Complaints unavailable'),
                          data: (list) => list.isEmpty
                              ? _emptyCard(
                                  Icons.chat_bubble_outline_rounded,
                                  'No complaints for this court',
                                )
                              : _ComplaintsSection(
                                  items: list,
                                  onStatusChange: (id, s) =>
                                      _updateComplaint(id, s),
                                ),
                        ),
                        const SizedBox(height: 24),

                        // ── Maintenance ────────────────────────
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
                          data: (list) => list.isEmpty
                              ? _emptyCard(
                                  Icons.build_outlined,
                                  'No maintenance issues for this court',
                                )
                              : _MaintenanceSection(
                                  items: list,
                                  onStatusChange: (id, s) =>
                                      _updateMaintenance(id, s),
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
  Widget _buildHeader(int openComplaints, int openMaintenance) {
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
                label: 'Open Complaints',
                value: '$openComplaints',
                color: openComplaints > 0 ? _danger : _ok,
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

  // ── Status update handlers ────────────────────────────────────────────────
  Future<void> _updateComplaint(int id, String newStatus) async {
    try {
      await ref.read(complaintsRepoProvider).updateStatus(id, newStatus);
      ref.invalidate(_courtComplaintsProvider(widget.court.id));
      HapticFeedback.mediumImpact();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update — please retry')),
      );
    }
  }

  Future<void> _updateMaintenance(int id, String newStatus) async {
    try {
      await ref.read(maintenanceRepoProvider).updateStatus(id, newStatus);
      ref.invalidate(_courtMaintenanceProvider(widget.court.id));
      HapticFeedback.mediumImpact();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update — please retry')),
      );
    }
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

  Widget _skeletonCard(double h) => Container(
    height: h,
    decoration: BoxDecoration(
      color: const Color(0xFFEEEEEC),
      borderRadius: BorderRadius.circular(18),
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

// ─── Complaints Section ───────────────────────────────────────────────────────

class _ComplaintsSection extends StatelessWidget {
  final List<ComplaintModel> items;
  final void Function(int id, String status) onStatusChange;
  const _ComplaintsSection({required this.items, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final open = items.where((c) => c.status == 'open').toList();
    final inProg = items.where((c) => c.status == 'in_progress').toList();
    final resolved = items.where((c) => c.status == 'resolved').toList();
    final sorted = [...open, ...inProg, ...resolved];

    return Column(
      children: [
        // Summary bar — matches complaints_screen.dart style
        _SummaryBar(
          total: items.length,
          open: open.length,
          inProg: inProg.length,
          resolved: resolved.length,
        ),
        const SizedBox(height: 10),
        ...sorted.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ComplaintTile(
              item: c,
              onStatusChange: (s) => onStatusChange(c.id, s),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Maintenance Section ──────────────────────────────────────────────────────

class _MaintenanceSection extends StatelessWidget {
  final List<MaintenanceIssue> items;
  final void Function(int id, String status) onStatusChange;
  const _MaintenanceSection({
    required this.items,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final open = items.where((i) => i.status == 'open').toList();
    final inProg = items.where((i) => i.status == 'in_progress').toList();
    final resolved = items.where((i) => i.status == 'resolved').toList();
    final sorted = [...open, ...inProg, ...resolved];

    return Column(
      children: [
        _SummaryBar(
          total: items.length,
          open: open.length,
          inProg: inProg.length,
          resolved: resolved.length,
        ),
        const SizedBox(height: 10),
        ...sorted.map(
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _IssueTile(
              item: i,
              onStatusChange: (s) => onStatusChange(i.id, s),
            ),
          ),
        ),
      ],
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

// ─── Complaint Tile (matches complaints_screen.dart exactly) ─────────────────

class _ComplaintTile extends StatelessWidget {
  final ComplaintModel item;
  final void Function(String) onStatusChange;
  const _ComplaintTile({required this.item, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final cat = _catMeta(item.category);
    final status = _statusMeta(item.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: status.color.withOpacity(0.2), width: 1.5),
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
                  color: cat.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(cat.emoji, style: const TextStyle(fontSize: 19)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.label,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _black,
                      ),
                    ),
                    Text(
                      '${_fmtTime(item.createdAt)}',
                      style: GoogleFonts.inter(fontSize: 12, color: _grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: status.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: status.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.grey.shade100, height: 1),
          const SizedBox(height: 10),
          Text(
            item.description,
            style: GoogleFonts.inter(fontSize: 13, color: _black, height: 1.5),
          ),
          if (item.status != 'resolved') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.status == 'open') ...[
                  _ActionBtn(
                    'In Progress',
                    _warn,
                    () => onStatusChange('in_progress'),
                  ),
                  const SizedBox(width: 8),
                ],
                _ActionBtn('Resolve', _ok, () => onStatusChange('resolved')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Issue Tile (matches maintenance_screen.dart exactly) ────────────────────

class _IssueTile extends StatelessWidget {
  final MaintenanceIssue item;
  final void Function(String) onStatusChange;
  const _IssueTile({required this.item, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final meta = _issueMeta(item.issueType);
    final status = _statusMeta(item.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: status.color.withOpacity(0.2), width: 1.5),
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
                  color: meta.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(meta.emoji, style: const TextStyle(fontSize: 19)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.label,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _black,
                      ),
                    ),
                    Text(
                      '${item.cartName.isNotEmpty ? item.cartName : item.cartId}  ·  ${_fmtTime(item.createdAt)}',
                      style: GoogleFonts.inter(fontSize: 12, color: _grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: status.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: status.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.grey.shade100, height: 1),
          const SizedBox(height: 10),
          Text(
            item.description,
            style: GoogleFonts.inter(fontSize: 13, color: _black, height: 1.5),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 13, color: _grey),
              const SizedBox(width: 4),
              Text(
                'Reported by ${item.staffName}',
                style: GoogleFonts.inter(fontSize: 12, color: _grey),
              ),
            ],
          ),
          if (item.status != 'resolved') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.status == 'open') ...[
                  _ActionBtn(
                    'In Progress',
                    _warn,
                    () => onStatusChange('in_progress'),
                  ),
                  const SizedBox(width: 8),
                ],
                _ActionBtn('Resolve', _ok, () => onStatusChange('resolved')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      onTap();
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );
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

class _CatMeta {
  final String emoji, label;
  final Color color;
  const _CatMeta(this.emoji, this.label, this.color);
}

class _IssueMetaD {
  final String emoji, label;
  final Color color;
  const _IssueMetaD(this.emoji, this.label, this.color);
}

class _StatusMetaD {
  final String label;
  final Color color;
  const _StatusMetaD(this.label, this.color);
}

_CatMeta _catMeta(String cat) => switch (cat) {
  'food' => const _CatMeta('🍔', 'Food Quality', _blue),
  'staff' => const _CatMeta('🧑', 'Staff Behaviour', _danger),
  'cleanliness' => const _CatMeta('🧹', 'Cleanliness', _purple),
  _ => const _CatMeta('📋', 'Other Issue', _grey),
};

_IssueMetaD _issueMeta(String type) => switch (type.toLowerCase()) {
  'electrical' => const _IssueMetaD('⚡', 'Electrical', _warn),
  'plumbing' => const _IssueMetaD('💧', 'Plumbing', _blue),
  'equipment' => const _IssueMetaD('🔧', 'Equipment', _orange),
  'cleaning' => const _IssueMetaD('🧹', 'Cleaning', _purple),
  'safety' => const _IssueMetaD('🛡️', 'Safety', _danger),
  _ => const _IssueMetaD('🔨', 'Other Issue', _grey),
};

_StatusMetaD _statusMeta(String s) => switch (s) {
  'open' => const _StatusMetaD('Open', _danger),
  'in_progress' => const _StatusMetaD('In Progress', _warn),
  'resolved' => const _StatusMetaD('Resolved', _ok),
  _ => const _StatusMetaD('Unknown', _grey),
};

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
