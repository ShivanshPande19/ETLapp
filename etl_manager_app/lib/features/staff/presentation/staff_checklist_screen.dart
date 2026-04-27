import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/housekeeping_notifier.dart';
import '../domain/housekeeping_models.dart' as hk;

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
  final List<hk.Shift> shifts; // empty = visible in all shifts
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

  // ── Task tap → photo → confirm → upload + lock ─────────────────────────────

  Future<void> _handleTaskTap(_TaskDef task) async {
    final hkState = ref.read(housekeepingNotifierProvider);

    // Locked or currently uploading → ignore
    if (hkState.isTaskLocked(task.id)) return;
    if (hkState.isTaskLoading(task.id)) return;

    HapticFeedback.mediumImpact();

    // Step 1: photo source picker sheet
    final source = await _showPhotoSourceSheet(task);
    if (source == null || !mounted) return;

    // Step 2: pick image
    final picker = ImagePicker();
    final xFile = source == ImageSource.camera
        ? await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 80,
            maxWidth: 1280,
          )
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xFile == null || !mounted) return;
    final photo = File(xFile.path);

    // Step 3: confirmation dialog
    final confirmed = await _showConfirmDialog(task, photo);
    if (!confirmed || !mounted) return;

    // Step 4: upload to Cloudinary + POST single task to backend
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
      useRootNavigator: true, // ✅ renders above shell nav bar
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PhotoPickerSheet(task: task),
    );
  }

  Future<bool> _showConfirmDialog(_TaskDef task, File photo) async {
    return await showDialog<bool>(
          context: context,
          useRootNavigator: true, // ✅ renders above shell nav bar
          barrierColor: Colors.black.withOpacity(0.80),
          builder: (_) => _ConfirmTaskDialog(task: task, photo: photo),
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

  @override
  Widget build(BuildContext context) {
    final hkState = ref.watch(housekeepingNotifierProvider);
    final shift = hkState.shift;
    final dailyTasks = _tasksForShift(shift);
    final totalVisible = dailyTasks.length + 2; // +weekly +monthly
    final doneCount = hkState.lockedDoneCount;
    final courtLabel = hkState.courtId != null
        ? 'Court ${hkState.courtId}'
        : 'Unassigned Court';

    // Shell nav bar clearance: bottomSafeArea + 16 (margin) + 60 (height)
    final navBarClearance = MediaQuery.of(context).padding.bottom + 92.0;

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Dark header ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Court label + progress chip
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
                                '$doneCount of $totalVisible tasks completed',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: _grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (doneCount > 0)
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

                    // Shift selector tabs
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: hk.Shift.values.map((s) {
                          final selected = shift == s;
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
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ── White task list ────────────────────────────────────────
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      navBarClearance, // clears shell nav bar
                    ),
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
                        onTap: () => _handleTaskTap(_kMonthlyTask),
                      ),

                      const SizedBox(height: 16),

                      // Inline error banner
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
                  ),
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
  final VoidCallback onTap;

  const _TaskTile({
    super.key,
    required this.taskDef,
    required this.index,
    required this.isDone,
    required this.isLocked,
    required this.isLoading,
    required this.photo,
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

  @override
  Widget build(BuildContext context) {
    final locked = widget.isLocked;
    final loading = widget.isLoading;
    final hasPhoto = widget.photo != null;

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
              color: locked ? _success.withOpacity(0.06) : _light,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: locked
                    ? _success.withOpacity(0.25)
                    : _black.withOpacity(0.06),
              ),
            ),
            child: Row(
              children: [
                // Left icon / spinner
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: locked
                        ? _success.withOpacity(0.12)
                        : widget.taskDef.color.withOpacity(0.10),
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
                          locked ? Icons.check_rounded : widget.taskDef.icon,
                          size: 18,
                          color: locked ? _success : widget.taskDef.color,
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
                          color: loading
                              ? _grey
                              : locked
                              ? _success
                              : _black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loading
                            ? 'Uploading & saving...'
                            : locked
                            ? 'Saved ✓ — cannot be undone'
                            : 'Tap to take photo & complete',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: loading
                              ? _grey
                              : locked
                              ? _success.withOpacity(0.65)
                              : _grey,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Right: loading spinner / thumbnail / lock / camera
                if (loading)
                  const SizedBox(
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
                else if (locked && hasPhoto)
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: _success.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(widget.photo!, fit: BoxFit.cover),
                    ),
                  )
                else if (locked)
                  const Icon(Icons.lock_rounded, size: 16, color: _success)
                else
                  Container(
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
                  ),
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

              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              const SizedBox(height: 24),

              // Task identity chip
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
                'A photo is required to mark this task done.',
                style: GoogleFonts.inter(fontSize: 13, color: _grey),
              ),

              const SizedBox(height: 28),

              // Camera (primary)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SheetOptionButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Take Photo',
                  sublabel: 'Open camera now',
                  isPrimary: true,
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ),

              const SizedBox(height: 10),

              // Gallery (secondary)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SheetOptionButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Choose from Gallery',
                  sublabel: 'Pick an existing photo',
                  isPrimary: false,
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ),

              const SizedBox(height: 8),

              // Cancel
              GestureDetector(
                onTap: () => Navigator.pop(context, null),
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
              // Icon box
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

              // Labels
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
            // Photo preview with task chip overlay
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

                  // Warning banner
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

                  // Cancel / Confirm buttons
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, false),
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
                          onTap: () => Navigator.pop(context, true),
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
