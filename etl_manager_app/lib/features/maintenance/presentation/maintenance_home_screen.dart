// lib/features/maintenance/presentation/maintenance_home_screen.dart
//
// ROLE SPLIT — the tickets-only home for the two maintenance worker roles:
//   • Azimuth Maintenance        → assigned tickets + Settings.
//   • Crownest Maintenance Head  → assigned tickets + Settings + own attendance
//                                  (same check-in/out flow as ETL staff).
//
// Deliberately on the existing app theme (dark header + white canvas, brand red)
// so it looks native. Reuses maintenanceNotifierProvider (list + assign/resolve)
// and attendanceNotifierProvider (check-in/out).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/domain/auth_notifier.dart';
import '../domain/maintenance_notifier.dart';
import '../../staff/domain/attendance_notifier.dart';
import '../../notices/domain/notices_notifier.dart';
import '../../notices/presentation/notices_screen.dart';
import '../../settings/presentation/staff_settings_screen.dart';

// ─── Palette (matches the app theme) ──────────────────────────────────────────
const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _line = Color(0xFFEDEDED);
const _red = Color(0xFFD02128);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFE5A000);
const _danger = Color(0xFFFF4444);
const _blue = Color(0xFF3B82F6);

class MaintenanceHomeScreen extends ConsumerStatefulWidget {
  const MaintenanceHomeScreen({super.key});

  @override
  ConsumerState<MaintenanceHomeScreen> createState() =>
      _MaintenanceHomeScreenState();
}

class _MaintenanceHomeScreenState extends ConsumerState<MaintenanceHomeScreen> {
  bool get _isCrownestHead =>
      ref.read(authNotifierProvider).isCrownestMaintenanceHead;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
    // Load today's attendance for the Crownest Maintenance Head (has attendance).
    if (_isCrownestHead) {
      Future.microtask(
        () => ref.read(attendanceNotifierProvider.notifier).loadToday(),
      );
    }
  }

  Future<void> _refresh() async {
    HapticFeedback.mediumImpact();
    await ref.read(maintenanceNotifierProvider.notifier).refresh();
    if (_isCrownestHead) {
      await ref.read(attendanceNotifierProvider.notifier).loadToday();
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? _danger : _ok,
        content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ─── Attendance (Crownest Maintenance Head only) ────────────────────────────
  Future<void> _checkIn() async {
    HapticFeedback.selectionClick();
    final result = await context.push('/staff/mark-attendance');
    if (!mounted || result is! Map) return;
    final lat = (result['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (result['longitude'] as num?)?.toDouble() ?? 0.0;
    final imagePath = result['image_path'] as String?;
    if ((lat == 0.0 && lng == 0.0) || imagePath == null) {
      _toast('Could not capture location/photo. Try again.', isError: true);
      return;
    }
    await ref.read(attendanceNotifierProvider.notifier).markAttendance(
          lat: lat,
          lng: lng,
          imagePath: imagePath,
          accuracy: (result['accuracy'] as num?)?.toDouble(),
          isMocked: result['is_mocked'] == true,
        );
  }

  Future<void> _checkOut() async {
    HapticFeedback.selectionClick();
    final result = await context.push('/staff/mark-attendance');
    if (!mounted || result is! Map) return;
    final lat = (result['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (result['longitude'] as num?)?.toDouble() ?? 0.0;
    final imagePath = result['image_path'] as String?;
    if (lat == 0.0 && lng == 0.0) {
      _toast('Could not capture location. Try again.', isError: true);
      return;
    }
    await ref.read(attendanceNotifierProvider.notifier).checkOut(
          lat: lat,
          lng: lng,
          imagePath: imagePath,
          accuracy: (result['accuracy'] as num?)?.toDouble(),
          isMocked: result['is_mocked'] == true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final name = auth.managerName ?? auth.staffName ?? 'there';
    final roleLabel = auth.isCrownestMaintenanceHead
        ? 'Crownest · Maintenance Head'
        : 'Azimuth · Maintenance';

    // Attendance snackbars (only meaningful for the Crownest Maintenance Head,
    // but the listener is unconditional so Riverpod sees a stable subscription;
    // Azimuth Maintenance never triggers attendance changes).
    ref.listen<AttendanceState>(attendanceNotifierProvider, (prev, next) {
      if (prev?.status == next.status) return;
      if (next.status == AttendanceStatus.success) {
        _toast(next.isCheckedOut
            ? 'Shift ended. Great work today!'
            : 'Checked in successfully!');
      } else if (next.status == AttendanceStatus.error) {
        _toast(next.errorMessage ?? 'Something went wrong.', isError: true);
      }
    });

    final ticketsAsync = ref.watch(maintenanceNotifierProvider);
    final navClearance = MediaQuery.of(context).padding.bottom + 24.0;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Dark header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hi, $name',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _white.withOpacity(0.55),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Maintenance',
                          style: GoogleFonts.antonSc(
                            fontSize: 30,
                            color: _white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _red.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _red.withOpacity(0.3)),
                          ),
                          child: Text(
                            roleLabel,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: _red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CircleBtn(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final unread = ref.watch(unreadCountProvider).value ?? 0;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(Icons.notifications_none_rounded,
                                size: 19, color: _white.withOpacity(0.9)),
                            if (unread > 0)
                              Positioned(
                                right: -6,
                                top: -6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(
                                      minWidth: 16, minHeight: 16),
                                  decoration: BoxDecoration(
                                    color: _red,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _bg, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      unread > 9 ? '9+' : '$unread',
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        height: 1,
                                        color: _white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NoticesScreen()),
                    ).then((_) => ref.invalidate(unreadCountProvider)),
                  ),
                  const SizedBox(width: 10),
                  _CircleBtn(
                    accent: true,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'M',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: _red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const StaffSettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),

            // ── White canvas ─────────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: RefreshIndicator(
                  color: _black,
                  backgroundColor: _white,
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(20, 24, 20, navClearance),
                    children: [
                      if (_isCrownestHead) ...[
                        _sectionLabel('Your Attendance'),
                        const SizedBox(height: 12),
                        _AttendanceCard(
                          state: ref.watch(attendanceNotifierProvider),
                          onCheckIn: _checkIn,
                          onCheckOut: _checkOut,
                        ),
                        const SizedBox(height: 26),
                      ],
                      Row(
                        children: [
                          Expanded(child: _sectionLabel('Assigned Tickets')),
                          ticketsAsync.maybeWhen(
                            data: (list) => _CountPill(count: list.length),
                            orElse: () => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ticketsAsync.when(
                        loading: () => const _Loader(),
                        error: (e, _) => _ErrorBox(
                          message: '$e',
                          onRetry: () => ref
                              .read(maintenanceNotifierProvider.notifier)
                              .refresh(),
                        ),
                        data: (list) {
                          if (list.isEmpty) return const _EmptyBox();
                          return Column(
                            children: [
                              for (final t in list)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _TicketCard(
                                    issue: t,
                                    onTap: () => _openTicket(t),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String title) => Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: _black,
          letterSpacing: -0.3,
        ),
      );

  // ─── Ticket detail sheet ────────────────────────────────────────────────────
  void _openTicket(MaintenanceIssueModel t) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TicketSheet(
        issue: t,
        onAssign: (name, phone) async {
          final err = await ref
              .read(maintenanceNotifierProvider.notifier)
              .assignTechnician(t.id, name, phone);
          if (!mounted) return false;
          if (err == null) {
            _toast('Technician assigned.');
          } else {
            _toast(err, isError: true);
          }
          return err == null;
        },
        onResolve: (photos) async {
          final err = await ref
              .read(maintenanceNotifierProvider.notifier)
              .markResolved(t.id, photos: photos);
          if (!mounted) return false;
          if (err == null) {
            _toast('Marked resolved.');
          } else {
            _toast(err, isError: true);
          }
          return err == null;
        },
      ),
    );
  }
}

// ─── Header circle button ─────────────────────────────────────────────────────
class _CircleBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool accent;
  const _CircleBtn(
      {required this.child, required this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accent ? _red.withOpacity(0.15) : _white.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: accent ? _red.withOpacity(0.35) : _white.withOpacity(0.15),
            width: accent ? 1.5 : 1,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill({required this.count});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: GoogleFonts.inter(
            fontSize: 12, color: _white, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// ─── Attendance card (Crownest Maintenance Head) ────────────────────────────────
class _AttendanceCard extends StatelessWidget {
  final AttendanceState state;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  const _AttendanceCard({
    required this.state,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    final loading = state.loadingToday || state.status == AttendanceStatus.loading;

    Widget body;
    if (loading) {
      body = const SizedBox(
        height: 44,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _black),
          ),
        ),
      );
    } else if (state.isCheckedIn) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                state.isCheckedOut
                    ? Icons.check_circle_rounded
                    : Icons.timelapse_rounded,
                size: 18,
                color: state.isCheckedOut ? _ok : _blue,
              ),
              const SizedBox(width: 8),
              Text(
                state.isCheckedOut ? 'Shift ended' : 'On shift',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w800, color: _black),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Checked in ${_clock(state.today.checkInTime)}'
            '${state.isCheckedOut ? '  ·  Out ${_clock(state.today.checkOutTime)}' : ''}',
            style: GoogleFonts.inter(fontSize: 12.5, color: _grey),
          ),
          if (!state.isCheckedOut && state.isShiftActive) ...[
            const SizedBox(height: 14),
            _wideBtn('End shift', onCheckOut, filled: false),
          ],
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mark your attendance',
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w800, color: _black),
          ),
          const SizedBox(height: 4),
          Text(
            'Check in with a live photo at your zone.',
            style: GoogleFonts.inter(fontSize: 12.5, color: _grey),
          ),
          const SizedBox(height: 14),
          _wideBtn('Check in', onCheckIn, filled: true),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: body,
    );
  }

  static Widget _wideBtn(String label, VoidCallback onTap,
      {required bool filled}) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: filled ? _black : _white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: filled ? _black : _line),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: filled ? _white : _black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Ticket card ────────────────────────────────────────────────────────────────
class _TicketCard extends StatelessWidget {
  final MaintenanceIssueModel issue;
  final VoidCallback onTap;
  const _TicketCard({required this.issue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final where = issue.scope == 'general'
        ? '${issue.courtName} · General'
        : (issue.outletName.isNotEmpty ? issue.outletName : issue.courtName);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
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
                Expanded(
                  child: Text(
                    '#${issue.id}  ·  ${_titleCase(issue.issueType)}',
                    style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: _black),
                  ),
                ),
                if (issue.isUrgent) _tag('URGENT', _danger),
                if (!issue.isUrgent) _statusPill(issue.status),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.place_rounded, size: 13, color: _grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12.5, color: _grey),
                  ),
                ),
                if (issue.isUrgent) ...[
                  const SizedBox(width: 6),
                  _statusPill(issue.status),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              issue.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 13, color: _black.withOpacity(0.75), height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _priorityChip(issue.priority),
                const Spacer(),
                Text(
                  issue.technicianName == null || issue.technicianName!.isEmpty
                      ? 'No technician yet'
                      : 'Tech: ${issue.technicianName}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: issue.technicianName == null ? _grey : _black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ticket sheet (detail + actions) ──────────────────────────────────────────
class _TicketSheet extends StatefulWidget {
  final MaintenanceIssueModel issue;
  // Return true on success so the sheet can close.
  final Future<bool?> Function(String name, String phone) onAssign;
  final Future<bool?> Function(List<File> photos) onResolve;
  const _TicketSheet({
    required this.issue,
    required this.onAssign,
    required this.onResolve,
  });

  @override
  State<_TicketSheet> createState() => _TicketSheetState();
}

class _TicketSheetState extends State<_TicketSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _busy = false;
  bool _showAssign = false;
  final List<File> _photos = []; // resolution proof (one or many)

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.issue.technicianName ?? '';
    _phoneCtrl.text = widget.issue.technicianPhone ?? '';
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, imageQuality: 80, maxWidth: 1280);
    if (x != null && mounted) setState(() => _photos.add(File(x.path)));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  bool get _isOpen =>
      widget.issue.status == 'RAISED' ||
      widget.issue.status == 'ASSIGNED' ||
      widget.issue.status == 'DISPUTED';

  Future<void> _doAssign() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.length < 2 || phone.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid technician name & phone.')),
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await widget.onAssign(name, phone);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) Navigator.pop(context);
  }

  Future<void> _doResolve() async {
    setState(() => _busy = true);
    final ok = await widget.onResolve(_photos);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.issue;
    final where = i.scope == 'general'
        ? '${i.courtName} · General'
        : (i.outletName.isNotEmpty ? i.outletName : i.courtName);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${i.id}  ${_titleCase(i.issueType)}',
                    style: GoogleFonts.antonSc(fontSize: 22, color: _black),
                  ),
                ),
                if (i.isUrgent) _tag('URGENT', _danger) else _statusPill(i.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(where, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                i.description,
                style: GoogleFonts.inter(
                    fontSize: 14, color: _black, height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _priorityChip(i.priority),
                const SizedBox(width: 8),
                _statusPill(i.status),
              ],
            ),
            const SizedBox(height: 18),

            if (!_isOpen) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (i.status == 'RESOLVED' ? _warn : _ok).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  i.status == 'RESOLVED'
                      ? 'Marked resolved — awaiting verification.'
                      : 'This ticket is ${_titleCase(i.status)}.',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _black),
                ),
              ),
            ] else if (_showAssign) ...[
              _field('Technician name', _nameCtrl),
              const SizedBox(height: 10),
              _field('Technician phone', _phoneCtrl,
                  keyboard: TextInputType.phone),
              const SizedBox(height: 14),
              _primaryBtn(_busy ? 'Saving…' : 'Save technician',
                  _busy ? null : _doAssign),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => setState(() => _showAssign = false),
                  child: Text('Cancel',
                      style: GoogleFonts.inter(color: _grey)),
                ),
              ),
            ] else ...[
              _outlineBtn(
                i.technicianName == null || i.technicianName!.isEmpty
                    ? 'Assign technician'
                    : 'Change technician',
                Icons.engineering_rounded,
                _busy ? null : () => setState(() => _showAssign = true),
              ),
              const SizedBox(height: 16),
              Text('RESOLUTION PROOF  ·  optional',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _grey,
                    letterSpacing: 1.0,
                  )),
              const SizedBox(height: 6),
              Text('Add photos of the completed work — the ops head sees these.',
                  style: GoogleFonts.inter(fontSize: 12, color: _grey)),
              const SizedBox(height: 10),
              _photoStrip(),
              const SizedBox(height: 14),
              _primaryBtn(_busy ? 'Please wait…' : 'Mark resolved',
                  _busy ? null : _doResolve),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoStrip() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int idx = 0; idx < _photos.length; idx++)
          _thumb(_photos[idx], idx),
        _addPhotoTile(
            Icons.camera_alt_rounded, () => _pickPhoto(ImageSource.camera)),
        _addPhotoTile(
            Icons.photo_library_rounded, () => _pickPhoto(ImageSource.gallery)),
      ],
    );
  }

  Widget _thumb(File f, int idx) {
    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(f, width: 68, height: 68, fit: BoxFit.cover),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: _busy ? null : () => setState(() => _photos.removeAt(idx)),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _black.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 12, color: _white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addPhotoTile(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: _busy
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap();
            },
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Icon(icon, size: 20, color: _grey),
      ),
    );
  }

  Widget _field(String hint, TextEditingController c,
      {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      style: GoogleFonts.inter(fontSize: 15, color: _black),
      cursorColor: _black,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _grey, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _red, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _primaryBtn(String label, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: onTap == null ? _grey : _black,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _outlineBtn(String label, IconData icon, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _black),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _black),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Small shared bits ────────────────────────────────────────────────────────
String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

String _clock(DateTime? dt) {
  if (dt == null) return '--:--';
  final h = dt.hour;
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = h >= 12 ? 'PM' : 'AM';
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh:$m $ampm';
}

Widget _tag(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );

Widget _statusPill(String status) {
  final c = switch (status) {
    'RAISED' => _warn,
    'ASSIGNED' => _blue,
    'RESOLVED' => _ok,
    'CLOSED' => _grey,
    'DISPUTED' => _danger,
    _ => _grey,
  };
  return _tag(status, c);
}

Widget _priorityChip(String p) {
  final c = switch (p.toLowerCase()) {
    'high' => _danger,
    'medium' => _warn,
    _ => _grey,
  };
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.flag_rounded, size: 13, color: c),
      const SizedBox(width: 4),
      Text(
        _titleCase(p),
        style: GoogleFonts.inter(
            fontSize: 11.5, fontWeight: FontWeight.w700, color: c),
      ),
    ],
  );
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F3),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.task_alt_rounded, size: 40, color: _grey),
            const SizedBox(height: 10),
            Text('No tickets assigned to you',
                style: GoogleFonts.inter(fontSize: 14, color: _grey)),
            const SizedBox(height: 4),
            Text('Pull down to refresh',
                style: GoogleFonts.inter(fontSize: 12, color: _grey)),
          ],
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _danger.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _danger.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: _danger),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: _black)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
