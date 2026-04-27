// lib/features/housekeeping/presentation/manager_housekeeping_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../staff/data/housekeeping_repository.dart';
import '../../staff/domain/housekeeping_models.dart' as hk;

// ─── Palette (matches app design language) ────────────────────────────────────
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _lg = Color(0xFFF2F2F2);
const _border = Color(0xFF1A1A1A);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFE5A000);
const _danger = Color(0xFFFF4444);
const _blue = Color(0xFF60A5FA);
const _purple = Color(0xFFA78BFA);
const _bg = Color(0xFF080808);

// ─── Task definitions (source of truth for task list — backend may not return
//     pending tasks, so we always show these and overlay API status on top) ────

enum _Cat { cleaning, pest, laundry, audit }

class _TaskDef {
  final String id, title;
  final IconData icon;
  final _Cat cat;
  const _TaskDef(this.id, this.title, this.icon, this.cat);
}

const _kDailyTasks = [
  _TaskDef(
    'floorclean',
    'Floor Cleaning',
    Icons.cleaning_services_rounded,
    _Cat.cleaning,
  ),
  _TaskDef(
    'tablechairclean',
    'Table & Chair Clean',
    Icons.chair_rounded,
    _Cat.cleaning,
  ),
  _TaskDef(
    'binclean',
    'Bins Cleaning (outside)',
    Icons.delete_forever_rounded,
    _Cat.cleaning,
  ),
  _TaskDef(
    'trayclean',
    'Tray Cleaning',
    Icons.restaurant_rounded,
    _Cat.cleaning,
  ),
  _TaskDef(
    'binempty',
    'Garbage Bin Empty',
    Icons.delete_outline_rounded,
    _Cat.cleaning,
  ),
  _TaskDef('pestspray', 'Pest Spray', Icons.pest_control_rounded, _Cat.pest),
];

Color _catColor(_Cat c) => switch (c) {
  _Cat.cleaning => _blue,
  _Cat.pest => _warn,
  _Cat.laundry => _purple,
  _Cat.audit => _danger,
};

// ─── Provider ─────────────────────────────────────────────────────────────────
final managerHkProvider = FutureProvider.autoDispose
    .family<hk.FullStatusResponse?, String>((ref, date) async {
      return ref.read(housekeepingRepoProvider).getFullStatus(date: date);
    });

// ─── Screen ───────────────────────────────────────────────────────────────────
class ManagerHousekeepingScreen extends ConsumerStatefulWidget {
  const ManagerHousekeepingScreen({super.key});

  @override
  ConsumerState<ManagerHousekeepingScreen> createState() =>
      _ManagerHousekeepingScreenState();
}

class _ManagerHousekeepingScreenState
    extends ConsumerState<ManagerHousekeepingScreen>
    with SingleTickerProviderStateMixin {
  DateTime _date = DateTime.now();
  hk.Shift _shift = _autoShift();
  int _court = 1;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();

    // Auto-refresh every 30 s — manager sees staff updates without manual pull
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
    super.dispose();
  }

  String get _dateStr => _date.toIso8601String().substring(0, 10);
  void _refresh() => ref.invalidate(managerHkProvider(_dateStr));

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(managerHkProvider(_dateStr));
    final navClearance = MediaQuery.of(context).padding.bottom + 92.0;

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
                    child: statusAsync.when(
                      loading: () => const _Loader(),
                      error: (e, _) => _ErrorView(onRetry: _refresh),
                      data: (data) => data == null
                          ? _ErrorView(onRetry: _refresh)
                          : _buildContent(data, navClearance),
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

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row
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

        // Court tabs
        Row(
          children: List.generate(3, (i) {
            final sel = _court == i + 1;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _court = i + 1);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? _white : _white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Court ${i + 1}',
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
          }),
        ),

        const SizedBox(height: 10),

        // Shift tabs
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: hk.Shift.values.map((s) {
              final sel = _shift == s;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _shift = s);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: sel ? _white : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _shiftIcon(s),
                          size: 13,
                          color: sel ? _black : _grey,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _shiftLabel(s),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sel ? _black : _grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 18),
      ],
    ),
  );

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
    if (picked != null) setState(() => _date = picked);
  }

  // ── Content ────────────────────────────────────────────────────────────────
  Widget _buildContent(hk.FullStatusResponse data, double navClearance) {
    final courtData = data.courts.firstWhere(
      (c) => c.courtId == _court,
      orElse: () =>
          hk.CourtDayStatus(courtId: _court, date: _dateStr, shifts: []),
    );
    final shiftData = courtData.shifts.firstWhere(
      (s) => s.shift == _shift,
      orElse: () => hk.ShiftStatus(
        shift: _shift,
        total: 0,
        done: 0,
        submitted: false,
        tasks: [],
      ),
    );

    // ── FIX: always show all expected tasks, overlay API status ───────────────
    // Backend only stores tasks that were submitted, so pending ones won't appear
    // in shiftData.tasks. We merge with the local task definitions to fill gaps.
    final apiMap = {for (final t in shiftData.tasks) t.taskId: t};
    final mergedTasks = _kDailyTasks.map((def) {
      final api = apiMap[def.id];
      return _MergedTask(
        def: def,
        isDone: api?.isDone ?? false,
        photoUrl: api?.photoUrl,
        doneAt: api?.doneAt,
      );
    }).toList();

    final doneCount = mergedTasks.where((t) => t.isDone).length;
    final total = mergedTasks.length;

    final weekly = data.weeklyTasks.firstWhere(
      (w) => w.courtId == _court,
      orElse: () => hk.WeeklyTaskStatus(courtId: _court, isOverdue: true),
    );
    final monthly = data.monthlyTasks.firstWhere(
      (m) => m.courtId == _court,
      orElse: () => hk.MonthlyTaskStatus(courtId: _court, isOverdue: true),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, navClearance),
      children: [
        // Summary card
        _SummaryCard(
          done: doneCount,
          total: total,
          court: _court,
          shift: _shift,
        ),
        const SizedBox(height: 16),

        // Daily tasks section label
        _SectionLabel(label: 'Daily Tasks', right: '$doneCount / $total done'),
        const SizedBox(height: 10),

        // Task tiles — all 6, always visible (done + pending)
        ...mergedTasks.map(
          (t) => _DailyTaskTile(
            key: ValueKey(t.def.id),
            task: t,
            onPhotoTap: t.photoUrl != null
                ? () => _openPhoto(t.photoUrl!, t.def.title)
                : null,
          ),
        ),

        const SizedBox(height: 10),

        // Weekly
        _SectionLabel(label: 'Weekly Task'),
        const SizedBox(height: 10),
        _RecurringTile(
          icon: Icons.flag_rounded,
          title: 'Flags Washing',
          accentColor: _purple,
          lastDoneAt: weekly.lastDoneAt,
          nextDueAt: weekly.nextDueAt,
          isOverdue: weekly.isOverdue,
          photoUrl: weekly.photoUrl,
          onPhotoTap: weekly.photoUrl != null
              ? () => _openPhoto(weekly.photoUrl!, 'Flags Washing')
              : null,
        ),

        const SizedBox(height: 10),

        // Monthly
        _SectionLabel(label: 'Monthly Task'),
        const SizedBox(height: 10),
        _RecurringTile(
          icon: Icons.fire_extinguisher_rounded,
          title: 'Fire Safety Audit',
          accentColor: _danger,
          lastDoneAt: monthly.lastDoneAt,
          nextDueAt: monthly.nextDueAt,
          isOverdue: monthly.isOverdue,
          photoUrl: monthly.photoUrl,
          onPhotoTap: monthly.photoUrl != null
              ? () => _openPhoto(monthly.photoUrl!, 'Fire Safety Audit')
              : null,
        ),

        const SizedBox(height: 20),

        Center(
          child: Text(
            'Pull to refresh · auto-refreshes every 30s',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: _black.withOpacity(0.28),
            ),
          ),
        ),
      ],
    );
  }

  void _openPhoto(String url, String title) => showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.92),
    builder: (_) => _PhotoViewer(url: url, title: title),
  );
}

// ─── Merged task model ────────────────────────────────────────────────────────
class _MergedTask {
  final _TaskDef def;
  final bool isDone;
  final String? photoUrl;
  final DateTime? doneAt;
  const _MergedTask({
    required this.def,
    required this.isDone,
    this.photoUrl,
    this.doneAt,
  });
}

// ─── Summary Card (matches OutlineCard / FilledCard style from home_screen) ───
class _SummaryCard extends StatelessWidget {
  final int done, total, court;
  final hk.Shift shift;
  const _SummaryCard({
    required this.done,
    required this.total,
    required this.court,
    required this.shift,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : done / total;
    final allDone = total > 0 && done == total;
    final barColor = allDone ? _ok : (pct >= 0.5 ? _warn : _danger);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _black, // FilledCard style
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon
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
                      'Court $court · ${_shiftLabel(shift)} Shift',
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
              // Percentage
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
          // Progress bar
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

// ─── Daily Task Tile (OutlineCard style — white + dark 1.5px border) ──────────
class _DailyTaskTile extends StatelessWidget {
  final _MergedTask task;
  final VoidCallback? onPhotoTap;
  const _DailyTaskTile({super.key, required this.task, this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    final done = task.isDone;
    final catColor = _catColor(task.def.cat);
    final hasPhoto = task.photoUrl != null;

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
          // Category icon circle
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: done ? _ok.withOpacity(0.1) : catColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? Icons.check_rounded : task.def.icon,
              size: 18,
              color: done ? _ok : catColor,
            ),
          ),
          const SizedBox(width: 12),

          // Title + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.def.title,
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
                    if (done && task.doneAt != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        _fmtTime(task.doneAt!.toLocal()),
                        style: GoogleFonts.inter(fontSize: 11, color: _grey),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Photo thumbnail (only if done + has photo)
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.5),
                      child: Image.network(
                        task.photoUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, prog) => prog == null
                            ? child
                            : Container(
                                color: _ok.withOpacity(0.06),
                                child: const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: _ok,
                                    ),
                                  ),
                                ),
                              ),
                        errorBuilder: (_, __, ___) => Container(
                          color: _lg,
                          child: const Icon(
                            Icons.broken_image_rounded,
                            size: 18,
                            color: _grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Expand hint
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
          // Camera icon hint when done but no photo
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
          // Pending badge
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

// ─── Recurring Task Tile (weekly / monthly) ───────────────────────────────────
class _RecurringTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accentColor;
  final DateTime? lastDoneAt, nextDueAt;
  final bool isOverdue;
  final String? photoUrl;
  final VoidCallback? onPhotoTap;

  const _RecurringTile({
    required this.icon,
    required this.title,
    required this.accentColor,
    this.lastDoneAt,
    this.nextDueAt,
    required this.isOverdue,
    this.photoUrl,
    this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = lastDoneAt != null && !isOverdue;
    final stColor = isOverdue ? _danger : (isDone ? _ok : _warn);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: stColor.withOpacity(isOverdue ? 0.35 : 0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
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
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: stColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isOverdue ? 'Overdue' : (isDone ? 'Done' : 'Pending'),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: stColor,
                        ),
                      ),
                    ),
                    if (lastDoneAt != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isDone
                              ? 'Done ${_fmtDateShort(lastDoneAt!.toLocal())}'
                              : 'Last: ${_fmtDateShort(lastDoneAt!.toLocal())}',
                          style: GoogleFonts.inter(fontSize: 11, color: _grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.5),
                      child: Image.network(
                        photoUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, prog) => prog == null
                            ? child
                            : Container(
                                color: stColor.withOpacity(0.06),
                                child: const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                        errorBuilder: (_, __, ___) => Container(
                          color: _lg,
                          child: const Icon(
                            Icons.broken_image_rounded,
                            size: 18,
                            color: _grey,
                          ),
                        ),
                      ),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: stColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isOverdue ? '⚠ Overdue' : 'No photo',
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

// ─── Photo Viewer ──────────────────────────────────────────────────────────────
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
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, prog) => prog == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(
                        color: _white,
                        strokeWidth: 2,
                      ),
                    ),
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_rounded, color: _grey, size: 48),
              ),
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

// ─── Utility Widgets ──────────────────────────────────────────────────────────
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

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(color: _black, strokeWidth: 2),
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

// ─── Helpers ──────────────────────────────────────────────────────────────────
hk.Shift _autoShift() {
  final h = DateTime.now().hour;
  if (h >= 6 && h < 12) return hk.Shift.morning;
  if (h >= 12 && h < 17) return hk.Shift.day;
  return hk.Shift.night;
}

String _shiftLabel(hk.Shift s) => const {
  hk.Shift.morning: 'Morning',
  hk.Shift.day: 'Day',
  hk.Shift.night: 'Night',
}[s]!;

IconData _shiftIcon(hk.Shift s) => switch (s) {
  hk.Shift.morning => Icons.wb_sunny_rounded,
  hk.Shift.day => Icons.light_mode_rounded,
  hk.Shift.night => Icons.nights_stay_rounded,
};

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

String _fmtDate(DateTime d) {
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
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _fmtDateShort(DateTime d) {
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
  return '${d.day} ${m[d.month - 1]}';
}

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
