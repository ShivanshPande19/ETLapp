// lib/features/maintenance/presentation/ops_maintenance.dart
//
// ROLE SPLIT — Crownest Ops Head tooling:
//   • OpsRaiseTicketScreen — raise a general (court/zone) or outlet-specific
//     maintenance ticket, choose target team(s), mention people, mark urgent.
//   • OpsRouteSheet — triage/route an existing ticket (set target team(s) +
//     mentions + urgent).
//
// Uses the app's dark Material theme directly (themed AppBar / inputs / buttons)
// so it stays native without bespoke styling.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../courts/domain/courts_notifier.dart';
import '../domain/maintenance_notifier.dart';

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

// ══════════════════════════════════════════════════════════════════════════════
// Raise screen
// ══════════════════════════════════════════════════════════════════════════════
Future<void> openOpsRaise(BuildContext context) => Navigator.of(context,
        rootNavigator: true)
    .push(MaterialPageRoute(builder: (_) => const OpsRaiseTicketScreen()));

class OpsRaiseTicketScreen extends ConsumerStatefulWidget {
  const OpsRaiseTicketScreen({super.key});
  @override
  ConsumerState<OpsRaiseTicketScreen> createState() => _OpsRaiseTicketScreenState();
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
  bool _busy = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _submit() async {
    final desc = _descCtrl.text.trim();
    if (desc.length < 5) {
      _snack('Please add a description (min 5 characters).');
      return;
    }
    if (_scope == 'general' && _courtId == null) {
      _snack('Select a zone (court).');
      return;
    }
    if (_scope == 'outlet' && _outletId == null) {
      _snack('Select an outlet.');
      return;
    }
    if (_targets.isEmpty) {
      _snack('Choose at least one team to assign.');
      return;
    }
    setState(() => _busy = true);
    final err = await ref.read(maintenanceNotifierProvider.notifier).raiseTicketAsOps(
          issueType: _issueType,
          priority: _priority,
          description: desc,
          scope: _scope,
          courtId: _scope == 'general' ? _courtId : null,
          outletId: _scope == 'outlet' ? _outletId : null,
          targetTeams: _targets.toList(),
          mentions: _mentionPayload(_mentions),
          isUrgent: _urgent,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      _snack('Ticket raised.');
      Navigator.of(context).pop();
    } else {
      _snack(err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final courtsAsync = ref.watch(courtsNotifierProvider);
    final outletsAsync = ref.watch(opsOutletsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Raise Maintenance Ticket')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          _label('Scope'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'general', label: Text('General (Zone)')),
              ButtonSegment(value: 'outlet', label: Text('Outlet')),
            ],
            selected: {_scope},
            onSelectionChanged: (s) => setState(() {
              _scope = s.first;
              _outletId = null;
            }),
          ),
          const SizedBox(height: 18),

          // Zone (court) — always needed (drives outlet filter too).
          _label('Zone (court)'),
          courtsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load courts', style: _err()),
            data: (courts) => DropdownButtonFormField<int>(
              initialValue: _courtId,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Select a zone'),
              items: [
                for (final c in courts)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() {
                _courtId = v;
                _outletId = null;
              }),
            ),
          ),
          const SizedBox(height: 14),

          // Outlet picker (outlet scope only), filtered by the chosen zone.
          if (_scope == 'outlet') ...[
            _label('Outlet'),
            outletsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load outlets', style: _err()),
              data: (outlets) {
                final filtered = _courtId == null
                    ? const <OutletLite>[]
                    : outlets.where((o) => o.courtId == _courtId).toList();
                return DropdownButtonFormField<int>(
                  initialValue: _outletId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    hintText: _courtId == null
                        ? 'Pick a zone first'
                        : (filtered.isEmpty ? 'No outlets in this zone' : 'Select an outlet'),
                  ),
                  items: [
                    for (final o in filtered)
                      DropdownMenuItem(value: o.id, child: Text(o.name)),
                  ],
                  onChanged: filtered.isEmpty
                      ? null
                      : (v) => setState(() => _outletId = v),
                );
              },
            ),
            const SizedBox(height: 14),
          ],

          _label('Issue type'),
          DropdownButtonFormField<String>(
            initialValue: _issueType,
            isExpanded: true,
            items: [
              for (final t in _issueTypes)
                DropdownMenuItem(value: t.$1, child: Text(t.$2)),
            ],
            onChanged: (v) => setState(() => _issueType = v ?? 'other'),
          ),
          const SizedBox(height: 14),

          _label('Priority'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'low', label: Text('Low')),
              ButtonSegment(value: 'medium', label: Text('Medium')),
              ButtonSegment(value: 'high', label: Text('High')),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mark as urgent'),
            subtitle: Text('Notifies mentioned teams immediately',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
            value: _urgent,
            onChanged: (v) => setState(() => _urgent = v),
          ),
          const SizedBox(height: 8),

          _label('Description'),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Describe the issue / work needed…',
            ),
          ),
          const SizedBox(height: 18),

          _label('Assign to team(s)'),
          for (final t in _targetTeams)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.$2),
              value: _targets.contains(t.$1),
              onChanged: (v) => setState(() =>
                  v == true ? _targets.add(t.$1) : _targets.remove(t.$1)),
            ),
          const SizedBox(height: 12),

          _label('Also notify (mentions)'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in _mentionRoles)
                FilterChip(
                  label: Text(r.$2),
                  selected: _mentions.contains(r.$1),
                  onSelected: (sel) => setState(() =>
                      sel ? _mentions.add(r.$1) : _mentions.remove(r.$1)),
                ),
            ],
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_busy ? 'Raising…' : 'Raise ticket'),
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Text(s,
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      );

  TextStyle _err() => GoogleFonts.inter(color: AppTheme.danger, fontSize: 13);
}

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one team.')),
      );
      return;
    }
    setState(() => _busy = true);
    final err = await ref.read(maintenanceNotifierProvider.notifier).routeTicket(
          widget.issue.id,
          targetTeams: _targets.toList(),
          mentions: _mentionPayload(_mentions),
          isUrgent: _urgent,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Ticket routed.')),
    );
    if (err == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Route ticket #${widget.issue.id}',
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text('Assign the team(s) that will handle this.',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),
            for (final t in _targetTeams)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(t.$2, style: const TextStyle(color: AppTheme.textPrimary)),
                value: _targets.contains(t.$1),
                onChanged: (v) => setState(() =>
                    v == true ? _targets.add(t.$1) : _targets.remove(t.$1)),
              ),
            const SizedBox(height: 8),
            Text('Also notify',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in _mentionRoles)
                  FilterChip(
                    label: Text(r.$2),
                    selected: _mentions.contains(r.$1),
                    onSelected: (sel) => setState(() =>
                        sel ? _mentions.add(r.$1) : _mentions.remove(r.$1)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Urgent', style: TextStyle(color: AppTheme.textPrimary)),
              value: _urgent,
              onChanged: (v) => setState(() => _urgent = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Routing…' : 'Save routing'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
