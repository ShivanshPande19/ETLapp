// lib/features/maintenance/presentation/ops_maintenance.dart
//
// ROLE SPLIT — Crownest Ops Head tooling:
//   • OpsRaiseTicketScreen — raise a general (court/zone) or outlet-specific
//     maintenance ticket, choose target team(s), mention people, mark urgent.
//   • OpsRouteSheet — triage/route an existing ticket (set target team(s) +
//     mentions + urgent).
//
// UI matches the app theme (dark header + white canvas + red brand accent +
// AntonSC titles + custom chips/toggles), mirroring the outlet raise sheet and
// ManageAccountsScreen — deliberately NOT the raw Material theme.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../courts/domain/courts_notifier.dart';
import '../domain/maintenance_notifier.dart';

// ─── Palette (matches the app theme) ──────────────────────────────────────────
const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _brand = Color(0xFFD02128); // ETL brand red
const _danger = Color(0xFFEF4444);
const _field = Color(0xFFF5F5F5);

// ─── Reference data ───────────────────────────────────────────────────────────
const _targetTeams = <(String, String)>[
  ('azimuth_maintenance', 'Azimuth Maintenance'),
  ('crownest_maintenance_head', 'Crownest Maintenance Head'),
];
const _mentionRoles = <(String, String)>[
  ('azimuth_management', 'Azimuth Management'),
  ('crownest_head', 'Crownest Head'),
  ('azimuth_maintenance', 'Azimuth Maintenance'),
  ('crownest_maintenance_head', 'Crownest Maintenance Head'),
];
const _issueTypes = <(String, String)>[
  ('electrical', '⚡ Electrical'),
  ('plumbing', '🔧 Plumbing'),
  ('furniture', '🪑 Furniture'),
  ('cleaning', '🧹 Deep Clean'),
  ('other', '📋 Other'),
];

// ─── Lightweight outlet list (for the outlet picker) ──────────────────────────
class OutletLite {
  final int id;
  final String name;
  final int courtId;
  const OutletLite({required this.id, required this.name, required this.courtId});
}

final opsOutletsProvider = FutureProvider.autoDispose<List<OutletLite>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get('/outlets/');
  final list = (res.data as List?) ?? [];
  return list
      .map((o) => OutletLite(
            id: (o['id'] ?? 0) as int,
            name: (o['vendor_name'] ?? 'Outlet').toString(),
            courtId: (o['court_id'] ?? 0) as int,
          ))
      .toList();
});

List<Map<String, String>> _mentionPayload(Set<String> roles) =>
    roles.map((r) => {'kind': 'role', 'value': r}).toList();

// ─── Shared themed widgets ────────────────────────────────────────────────────

Widget _sectionLabel(String t) => Text(
      t,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: _grey,
        letterSpacing: 1.0,
      ),
    );

/// A pill chip. Selected = solid black; unselected = light grey fill. Set
/// [showCheck] for multi-select chips (shows a tick when selected).
Widget _chip({
  required String label,
  required bool selected,
  required VoidCallback onTap,
  bool showCheck = false,
}) {
  return GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      onTap();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? _black : _field,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showCheck && selected) ...[
            const Icon(Icons.check_rounded, size: 14, color: _white),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _white : _black,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The "Mark as urgent" toggle card (shared by the raise screen + route sheet).
Widget _urgentCard(bool on, VoidCallback onTap) {
  return GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      onTap();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: on ? _danger.withOpacity(0.08) : _field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: on ? _danger.withOpacity(0.5) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 18, color: on ? _danger : _grey),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mark as urgent',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: on ? _danger : _black)),
                const SizedBox(height: 2),
                Text('Notifies the mentioned teams immediately',
                    style: GoogleFonts.inter(fontSize: 11.5, color: _grey)),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: on ? _danger : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  color: _white, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _submitBtn(String label, bool busy, VoidCallback? onTap) {
  return GestureDetector(
    onTap: busy ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: busy ? _grey : _black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: _white, strokeWidth: 2),
              )
            : Text(label,
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _white)),
      ),
    ),
  );
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg,
          style: GoogleFonts.inter(color: _white, fontWeight: FontWeight.w600)),
      backgroundColor: _black,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Raise screen
// ══════════════════════════════════════════════════════════════════════════════
Future<void> openOpsRaise(BuildContext context) =>
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const OpsRaiseTicketScreen()));

class OpsRaiseTicketScreen extends ConsumerStatefulWidget {
  const OpsRaiseTicketScreen({super.key});
  @override
  ConsumerState<OpsRaiseTicketScreen> createState() =>
      _OpsRaiseTicketScreenState();
}

class _OpsRaiseTicketScreenState extends ConsumerState<OpsRaiseTicketScreen> {
  String _scope = 'general'; // 'general' | 'outlet'
  String _issueType = 'other';
  String _priority = 'medium';
  bool _urgent = false;
  int? _courtId;
  int? _outletId;
  final _targets = <String>{};
  final _mentions = <String>{};
  final _descCtrl = TextEditingController();
  File? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, imageQuality: 80, maxWidth: 1280);
    if (x != null && mounted) setState(() => _photo = File(x.path));
  }

  Future<void> _submit() async {
    final desc = _descCtrl.text.trim();
    if (desc.length < 5) {
      _snack(context, 'Please add a description (min 5 characters).');
      return;
    }
    if (_scope == 'general' && _courtId == null) {
      _snack(context, 'Select a zone (court).');
      return;
    }
    if (_scope == 'outlet' && _outletId == null) {
      _snack(context, 'Select an outlet.');
      return;
    }
    if (_targets.isEmpty) {
      _snack(context, 'Choose at least one team to assign.');
      return;
    }
    setState(() => _busy = true);
    final err =
        await ref.read(maintenanceNotifierProvider.notifier).raiseTicketAsOps(
              issueType: _issueType,
              priority: _priority,
              description: desc,
              scope: _scope,
              courtId: _scope == 'general' ? _courtId : null,
              outletId: _scope == 'outlet' ? _outletId : null,
              targetTeams: _targets.toList(),
              mentions: _mentionPayload(_mentions),
              isUrgent: _urgent,
              photo: _photo,
            );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      HapticFeedback.heavyImpact();
      _snack(context, 'Ticket raised.');
      Navigator.of(context).pop();
    } else {
      _snack(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final courtsAsync = ref.watch(courtsNotifierProvider);
    final outletsAsync = ref.watch(opsOutletsProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Dark header ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _white.withOpacity(0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.west_rounded,
                              size: 14, color: _white.withOpacity(0.9)),
                          const SizedBox(width: 6),
                          Text('Back',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _white.withOpacity(0.9),
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.antonSc(
                          fontSize: 34, height: 0.95, letterSpacing: -0.5),
                      children: const [
                        TextSpan(text: 'R', style: TextStyle(color: _brand)),
                        TextSpan(
                            text: 'AISE TICKET',
                            style: TextStyle(color: _white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.build_rounded, size: 13, color: _grey),
                      const SizedBox(width: 6),
                      Text('New maintenance ticket',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _white.withOpacity(0.45),
                            fontWeight: FontWeight.w500,
                          )),
                    ],
                  ),
                ],
              ),
            ),

            // ─── White canvas ───
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                      24, 26, 24, MediaQuery.of(context).padding.bottom + 32),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _sectionLabel('SCOPE'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _scopeCard('general', 'Zone', 'Court-wide',
                              Icons.stadium_rounded),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _scopeCard('outlet', 'Outlet', 'One vendor',
                              Icons.storefront_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    _sectionLabel('ZONE'),
                    const SizedBox(height: 10),
                    courtsAsync.when(
                      loading: () => _loader(),
                      error: (_, __) => _errText('Could not load zones.'),
                      data: (courts) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in courts)
                            _chip(
                              label: c.name,
                              selected: _courtId == c.id,
                              onTap: () => setState(() {
                                _courtId = c.id;
                                _outletId = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    if (_scope == 'outlet') ...[
                      _sectionLabel('OUTLET'),
                      const SizedBox(height: 10),
                      outletsAsync.when(
                        loading: () => _loader(),
                        error: (_, __) => _errText('Could not load outlets.'),
                        data: (outlets) {
                          if (_courtId == null) {
                            return _hintText('Pick a zone first.');
                          }
                          final filtered = outlets
                              .where((o) => o.courtId == _courtId)
                              .toList();
                          if (filtered.isEmpty) {
                            return _hintText('No outlets in this zone.');
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final o in filtered)
                                _chip(
                                  label: o.name,
                                  selected: _outletId == o.id,
                                  onTap: () =>
                                      setState(() => _outletId = o.id),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                    ],

                    _sectionLabel('ISSUE TYPE'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in _issueTypes)
                          _chip(
                            label: t.$2,
                            selected: _issueType == t.$1,
                            onTap: () => setState(() => _issueType = t.$1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    _sectionLabel('PRIORITY'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final p in const ['low', 'medium', 'high'])
                          Expanded(child: _priorityCard(p)),
                      ],
                    ),
                    const SizedBox(height: 22),

                    _urgentCard(_urgent, () => setState(() => _urgent = !_urgent)),
                    const SizedBox(height: 22),

                    _sectionLabel('DESCRIPTION'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 4,
                      maxLength: 1000,
                      style: GoogleFonts.inter(color: _black, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Describe the issue / work needed…',
                        hintStyle: GoogleFonts.inter(color: _grey),
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _black, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    _sectionLabel('PHOTO  ·  optional'),
                    const SizedBox(height: 10),
                    if (_photo == null)
                      Row(
                        children: [
                          _photoBtn(Icons.camera_alt_rounded, 'Camera',
                              () => _pickPhoto(ImageSource.camera)),
                          const SizedBox(width: 10),
                          _photoBtn(Icons.photo_library_rounded, 'Gallery',
                              () => _pickPhoto(ImageSource.gallery)),
                        ],
                      )
                    else
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              _photo!,
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() => _photo = null),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: _black.withOpacity(0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded,
                                    size: 14, color: _white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 22),

                    _sectionLabel('ASSIGN TO TEAM(S)'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in _targetTeams)
                          _chip(
                            label: t.$2,
                            selected: _targets.contains(t.$1),
                            showCheck: true,
                            onTap: () => setState(() => _targets.contains(t.$1)
                                ? _targets.remove(t.$1)
                                : _targets.add(t.$1)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    _sectionLabel('ALSO NOTIFY  ·  optional'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final r in _mentionRoles)
                          _chip(
                            label: r.$2,
                            selected: _mentions.contains(r.$1),
                            showCheck: true,
                            onTap: () => setState(() =>
                                _mentions.contains(r.$1)
                                    ? _mentions.remove(r.$1)
                                    : _mentions.add(r.$1)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    _submitBtn('Raise ticket', _busy, _submit),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeCard(
      String value, String title, String subtitle, IconData icon) {
    final sel = _scope == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _scope = value;
          _outletId = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: sel ? _black : _field,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: sel ? _white : _grey),
            const SizedBox(height: 8),
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: sel ? _white : _black)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: sel ? _white.withOpacity(0.6) : _grey)),
          ],
        ),
      ),
    );
  }

  Widget _priorityCard(String p) {
    final (color, label) = _priorityMeta(p);
    final sel = _priority == p;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _priority = p);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: EdgeInsets.only(right: p != 'high' ? 8 : 0),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? color.withOpacity(0.12) : _field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? color : Colors.transparent, width: 1.5),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_rounded, size: 13, color: sel ? color : _grey),
              const SizedBox(width: 5),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: sel ? color : _grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoBtn(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: _black),
                const SizedBox(width: 8),
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _black)),
              ],
            ),
          ),
        ),
      );
}

(Color, String) _priorityMeta(String p) => switch (p) {
      'high' => (_danger, 'High'),
      'low' => (const Color(0xFF94A3B8), 'Low'),
      _ => (const Color(0xFFF59E0B), 'Medium'),
    };

Widget _loader() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: _grey),
      ),
    );

Widget _errText(String s) =>
    Text(s, style: GoogleFonts.inter(color: _danger, fontSize: 12));

Widget _hintText(String s) =>
    Text(s, style: GoogleFonts.inter(color: _grey, fontSize: 12));

// ══════════════════════════════════════════════════════════════════════════════
// Route / triage sheet
// ══════════════════════════════════════════════════════════════════════════════
void openOpsRoute(BuildContext context, MaintenanceIssueModel issue) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OpsRouteSheet(issue: issue),
  );
}

class OpsRouteSheet extends ConsumerStatefulWidget {
  final MaintenanceIssueModel issue;
  const OpsRouteSheet({super.key, required this.issue});
  @override
  ConsumerState<OpsRouteSheet> createState() => _OpsRouteSheetState();
}

class _OpsRouteSheetState extends ConsumerState<OpsRouteSheet> {
  late final Set<String> _targets = {...widget.issue.targetTeams};
  final _mentions = <String>{};
  late bool _urgent = widget.issue.isUrgent;
  bool _busy = false;

  Future<void> _save() async {
    if (_targets.isEmpty) {
      _snack(context, 'Choose at least one team.');
      return;
    }
    setState(() => _busy = true);
    final err =
        await ref.read(maintenanceNotifierProvider.notifier).routeTicket(
              widget.issue.id,
              targetTeams: _targets.toList(),
              mentions: _mentionPayload(_mentions),
              isUrgent: _urgent,
            );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      HapticFeedback.heavyImpact();
      _snack(context, 'Ticket routed.');
      Navigator.of(context).pop();
    } else {
      _snack(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Route ticket #${widget.issue.id}',
                    style: GoogleFonts.antonSc(fontSize: 24, color: _black)),
                const SizedBox(height: 4),
                Text('Assign the team(s) that will handle this.',
                    style: GoogleFonts.inter(fontSize: 13, color: _grey)),
                const SizedBox(height: 22),
                _sectionLabel('ASSIGN TO TEAM(S)'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in _targetTeams)
                      _chip(
                        label: t.$2,
                        selected: _targets.contains(t.$1),
                        showCheck: true,
                        onTap: () => setState(() => _targets.contains(t.$1)
                            ? _targets.remove(t.$1)
                            : _targets.add(t.$1)),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _sectionLabel('ALSO NOTIFY  ·  optional'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in _mentionRoles)
                      _chip(
                        label: r.$2,
                        selected: _mentions.contains(r.$1),
                        showCheck: true,
                        onTap: () => setState(() => _mentions.contains(r.$1)
                            ? _mentions.remove(r.$1)
                            : _mentions.add(r.$1)),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _urgentCard(_urgent, () => setState(() => _urgent = !_urgent)),
                const SizedBox(height: 26),
                _submitBtn('Save routing', _busy, _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
