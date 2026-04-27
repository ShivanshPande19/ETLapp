// lib/features/housekeeping/presentation/manager_housekeeping_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../staff/data/housekeeping_repository.dart';
import '../../staff/domain/housekeeping_models.dart' as hk;

// ─── Colours ──────────────────────────────────────────────────
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

// ─── Local display models ─────────────────────────────────────
enum TaskCat { cleaning, pest, laundry, audit }

enum TaskFreq { daily, weekly, monthly }

enum TaskSt { done, pending, overdue }

class HkTask {
  final String id;
  final String title;
  final TaskCat category;
  final IconData icon;
  final TaskFreq frequency;
  const HkTask({
    required this.id,
    required this.title,
    required this.category,
    required this.icon,
    this.frequency = TaskFreq.daily,
  });
}

class CourtTaskRecord {
  final HkTask task;
  final TaskSt status;
  final String? doneBy;
  final DateTime? doneAt;
  final bool hasPhoto;
  final String? photoUrl; // Cloudinary URL
  const CourtTaskRecord({
    required this.task,
    required this.status,
    this.doneBy,
    this.doneAt,
    this.hasPhoto = false,
    this.photoUrl,
  });
}

const _kDailyTasks = [
  HkTask(
    id: 'floorclean',
    title: 'Floor Cleaning',
    category: TaskCat.cleaning,
    icon: Icons.cleaning_services_rounded,
  ),
  HkTask(
    id: 'tablechairclean',
    title: 'Table & Chair Clean',
    category: TaskCat.cleaning,
    icon: Icons.chair_rounded,
  ),
  HkTask(
    id: 'binclean',
    title: 'Bins Cleaning (outside)',
    category: TaskCat.cleaning,
    icon: Icons.delete_forever_rounded,
  ),
  HkTask(
    id: 'trayclean',
    title: 'Tray Cleaning',
    category: TaskCat.cleaning,
    icon: Icons.restaurant_rounded,
  ),
  HkTask(
    id: 'binempty',
    title: 'Garbage Bin Empty',
    category: TaskCat.cleaning,
    icon: Icons.delete_outline_rounded,
  ),
  HkTask(
    id: 'pestspray',
    title: 'Pest Spray',
    category: TaskCat.pest,
    icon: Icons.pest_control_rounded,
  ),
];
const _kFlags = HkTask(
  id: 'flagswash',
  title: 'Flags Washing',
  category: TaskCat.laundry,
  icon: Icons.flag_rounded,
  frequency: TaskFreq.weekly,
);
const _kFire = HkTask(
  id: 'fireaudit',
  title: 'Fire Safety Audit',
  category: TaskCat.audit,
  icon: Icons.fire_extinguisher_rounded,
  frequency: TaskFreq.monthly,
);

// ─── Helpers ──────────────────────────────────────────────────
Color _catColor(TaskCat c) => switch (c) {
  TaskCat.cleaning => _blue,
  TaskCat.pest => _warn,
  TaskCat.laundry => _purple,
  TaskCat.audit => _danger,
};

Color _stColor(TaskSt s) => switch (s) {
  TaskSt.done => _ok,
  TaskSt.pending => _warn,
  TaskSt.overdue => _danger,
};

String _stLabel(TaskSt s) => switch (s) {
  TaskSt.done => 'Done',
  TaskSt.pending => 'Pending',
  TaskSt.overdue => 'Overdue',
};

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

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String _dateLabel(DateTime d) {
  final diff = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return _fmtDate(d);
}

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

/// Maps API TaskStatusItem → CourtTaskRecord using local HkTask definitions
CourtTaskRecord _fromApi(hk.TaskStatusItem item) {
  final allDefs = [..._kDailyTasks, _kFlags, _kFire];
  final def =
      allDefs.cast<HkTask?>().firstWhere(
        (t) => t!.id == item.taskId,
        orElse: () => null,
      ) ??
      HkTask(
        id: item.taskId,
        title: item.taskTitle,
        category: TaskCat.cleaning,
        icon: Icons.task_rounded,
      );
  return CourtTaskRecord(
    task: def,
    status: item.isDone ? TaskSt.done : TaskSt.pending,
    doneAt: item.doneAt,
    hasPhoto: item.photoUrl != null,
    photoUrl: item.photoUrl,
  );
}

CourtTaskRecord _fromWeekly(hk.WeeklyTaskStatus w) => CourtTaskRecord(
  task: _kFlags,
  status: w.isOverdue
      ? TaskSt.overdue
      : (w.lastDoneAt != null ? TaskSt.done : TaskSt.pending),
  doneAt: w.lastDoneAt,
  hasPhoto: w.photoUrl != null,
  photoUrl: w.photoUrl,
);

CourtTaskRecord _fromMonthly(hk.MonthlyTaskStatus m) => CourtTaskRecord(
  task: _kFire,
  status: m.isOverdue
      ? TaskSt.overdue
      : (m.lastDoneAt != null ? TaskSt.done : TaskSt.pending),
  doneAt: m.lastDoneAt,
  hasPhoto: m.photoUrl != null,
  photoUrl: m.photoUrl,
);

// ─── Provider ─────────────────────────────────────────────────
final _managerHkProvider = FutureProvider.autoDispose
    .family<hk.FullStatusResponse?, String>((ref, date) async {
      return ref.read(housekeepingRepoProvider).getFullStatus(date: date);
    });

// ─── Screen ───────────────────────────────────────────────────
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
  int _court = 0; // 0 = all courts
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  final _courtNames = const ['All Courts', 'Court 1', 'Court 2', 'Court 3'];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  String get _dateStr => _date.toIso8601String().substring(0, 10);

  Future<void> _pickDate() async {
    HapticFeedback.lightImpact();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _black,
            onPrimary: _white,
            surface: _white,
            onSurface: _black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
      });
      _fadeCtrl.forward(from: 0);
    }
  }

  void _refresh() => ref.invalidate(_managerHkProvider(_dateStr));

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(_managerHkProvider(_dateStr));

    return Scaffold(
      backgroundColor: _black,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: statusAsync.when(
            loading: () => _buildShell(
              totalDone: 0,
              totalTasks: 0,
              body: const _LoadingBody(),
            ),
            error: (e, _) => _buildShell(
              totalDone: 0,
              totalTasks: 0,
              body: _ErrorBody(error: e.toString(), onRetry: _refresh),
            ),
            data: (data) => _buildShell(
              totalDone: _totalDone(data),
              totalTasks: _totalTasks(data),
              body: _DataBody(
                data: data,
                courtNames: _courtNames,
                shift: _shift,
                court: _court,
                onShiftTap: (s) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _shift = s;
                  });
                  _fadeCtrl.forward(from: 0);
                },
                onCourtTap: (i) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _court = i;
                  });
                  _fadeCtrl.forward(from: 0);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShell({
    required int totalDone,
    required int totalTasks,
    required Widget body,
  }) {
    return Column(
      children: [
        // ── Black header ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Housekeeping',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: Colors.white54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _refresh,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _white.withOpacity(0.1)),
                          ),
                          child: Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: _white.withOpacity(0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _white.withOpacity(0.12)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 12,
                                color: _white.withOpacity(0.6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _dateLabel(_date),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 15,
                                color: Colors.white54,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: totalDone),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, val, __) => Text(
                  '$val/$totalTasks',
                  style: GoogleFonts.antonSc(
                    fontSize: 56,
                    color: _white,
                    height: 1,
                    letterSpacing: -1,
                  ),
                ),
              ),
              Text(
                'tasks completed',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 16),
              // Shift tabs
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: hk.Shift.values.map((s) {
                    final isSel = s == _shift;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _shift = s);
                          _fadeCtrl.forward(from: 0);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isSel ? _white : _white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isSel ? _white : _white.withOpacity(0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _shiftIcon(s),
                                size: 12,
                                color: isSel ? _black : Colors.white54,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _shiftLabel(s),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isSel ? _black : Colors.white54,
                                ),
                              ),
                              if (s == _autoShift() &&
                                  _date.day == DateTime.now().day) ...[
                                const SizedBox(width: 5),
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? _black.withOpacity(0.4)
                                        : _ok,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        // ── White body ────────────────────────────────────
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: body,
          ),
        ),
      ],
    );
  }

  int _totalDone(hk.FullStatusResponse? d) {
    if (d == null) return 0;
    return d.courts
        .expand((c) => c.shifts)
        .fold<int>(0, (acc, s) => acc + s.done);
  }

  int _totalTasks(hk.FullStatusResponse? d) {
    if (d == null) return 0;
    return d.courts
        .expand((c) => c.shifts)
        .fold<int>(0, (acc, s) => acc + s.total);
  }
}

// ─── Data Body ────────────────────────────────────────────────
class _DataBody extends StatelessWidget {
  final hk.FullStatusResponse? data;
  final List<String> courtNames;
  final hk.Shift shift;
  final int court;
  final ValueChanged<hk.Shift> onShiftTap;
  final ValueChanged<int> onCourtTap;

  const _DataBody({
    required this.data,
    required this.courtNames,
    required this.shift,
    required this.court,
    required this.onShiftTap,
    required this.onCourtTap,
  });

  List<CourtTaskRecord> _recordsForCourt(int courtId) {
    if (data == null) return [];
    final courtStatus = data!.courts.cast<hk.CourtDayStatus?>().firstWhere(
      (c) => c!.courtId == courtId,
      orElse: () => null,
    );
    if (courtStatus == null) return [];
    final shiftStatus = courtStatus.shifts.cast<hk.ShiftStatus?>().firstWhere(
      (s) => s!.shift == shift,
      orElse: () => null,
    );
    return shiftStatus?.tasks.map(_fromApi).toList() ?? [];
  }

  CourtTaskRecord? _weeklyForCourt(int courtId) {
    if (data == null) return null;
    final w = data!.weeklyTasks.cast<hk.WeeklyTaskStatus?>().firstWhere(
      (w) => w!.courtId == courtId,
      orElse: () => null,
    );
    return w == null ? null : _fromWeekly(w);
  }

  CourtTaskRecord? _monthlyForCourt(int courtId) {
    if (data == null) return null;
    final m = data!.monthlyTasks.cast<hk.MonthlyTaskStatus?>().firstWhere(
      (m) => m!.courtId == courtId,
      orElse: () => null,
    );
    return m == null ? null : _fromMonthly(m);
  }

  @override
  Widget build(BuildContext context) {
    final perCourt = [1, 2, 3].map(_recordsForCourt).toList();

    return Column(
      children: [
        // Court tabs
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: _CourtTabBar(
            courtNames: courtNames,
            selected: court,
            recordsPerCourt: perCourt,
            onSelect: onCourtTap,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: court == 0
              ? _AllCourtsView(
                  courtNames: courtNames.skip(1).toList(),
                  recordsPerCourt: perCourt,
                  onCourtTap: (i) => onCourtTap(i + 1),
                )
              : _CourtDetailView(
                  courtName: courtNames[court],
                  courtId: court,
                  records: perCourt[court - 1],
                  weekly: _weeklyForCourt(court),
                  monthly: _monthlyForCourt(court),
                ),
        ),
      ],
    );
  }
}

// ─── Court Tab Bar ────────────────────────────────────────────
class _CourtTabBar extends StatelessWidget {
  final List<String> courtNames;
  final int selected;
  final List<List<CourtTaskRecord>> recordsPerCourt;
  final ValueChanged<int> onSelect;

  const _CourtTabBar({
    required this.courtNames,
    required this.selected,
    required this.recordsPerCourt,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _lg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(courtNames.length, (i) {
          final isSel = i == selected;
          int? done, total;
          if (i > 0) {
            final r = recordsPerCourt[i - 1];
            done = r.where((x) => x.status == TaskSt.done).length;
            total = r.length;
          }
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSel ? _white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSel
                      ? [
                          BoxShadow(
                            color: _black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      courtNames[i],
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSel ? _black : _grey,
                      ),
                    ),
                    if (done != null && total != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        '$done/$total',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isSel ? _grey : const Color(0xFFBBBBBB),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── All Courts View ─────────────────────────────────────────
class _AllCourtsView extends StatelessWidget {
  final List<String> courtNames;
  final List<List<CourtTaskRecord>> recordsPerCourt;
  final ValueChanged<int> onCourtTap;

  const _AllCourtsView({
    required this.courtNames,
    required this.recordsPerCourt,
    required this.onCourtTap,
  });

  @override
  Widget build(BuildContext context) {
    final all = recordsPerCourt.expand((r) => r).toList();
    final done = all.where((r) => r.status == TaskSt.done).length;
    final pending = all.where((r) => r.status == TaskSt.pending).length;
    final overdue = all.where((r) => r.status == TaskSt.overdue).length;
    final total = all.length;
    final progress = total > 0 ? done / total : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        SizedBox(
          height: 96,
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
                        'Overall',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: GoogleFonts.antonSc(
                          fontSize: 30,
                          color: _black,
                          height: 1,
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: _lg,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0 ? _ok : _black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 45,
                child: Column(
                  children: [
                    Expanded(
                      child: _FilledCard(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Done',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white60,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '$done',
                              style: GoogleFonts.antonSc(
                                fontSize: 20,
                                color: _white,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: _StatusCard(
                        label: 'Pending',
                        count: pending,
                        color: _warn,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (overdue > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _danger.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _danger.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: _danger),
                const SizedBox(width: 8),
                Text(
                  '$overdue overdue task${overdue > 1 ? 's' : ''} across all courts',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        ...courtNames.asMap().entries.map((e) {
          final recs = recordsPerCourt[e.key];
          final d = recs.where((r) => r.status == TaskSt.done).length;
          final p = recs.where((r) => r.status == TaskSt.pending).length;
          final ov = recs.where((r) => r.status == TaskSt.overdue).length;
          final ct = recs.length;
          final prog = ct > 0 ? d / ct : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => onCourtTap(e.key),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _border.withOpacity(0.1),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: prog >= 1.0
                                ? _ok
                                : ov > 0
                                ? _danger
                                : _warn,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          courtNames[e.key],
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _black,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$d/$ct',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Color(0xFFCCCCCC),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: prog,
                        minHeight: 4,
                        backgroundColor: _lg,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          prog >= 1.0
                              ? _ok
                              : ov > 0
                              ? _danger
                              : _black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MiniChip(label: '$d Done', color: _ok),
                        const SizedBox(width: 6),
                        _MiniChip(label: '$p Pending', color: _warn),
                        const SizedBox(width: 6),
                        _MiniChip(label: '$ov Overdue', color: _danger),
                      ],
                    ),
                    if (recs.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: recs
                            .map(
                              (r) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _stColor(r.status).withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _stColor(r.status).withOpacity(0.18),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      r.task.icon,
                                      size: 11,
                                      color: _stColor(r.status),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      r.task.title,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: _stColor(r.status),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ─── Court Detail View ────────────────────────────────────────
class _CourtDetailView extends StatelessWidget {
  final String courtName;
  final int courtId;
  final List<CourtTaskRecord> records;
  final CourtTaskRecord? weekly;
  final CourtTaskRecord? monthly;

  const _CourtDetailView({
    required this.courtName,
    required this.courtId,
    required this.records,
    required this.weekly,
    required this.monthly,
  });

  @override
  Widget build(BuildContext context) {
    final done = records.where((r) => r.status == TaskSt.done).length;
    final total = records.length;
    final prog = total > 0 ? done / total : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        // Progress
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: prog,
                    minHeight: 5,
                    backgroundColor: _lg,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      prog >= 1.0 ? _ok : _black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                '$done/$total ${done == total ? '✓' : ''}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _black,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (records.isEmpty) ...[
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Icon(Icons.cleaning_services_rounded, size: 40, color: _lg),
                const SizedBox(height: 12),
                Text(
                  'No tasks submitted for this shift yet.',
                  style: GoogleFonts.inter(fontSize: 13, color: _grey),
                ),
              ],
            ),
          ),
        ] else
          ...records.asMap().entries.map(
            (e) => _AnimatedTaskRow(record: e.value, index: e.key),
          ),
        // Weekly
        const SizedBox(height: 8),
        _SectionDiv(label: 'Weekly Task'),
        const SizedBox(height: 8),
        weekly != null
            ? _PeriodicCard(
                record: weekly!,
                nextDue: weekly!.doneAt?.add(const Duration(days: 7)),
              )
            : _EmptyPeriodic(label: 'Flags Washing not submitted yet'),
        // Monthly
        const SizedBox(height: 8),
        _SectionDiv(label: 'Monthly Task'),
        const SizedBox(height: 8),
        monthly != null
            ? _PeriodicCard(
                record: monthly!,
                nextDue: monthly!.doneAt?.add(const Duration(days: 30)),
              )
            : _EmptyPeriodic(label: 'Fire Safety Audit not submitted yet'),
      ],
    );
  }
}

// ─── Animated Task Row ────────────────────────────────────────
class _AnimatedTaskRow extends StatefulWidget {
  final CourtTaskRecord record;
  final int index;
  const _AnimatedTaskRow({required this.record, required this.index});

  @override
  State<_AnimatedTaskRow> createState() => _AnimatedTaskRowState();
}

class _AnimatedTaskRowState extends State<_AnimatedTaskRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(
      position: _slide,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _TaskRow(record: widget.record),
      ),
    ),
  );
}

// ─── Task Row ─────────────────────────────────────────────────
class _TaskRow extends StatelessWidget {
  final CourtTaskRecord record;
  const _TaskRow({required this.record});

  void _showPhoto(BuildContext context) {
    if (record.photoUrl == null) return;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _lg,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    record.task.icon,
                    size: 18,
                    color: _catColor(record.task.category),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    record.task.title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _black,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 220,
              decoration: BoxDecoration(
                color: _lg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  record.photoUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(
                            color: _black,
                            strokeWidth: 2,
                          ),
                        ),
                  errorBuilder: (_, __, ___) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_rounded,
                          size: 36,
                          color: _grey,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Could not load photo',
                          style: GoogleFonts.inter(fontSize: 12, color: _grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (record.doneAt != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 13, color: _grey),
                    const SizedBox(width: 6),
                    Text(
                      '${_fmtDate(record.doneAt!)} at ${_fmtTime(record.doneAt!)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sc = _stColor(record.status);
    final cc = _catColor(record.task.category);
    final isDone = record.status == TaskSt.done;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone ? _ok.withOpacity(0.25) : _border.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cc.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Icon(record.task.icon, size: 18, color: cc)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.task.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDone ? _grey : _black,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    decorationColor: _grey,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (record.doneAt != null) ...[
                      Text(
                        _fmtTime(record.doneAt!),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFFBBBBBB),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: Color(0xFFCCCCCC),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _stLabel(record.status),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: sc,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MiniChip(label: _stLabel(record.status), color: sc),
              if (record.hasPhoto) ...[
                const SizedBox(height: 5),
                GestureDetector(
                  onTap: () => _showPhoto(context),
                  child: _MiniChip(
                    label: 'Photo',
                    color: _blue,
                    icon: Icons.photo_camera_rounded,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Periodic Card ────────────────────────────────────────────
class _PeriodicCard extends StatelessWidget {
  final CourtTaskRecord record;
  final DateTime? nextDue;
  const _PeriodicCard({required this.record, this.nextDue});

  @override
  Widget build(BuildContext context) {
    final isDone = record.status == TaskSt.done;
    final sc = _stColor(record.status);
    final cc = _catColor(record.task.category);
    final isOverdue = nextDue != null && nextDue!.isBefore(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue
              ? _danger.withOpacity(0.3)
              : isDone
              ? _ok.withOpacity(0.25)
              : _border.withOpacity(0.12),
        ),
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
                  color: cc.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(record.task.icon, size: 18, color: cc),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.task.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (record.doneAt != null)
                      Text(
                        'Done on ${_fmtDate(record.doneAt!)}',
                        style: GoogleFonts.inter(fontSize: 11, color: _grey),
                      )
                    else
                      Text(
                        'Not completed yet',
                        style: GoogleFonts.inter(fontSize: 11, color: _danger),
                      ),
                  ],
                ),
              ),
              _MiniChip(
                label: isOverdue ? 'Overdue' : _stLabel(record.status),
                color: isOverdue ? _danger : sc,
              ),
            ],
          ),
          if (record.hasPhoto) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _TaskRow(record: record)._showPhoto(context),
              child: Row(
                children: [
                  Icon(Icons.photo_camera_rounded, size: 14, color: _blue),
                  const SizedBox(width: 6),
                  Text(
                    'View photo proof',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (nextDue != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isOverdue ? _danger.withOpacity(0.05) : _lg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOverdue
                        ? Icons.warning_amber_rounded
                        : Icons.event_rounded,
                    size: 13,
                    color: isOverdue ? _danger : _grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOverdue
                        ? 'Was due on ${_fmtDate(nextDue!)}'
                        : 'Next due ${_fmtDate(nextDue!)}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isOverdue ? _danger : _grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyPeriodic extends StatelessWidget {
  final String label;
  const _EmptyPeriodic({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border.withOpacity(0.1)),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _lg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.hourglass_empty_rounded,
            size: 18,
            color: _grey,
          ),
        ),
        const SizedBox(width: 12),
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
      ],
    ),
  );
}

// ─── Section Divider ─────────────────────────────────────────
class _SectionDiv extends StatelessWidget {
  final String label;
  const _SectionDiv({required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Container(height: 1, color: _border.withOpacity(0.08))),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _lg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _grey,
            letterSpacing: 0.3,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: _border.withOpacity(0.08))),
    ],
  );
}

// ─── Loading / Error / Shared widgets ────────────────────────
class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(color: _black, strokeWidth: 2),
  );
}

class _ErrorBody extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 40, color: _grey),
          const SizedBox(height: 12),
          Text(
            'Could not load housekeeping data.',
            style: GoogleFonts.inter(fontSize: 14, color: _grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: _white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OutlineCard extends StatelessWidget {
  final Widget child;
  final double? height;
  const _OutlineCard({required this.child, this.height});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border.withOpacity(0.1), width: 1.2),
    ),
    child: child,
  );
}

class _FilledCard extends StatelessWidget {
  final Widget child;
  const _FilledCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: _black,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class _StatusCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatusCard({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '$count',
          style: GoogleFonts.antonSc(fontSize: 20, color: color, height: 1),
        ),
      ],
    ),
  );
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _MiniChip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.2), width: 0.8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}
