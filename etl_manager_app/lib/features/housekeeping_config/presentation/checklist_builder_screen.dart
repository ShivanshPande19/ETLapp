// lib/features/housekeeping_config/presentation/checklist_builder_screen.dart
//
// Premium per-court housekeeping checklist builder:
//  • Reorderable shift cards (drag handle) with 12h time-range
//  • Tap a shift → deep editor: drag-drop tasks, swipe-to-delete, add, icon pick
//  • Adding a shift copies the previous shift's tasks (editable)
//  • Weekly / Monthly recurring tasks
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/checklist_config_models.dart';
import '../data/checklist_config_repository.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);
const _ok = Color(0xFF16A34A);

// ─── Time helpers ─────────────────────────────────────────────────────────────
String _to24(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? _parseTod(String? s) {
  if (s == null || !s.contains(':')) return null;
  final p = s.split(':');
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String _fmt12(String? hhmm) {
  final t = _parseTod(hhmm);
  if (t == null) return '--:--';
  final ap = t.hour < 12 ? 'AM' : 'PM';
  var h = t.hour % 12;
  if (h == 0) h = 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} $ap';
}

// ─── Builder screen ─────────────────────────────────────────────────────────

class ChecklistBuilderScreen extends ConsumerStatefulWidget {
  final int courtId;
  final String courtName;
  const ChecklistBuilderScreen({
    super.key,
    required this.courtId,
    required this.courtName,
  });

  @override
  ConsumerState<ChecklistBuilderScreen> createState() =>
      _ChecklistBuilderScreenState();
}

class _ChecklistBuilderScreenState
    extends ConsumerState<ChecklistBuilderScreen> {
  ChecklistDraft? _draft;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref
          .read(checklistConfigRepositoryProvider)
          .getConfig(widget.courtId);
      setState(() {
        _draft = d;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load checklist';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    if (d.shifts.isEmpty) {
      _toast('Add at least one shift', err: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(checklistConfigRepositoryProvider)
          .saveConfig(widget.courtId, d);
      if (!mounted) return;
      setState(() {
        _draft = saved;
        _saving = false;
      });
      _toast('Checklist saved');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save', err: true);
    }
  }

  void _toast(String m, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: err ? _red : _black,
      ),
    );
  }

  // ── Shift ops ──────────────────────────────────────────────────────────────
  void _addShift() async {
    HapticFeedback.selectionClick();
    final d = _draft!;
    // Copy the previous shift's tasks so the manager doesn't retype shared ones.
    final copied = d.shifts.isNotEmpty
        ? d.shifts.last.tasks.map((t) => t.copy()).toList()
        : <TaskDraft>[];
    final shift = ShiftDraft(
      name: 'New Shift',
      start: '09:00',
      end: '17:00',
      tasks: copied,
    );
    final edited = await _openShiftEditor(shift, isNew: true);
    if (edited != null) setState(() => d.shifts.add(edited));
  }

  Future<ShiftDraft?> _openShiftEditor(ShiftDraft shift, {bool isNew = false}) {
    return Navigator.of(context).push<ShiftDraft>(
      MaterialPageRoute(
        builder: (_) => _ShiftEditorScreen(shift: shift, isNew: isNew),
      ),
    );
  }

  void _editShift(int index) async {
    final d = _draft!;
    // Edit a copy so Cancel discards changes.
    final working = ShiftDraft(
      key: d.shifts[index].key,
      name: d.shifts[index].name,
      start: d.shifts[index].start,
      end: d.shifts[index].end,
      tasks: d.shifts[index].tasks
          .map((t) => TaskDraft(
              key: t.key, title: t.title, icon: t.icon, intervalDays: t.intervalDays))
          .toList(),
    );
    final edited = await _openShiftEditor(working);
    if (edited != null) setState(() => d.shifts[index] = edited);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _black))
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _body(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: (_loading || _error != null)
          ? null
          : _SaveFab(saving: _saving, onTap: _save),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _white.withOpacity(0.12)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.west_rounded, size: 14, color: _white.withOpacity(0.9)),
                  const SizedBox(width: 6),
                  Text('Back',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _white.withOpacity(0.9))),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            RichText(
              text: TextSpan(
                style: GoogleFonts.antonSc(
                    fontSize: 30, height: 0.95, letterSpacing: -0.5),
                children: const [
                  TextSpan(text: 'CHECK', style: TextStyle(color: _white)),
                  TextSpan(text: 'LIST', style: TextStyle(color: _red)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(widget.courtName,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _white.withOpacity(0.5),
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _body() {
    final d = _draft!;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          20, 22, 20, MediaQuery.of(context).padding.bottom + 110),
      children: [
        _sectionLabel('SHIFTS', '${d.shifts.length}'),
        const SizedBox(height: 10),
        if (d.shifts.isEmpty)
          _emptyHint('No shifts yet — add the first one below.')
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: d.shifts.length,
            onReorder: (oldI, newI) {
              HapticFeedback.selectionClick();
              setState(() {
                if (newI > oldI) newI -= 1;
                final s = d.shifts.removeAt(oldI);
                d.shifts.insert(newI, s);
              });
            },
            itemBuilder: (_, i) => _ShiftCard(
              key: ValueKey('shift_$i${d.shifts[i].key}${d.shifts[i].name}'),
              index: i,
              shift: d.shifts[i],
              onTap: () => _editShift(i),
              onDelete: () {
                HapticFeedback.mediumImpact();
                setState(() => d.shifts.removeAt(i));
              },
            ),
          ),
        const SizedBox(height: 10),
        _AddButton(label: 'Add shift', onTap: _addShift),
        const SizedBox(height: 28),
        _RecurringSection(
          title: 'WEEKLY TASKS',
          accent: const Color(0xFFA855F7),
          tasks: d.weekly,
          defaultInterval: 7,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 24),
        _RecurringSection(
          title: 'MONTHLY TASKS',
          accent: const Color(0xFFFF4444),
          tasks: d.monthly,
          defaultInterval: 30,
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }

  Widget _sectionLabel(String t, String count) => Row(
        children: [
          Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                  color: _red, borderRadius: BorderRadius.circular(999))),
          const SizedBox(width: 8),
          Text(t,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _grey,
                  letterSpacing: 1.2)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: _black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999)),
            child: Text(count,
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w800, color: _black)),
          ),
        ],
      );

  Widget _emptyHint(String t) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEDED)),
        ),
        child: Text(t, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
      );
}

// ─── Shift card (on the main list) ──────────────────────────────────────────

class _ShiftCard extends StatelessWidget {
  final int index;
  final ShiftDraft shift;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ShiftCard({
    super.key,
    required this.index,
    required this.shift,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.drag_indicator_rounded,
                      color: _grey, size: 22),
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.schedule_rounded, color: _red, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shift.name,
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _black)),
                    const SizedBox(height: 3),
                    Text(
                      '${_fmt12(shift.start)} – ${_fmt12(shift.end)}  ·  ${shift.tasks.length} task${shift.tasks.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(fontSize: 12, color: _grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444), size: 20),
                onPressed: onDelete,
              ),
              Icon(Icons.chevron_right_rounded,
                  color: _grey.withOpacity(0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Recurring (weekly/monthly) section ──────────────────────────────────────

class _RecurringSection extends StatelessWidget {
  final String title;
  final Color accent;
  final List<TaskDraft> tasks;
  final int defaultInterval;
  final VoidCallback onChanged;
  const _RecurringSection({
    required this.title,
    required this.accent,
    required this.tasks,
    required this.defaultInterval,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                  color: accent, borderRadius: BorderRadius.circular(999))),
          const SizedBox(width: 8),
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _grey,
                  letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 10),
        ...tasks.asMap().entries.map((e) {
          final t = e.value;
          return Dismissible(
            key: ValueKey('rec_${title}_${e.key}_${t.title}'),
            direction: DismissDirection.endToStart,
            background: _swipeBg(),
            onDismissed: (_) {
              HapticFeedback.mediumImpact();
              tasks.removeAt(e.key);
              onChanged();
            },
            child: _TaskRow(
              task: t,
              accent: accent,
              trailing: '${t.intervalDays ?? defaultInterval}d',
              onTap: () async {
                final edited = await _editTaskSheet(context, t,
                    recurring: true, defaultInterval: defaultInterval);
                if (edited != null) {
                  tasks[e.key] = edited;
                  onChanged();
                }
              },
            ),
          );
        }),
        const SizedBox(height: 6),
        _AddButton(
          label: 'Add ${title.split(' ').first.toLowerCase()} task',
          onTap: () async {
            final t = await _editTaskSheet(context, null,
                recurring: true, defaultInterval: defaultInterval);
            if (t != null) {
              tasks.add(t);
              onChanged();
            }
          },
        ),
      ],
    );
  }
}

Widget _swipeBg() => Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_rounded, color: _white),
    );

class _TaskRow extends StatelessWidget {
  final TaskDraft task;
  final Color accent;
  final String? trailing;
  final VoidCallback onTap;
  final Widget? dragHandle;
  const _TaskRow({
    required this.task,
    required this.accent,
    required this.onTap,
    this.trailing,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
        ),
        child: Row(
          children: [
            if (dragHandle != null) dragHandle!,
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(hkIcon(task.icon), color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(task.title,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _black)),
            ),
            if (trailing != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(trailing!,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent)),
              ),
            const SizedBox(width: 4),
            Icon(Icons.edit_rounded, size: 15, color: _grey.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: _black.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _black.withOpacity(0.12),
                width: 1.5,
                style: BorderStyle.solid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, size: 18, color: _black),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _black)),
            ],
          ),
        ),
      );
}

class _SaveFab extends StatelessWidget {
  final bool saving;
  final VoidCallback onTap;
  const _SaveFab({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: saving ? null : onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: _red,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                  color: _red.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (saving)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: _white, strokeWidth: 2))
            else
              const Icon(Icons.check_rounded, color: _white, size: 20),
            const SizedBox(width: 8),
            Text(saving ? 'Saving…' : 'Save Checklist',
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w800, color: _white)),
          ]),
        ),
      );
}

// ─── Shift editor (full screen, drag-drop tasks) ─────────────────────────────

class _ShiftEditorScreen extends StatefulWidget {
  final ShiftDraft shift;
  final bool isNew;
  const _ShiftEditorScreen({required this.shift, this.isNew = false});

  @override
  State<_ShiftEditorScreen> createState() => _ShiftEditorScreenState();
}

class _ShiftEditorScreenState extends State<_ShiftEditorScreen> {
  late final TextEditingController _nameCtrl;
  late ShiftDraft _s;

  @override
  void initState() {
    super.initState();
    _s = widget.shift;
    _nameCtrl = TextEditingController(text: _s.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final t = await showTimePicker(
      context: context,
      initialTime: _parseTod(start ? _s.start : _s.end) ??
          const TimeOfDay(hour: 9, minute: 0),
    );
    if (t != null) {
      setState(() {
        if (start) {
          _s.start = _to24(t);
        } else {
          _s.end = _to24(t);
        }
      });
    }
  }

  void _done() {
    _s.name = _nameCtrl.text.trim().isEmpty ? 'Shift' : _nameCtrl.text.trim();
    Navigator.pop(context, _s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context), // cancel
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _white.withOpacity(0.12)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.close_rounded,
                            size: 14, color: _white.withOpacity(0.9)),
                        const SizedBox(width: 6),
                        Text('Cancel',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _white.withOpacity(0.9))),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _done,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        color: _ok,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_rounded, size: 16, color: _white),
                        const SizedBox(width: 6),
                        Text(widget.isNew ? 'Add' : 'Done',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _white)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: ReorderableListView(
                  padding: EdgeInsets.fromLTRB(
                      20, 22, 20, MediaQuery.of(context).padding.bottom + 24),
                  buildDefaultDragHandles: false,
                  header: _editorHeader(),
                  onReorder: (oldI, newI) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (newI > oldI) newI -= 1;
                      final t = _s.tasks.removeAt(oldI);
                      _s.tasks.insert(newI, t);
                    });
                  },
                  footer: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _AddButton(
                      label: 'Add task',
                      onTap: () async {
                        final t = await _editTaskSheet(context, null);
                        if (t != null) setState(() => _s.tasks.add(t));
                      },
                    ),
                  ),
                  children: [
                    for (int i = 0; i < _s.tasks.length; i++)
                      Dismissible(
                        key: ValueKey('task_${i}_${_s.tasks[i].title}'),
                        direction: DismissDirection.endToStart,
                        background: _swipeBg(),
                        onDismissed: (_) {
                          HapticFeedback.mediumImpact();
                          setState(() => _s.tasks.removeAt(i));
                        },
                        child: _TaskRow(
                          task: _s.tasks[i],
                          accent: const Color(0xFF60A5FA),
                          dragHandle: ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.drag_indicator_rounded,
                                  color: _grey, size: 20),
                            ),
                          ),
                          onTap: () async {
                            final edited =
                                await _editTaskSheet(context, _s.tasks[i]);
                            if (edited != null) {
                              setState(() => _s.tasks[i] = edited);
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorHeader() => Column(
        key: const ValueKey('editor_header'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SHIFT NAME',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _grey,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700, color: _black),
            cursorColor: _black,
            decoration: InputDecoration(
              hintText: 'e.g. Afternoon',
              hintStyle: GoogleFonts.inter(fontSize: 15, color: _grey),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E5E5))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E5E5))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _black, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _timeBox('STARTS', _s.start, () => _pickTime(true))),
            const SizedBox(width: 12),
            Expanded(child: _timeBox('ENDS', _s.end, () => _pickTime(false))),
          ]),
          const SizedBox(height: 24),
          Text('TASKS  ·  drag to reorder, swipe to delete',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _grey,
                  letterSpacing: 0.6)),
          const SizedBox(height: 10),
        ],
      );

  Widget _timeBox(String label, String? val, VoidCallback onTap) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, fontWeight: FontWeight.w800, color: _grey)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E5E5)),
              ),
              child: Row(children: [
                const Icon(Icons.access_time_rounded, size: 18, color: _grey),
                const SizedBox(width: 8),
                Text(_fmt12(val),
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _black)),
              ]),
            ),
          ),
        ],
      );
}

// ─── Task editor sheet (title + icon [+ interval for recurring]) ─────────────

Future<TaskDraft?> _editTaskSheet(
  BuildContext context,
  TaskDraft? existing, {
  bool recurring = false,
  int defaultInterval = 7,
}) {
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  String icon = existing?.icon ?? (recurring ? 'flag' : 'cleaning_services');
  int interval = existing?.intervalDays ?? defaultInterval;

  return showModalBottomSheet<TaskDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          decoration: const BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5E5E5),
                        borderRadius: BorderRadius.circular(999))),
              ),
              const SizedBox(height: 18),
              Text(existing == null ? 'Add task' : 'Edit task',
                  style: GoogleFonts.antonSc(
                      fontSize: 22, color: _black, letterSpacing: -0.3)),
              const SizedBox(height: 18),
              TextField(
                controller: titleCtrl,
                autofocus: existing == null,
                style: GoogleFonts.inter(fontSize: 15, color: _black),
                cursorColor: _black,
                decoration: InputDecoration(
                  hintText: 'Task name (e.g. Floor Cleaning)',
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: _grey),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E5E5))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E5E5))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _black, width: 1.5)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 18),
              Text('ICON',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _grey,
                      letterSpacing: 1)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: kHkIcons.entries.map((e) {
                  final sel = e.key == icon;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setSheet(() => icon = e.key);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: sel ? _black : const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: sel ? _black : const Color(0xFFE5E5E5)),
                      ),
                      child: Icon(e.value,
                          color: sel ? _white : _grey, size: 22),
                    ),
                  );
                }).toList(),
              ),
              if (recurring) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('EVERY',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _grey,
                            letterSpacing: 1)),
                    const SizedBox(width: 12),
                    _stepper('${interval}d', () {
                      if (interval > 1) setSheet(() => interval--);
                    }, () => setSheet(() => interval++)),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Enter a task name'),
                          behavior: SnackBarBehavior.floating));
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      TaskDraft(
                        key: existing?.key ?? '',
                        title: title,
                        icon: icon,
                        intervalDays: recurring ? interval : null,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                        color: _black,
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(
                      child: Text(existing == null ? 'Add task' : 'Save',
                          style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _white)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _stepper(String label, VoidCallback onMinus, VoidCallback onPlus) => Row(
      children: [
        _stepBtn(Icons.remove_rounded, onMinus),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w800, color: _black)),
        ),
        _stepBtn(Icons.add_rounded, onPlus),
      ],
    );

Widget _stepBtn(IconData i, VoidCallback onTap) => GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E5E5))),
        child: Icon(i, size: 18, color: _black),
      ),
    );
