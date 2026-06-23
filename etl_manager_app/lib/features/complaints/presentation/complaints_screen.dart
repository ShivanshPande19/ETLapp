// lib/features/complaints/presentation/complaints_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/skeleton.dart';

// NEW IMPORT: Dynamic Courts Notifier
import '../../courts/domain/courts_notifier.dart';
import '../data/complaints_repository.dart';
import '../domain/complaint_model.dart';

const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
const _purple = Color(0xFFA78BFA);

class ComplaintsScreen extends ConsumerStatefulWidget {
  const ComplaintsScreen({super.key});
  @override
  ConsumerState<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends ConsumerState<ComplaintsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _listCtrl;
  late final Animation<double> _fadeAnim;
  Timer? _pollTimer;

  int _filterCourt = 0; // 0 means 'All'
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _listCtrl.forward();
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(complaintsProvider);
    });

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _fadeCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(complaintsProvider);
    ref.invalidate(courtsNotifierProvider);
    _listCtrl
      ..reset()
      ..forward();
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
    final async = ref.watch(complaintsProvider);
    final courtsAsync = ref.watch(courtsNotifierProvider);
    final bottom = MediaQuery.of(context).padding.bottom + 92.0;

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(courtsAsync),
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
                      loading: () => const SkeletonList(
                        dark: false,
                        count: 6,
                        tileHeight: 88,
                      ),
                      error: (_, __) => _errorView(),
                      data: (items) => courtsAsync.when(
                        loading: () => const SkeletonList(
                          dark: false,
                          count: 6,
                          tileHeight: 88,
                        ),
                        error: (_, __) => _errorView(),
                        data: (courts) => _buildContent(items, courts, bottom),
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

  Widget _buildHeader(AsyncValue<List<dynamic>> courtsAsync) => Padding(
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
                    'Complaints',
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

        // NEW: Dynamic Courts
        courtsAsync.when(
          loading: () => const SizedBox(height: 32),
          error: (_, __) => const SizedBox(height: 32),
          data: (courts) {
            return SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _courtTab('All', 0),
                  ...courts.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _courtTab(c.name, c.id),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 10),
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filterCourt = court);
        _listCtrl
          ..reset()
          ..forward();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
    );
  }

  Widget _statusTab(String val, String label) {
    final sel = _filterStatus == val;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _filterStatus = val);
          _listCtrl
            ..reset()
            ..forward();
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

  Widget _buildContent(
    List<ComplaintModel> all,
    List<dynamic> courts,
    double navClearance,
  ) {
    final filtered = all.where((c) {
      if (_filterCourt > 0 && c.courtId != _filterCourt) return false;
      if (_filterStatus != 'all' && c.status != _filterStatus) return false;
      return true;
    }).toList();

    final open = all.where((c) => c.status == 'open').length;
    final inProg = all.where((c) => c.status == 'in_progress').length;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, navClearance),
      children: [
        _StaggerItem(
          anim: _itemAnim(0),
          child: _SummaryBar(
            total: all.length,
            open: open,
            inProg: inProg,
            resolved: all.length - open - inProg,
          ),
        ),

        const SizedBox(height: 16),

        if (filtered.isEmpty) ...[
          const SizedBox(height: 40),
          _StaggerItem(anim: _itemAnim(1), child: _emptyView()),
        ] else ...[
          _StaggerItem(
            anim: _itemAnim(1),
            child: Text(
              '${filtered.length} complaint${filtered.length == 1 ? '' : 's'}',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _black,
                letterSpacing: -.3,
              ),
            ),
          ),
          const SizedBox(height: 10),

          ...filtered.asMap().entries.map((e) {
            // ✅ THE FIX: Safely finding the court without crashing
            final matchedCourts = courts.where((c) => c.id == e.value.courtId);
            final courtName = matchedCourts.isNotEmpty
                ? matchedCourts.first.name
                : 'Unknown Court';

            return _StaggerItem(
              anim: _itemAnim(e.key + 2),
              child: _ComplaintTile(
                key: ValueKey('complaint_${e.value.id}'),
                item: e.value,
                courtName: courtName,
                onStatusChange: (s) => _updateStatus(e.value.id, s),
              ),
            );
          }),

          const SizedBox(height: 8),
          _StaggerItem(
            anim: _itemAnim(filtered.length + 2),
            child: Center(
              child: Text(
                'Pull to refresh  ·  auto-refresh 30s',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: _black.withOpacity(0.25),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _updateStatus(int id, String newStatus) async {
    try {
      await ref.read(complaintsRepoProvider).updateStatus(id, newStatus);
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
    padding: const EdgeInsets.all(40),
    children: [
      const Icon(Icons.wifi_off_rounded, size: 40, color: _grey),
      const SizedBox(height: 12),
      Text(
        'Could not load complaints',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _black,
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: GestureDetector(
          onTap: _refresh,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: _black,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _white,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _emptyView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline_rounded,
          size: 48,
          color: _grey.withOpacity(0.4),
        ),
        const SizedBox(height: 12),
        Text(
          'No complaints',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Nothing matches your current filters',
          style: GoogleFonts.inter(fontSize: 13, color: _grey),
        ),
      ],
    ),
  );
}

class _StaggerItem extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const _StaggerItem({required this.anim, required this.child});

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: anim,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(anim),
      child: child,
    ),
  );
}

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
  Widget _vDiv() => Container(
    width: 1,
    height: 36,
    color: _white.withOpacity(0.1),
    margin: const EdgeInsets.symmetric(horizontal: 10),
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
          style: GoogleFonts.antonSc(fontSize: 22, color: color, height: 1.0),
        ),
        const SizedBox(height: 3),
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

class _ComplaintTile extends StatelessWidget {
  final ComplaintModel item;
  final String courtName;
  final void Function(String) onStatusChange;
  const _ComplaintTile({
    super.key,
    required this.item,
    required this.courtName,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final cat = _catMeta(item.category);
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
                      '$courtName  ·  ${_fmtTime(item.createdAt)}',
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

class _CatMeta {
  final String emoji, label;
  final Color color;
  const _CatMeta(this.emoji, this.label, this.color);
}

class _StatusMeta {
  final String label;
  final Color color;
  const _StatusMeta(this.label, this.color);
}

_CatMeta _catMeta(String cat) => switch (cat) {
  'food' => const _CatMeta('🍔', 'Food Quality', _blue),
  'staff' => const _CatMeta('🧑', 'Staff Behaviour', _danger),
  'cleanliness' => const _CatMeta('🧹', 'Cleanliness', _purple),
  _ => const _CatMeta('📋', 'Other Issue', _grey),
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
