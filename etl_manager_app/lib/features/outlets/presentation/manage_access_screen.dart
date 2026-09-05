// lib/features/outlets/presentation/manage_access_screen.dart
//
// Owner-only screen to manage who can access ONE outlet: list the linked
// managers, invite a limited co-manager (by name + email), and revoke access.
// The backend enforces that only an OWNER (or ETL manager) can reach these
// endpoints; this screen is additionally shown only to owners.
//
// UI matches the app theme (dark header + white sheet + light cards + red
// brand accent + AntonSC titles) — mirrors OutletStaffManagementScreen. The
// access LOGIC (list / add / remove via outletsRepository) is unchanged.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import '../../../core/widgets/skeleton.dart';

import '../data/outlets_repository.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);
const _danger = Color(0xFFEF4444);

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

class _ManageAccessScreenState extends ConsumerState<ManageAccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool _loading = true;
  String? _error;
  List<OutletManager> _managers = const [];

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
      final list = await ref
          .read(outletsRepositoryProvider)
          .listManagers(widget.outletId);
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _black,
      ),
    );
  }

  Future<void> _remove(OutletManager m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove access?',
            style: GoogleFonts.inter(color: _black, fontWeight: FontWeight.w800)),
        content: Text(
          '${m.name} will lose access to ${widget.outletName}. This does not delete their account.',
          style: GoogleFonts.inter(color: _grey, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: _grey, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: GoogleFonts.inter(color: _danger, fontWeight: FontWeight.w800)),
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
      _snack('Access removed.');
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _addSheet() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    bool loading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                  Text('Add Manager',
                      style: GoogleFonts.antonSc(fontSize: 22, color: _black)),
                  const SizedBox(height: 4),
                  Text('Give someone manager access to ${widget.outletName}.',
                      style: GoogleFonts.inter(fontSize: 13, color: _grey)),
                  const SizedBox(height: 20),
                  _field(nameCtrl, 'Full name'),
                  const SizedBox(height: 12),
                  _field(emailCtrl, 'Email',
                      keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 15, color: _grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'They get manager access to THIS outlet only, and cannot manage access themselves.',
                            style: GoogleFonts.inter(
                                color: _grey, fontSize: 11, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                            setSheet(() => loading = true);
                            try {
                              final res = await ref
                                  .read(outletsRepositoryProvider)
                                  .addManager(widget.outletId,
                                      name: name, email: email);
                              HapticFeedback.mediumImpact();
                              if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                              await _load();
                              final link = res['set_password_link'] as String?;
                              final emailSent = res['email_sent'] == true;
                              if (link != null && !emailSent) {
                                _showLink(link);
                              } else {
                                _snack('Manager added.');
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
                          : Text('Add Manager',
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
        ),
      ),
    );
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
              'The email couldn\'t be sent. Copy this link and share it so they can set their password.',
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
                style: GoogleFonts.inter(color: _red, fontWeight: FontWeight.w800)),
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
                    Text('Add Manager',
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
                              text: 'CCESS', style: TextStyle(color: _white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            size: 13, color: _grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(widget.outletName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _white.withOpacity(0.45),
                                fontWeight: FontWeight.w500,
                              )),
                        ),
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
                      ? const SkeletonList(dark: false, count: 4, tileHeight: 76)
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
                                  Text('People with access',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _grey,
                                        letterSpacing: 0.3,
                                      )),
                                  const SizedBox(height: 14),
                                  ..._managers.map(
                                    (m) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _tile(m),
                                    ),
                                  ),
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

  Widget _tile(OutletManager m) {
    final isOwner = m.isOwner;
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
            backgroundColor: (isOwner ? _red : _black).withOpacity(0.08),
            child: Text(
              (m.name.isNotEmpty ? m.name[0] : '?').toUpperCase(),
              style: GoogleFonts.inter(
                  color: isOwner ? _red : _black, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name.isEmpty ? 'Unnamed' : m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        color: _black,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(m.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: _grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (isOwner ? _red : _grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isOwner ? 'Owner' : 'Manager',
              style: GoogleFonts.inter(
                color: isOwner ? _red : _grey,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // Owners can't be removed here; only limited co-managers show remove.
          if (!isOwner) ...[
            const SizedBox(width: 2),
            IconButton(
              onPressed: () => _remove(m),
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: _danger, size: 22),
              tooltip: 'Remove access',
            ),
          ],
        ],
      ),
    );
  }
}
