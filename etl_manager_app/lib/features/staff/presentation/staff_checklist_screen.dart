// lib/features/staff/presentation/staff_checklist_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/housekeeping_notifier.dart';
import '../domain/housekeeping_models.dart' as hk;
import '../data/housekeeping_repository.dart';
import '../../../core/network/api_client.dart';

// ✅ NEW IMPORT: DB se real court name laane ke liye
import '../../courts/domain/courts_notifier.dart';

// ✅ Read-only status for a specific (past) date — used by the date browser.
final _dayStatusProvider = FutureProvider.autoDispose
    .family<hk.FullStatusResponse?, String>((ref, date) async {
      return ref.read(housekeepingRepoProvider).getFullStatus(date: date);
    });

// ─── Palette ──────────────────────────────────────────────────────────────────

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _bg = Color(0xFF080808);
const _surface = Color(0xFF141414);
const _card = Color(0xFF1F1F1F);
const _border = Color(0xFF2C2C2C);
const _grey = Color(0xFF888888);
const _faint = Color(0xFF444444);
const _light = Color(0xFFF2F2F2);
const _success = Color(0xFF22C55E);
const _warning = Color(0xFFE5A000);
const _danger = Color(0xFFFF4444);
const _blue = Color(0xFF60A5FA);
const _purple = Color(0xFFA78BFA);

// ─── Task definitions ─────────────────────────────────────────────────────────

class _TaskDef {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<hk.Shift> shifts;
  const _TaskDef({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.shifts = const [],
  });
}

const _kDailyTasks = [
  _TaskDef(
    id: 'floorclean',
    title: 'Floor Cleaning',
    icon: Icons.cleaning_services_rounded,
    color: _blue,
  ),
  _TaskDef(
    id: 'tablechairclean',
    title: 'Table & Chair Clean',
    icon: Icons.chair_rounded,
    color: _blue,
  ),
  _TaskDef(
    id: 'binclean',
    title: 'Bins Cleaning (outside)',
    icon: Icons.delete_forever_rounded,
    color: _blue,
  ),
  _TaskDef(
    id: 'trayclean',
    title: 'Tray Cleaning',
    icon: Icons.restaurant_rounded,
    color: _blue,
  ),
  _TaskDef(
    id: 'binempty',
    title: 'Garbage Bin Empty',
    icon: Icons.delete_outline_rounded,
    color: _warning,
    shifts: [hk.Shift.night],
  ),
  _TaskDef(
    id: 'pestspray',
    title: 'Pest Spray',
    icon: Icons.pest_control_rounded,
    color: _warning,
    shifts: [hk.Shift.morning, hk.Shift.night],
  ),
];

const _kWeeklyTask = _TaskDef(
  id: 'flagswash',
  title: 'Flags Washing',
  icon: Icons.flag_rounded,
  color: _purple,
);

const _kMonthlyTask = _TaskDef(
  id: 'fireaudit',
  title: 'Fire Safety Audit',
  icon: Icons.fire_extinguisher_rounded,
  color: _danger,
);

// ─── Helpers ──────────────────────────────────────────────────────────────────

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

bool _isShiftTimeActive(hk.Shift shift) {
  final h = TimeOfDay.now().hour;
  switch (shift) {
    case hk.Shift.morning:
      return h >= 6 && h < 12;
    case hk.Shift.day:
      return h >= 12 && h < 16;
    case hk.Shift.night:
      return h >= 16 && h < 24;
  }
}

String _shiftTimeRange(hk.Shift shift) => const {
  hk.Shift.morning: '6:00 AM – 12:00 PM',
  hk.Shift.day: '12:00 PM – 4:00 PM',
  hk.Shift.night: '4:00 PM – 12:00 AM',
}[shift]!;

// ─── Date helpers (date browser) ──────────────────────────────────────────────

const _kWeekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _kMonthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _ymd(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _prettyDay(DateTime d) {
  final now = DateTime.now();
  if (_isSameDay(d, now)) return 'Today';
  if (_isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${_kWeekdayNames[d.weekday - 1]}, ${d.day} ${_kMonthNames[d.month - 1]}';
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class StaffChecklistScreen extends ConsumerStatefulWidget {
  const StaffChecklistScreen({super.key});

  @override
  ConsumerState<StaffChecklistScreen> createState() =>
      _StaffChecklistScreenState();
}

class _StaffChecklistScreenState extends ConsumerState<StaffChecklistScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ✅ Date browser — defaults to today; can navigate to past dates (read-only).
  DateTime _selectedDate = DateTime.now();

  bool get _isToday => _isSameDay(_selectedDate, DateTime.now());

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
      SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  List<_TaskDef> _tasksForShift(hk.Shift shift) => _kDailyTasks
      .where((t) => t.shifts.isEmpty || t.shifts.contains(shift))
      .toList();

  // ── Shift not active dialog ───────────────────────────────────────────────

  void _showShiftNotActiveDialog(hk.Shift shift) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.70),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _danger.withOpacity(0.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: _danger.withOpacity(0.25)),
                ),
                child: const Icon(
                  Icons.block_rounded,
                  color: _danger,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Not Possible',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${_shiftLabel(shift)} shift tasks can only be\ncompleted during its active hours.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: _grey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _warning.withOpacity(0.22)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: _warning,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_shiftLabel(shift)}  •  ${_shiftTimeRange(shift)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _warning,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.of(dialogContext).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'OK, Got it',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _black,
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

  // ✅ NEW: Cooldown dialog for weekly/monthly tasks ─────────────────────────

  void _showCooldownDialog({
    required String taskTitle,
    required int remainingDays,
    required bool isWeekly,
  }) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.70),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Countdown ring ───────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _warning.withOpacity(0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _warning.withOpacity(0.35),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$remainingDays',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _warning,
                      ),
                    ),
                    Text(
                      remainingDays == 1 ? 'day' : 'days',
                      style: GoogleFonts.inter(fontSize: 10, color: _warning),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Not Available Yet',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '"$taskTitle" was already completed.\nCome back in $remainingDays ${remainingDays == 1 ? 'day' : 'days'}.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: _grey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: _grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isWeekly
                            ? 'Weekly tasks reset every 7 days after completion.'
                            : 'Monthly tasks reset every 30 days after completion.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _grey,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.of(dialogContext).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Got it',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _black,
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

  // ── Task tap ───────────────────────────────────────────────────────────────

  Future<void> _handleTaskTap(_TaskDef task) async {
    final hkState = ref.read(housekeepingNotifierProvider);
    if (hkState.isTaskLoading(task.id)) return;

    HapticFeedback.mediumImpact();

    // ✅ Weekly cooldown check
    if (task.id == 'flagswash' && hkState.isWeeklyCooldown) {
      _showCooldownDialog(
        taskTitle: task.title,
        remainingDays: hkState.weeklyRemainingDays,
        isWeekly: true,
      );
      return;
    }

    // ✅ Monthly cooldown check
    if (task.id == 'fireaudit' && hkState.isMonthlyCooldown) {
      _showCooldownDialog(
        taskTitle: task.title,
        remainingDays: hkState.monthlyRemainingDays,
        isWeekly: false,
      );
      return;
    }

    // Already locked (daily task already done)
    if (hkState.isTaskLocked(task.id)) return;

    if (!_isShiftTimeActive(hkState.shift)) {
      _showShiftNotActiveDialog(hkState.shift);
      return;
    }

    final proceed = await _showPhotoSourceSheet(task);
    if (proceed != ImageSource.camera || !mounted) return;

    final picker = ImagePicker();
    // Camera ONLY — gallery is intentionally disabled so staff cannot submit
    // old/fake photos. Every proof is a live capture, watermarked on upload.
    final xFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1280,
    );
    if (xFile == null || !mounted) return;
    final photo = File(xFile.path);

    final confirmed = await _showConfirmDialog(task, photo);
    if (!confirmed || !mounted) return;

    final ok = await ref
        .read(housekeepingNotifierProvider.notifier)
        .confirmTask(taskId: task.id, taskTitle: task.title, photo: photo);

    if (!mounted) return;

    if (ok) {
      HapticFeedback.heavyImpact();
      _showTaskSavedSnackbar(task.title);
    } else {
      HapticFeedback.lightImpact();
      final err = ref.read(housekeepingNotifierProvider).error;
      _showErrorSnackbar(err ?? 'Upload failed. Try again.');
    }
  }

  Future<ImageSource?> _showPhotoSourceSheet(_TaskDef task) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _PhotoPickerSheet(task: task),
    );
  }

  Future<bool> _showConfirmDialog(_TaskDef task, File photo) async {
    return await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          barrierColor: Colors.black.withOpacity(0.80),
          builder: (dialogContext) =>
              _ConfirmTaskDialog(task: task, photo: photo),
        ) ??
        false;
  }

  void _showTaskSavedSnackbar(String taskTitle) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _success.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: _success, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '"$taskTitle" saved ✓',
                  style: GoogleFonts.inter(
                    color: _white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _danger.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _danger.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: _danger, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(color: _white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  // ── Date browser controls ──────────────────────────────────────────────────

  void _changeDate(int deltaDays) {
    final next = _selectedDate.add(Duration(days: deltaDays));
    // Block navigation into the future.
    if (next.isAfter(DateTime.now())) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedDate = next);
  }

  void _goToday() {
    if (_isToday) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedDate = DateTime.now());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _white,
            onPrimary: _black,
            surface: _surface,
            onSurface: _white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      HapticFeedback.selectionClick();
      setState(() => _selectedDate = picked);
    }
  }

  // ── Read-only history list (for past dates) ────────────────────────────────

  Widget _buildHistoryList(hk.Shift shift, double bottomPad) {
    final hkState = ref.watch(housekeepingNotifierProvider);
    final courtId = hkState.courtId;
    final dateStr = _ymd(_selectedDate);
    final async = ref.watch(_dayStatusProvider(dateStr));
    final dailyTasks = _tasksForShift(shift);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
          child: CircularProgressIndicator(color: _black, strokeWidth: 2),
        ),
      ),
      error: (_, __) => _HistoryMessage(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load',
        subtitle: 'Switch dates and try again.',
      ),
      data: (status) {
        // Map taskId -> status item for this court + shift + date.
        final Map<String, hk.TaskStatusItem> items = {};
        if (status != null && courtId != null) {
          for (final court in status.courts) {
            if (court.courtId != courtId) continue;
            for (final sh in court.shifts) {
              if (sh.shift != shift) continue;
              for (final t in sh.tasks) {
                items[t.taskId] = t;
              }
            }
          }
        }

        final doneCount =
            dailyTasks.where((t) => items[t.id]?.isDone == true).length;

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, bottomPad),
          children: [
            // Summary banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _light,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _black.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 17, color: _grey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Viewing past records · read only',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _grey,
                      ),
                    ),
                  ),
                  Text(
                    '$doneCount / ${dailyTasks.length}',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: doneCount == dailyTasks.length
                          ? _success
                          : _black,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            ...dailyTasks.asMap().entries.map((e) {
              final item = items[e.value.id];
              return _HistoryTaskTile(
                taskDef: e.value,
                isDone: item?.isDone == true,
                photoUrl: item?.photoUrl,
                doneByName: item?.doneByName,
              );
            }),

            const SizedBox(height: 8),
            Center(
              child: Text(
                'Weekly & monthly tasks are tracked on Today.',
                style: GoogleFonts.inter(fontSize: 11.5, color: _faint),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hkState = ref.watch(housekeepingNotifierProvider);
    final courtsAsync = ref.watch(courtsNotifierProvider);

    final shift = hkState.shift;
    final dailyTasks = _tasksForShift(shift);
    final totalVisible = dailyTasks.length + 2;
    final doneCount = hkState.lockedDoneCount;

    // ✅ FIX: Dynamic Court Name Fetching
    String courtLabel = 'Unassigned Court';
    if (hkState.courtId != null) {
      courtLabel = 'Court ${hkState.courtId}'; // Fallback
      courtsAsync.whenData((courts) {
        final match = courts.where((c) => c.id == hkState.courtId);
        if (match.isNotEmpty) {
          courtLabel = match.first.name;
        }
      });
    }

    final navBarClearance = MediaQuery.of(context).padding.bottom + 92.0;
    final shiftActive = _isShiftTimeActive(shift);
    final isToday = _isToday;

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────
              Padding(
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
                                courtLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isToday
                                    ? '$doneCount of $totalVisible tasks completed'
                                    : _prettyDay(_selectedDate),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: _grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isToday && doneCount > 0)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: doneCount == totalVisible
                                  ? _success.withOpacity(0.12)
                                  : _white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: doneCount == totalVisible
                                    ? _success.withOpacity(0.3)
                                    : _white.withOpacity(0.1),
                              ),
                            ),
                            child: Text(
                              doneCount == totalVisible
                                  ? '✓ All Done'
                                  : '$doneCount / $totalVisible',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: doneCount == totalVisible
                                    ? _success
                                    : _grey,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Shift selector tabs ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: hk.Shift.values.map((s) {
                          final selected = shift == s;
                          final isActive = _isShiftTimeActive(s);
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref
                                    .read(housekeepingNotifierProvider.notifier)
                                    .changeShift(s);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected ? _white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _shiftIcon(s),
                                      size: 13,
                                      color: selected ? _black : _grey,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _shiftLabel(s),
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: selected ? _black : _grey,
                                      ),
                                    ),
                                    if (!isActive) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: selected ? _danger : _faint,
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

                    // ── Date browser ─────────────────────────────────
                    const SizedBox(height: 10),
                    _DateNavBar(
                      label: _prettyDay(_selectedDate),
                      isToday: isToday,
                      onPrev: () => _changeDate(-1),
                      onNext: isToday ? null : () => _changeDate(1),
                      onToday: _goToday,
                      onPickDate: _pickDate,
                    ),

                    // ── Inactive warning banner (today only) ──────────
                    if (isToday && !shiftActive) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _danger.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _danger.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: _danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_shiftLabel(shift)} shift is not active  •  ${_shiftTimeRange(shift)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _danger,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ── White task list ──────────────────────────────────────
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: isToday
                      ? ListView(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, navBarClearance),
                    children: [
                      // Daily tasks
                      ...dailyTasks.asMap().entries.map(
                        (e) => _TaskTile(
                          key: ValueKey('${shift.name}_${e.value.id}'),
                          taskDef: e.value,
                          index: e.key,
                          isDone: hkState.isTaskDone(e.value.id),
                          isLocked: hkState.isTaskLocked(e.value.id),
                          isLoading: hkState.isTaskLoading(e.value.id),
                          photo: hkState.taskPhoto(e.value.id),
                          photoUrl: hkState.taskPhotoUrl(e.value.id),
                          isShiftActive: shiftActive,
                          cooldownDays: 0, // daily tasks have no cooldown
                          doneByName: hkState.taskDoneBy(e.value.id),
                          onTap: () => _handleTaskTap(e.value),
                        ),
                      ),

                      // Weekly
                      const SizedBox(height: 4),
                      const _SectionDivider(label: 'Weekly Task'),
                      const SizedBox(height: 8),
                      _TaskTile(
                        key: ValueKey('${shift.name}_${_kWeeklyTask.id}'),
                        taskDef: _kWeeklyTask,
                        index: dailyTasks.length,
                        isDone: hkState.isTaskDone(_kWeeklyTask.id),
                        isLocked: hkState.isTaskLocked(_kWeeklyTask.id),
                        isLoading: hkState.isTaskLoading(_kWeeklyTask.id),
                        photo: hkState.taskPhoto(_kWeeklyTask.id),
                        photoUrl: hkState.taskPhotoUrl(_kWeeklyTask.id),
                        isShiftActive: shiftActive,
                        cooldownDays: hkState.weeklyRemainingDays, // ✅
                        doneByName: hkState.taskDoneBy(_kWeeklyTask.id),
                        onTap: () => _handleTaskTap(_kWeeklyTask),
                      ),

                      // Monthly
                      const SizedBox(height: 4),
                      const _SectionDivider(label: 'Monthly Task'),
                      const SizedBox(height: 8),
                      _TaskTile(
                        key: ValueKey('${shift.name}_${_kMonthlyTask.id}'),
                        taskDef: _kMonthlyTask,
                        index: dailyTasks.length + 1,
                        isDone: hkState.isTaskDone(_kMonthlyTask.id),
                        isLocked: hkState.isTaskLocked(_kMonthlyTask.id),
                        isLoading: hkState.isTaskLoading(_kMonthlyTask.id),
                        photo: hkState.taskPhoto(_kMonthlyTask.id),
                        photoUrl: hkState.taskPhotoUrl(_kMonthlyTask.id),
                        isShiftActive: shiftActive,
                        cooldownDays: hkState.monthlyRemainingDays, // ✅
                        doneByName: hkState.taskDoneBy(_kMonthlyTask.id),
                        onTap: () => _handleTaskTap(_kMonthlyTask),
                      ),

                      const SizedBox(height: 16),

                      // Error banner
                      if (hkState.error != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _danger.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _danger.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: _danger,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  hkState.error!,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: _danger,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => ref
                                    .read(housekeepingNotifierProvider.notifier)
                                    .clearError(),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: _danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                      )
                    : _buildHistoryList(shift, navBarClearance),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Task Tile ────────────────────────────────────────────────────────────────

class _TaskTile extends StatefulWidget {
  final _TaskDef taskDef;
  final int index;
  final bool isDone;
  final bool isLocked;
  final bool isLoading;
  final File? photo;
  final String? photoUrl;
  final bool isShiftActive;
  final int cooldownDays; // ✅ 0 = no cooldown, >0 = locked with countdown
  final String? doneByName;
  final VoidCallback onTap;

  const _TaskTile({
    super.key,
    required this.taskDef,
    required this.index,
    required this.isDone,
    required this.isLocked,
    required this.isLoading,
    required this.photo,
    required this.photoUrl,
    required this.isShiftActive,
    required this.cooldownDays,
    this.doneByName,
    required this.onTap,
  });

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile>
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
      begin: const Offset(0, 0.06),
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

  void _openViewer() {
    final hasLocal = widget.photo != null;
    final hasNetwork = widget.photoUrl != null && widget.photoUrl!.isNotEmpty;
    if (!hasLocal && !hasNetwork) return;
    HapticFeedback.selectionClick();
    showHkPhotoViewer(
      context,
      url: hasNetwork ? widget.photoUrl : null,
      file: hasLocal ? widget.photo : null,
      title: widget.taskDef.title,
      doneByName: widget.doneByName,
    );
  }

  Widget _buildThumbnail() {
    final hasLocal = widget.photo != null;
    final hasNetwork = widget.photoUrl != null && widget.photoUrl!.isNotEmpty;

    if (!hasLocal && !hasNetwork) {
      return const Icon(Icons.lock_rounded, size: 16, color: _success);
    }

    return GestureDetector(
      onTap: _openViewer,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _success.withOpacity(0.3), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: hasLocal
                  ? Image.file(widget.photo!, fit: BoxFit.cover)
                  : Image.network(
                      resolveMediaUrl(widget.photoUrl)!,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: _success.withOpacity(0.08),
                          child: const Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _success,
                              ),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: _success.withOpacity(0.08),
                        child: const Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: _success,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.isLocked;
    final loading = widget.isLoading;
    final onCooldown = widget.cooldownDays > 0; // ✅
    final dimmed = !widget.isShiftActive && !locked && !onCooldown;

    // ── Tile appearance ────────────────────────────────────────────────────
    final Color tileBg;
    final Color tileBorder;
    final Color iconBg;
    final Color iconColor;
    final Color titleColor;
    final String subtitle;
    final Widget rightWidget;

    if (onCooldown) {
      // ✅ Cooldown state — warning orange tint
      tileBg = _warning.withOpacity(0.06);
      tileBorder = _warning.withOpacity(0.22);
      iconBg = _warning.withOpacity(0.10);
      iconColor = _warning;
      titleColor = _warning;
      subtitle =
          'Available in ${widget.cooldownDays} ${widget.cooldownDays == 1 ? 'day' : 'days'}';
      rightWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _warning.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _warning.withOpacity(0.28)),
        ),
        child: Text(
          '${widget.cooldownDays}d',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _warning,
          ),
        ),
      );
    } else if (locked) {
      // Done & locked
      tileBg = _success.withOpacity(0.06);
      tileBorder = _success.withOpacity(0.25);
      iconBg = _success.withOpacity(0.12);
      iconColor = _success;
      titleColor = _success;
      subtitle = (widget.doneByName != null && widget.doneByName!.trim().isNotEmpty)
          ? 'By ${widget.doneByName} · Saved ✓'
          : 'Saved ✓ — cannot be undone';
      rightWidget = _buildThumbnail();
    } else if (dimmed) {
      // Outside shift hours
      tileBg = _light.withOpacity(0.5);
      tileBorder = _black.withOpacity(0.03);
      iconBg = widget.taskDef.color.withOpacity(0.05);
      iconColor = widget.taskDef.color.withOpacity(0.35);
      titleColor = _grey;
      subtitle = 'Not available outside shift hours';
      rightWidget = const Icon(
        Icons.lock_clock_rounded,
        size: 18,
        color: _faint,
      );
    } else {
      // Normal/available
      tileBg = _light;
      tileBorder = _black.withOpacity(0.06);
      iconBg = widget.taskDef.color.withOpacity(0.10);
      iconColor = widget.taskDef.color;
      titleColor = _black;
      subtitle = loading
          ? 'Uploading & saving...'
          : 'Tap to take photo & complete';
      rightWidget = loading
          ? const SizedBox(
              width: 38,
              height: 38,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _grey,
                  ),
                ),
              ),
            )
          : Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _black.withOpacity(0.07)),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 17,
                color: _grey,
              ),
            );
    }

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: (locked || loading) ? null : widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tileBorder),
            ),
            child: Row(
              children: [
                // Left icon box
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: loading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _grey,
                          ),
                        )
                      : Icon(
                          locked
                              ? Icons.check_rounded
                              : onCooldown
                              ? Icons.hourglass_top_rounded
                              : widget.taskDef.icon,
                          size: 18,
                          color: iconColor,
                        ),
                ),

                const SizedBox(width: 12),

                // Title + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.taskDef.title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: loading ? _grey : titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loading ? 'Uploading & saving...' : subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: loading
                              ? _grey
                              : onCooldown
                              ? _warning.withOpacity(0.75)
                              : locked
                              ? _success.withOpacity(0.65)
                              : _grey,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Right widget
                rightWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Photo Picker Sheet ───────────────────────────────────────────────────────

class _PhotoPickerSheet extends StatefulWidget {
  final _TaskDef task;
  const _PhotoPickerSheet({super.key, required this.task});

  @override
  State<_PhotoPickerSheet> createState() => _PhotoPickerSheetState();
}

class _PhotoPickerSheetState extends State<_PhotoPickerSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scaleAnim = Tween<double>(
      begin: 0.93,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final taskColor = widget.task.color;

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 48,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: taskColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: taskColor.withOpacity(0.22)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.task.icon, size: 13, color: taskColor),
                    const SizedBox(width: 7),
                    Text(
                      widget.task.title,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: taskColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Add Photo Proof',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _white,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Live camera only - take a fresh photo to mark this done.',
                style: GoogleFonts.inter(fontSize: 13, color: _grey),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SheetOptionButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Take Photo',
                  sublabel: 'Open camera now',
                  isPrimary: true,
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.verified_user_rounded,
                    size: 13,
                    color: _faint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Location & time are stamped on every photo',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: _faint,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(null),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _faint,
                    ),
                  ),
                ),
              ),
              SizedBox(height: bottomPad + 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sheet Option Button ──────────────────────────────────────────────────────

class _SheetOptionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool isPrimary;
  final VoidCallback onTap;

  const _SheetOptionButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_SheetOptionButton> createState() => _SheetOptionButtonState();
}

class _SheetOptionButtonState extends State<_SheetOptionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isPrimary
        ? (_pressed ? const Color(0xFFE0E0E0) : _white)
        : (_pressed ? const Color(0xFF2A2A2A) : _card);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isPrimary ? Colors.transparent : _border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.isPrimary
                      ? const Color(0xFFF0F0F0)
                      : const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: widget.isPrimary ? _black : _grey,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: widget.isPrimary ? _black : _white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.sublabel,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: widget.isPrimary ? _grey : _faint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: widget.isPrimary ? const Color(0xFFBBBBBB) : _faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Confirm Dialog ───────────────────────────────────────────────────────────

class _ConfirmTaskDialog extends StatelessWidget {
  final _TaskDef task;
  final File photo;
  const _ConfirmTaskDialog({required this.task, required this.photo});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Image.file(
                  photo,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(task.icon, size: 12, color: task.color),
                        const SizedBox(width: 6),
                        Text(
                          task.title,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload & mark as done?',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _warning.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _warning.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: _warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Photo will upload to server. '
                            'This cannot be undone for today.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _warning,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _border),
                            ),
                            child: Center(
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'Confirm Done',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Divider ──────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: _black.withOpacity(0.07))),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _light,
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
        Expanded(child: Container(height: 1, color: _black.withOpacity(0.07))),
      ],
    );
  }
}


// ─── Date Nav Bar ─────────────────────────────────────────────────────────────

class _DateNavBar extends StatelessWidget {
  final String label;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onToday;
  final VoidCallback onPickDate;

  const _DateNavBar({
    required this.label,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onPickDate,
  });

  Widget _navBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? _white.withOpacity(0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 20, color: enabled ? _white : _faint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          _navBtn(Icons.chevron_left_rounded, onPrev),
          Expanded(
            child: GestureDetector(
              onTap: onPickDate,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: _grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _white,
                      ),
                    ),
                    if (!isToday) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: onToday,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Today',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _navBtn(Icons.chevron_right_rounded, onNext),
        ],
      ),
    );
  }
}

// ─── History (read-only) Task Tile ──────────────────────────────────────────────

class _HistoryTaskTile extends StatelessWidget {
  final _TaskDef taskDef;
  final bool isDone;
  final String? photoUrl;
  final String? doneByName;

  const _HistoryTaskTile({
    required this.taskDef,
    required this.isDone,
    this.photoUrl,
    this.doneByName,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = isDone && photoUrl != null && photoUrl!.isNotEmpty;

    Widget right;
    if (hasPhoto) {
      right = GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          showHkPhotoViewer(
            context,
            url: photoUrl,
            title: taskDef.title,
            doneByName: doneByName,
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: _success.withOpacity(0.3), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  resolveMediaUrl(photoUrl)!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: _success.withOpacity(0.08),
                      child: const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: _success,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: _success.withOpacity(0.08),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: _success,
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
      );
    } else {
      right = Icon(
        isDone
            ? Icons.verified_rounded
            : Icons.remove_circle_outline_rounded,
        size: 18,
        color: isDone ? _success : _faint,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: isDone ? _success.withOpacity(0.06) : _light,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone ? _success.withOpacity(0.22) : _black.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (isDone ? _success : taskDef.color).withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isDone ? Icons.check_rounded : taskDef.icon,
              size: 18,
              color: isDone ? _success : taskDef.color.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  taskDef.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDone ? _black : _grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDone
                      ? ((doneByName != null && doneByName!.trim().isNotEmpty)
                            ? 'By $doneByName · Completed'
                            : 'Completed')
                      : 'Not completed',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDone ? _success.withOpacity(0.7) : _grey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          right,
        ],
      ),
    );
  }
}

// ─── History empty / error message ──────────────────────────────────────────────

class _HistoryMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(icon, size: 40, color: _grey),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: _grey),
          ),
        ],
      ),
    );
  }
}


// ─── Full-screen Photo Viewer (staff) ────────────────────────────────────────

void showHkPhotoViewer(
  BuildContext context, {
  String? url,
  File? file,
  required String title,
  String? doneByName,
}) {
  showDialog(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black.withOpacity(0.94),
    builder: (_) => _HkPhotoViewer(
      url: url,
      file: file,
      title: title,
      doneByName: doneByName,
    ),
  );
}

class _HkPhotoViewer extends StatelessWidget {
  final String? url;
  final File? file;
  final String title;
  final String? doneByName;

  const _HkPhotoViewer({
    this.url,
    this.file,
    required this.title,
    this.doneByName,
  });

  @override
  Widget build(BuildContext context) {
    final hasName = doneByName != null && doneByName!.trim().isNotEmpty;
    final resolved = url != null ? resolveMediaUrl(url) : null;

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: file != null
                    ? Image.file(file!, fit: BoxFit.contain)
                    : (resolved != null
                          ? Image.network(
                              resolved,
                              fit: BoxFit.contain,
                              loadingBuilder: (_, child, prog) => prog == null
                                  ? child
                                  : const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  color: Colors.white38,
                                  size: 48,
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.image_not_supported_rounded,
                                color: Colors.white38,
                                size: 48,
                              ),
                            )),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 12,
                8,
                16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (hasName) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.person_rounded,
                                size: 13,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'By $doneByName',
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
