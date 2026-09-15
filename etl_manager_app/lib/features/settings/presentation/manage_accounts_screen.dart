// lib/features/settings/presentation/manage_accounts_screen.dart
//
// Management-only screen to administer EVERY ETL-side role introduced by the
// role split: the three management roles (Azimuth Management, Crownest Ops
// Head, Crownest Head) and the two maintenance roles (Azimuth Maintenance,
// Crownest Maintenance Head). Management roles land in the managers table;
// maintenance roles land in the staff table — this screen hides that split
// behind a single /managers/accounts API.
//
// You list every account, invite a new one (by name + email + role — the
// backend emails a set-password link, so no password is handled here) and
// revoke / restore access. Crownest Maintenance Head additionally needs a zone
// (court) because it logs attendance and shows up in that court's roster.
//
// The backend gates every endpoint behind require_management; this screen is
// only reachable by management roles from Settings. UI matches the app theme
// (dark header + white sheet + light cards + red brand accent + AntonSC title),
// mirroring ManageEtlManagersScreen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../../core/widgets/skeleton.dart';
import '../../courts/domain/courts_notifier.dart';
import '../../courts/data/courts_repository.dart';
import '../data/etl_managers_repository.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128); // ETL brand red
const _danger = Color(0xFFEF4444);

/// A creatable role, with the copy this screen shows for it.
class _RoleOption {
  final String value; // backend role key
  final String label; // human label
  final String tier; // 'management' | 'maintenance'
  final bool needsZone; // true => a court must be picked
  final String hint; // one-line description shown in the add sheet

  const _RoleOption(
    this.value,
    this.label,
    this.tier, {
    this.needsZone = false,
    required this.hint,
  });
}

const List<_RoleOption> _roleOptions = [
  _RoleOption(
    'azimuth_management',
    'Azimuth Management',
    'management',
    hint: 'Full management access across Azimuth & Crownest.',
  ),
  _RoleOption(
    'crownest_ops_head',
    'Crownest Ops Head',
    'management',
    hint: 'Full management access. Runs day-to-day Crownest operations.',
  ),
  _RoleOption(
    'crownest_head',
    'Crownest Head',
    'management',
    hint: 'Full management access. Owns the Crownest org.',
  ),
  _RoleOption(
    'azimuth_maintenance',
    'Azimuth Maintenance',
    'maintenance',
    hint: 'Maintenance worker — a tickets-only view. No management access.',
  ),
  _RoleOption(
    'crownest_maintenance_head',
    'Crownest Maintenance Head',
    'maintenance',
    needsZone: true,
    hint: 'Maintenance head — logs attendance and appears in its zone roster.',
  ),
];

_RoleOption? _roleFor(String value) {
  for (final r in _roleOptions) {
    if (r.value == value) return r;
  }
  return null;
}

class ManageAccountsScreen extends ConsumerStatefulWidget {
  const ManageAccountsScreen({super.key});

  @override
  ConsumerState<ManageAccountsScreen> createState() =>
      _ManageAccountsScreenState();
}

class _ManageAccountsScreenState extends ConsumerState<ManageAccountsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool _loading = true;
  String? _error;
  List<Account> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(etlManagersRepositoryProvider).listAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load accounts. Pull to refresh.';
        _loading = false;
      });
    }
  }

  String _err(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['detail'] is String) return d['detail'] as String;
      if (e.response?.statusCode == 409) return 'That email is already in use.';
    }
    return 'Something went wrong. Try again.';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _black,
      ),
    );
  }

  Future<void> _addSheet() async {
    // Warm the courts list so the zone picker has data ready.
    ref.read(courtsNotifierProvider);

    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String? selectedRole;
    int? selectedCourtId;
    bool loading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final role = selectedRole == null ? null : _roleFor(selectedRole!);
          final needsZone = role?.needsZone ?? false;

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
              decoration: const BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
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
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Add Account',
                        style:
                            GoogleFonts.antonSc(fontSize: 22, color: _black)),
                    const SizedBox(height: 4),
                    Text('Pick a role. We email a set-password link.',
                        style: GoogleFonts.inter(fontSize: 13, color: _grey)),
                    const SizedBox(height: 20),
                    _field(nameCtrl, 'Full name'),
                    const SizedBox(height: 12),
                    _field(emailCtrl, 'Email',
                        keyboard: TextInputType.emailAddress),
                    const SizedBox(height: 20),

                    // ─── Role picker ───
                    Text('ROLE',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _grey,
                          letterSpacing: 1.0,
                        )),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _roleOptions.map((r) {
                        final active = r.value == selectedRole;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setSheet(() {
                              selectedRole = r.value;
                              if (!r.needsZone) selectedCourtId = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: active ? _black : _white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color:
                                    active ? _black : Colors.grey.shade300,
                                width: 1.5,
                              ),
                            ),
                            child: Text(r.label,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: active ? _white : _grey,
                                )),
                          ),
                        );
                      }).toList(),
                    ),

                    // ─── Zone picker (crownest_maintenance_head only) ───
                    if (needsZone) ...[
                      const SizedBox(height: 18),
                      Text('ZONE',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _grey,
                            letterSpacing: 1.0,
                          )),
                      const SizedBox(height: 10),
                      _ZonePicker(
                        selectedCourtId: selectedCourtId,
                        onSelected: (id) =>
                            setSheet(() => selectedCourtId = id),
                      ),
                    ],

                    // ─── Contextual hint ───
                    if (role != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              role.tier == 'management'
                                  ? Icons.shield_rounded
                                  : Icons.build_rounded,
                              size: 15,
                              color: _grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${role.hint} No password is set here — they '
                                'set their own via the emailed link.',
                                style: GoogleFonts.inter(
                                    color: _grey, fontSize: 11, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: loading
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final email = emailCtrl.text.trim();
                              if (name.isEmpty || !email.contains('@')) {
                                _snack('Enter a valid name and email.');
                                return;
                              }
                              if (selectedRole == null) {
                                _snack('Pick a role.');
                                return;
                              }
                              if (needsZone && selectedCourtId == null) {
                                _snack('Pick a zone for the maintenance head.');
                                return;
                              }
                              setSheet(() => loading = true);
                              try {
                                final res = await ref
                                    .read(etlManagersRepositoryProvider)
                                    .createAccount(
                                      name: name,
                                      email: email,
                                      role: selectedRole!,
                                      courtId:
                                          needsZone ? selectedCourtId : null,
                                    );
                                HapticFeedback.mediumImpact();
                                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                                await _load();
                                final link =
                                    res['set_password_link'] as String?;
                                final emailSent = res['email_sent'] == true;
                                if (link != null && !emailSent) {
                                  _showLink(link);
                                } else {
                                  _snack('Account added. Set-password email '
                                      'sent.');
                                }
                              } catch (e) {
                                setSheet(() => loading = false);
                                _snack(_err(e));
                              }
                            },
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: loading ? _grey : _black,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: _white, strokeWidth: 2),
                              )
                            : Text('Add Account',
                                style: GoogleFonts.inter(
                                    color: _white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deactivate(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Revoke access?',
            style:
                GoogleFonts.inter(color: _black, fontWeight: FontWeight.w800)),
        content: Text(
          '${a.name} will lose access and be signed out. You can restore '
          'their access later. This does not delete their account.',
          style: GoogleFonts.inter(color: _grey, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(
                    color: _grey, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Revoke',
                style: GoogleFonts.inter(
                    color: _danger, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(etlManagersRepositoryProvider)
          .deactivateAccount(a.kind, a.accountId);
      HapticFeedback.mediumImpact();
      await _load();
      _snack('Access revoked.');
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _reactivate(Account a) async {
    try {
      await ref
          .read(etlManagersRepositoryProvider)
          .reactivateAccount(a.kind, a.accountId);
      HapticFeedback.mediumImpact();
      await _load();
      _snack('Access restored.');
    } catch (e) {
      _snack(_err(e));
    }
  }

  void _showLink(String link) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Share set-password link',
            style: GoogleFonts.inter(
                color: _black, fontWeight: FontWeight.w800, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The email couldn\'t be sent. Copy this link and share it so '
              'they can set their password.',
              style: GoogleFonts.inter(color: _grey, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(link,
                  style: GoogleFonts.inter(color: _black, fontSize: 11)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(ctx);
              _snack('Link copied.');
            },
            child: Text('Copy link',
                style: GoogleFonts.inter(
                    color: _red, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      style: GoogleFonts.inter(color: _black, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _grey),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final management =
        _accounts.where((a) => a.kind == 'manager').toList(growable: false);
    final maintenance =
        _accounts.where((a) => a.kind == 'staff').toList(growable: false);

    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: _loading
          ? null
          : GestureDetector(
              onTap: _addSheet,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  color: _black,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_add_rounded,
                        color: _white, size: 18),
                    const SizedBox(width: 8),
                    Text('Add Account',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _white,
                        )),
                  ],
                ),
              ),
            ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ───
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
                            fontSize: 36, height: 0.95, letterSpacing: -0.5),
                        children: const [
                          TextSpan(text: 'A', style: TextStyle(color: _red)),
                          TextSpan(
                              text: 'CCOUNTS',
                              style: TextStyle(color: _white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.groups_rounded,
                            size: 13, color: _grey),
                        const SizedBox(width: 6),
                        Text('Management & maintenance logins',
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

              // ─── White sheet ───
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: _loading
                      ? const SkeletonList(
                          dark: false, count: 5, tileHeight: 76)
                      : _error != null
                          ? Center(
                              child: Text(_error!,
                                  style: GoogleFonts.inter(color: _grey)))
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: _black,
                              backgroundColor: _white,
                              child: ListView(
                                padding: EdgeInsets.fromLTRB(
                                  20,
                                  22,
                                  20,
                                  MediaQuery.of(context).padding.bottom + 100,
                                ),
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                children: [
                                  _section('MANAGEMENT', management,
                                      'No management accounts yet.'),
                                  const SizedBox(height: 26),
                                  _section('MAINTENANCE', maintenance,
                                      'No maintenance accounts yet.'),
                                ],
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

  Widget _section(String title, List<Account> items, String emptyMsg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _grey,
              letterSpacing: 1.0,
            )),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(emptyMsg,
                style: GoogleFonts.inter(color: _grey, fontSize: 13)),
          )
        else
          ...items.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _tile(a),
            ),
          ),
      ],
    );
  }

  Widget _tile(Account a) {
    final active = a.isActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: (active ? _red : _grey).withOpacity(0.08),
            child: Text(
              (a.name.isNotEmpty ? a.name[0] : '?').toUpperCase(),
              style: GoogleFonts.inter(
                  color: active ? _red : _grey, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(a.name.isEmpty ? 'Unnamed' : a.name,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: _black,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                    if (a.isSelf)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('(you)',
                            style:
                                GoogleFonts.inter(color: _grey, fontSize: 11)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(a.email,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: _grey, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _rolePill(a.roleLabel),
                    if (a.zoneName != null && a.zoneName!.isNotEmpty)
                      _zonePill(a.zoneName!),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _grey.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('Revoked',
                  style: GoogleFonts.inter(
                      color: _grey, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          // The caller can neither revoke nor restore their own row.
          if (!a.isSelf)
            active
                ? IconButton(
                    onPressed: () => _deactivate(a),
                    icon: const Icon(Icons.remove_circle_outline_rounded,
                        color: _danger, size: 22),
                    tooltip: 'Revoke access',
                  )
                : Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: TextButton(
                      onPressed: () => _reactivate(a),
                      child: Text('Restore',
                          style: GoogleFonts.inter(
                              color: _red, fontWeight: FontWeight.w800)),
                    ),
                  ),
        ],
      ),
    );
  }

  Widget _rolePill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              color: _red, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }

  Widget _zonePill(String zone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stadium_rounded, size: 11, color: _grey),
          const SizedBox(width: 4),
          Text(zone,
              style: GoogleFonts.inter(
                  color: _grey, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Zone (court) chooser used inside the add sheet — only shown for
/// crownest_maintenance_head. Watches the courts provider so it reflects
/// loading / error / empty states cleanly.
class _ZonePicker extends ConsumerWidget {
  final int? selectedCourtId;
  final ValueChanged<int> onSelected;

  const _ZonePicker({
    required this.selectedCourtId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtsAsync = ref.watch(courtsNotifierProvider);
    return courtsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _grey),
        ),
      ),
      error: (_, __) => Text('Could not load zones.',
          style: GoogleFonts.inter(color: _danger, fontSize: 12)),
      data: (courts) {
        if (courts.isEmpty) {
          return Text('No zones (courts) exist yet. Create one first.',
              style: GoogleFonts.inter(color: _grey, fontSize: 12));
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: courts.map((Court c) {
            final active = c.id == selectedCourtId;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(c.id);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? _red : _white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? _red : Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                child: Text(c.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active ? _white : _grey,
                    )),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
