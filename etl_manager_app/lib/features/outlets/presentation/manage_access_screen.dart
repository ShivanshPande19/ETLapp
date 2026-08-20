// lib/features/outlets/presentation/manage_access_screen.dart
//
// Owner-only screen to manage who can access ONE outlet: list the linked
// managers, invite a limited co-manager (by name + email), and revoke access.
// The backend enforces that only an OWNER (or ETL manager) can reach these
// endpoints; this screen is additionally shown only to owners.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../data/outlets_repository.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _accent = Color(0xFFDEFF9A);
const _danger = Color(0xFFEF4444);
const _card = Color(0xFF141414);

class ManageAccessScreen extends ConsumerStatefulWidget {
  final int outletId;
  final String outletName;
  const ManageAccessScreen({
    super.key,
    required this.outletId,
    required this.outletName,
  });

  @override
  ConsumerState<ManageAccessScreen> createState() => _ManageAccessScreenState();
}

class _ManageAccessScreenState extends ConsumerState<ManageAccessScreen> {
  bool _loading = true;
  String? _error;
  List<OutletManager> _managers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await ref.read(outletsRepositoryProvider).listManagers(widget.outletId);
      if (!mounted) return;
      setState(() {
        _managers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load managers. Pull to refresh.';
        _loading = false;
      });
    }
  }

  String _err(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['detail'] is String) return d['detail'] as String;
      if (e.response?.statusCode == 409) return 'That person already has access.';
    }
    return 'Something went wrong. Try again.';
  }

  Future<void> _remove(OutletManager m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Remove access?',
            style: GoogleFonts.inter(color: _white, fontWeight: FontWeight.w700)),
        content: Text(
          '${m.name} will lose access to ${widget.outletName}. This does not delete their account.',
          style: GoogleFonts.inter(color: _grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: _grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: GoogleFonts.inter(color: _danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(outletsRepositoryProvider)
          .removeManager(widget.outletId, m.managerId);
      HapticFeedback.mediumImpact();
      await _load();
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _addDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Add manager',
            style: GoogleFonts.inter(color: _white, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(nameCtrl, 'Full name'),
            const SizedBox(height: 10),
            _field(emailCtrl, 'Email', keyboard: TextInputType.emailAddress),
            const SizedBox(height: 6),
            Text(
              'They get manager access to this outlet only, and cannot manage access themselves.',
              style: GoogleFonts.inter(color: _grey, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: _grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Add', style: GoogleFonts.inter(color: _accent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (added != true) return;
    final name = nameCtrl.text.trim();
    final email = emailCtrl.text.trim();
    if (name.isEmpty || !email.contains('@')) {
      _snack('Enter a valid name and email.');
      return;
    }
    try {
      final res = await ref
          .read(outletsRepositoryProvider)
          .addManager(widget.outletId, name: name, email: email);
      HapticFeedback.mediumImpact();
      await _load();
      final link = res['set_password_link'] as String?;
      final emailSent = res['email_sent'] == true;
      if (link != null && !emailSent) {
        // Email not delivered (e.g. Resend off) — surface the link to share.
        _showLink(link);
      } else {
        _snack('Manager added.');
      }
    } catch (e) {
      _snack(_err(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showLink(String link) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Share set-password link',
            style: GoogleFonts.inter(color: _white, fontWeight: FontWeight.w700, fontSize: 15)),
        content: SelectableText(link,
            style: GoogleFonts.inter(color: _grey, fontSize: 11)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(ctx);
              _snack('Link copied.');
            },
            child: Text('Copy', style: GoogleFonts.inter(color: _accent, fontWeight: FontWeight.w700)),
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
      style: GoogleFonts.inter(color: _white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _grey),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: Text('Manage Access',
            style: GoogleFonts.inter(color: _white, fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDialog,
        backgroundColor: _accent,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF0A0A0A)),
        label: Text('Add manager',
            style: GoogleFonts.inter(color: const Color(0xFF0A0A0A), fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _white,
        backgroundColor: _card,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(widget.outletName.toUpperCase(),
                  style: GoogleFonts.inter(color: _grey, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: _white)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: Text(_error!, style: GoogleFonts.inter(color: _grey))),
              )
            else
              ..._managers.map(_tile),
          ],
        ),
      ),
    );
  }

  Widget _tile(OutletManager m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.08),
            child: Text(
              (m.name.isNotEmpty ? m.name[0] : '?').toUpperCase(),
              style: GoogleFonts.inter(color: _white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    style: GoogleFonts.inter(color: _white, fontWeight: FontWeight.w700, fontSize: 14)),
                Text(m.email,
                    style: GoogleFonts.inter(color: _grey, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: (m.isOwner ? _accent : _grey).withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              m.isOwner ? 'Owner' : 'Manager',
              style: GoogleFonts.inter(
                color: m.isOwner ? _accent : _grey,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Owners cannot be removed here; only limited co-managers show a remove.
          if (!m.isOwner)
            IconButton(
              onPressed: () => _remove(m),
              icon: const Icon(Icons.remove_circle_outline_rounded, color: _danger, size: 22),
              tooltip: 'Remove access',
            ),
        ],
      ),
    );
  }
}
