// lib/features/housekeeping/presentation/manager_housekeeping_screen.dart
//
// Config-driven manager housekeeping monitor (Phase 3b).
//
// Renders each court's CONFIGURED shifts (names/timings), daily tasks, and any
// number of weekly/monthly recurring tasks — all dynamic, nothing hardcoded.

import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../courts/domain/courts_notifier.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/appear_fade.dart';
import '../../staff/data/housekeeping_repository.dart';
import '../../staff/domain/housekeeping_models.dart' as hk;

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _lg = Color(0xFFF2F2F2);
const _border = Color(0xFF1A1A1A);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFE5A000);
const _danger = Color(0xFFFF4444);
const _purple = Color(0xFFA78BFA);
const _bg = Color(0xFF080808);

final managerHkProvider = FutureProvider.autoDispose
    .family<hk.FullStatusResponse?, String>((ref, date) async {
      return ref.read(housekeepingRepoProvider).getFullStatus(date: date);
    });

class ManagerHousekeepingScreen extends ConsumerStatefulWidget {
  const ManagerHousekeepingScreen({super.key});
  @override
  ConsumerState<ManagerHousekeepingScreen> createState() =>
      _ManagerHousekeepingScreenState();
}

class _ManagerHousekeepingScreenState
    extends ConsumerState<ManagerHousekeepingScreen>
    with TickerProviderStateMixin {
  DateTime _date = DateTime.now();
  String? _shiftKey; // selected shift (config key); auto-resolved if null
  int? _court; // selected court id; auto-selects first if null

  late final AnimationController _fadeCtrl;
  late final AnimationController _listCtrl;
  late final Animation<double> _fadeAnim;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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
      if (mounted) ref.invalidate(managerHkProvider(_dateStr));
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

  String get _dateStr => _date.toIso8601String().substring(0, 10);

  void _refresh() {
    ref.invalidate(managerHkProvider(_dateStr));
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

  // Shifts for the currently selected court (from status data).
  List<hk.ShiftStatus> _courtShifts(hk.FullStatusResponse? data) {
    if (data == null || _court == null) return const [];
    return data.courtById(_court!)?.shifts ?? const [];
  }

  // Valid selected shift key, falling back to the active/first shift.
  String? _effectiveShiftKey(List<hk.ShiftStatus> shifts) {
    if (shifts.isEmpty) return null;
    if (_shiftKey != null && shifts.any((s) => s.shiftKey == _shiftKey)) {
      return _shiftKey;
    }
    final active = shifts.firstWhereOrNull((s) => s.isActiveNow);
    return (active ?? shifts.first).shiftKey;
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(managerHkProvider(_dateStr));
    final courtsAsync = ref.watch(courtsNotifierProvider);

    final navClearance = MediaQuery.of(context).padding.bottom + 92.0;

    final statusData = statusAsync.asData?.value;
    final courtShifts = _courtShifts(statusData);
    final selectedShiftKey = _effectiveShiftKey(courtShifts);

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(courtsAsync, courtShifts, selectedShiftKey),
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
                    child: statusAsync.when(
                      skipLoadingOnReload: true,
                      loading: () => const _Loader(),
                      error: (e, _) => _ErrorView(onRetry: _refresh),
                      data: (data) {
                        if (data == null) return _ErrorView(onRetry: _refresh);
                        return courtsAsync.when(
                          skipLoadingOnReload: true,
                          loading: () => const _Loader(),
                          error: (err, stack) => _ErrorView(onRetry: _refresh),
                          data: (courts) {
                            if (courts.isEmpty) {
                              return const Center(
                                child: Text("No Courts available"),
                              );
                            }
                            if (_court == null ||
                                !courts.any((c) => c.id == _court)) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() => _court = courts.first.id);
                                }
                              });
                            }
                            if (_court == null) return const SizedBox.shrink();

                            return AppearFade(
                              child: _buildContent(
                                data,
                                selectedShiftKey,
                                navClearance,
                              ),
                            );
                          },
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

  Widget _buildHeader(
    AsyncValue<List<dynamic>> courtsAsync,
    List<hk.ShiftStatus> courtShifts,
    String? selectedShiftKey,
  ) {
    return Padding(
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
                      'Housekeeping',
                      style: GoogleFonts.antonSc(
                        fontSize: 30,
                        color: _white,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'live task status · auto-refresh 30s',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _grey,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              _hdrBtn(Icons.refresh_rounded, _refresh),
              const SizedBox(width: 8),
              _hdrBtn(Icons.calendar_today_rounded, _pickDate),
            ],
          ),

          const SizedBox(height: 20),

          // Date strip
          Row(
            children: [
              _hdrBtn(
                Icons.chevron_left_rounded,
                () => setState(
                  () => _date = _date.subtract(const Duration(days: 1)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _dateHeader(_date),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _hdrBtn(Icons.chevron_right_rounded, () {
                final cap = DateTime.now().add(const Duration(days: 1));
                if (_date.isBefore(DateTime(cap.year, cap.month, cap.day))) {
                  setState(() => _date = _date.add(const Duration(days: 1)));
                }
              }),
            ],
          ),

          const SizedBox(height: 14),

          // Dynamic court tabs
          courtsAsync.when(
            loading: () => const SizedBox(height: 38),
            error: (_, __) => const SizedBox(height: 38),
            data: (courts) {
              if (courts.isEmpty) return const SizedBox(height: 38);
              return SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: courts.length,
                  itemBuilder: (context, index) {
                    final courtInfo = courts[index];
                    final sel = _court == courtInfo.id;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _court = courtInfo.id;
                          _shiftKey = null; // re-resolve for new court
                        });
                        _listCtrl
                          ..reset()
                          ..forward();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(
                          right: index < courts.length - 1 ? 8 : 0,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? _white : _white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            courtInfo.name,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? _black : _grey,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          // Dynamic shift tabs (horizontal scroll — any number of shifts)
          if (courtShifts.isEmpty)
            const SizedBox(height: 4)
          else
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: courtShifts.length,
                itemBuilder: (context, index) {
                  final s = courtShifts[index];
                  final sel = s.shiftKey == selectedShiftKey;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _shiftKey = s.shiftKey);
                      _listCtrl
                        ..reset()
                        ..forward();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(
                        right: index < courtShifts.length - 1 ? 8 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? _white : const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: sel ? Colors.transparent : _white.withOpacity(0.06),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hk.hkShiftIcon(s.startTime),
                            size: 13,
                            color: sel ? _black : _grey,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            s.shiftName,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? _black : _grey,
                            ),
                          ),
                          if (!s.isActiveNow) ...[
                            const SizedBox(width: 5),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: sel ? _danger : _grey.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _hdrBtn(IconData icon, VoidCallback onTap) => GestureDetector(
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _white,
            onPrimary: _black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _listCtrl
        ..reset()
        ..forward();
    }
  }

  Widget _buildContent(
    hk.FullStatusResponse data,
    String? selectedShiftKey,
    double navClearance,
  ) {
    if (_court == null) return const SizedBox.shrink();

    final court = data.courtById(_court!);
    final courtName = court?.courtName.isNotEmpty == true
        ? court!.courtName
        : (ref
                  .read(courtsNotifierProvider)
                  .value
                  ?.firstWhereOrNull((c) => c.id == _court)
                  ?.name ??
              'Court $_court');

    final shifts = court?.shifts ?? const <hk.ShiftStatus>[];

    if (shifts.isEmpty) {
      return _EmptyConfig(courtName: courtName);
    }

    final shiftData =
        shifts.firstWhereOrNull((s) => s.shiftKey == selectedShiftKey) ??
        shifts.first;

    final tasks = shiftData.tasks;
    final doneCount = tasks.where((t) => t.isDone).length;
    final total = tasks.length;

    final viewDate = DateTime(_date.year, _date.month, _date.day, 23, 59, 59);

    final weekly = data.weeklyFor(_court!);
    final monthly = data.monthlyFor(_court!);

    var idx = 0;
    final children = <Widget>[
      _StaggerItem(
        anim: _itemAnim(idx++),
        child: _SummaryCard(
          done: doneCount,
          total: total,
          courtName: courtName,
          shiftName: shiftData.shiftName,
        ),
      ),
      const SizedBox(height: 16),
      _StaggerItem(
        anim: _itemAnim(idx++),
        child: _SectionLabel(
          label: 'Daily Tasks',
          right: '$doneCount / $total done',
        ),
      ),
      const SizedBox(height: 10),
    ];

    if (tasks.isEmpty) {
      children.add(
        _StaggerItem(
          anim: _itemAnim(idx++),
          child: const _EmptyRow(text: 'No daily tasks in this shift.'),
        ),
      );
    } else {
      for (final t in tasks) {
        final i = idx++;
        children.add(
          _StaggerItem(
            anim: _itemAnim(i),
            child: _DailyTaskTile(
              key: ValueKey('hk_daily_${_court}_${shiftData.shiftKey}_${t.taskId}'),
              title: t.taskTitle,
              icon: hk.hkIconFor(t.icon),
              accent: hk.hkAccentFor(t.icon),
              isDone: t.isDone,
              doneAt: t.doneAt,
              doneByName: t.doneByName,
              photoUrl: t.photoUrl,
              onPhotoTap: t.photoUrl != null
                  ? () => _openPhoto(t.photoUrl!, t.taskTitle)
                  : null,
            ),
          ),
        );
      }
    }

    // Weekly recurring (multiple)
    if (weekly.isNotEmpty) {
      children
        ..add(const SizedBox(height: 10))
        ..add(
          _StaggerItem(
            anim: _itemAnim(idx++),
            child: const _SectionLabel(label: 'Weekly Tasks'),
          ),
        )
        ..add(const SizedBox(height: 10));
      for (final raw in weekly) {
        final eff = _effective(raw, viewDate);
        final i = idx++;
        children.add(
          _StaggerItem(
            anim: _itemAnim(i),
            child: _RecurringTile(
              icon: hk.hkIconFor(eff.icon),
              title: eff.title.isNotEmpty ? eff.title : 'Weekly Task',
              accentColor: _purple,
              lastDoneAt: eff.lastDoneAt,
              nextDueAt: eff.nextDueAt,
              isOverdue: eff.isOverdue,
              photoUrl: eff.photoUrl,
              doneByName: eff.doneByName,
              onPhotoTap: eff.photoUrl != null
                  ? () => _openPhoto(eff.photoUrl!, eff.title)
                  : null,
            ),
          ),
        );
      }
    }

    // Monthly recurring (multiple)
    if (monthly.isNotEmpty) {
      children
        ..add(const SizedBox(height: 10))
        ..add(
          _StaggerItem(
            anim: _itemAnim(idx++),
            child: const _SectionLabel(label: 'Monthly Tasks'),
          ),
        )
        ..add(const SizedBox(height: 10));
      for (final raw in monthly) {
        final eff = _effective(raw, viewDate);
        final i = idx++;
        children.add(
          _StaggerItem(
            anim: _itemAnim(i),
            child: _RecurringTile(
              icon: hk.hkIconFor(eff.icon),
              title: eff.title.isNotEmpty ? eff.title : 'Monthly Task',
              accentColor: _danger,
              lastDoneAt: eff.lastDoneAt,
              nextDueAt: eff.nextDueAt,
              isOverdue: eff.isOverdue,
              photoUrl: eff.photoUrl,
              doneByName: eff.doneByName,
              onPhotoTap: eff.photoUrl != null
                  ? () => _openPhoto(eff.photoUrl!, eff.title)
                  : null,
            ),
          ),
        );
      }
    }

    children
      ..add(const SizedBox(height: 20))
      ..add(
        _StaggerItem(
          anim: _itemAnim(idx++),
          child: Center(
            child: Text(
              'Pull to refresh · auto-refreshes every 30s',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _black.withOpacity(0.28),
              ),
            ),
          ),
        ),
      );

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, navClearance),
      children: children,
    );
  }

  // Re-base a recurring task's cooldown/overdue to the *viewed* date so that
  // browsing past dates shows the historically-correct state.
  hk.RecurringTaskStatus _effective(
    hk.RecurringTaskStatus raw,
    DateTime viewDate,
  ) {
    final last = raw.lastDoneAt;
    if (last == null || last.isAfter(viewDate)) {
      // Not yet done as of the viewed date.
      return hk.RecurringTaskStatus(
        courtId: raw.courtId,
        taskId: raw.taskId,
        title: raw.title,
        icon: raw.icon,
        intervalDays: raw.intervalDays,
        isOverdue: true,
      );
    }
    final nextDue = last.add(Duration(days: raw.intervalDays));
    final overdue = viewDate.isAfter(nextDue);
    return raw.copyWith(
      lastDoneAt: last,
      nextDueAt: nextDue,
      isOverdue: overdue,
    );
  }

  void _openPhoto(String url, String title) => showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.92),
    builder: (_) => _PhotoViewer(url: url, title: title),
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

class _SummaryCard extends StatelessWidget {
  final int done, total;
  final String courtName;
  final String shiftName;
  const _SummaryCard({
    required this.done,
    required this.total,
    required this.courtName,
    required this.shiftName,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : done / total;
    final allDone = total > 0 && done == total;
    final barColor = allDone ? _ok : (pct >= 0.5 ? _warn : _danger);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  allDone
                      ? Icons.verified_rounded
                      : Icons.pending_actions_rounded,
                  size: 18,
                  color: allDone ? _ok : _white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$courtName · $shiftName Shift',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _white.withOpacity(0.85),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          total == 0 ? '—' : '$done / $total',
                          style: GoogleFonts.antonSc(
                            fontSize: 17,
                            color: allDone ? _ok : _white,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          total == 0 ? 'no tasks yet' : 'tasks done',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _white.withOpacity(0.45),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '${(pct * 100).round()}%',
                style: GoogleFonts.antonSc(
                  fontSize: 36,
                  height: 1,
                  color: allDone ? _ok : _white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: _white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyTaskTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final bool isDone;
  final DateTime? doneAt;
  final String? doneByName;
  final String? photoUrl;
  final VoidCallback? onPhotoTap;

  const _DailyTaskTile({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.isDone,
    this.doneAt,
    this.doneByName,
    this.photoUrl,
    this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final done = isDone;
    final hasPhoto = photoUrl != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done ? _ok.withOpacity(0.35) : _border.withOpacity(0.15),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: done ? _ok.withOpacity(0.1) : accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? Icons.check_rounded : icon,
              size: 18,
              color: done ? _ok : accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _black,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (done ? _ok : _warn).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        done ? 'Done' : 'Pending',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: done ? _ok : _warn,
                        ),
                      ),
                    ),
                    if (done && doneAt != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        _fmtTime(doneAt!.toLocal()),
                        style: GoogleFonts.inter(fontSize: 11, color: _grey),
                      ),
                    ],
                  ],
                ),
                if (done &&
                    doneByName != null &&
                    doneByName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 12,
                        color: _ok.withOpacity(0.75),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          doneByName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _ok.withOpacity(0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (hasPhoto)
            GestureDetector(
              onTap: onPhotoTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _ok.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: AppNetworkImage(
                      url: photoUrl,
                      width: 48,
                      height: 48,
                      memCacheWidth: 144,
                      borderRadius: BorderRadius.circular(8.5),
                      background: _ok.withOpacity(0.06),
                      accent: _ok,
                    ),
                  ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _black,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: _white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.open_in_full_rounded,
                        size: 8,
                        color: _white,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (done)
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _lg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border.withOpacity(0.1)),
              ),
              child: const Icon(
                Icons.no_photography_outlined,
                size: 16,
                color: _grey,
              ),
            )
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _warn.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.hourglass_empty_rounded,
                size: 16,
                color: _warn.withOpacity(0.6),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accentColor;
  final DateTime? lastDoneAt, nextDueAt;
  final bool isOverdue;
  final String? photoUrl;
  final String? doneByName;
  final VoidCallback? onPhotoTap;

  const _RecurringTile({
    required this.icon,
    required this.title,
    required this.accentColor,
    this.lastDoneAt,
    this.nextDueAt,
    required this.isOverdue,
    this.photoUrl,
    this.doneByName,
    this.onPhotoTap,
  });

  bool get _isCooldownActive =>
      nextDueAt != null && DateTime.now().isBefore(nextDueAt!);
  int get _cooldownDays {
    if (nextDueAt == null) return 0;
    final diff = nextDueAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inDays + (diff.inHours.remainder(24) > 0 ? 1 : 0);
  }

  int get _overdueDays {
    if (nextDueAt == null) return 0;
    final diff = DateTime.now().difference(nextDueAt!);
    return diff.isNegative ? 0 : diff.inDays;
  }

  @override
  Widget build(BuildContext context) {
    final cooldown = _isCooldownActive;
    final overdue = isOverdue && !cooldown;
    final neverDone = lastDoneAt == null;
    final justDone = cooldown;

    final Color stColor = (overdue || neverDone)
        ? _danger
        : justDone
        ? _ok
        : _warn;
    final String stLabel = neverDone
        ? 'Never Done'
        : overdue
        ? (_overdueDays > 0
              ? 'Overdue by $_overdueDays ${_overdueDays == 1 ? 'day' : 'days'}'
              : 'Overdue')
        : justDone
        ? 'Done'
        : 'Pending';

    String? subInfo;
    if (justDone && nextDueAt != null) {
      subInfo = 'Next due ${_fmtDateShort(nextDueAt!.toLocal())}';
    } else if (overdue && lastDoneAt != null) {
      subInfo = 'Last done ${_fmtDateShort(lastDoneAt!.toLocal())}';
    } else if (!neverDone && lastDoneAt != null) {
      subInfo = 'Last done ${_fmtDateShort(lastDoneAt!.toLocal())}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: stColor.withOpacity(overdue || neverDone ? 0.40 : 0.22),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _black,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: stColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        stLabel,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: stColor,
                        ),
                      ),
                    ),
                    if (justDone)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _ok.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _ok.withOpacity(0.20)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.hourglass_top_rounded,
                              size: 9,
                              color: _ok,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${_cooldownDays}d remaining',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _ok,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (overdue && _overdueDays > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _danger.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _danger.withOpacity(0.22)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 9,
                              color: _danger,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${_overdueDays}d overdue',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (subInfo != null)
                      Text(
                        subInfo,
                        style: GoogleFonts.inter(fontSize: 11, color: _grey),
                      ),
                    if (justDone &&
                        doneByName != null &&
                        doneByName!.trim().isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 11,
                            color: _ok.withOpacity(0.75),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'By $doneByName',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _ok.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (photoUrl != null)
            GestureDetector(
              onTap: onPhotoTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: stColor.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: AppNetworkImage(
                      url: photoUrl,
                      width: 48,
                      height: 48,
                      memCacheWidth: 144,
                      borderRadius: BorderRadius.circular(8.5),
                      background: stColor.withOpacity(0.06),
                      accent: stColor,
                    ),
                  ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _black,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: _white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.open_in_full_rounded,
                        size: 8,
                        color: _white,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: stColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: stColor.withOpacity(0.20)),
              ),
              child: Text(
                'No photo',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: stColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final String url, title;
  const _PhotoViewer({required this.url, required this.title});

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.transparent,
    child: Stack(
      children: [
        Center(
          child: InteractiveViewer(
            child: AppNetworkImage(
              url: url,
              fit: BoxFit.contain,
              background: Colors.transparent,
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: _white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _white,
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
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final String? right;
  const _SectionLabel({required this.label, this.right});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: _black,
          letterSpacing: -0.3,
        ),
      ),
      if (right != null)
        Text(right!, style: GoogleFonts.antonSc(fontSize: 14, color: _grey)),
    ],
  );
}

class _EmptyRow extends StatelessWidget {
  final String text;
  const _EmptyRow({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(
      color: _lg,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: _grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 12.5, color: _grey),
          ),
        ),
      ],
    ),
  );
}

class _EmptyConfig extends StatelessWidget {
  final String courtName;
  const _EmptyConfig({required this.courtName});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
    children: [
      const Icon(Icons.checklist_rtl_rounded, size: 44, color: _grey),
      const SizedBox(height: 14),
      Text(
        'No checklist configured',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: _black,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '$courtName has no housekeeping checklist yet.\nSet one up in Settings → Manage Courts.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: _grey, height: 1.5),
      ),
    ],
  );
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const SkeletonList(
    dark: false,
    count: 6,
    tileHeight: 70,
    showTrailing: true,
  );
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, size: 40, color: _grey),
        const SizedBox(height: 12),
        Text(
          'Could not load status',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pull to refresh or tap Retry',
          style: GoogleFonts.inter(fontSize: 12, color: _grey),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onRetry,
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
      ],
    ),
  );
}

String _dateHeader(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  final fmt = _fmtDate(d);
  if (diff == 0) return 'Today · $fmt';
  if (diff == 1) return 'Yesterday · $fmt';
  return fmt;
}

const _kMonthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDate(DateTime d) =>
    '${d.day} ${_kMonthsShort[d.month - 1]} ${d.year}';

String _fmtDateShort(DateTime d) => '${d.day} ${_kMonthsShort[d.month - 1]}';

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
