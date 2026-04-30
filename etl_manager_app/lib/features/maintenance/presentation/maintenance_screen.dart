// lib/features/maintenance/presentation/maintenance_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/maintenance_repository.dart';
import '../domain/maintenance_model.dart';

// ─── Palette (matches complaints_screen.dart exactly) ────────────────────────
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

// ─── Screen ──────────────────────────────────────────────────────────────────
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  Timer? _pollTimer;

  int _filterCourt = 0; // 0 = All courts
  String _filterStatus = 'all'; // all | open | in_progress | resolved

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();

    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(maintenanceProvider);
    });

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(maintenanceProvider);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(maintenanceProvider);
    final bottom = MediaQuery.of(context).padding.bottom + 92.0;

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
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
                    onRefresh: () async => _refresh(),
                    child: async.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: _black,
                          strokeWidth: 2,
                        ),
                      ),
                      error: (_, __) => _errorView(),
                      data: (items) => _buildContent(items, bottom),
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

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repairs',
                    style: GoogleFonts.antonSc(
                      fontSize: 30,
                      color: _white,
                      letterSpacing: -.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'auto-refresh every 30s',
                    style: GoogleFonts.inter(fontSize: 11, color: _grey),
                  ),
                ],
              ),
            ),
            _iconBtn(Icons.refresh_rounded, _refresh),
          ],
        ),

        const SizedBox(height: 16),

        // Court filter chips
        Row(
          children: [
            _courtTab('All', 0),
            const SizedBox(width: 6),
            _courtTab('Court 1', 1),
            const SizedBox(width: 6),
            _courtTab('Court 2', 2),
            const SizedBox(width: 6),
            _courtTab('Court 3', 3),
          ],
        ),

        const SizedBox(height: 10),

        // Status segmented control
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _statusTab('all', 'All'),
              _statusTab('open', 'Open'),
              _statusTab('in_progress', 'In Progress'),
              _statusTab('resolved', 'Resolved'),
            ],
          ),
        ),

        const SizedBox(height: 18),
      ],
    ),
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _white.withOpacity(0.08)),
      ),
      child: Icon(icon, size: 18, color: _grey),
    ),
  );

  Widget _courtTab(String label, int court) {
    final sel = _filterCourt == court;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _filterCourt = court);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _white : _white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: sel ? _black : _grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusTab(String val, String label) {
    final sel = _filterStatus == val;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _filterStatus = val);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: sel ? _black : _grey,
            ),
          ),
        ),
      ),
    );
  }

  // ── Content ─────────────────────────────────────────────────────────────────
  Widget _buildContent(List<MaintenanceIssue> all, double navClearance) {
    final filtered = all.where((i) {
      if (_filterCourt > 0 && i.courtId != _filterCourt) return false;
      if (_filterStatus != 'all' && i.status != _filterStatus) return false;
      return true;
    }).toList();

    final open = all.where((i) => i.status == 'open').length;
    final inProg = all.where((i) => i.status == 'in_progress').length;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, navClearance),
      children: [
        _SummaryBar(
          total: all.length,
          open: open,
          inProg: inProg,
          resolved: all.length - open - inProg,
        ),

        const SizedBox(height: 16),

        if (filtered.isEmpty) ...[
          const SizedBox(height: 40),
          _emptyView(),
        ] else ...[
          Text(
            '${filtered.length} issue${filtered.length == 1 ? '' : 's'}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _black,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 10),
          ...filtered.map(
            (i) => _IssueTile(
              key: ValueKey(i.id),
              item: i,
              onStatusChange: (s) => _updateStatus(i.id, s),
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
      ],
    );
  }

  Future<void> _updateStatus(int id, String newStatus) async {
    try {
      await ref.read(maintenanceRepoProvider).updateStatus(id, newStatus);
      _refresh();
      HapticFeedback.mediumImpact();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update — please retry')),
      );
    }
  }

  Widget _errorView() => ListView(
    children: [
      const SizedBox(height: 80),
      Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text(
        'Could not load issues',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: _black,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Check your connection and pull to refresh.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: _grey),
      ),
    ],
  );

  Widget _emptyView() => Column(
    children: [
      Icon(Icons.handyman_rounded, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text(
        _filterStatus == 'resolved'
            ? 'No resolved issues yet'
            : _filterStatus == 'in_progress'
            ? 'Nothing in progress'
            : _filterStatus == 'open'
            ? 'No open issues 🎉'
            : 'No maintenance issues reported',
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: _black,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Staff scan cart QR codes to report issues.',
        style: GoogleFonts.inter(fontSize: 13, color: _grey),
      ),
    ],
  );
}

// ─── Summary Bar ─────────────────────────────────────────────────────────────
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
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _black,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        _Stat('Total', total.toString(), _white),
        _vDiv(),
        _Stat('Open', open.toString(), _danger),
        _vDiv(),
        _Stat('In Progress', inProg.toString(), _warn),
        _vDiv(),
        _Stat('Resolved', resolved.toString(), _ok),
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
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: _grey)),
      ],
    ),
  );
}

// ─── Issue Tile ───────────────────────────────────────────────────────────────
class _IssueTile extends StatelessWidget {
  final MaintenanceIssue item;
  final void Function(String) onStatusChange;
  const _IssueTile({
    super.key,
    required this.item,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _issueMeta(item.issueType);
    final status = _statusMeta(item.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
          // Top row: icon + info + status badge
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
                      '${item.courtName}  ·  ${item.cartName}  ·  ${_fmtTime(item.createdAt)}',
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

          // Description
          Text(
            item.description,
            style: GoogleFonts.inter(fontSize: 13, color: _black, height: 1.5),
          ),

          // Staff name row
          const SizedBox(height: 8),
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

          // Action buttons
          if (item.status != 'resolved') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.status == 'open') ...[
                  _ActionBtn(
                    'Mark In Progress',
                    _warn,
                    () => onStatusChange('in_progress'),
                  ),
                  const SizedBox(width: 8),
                ],
                _ActionBtn('Resolve', _ok, () => onStatusChange('resolved')),
              ],
            ),
          ],

          if (item.status == 'resolved' && item.resolvedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Resolved ${_fmtTime(item.resolvedAt)}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _ok.withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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

// ─── Helpers ──────────────────────────────────────────────────────────────────
class _IssueMeta {
  final String emoji, label;
  final Color color;
  const _IssueMeta(this.emoji, this.label, this.color);
}

class _StatusMeta {
  final String label;
  final Color color;
  const _StatusMeta(this.label, this.color);
}

_IssueMeta _issueMeta(String type) => switch (type) {
  'electrical' => const _IssueMeta('⚡', 'Electrical', _warn),
  'plumbing' => const _IssueMeta('🔧', 'Plumbing', _blue),
  'furniture' => const _IssueMeta('🪑', 'Furniture', _purple),
  'cleaning' => const _IssueMeta('🧹', 'Deep Cleaning', _orange),
  _ => const _IssueMeta('📋', 'Other Issue', _grey),
};

_StatusMeta _statusMeta(String s) => switch (s) {
  'open' => const _StatusMeta('Open', _danger),
  'in_progress' => const _StatusMeta('In Progress', _warn),
  'resolved' => const _StatusMeta('Resolved', _ok),
  _ => const _StatusMeta('Unknown', _grey),
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
