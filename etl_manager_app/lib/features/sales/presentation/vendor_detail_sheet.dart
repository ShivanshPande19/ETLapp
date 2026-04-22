import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import '../data/sales_repository.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _lightGrey = Color(0xFFF2F2F2);
const _border = Color(0xFF1A1A1A);

// ── Entry point ───────────────────────────────────────────────────────────────

void showVendorDetail({
  required BuildContext context,
  required String vendorName,
  required int courtId,
  required SalesRepository repo,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VendorDetailSheet(
      vendorName: vendorName,
      courtId: courtId,
      repo: repo,
    ),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _VendorDetailSheet extends StatefulWidget {
  final String vendorName;
  final int courtId;
  final SalesRepository repo;
  const _VendorDetailSheet({
    required this.vendorName,
    required this.courtId,
    required this.repo,
  });

  @override
  State<_VendorDetailSheet> createState() => _VendorDetailSheetState();
}

class _VendorDetailSheetState extends State<_VendorDetailSheet>
    with SingleTickerProviderStateMixin {
  VendorHistory? _data;
  bool _loading = true;
  String? _error;
  late AnimationController _barCtrl;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.repo.fetchVendorHistory(
        vendorName: widget.vendorName,
        courtId: widget.courtId,
      );
      if (mounted) {
        setState(() {
          _data = result;
          _loading = false;
        });
        _barCtrl.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load vendor data';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────

  String _fmt(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  String _dayLetter(String iso) {
    try {
      const l = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      return l[DateTime.parse(iso).weekday - 1];
    } catch (_) {
      return '?';
    }
  }

  String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const m = [
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
      return '${m[d.month - 1]} ${d.day}';
    } catch (_) {
      return iso;
    }
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _border.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _black,
                        strokeWidth: 2,
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: _grey,
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: GoogleFonts.inter(
                              color: _grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildContent(scrollCtrl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ScrollController scrollCtrl) {
    final d = _data!;
    final maxSales = d.dailyHistory.isEmpty
        ? 1.0
        : d.dailyHistory.map((e) => e.totalSales).reduce(math.max);

    final weekDiff = d.weekTotal - d.lastWeekTotal;
    final weekDiffPct = d.lastWeekTotal > 0
        ? (weekDiff / d.lastWeekTotal * 100)
        : 0.0;
    final isUp = weekDiff >= 0;

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        // ── Header ─────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _black,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  d.vendorName.substring(0, 1).toUpperCase(),
                  style: GoogleFonts.antonSc(fontSize: 20, color: _white),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.vendorName,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _black,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Data as of yesterday · synced 11 PM',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _grey,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Yesterday stats ─────────────────────────────────
        Row(
          children: [
            _StatBox(label: 'Yesterday', value: _fmt(d.totalSales), flex: 2),
            const SizedBox(width: 10),
            _StatBox(label: 'Bills', value: '${d.billCount}'),
            const SizedBox(width: 10),
            _StatBox(label: 'Avg Bill', value: _fmt(d.avgBillValue)),
          ],
        ),
        const SizedBox(height: 10),

        // ── Week comparison ─────────────────────────────────
        Row(
          children: [
            _StatBox(label: 'This Week', value: _fmt(d.weekTotal), flex: 2),
            const SizedBox(width: 10),
            _StatBox(label: 'Last Week', value: _fmt(d.lastWeekTotal), flex: 2),
            const SizedBox(width: 10),
            _StatBox(
              label: 'WoW',
              value: '${isUp ? '+' : ''}${weekDiffPct.toStringAsFixed(1)}%',
              valueColor: isUp
                  ? const Color(0xFF22A06B)
                  : const Color(0xFFE53E3E),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Best day badge ──────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _black,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
              const SizedBox(width: 8),
              Text(
                'Best day this week: ',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white54,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                d.bestDay,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: _white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── 7-Day bar chart ─────────────────────────────────
        Text(
          'Last 7 Days',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _black,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),

        // Total fixed heights:
        // label zone = 20, bar max = 120, gap = 5,
        // day letter = 14, date num = 12  →  total = 171 < 190
        SizedBox(
          height: 190,
          child: AnimatedBuilder(
            animation: _barCtrl,
            builder: (_, __) {
              final progress = CurvedAnimation(
                parent: _barCtrl,
                curve: Curves.easeOutCubic,
              ).value;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: d.dailyHistory.asMap().entries.map((e) {
                  final snap = e.value;
                  final isLast = e.key == d.dailyHistory.length - 1;
                  final isBestBar = snap.totalSales == maxSales;
                  final ratio = maxSales > 0 ? snap.totalSales / maxSales : 0.0;
                  // max bar = 120, always clamped
                  final barH = (120 * ratio * progress).clamp(2.0, 120.0);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Label zone — always 20px
                          SizedBox(
                            height: 20,
                            child: isBestBar
                                ? Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Text(
                                      _fmt(snap.totalSales),
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        color: _black,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          // Bar — clamped height
                          Container(
                            height: barH,
                            decoration: BoxDecoration(
                              color: isLast
                                  ? _black
                                  : isBestBar
                                  ? _border
                                  : _lightGrey,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                          // Gap — always 5px
                          const SizedBox(height: 5),
                          // Day letter — always 14px
                          SizedBox(
                            height: 14,
                            child: Text(
                              _dayLetter(snap.date),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: isLast ? _black : _grey,
                                fontWeight: isLast
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          // Date number — always 12px
                          SizedBox(
                            height: 12,
                            child: Text(
                              _shortDate(snap.date).split(' ').last,
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: _grey.withOpacity(0.5),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // ── Daily breakdown list ────────────────────────────
        Text(
          'Daily Breakdown',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _black,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),

        ...d.dailyHistory.reversed.map((snap) {
          final isBest = snap.totalSales == maxSales;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isBest ? _black : _lightGrey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  _shortDate(snap.date),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isBest ? _white : _black,
                  ),
                ),
                if (isBest) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Best',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: Colors.amber,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${snap.totalBills} bills',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isBest ? Colors.white54 : _grey,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _fmt(snap.totalSales),
                  style: GoogleFonts.antonSc(
                    fontSize: 15,
                    color: isBest ? _white : _black,
                    height: 1,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── Stat Box ──────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final int flex;
  final Color? valueColor;
  const _StatBox({
    required this.label,
    required this.value,
    this.flex = 1,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _lightGrey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _grey,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: GoogleFonts.antonSc(
                fontSize: 17,
                color: valueColor ?? _black,
                height: 1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
