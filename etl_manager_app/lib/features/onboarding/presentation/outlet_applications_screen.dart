// lib/features/onboarding/presentation/outlet_applications_screen.dart
//
// ETL manager: review outlet onboarding applications for a court and
// approve (creates outlet + manager + set-password link) or reject them.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/dio_provider.dart'; // baseUrl for document links
import '../data/onboarding_repository.dart';
import '../domain/onboarding_models.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFE5A000);
const _danger = Color(0xFFEF4444);
const _card = Color(0xFFFAFAFA);

Color _statusColor(String s) => switch (s) {
  'approved' => _ok,
  'rejected' => _danger,
  _ => _warn,
};

String _statusLabel(String s) => switch (s) {
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  _ => 'Pending',
};

String _fmtDate(DateTime? d) {
  if (d == null) return '';
  return DateFormat('d MMM, h:mm a').format(d);
}

class OutletApplicationsScreen extends ConsumerStatefulWidget {
  final int courtId;
  final String courtName;
  const OutletApplicationsScreen({
    super.key,
    required this.courtId,
    required this.courtName,
  });

  @override
  ConsumerState<OutletApplicationsScreen> createState() =>
      _OutletApplicationsScreenState();
}

class _OutletApplicationsScreenState
    extends ConsumerState<OutletApplicationsScreen> {
  String _filter = 'pending'; // pending | approved | rejected | all

  Future<void> _refresh() async {
    ref.invalidate(applicationsProvider(widget.courtId));
    await ref.read(applicationsProvider(widget.courtId).future).catchError(
      (_) => ApplicationsData(applications: [], pendingCount: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(applicationsProvider(widget.courtId));

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────
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
                          Icon(Icons.west_rounded, size: 14,
                              color: _white.withOpacity(0.9)),
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
                        TextSpan(text: 'A', style: TextStyle(color: _red)),
                        TextSpan(
                            text: 'PPLICATIONS',
                            style: TextStyle(color: _white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.stadium_rounded, size: 13, color: _grey),
                      const SizedBox(width: 6),
                      Text(widget.courtName,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _white.withOpacity(0.5),
                            fontWeight: FontWeight.w500,
                          )),
                    ],
                  ),
                ],
              ),
            ),

            // ── White canvas ────────────────────────────────────────
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: async.when(
                  loading: () => const SkeletonList(
                    dark: false,
                    count: 5,
                    tileHeight: 76,
                  ),
                  error: (e, _) => _ErrorView(onRetry: _refresh),
                  data: (data) {
                    final filtered = _filter == 'all'
                        ? data.applications
                        : data.applications
                            .where((a) => a.status == _filter)
                            .toList();
                    return RefreshIndicator(
                      color: _black,
                      backgroundColor: _white,
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                            20, 20, 20,
                            MediaQuery.of(context).padding.bottom + 30),
                        children: [
                          _FilterTabs(
                            current: _filter,
                            pendingCount: data.pendingCount,
                            onChange: (f) =>
                                setState(() => _filter = f),
                          ),
                          const SizedBox(height: 18),
                          if (filtered.isEmpty)
                            _EmptyView(filter: _filter)
                          else
                            ...filtered.map((a) => _AppCard(
                                  app: a,
                                  onTap: () => _openDetail(a),
                                )),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Document opener ────────────────────────────────────────────────────────

  Future<void> _openDoc(String? url) async {
    if (url == null || url.isEmpty) return;
    final clean = url.startsWith('/') ? url.substring(1) : url;
    final uri = Uri.parse('$baseUrl/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      _toast('Could not open document', isError: true);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? _danger : _ok,
    ));
  }

  // ─── Detail bottom sheet ──────────────────────────────────────────────────

  void _openDetail(OutletApplication a) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(a.outletName,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _black,
                        )),
                  ),
                  _StatusPill(status: a.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(a.courtName ?? widget.courtName,
                  style: GoogleFonts.inter(fontSize: 13, color: _grey)),
              const SizedBox(height: 20),

              _DetailRow(icon: Icons.person_rounded, label: 'Owner', value: a.ownerName),
              _DetailRow(icon: Icons.phone_rounded, label: 'Phone', value: a.ownerPhone),
              _DetailRow(icon: Icons.email_rounded, label: 'Email', value: a.ownerEmail),
              _DetailRow(
                  icon: Icons.schedule_rounded,
                  label: 'Submitted',
                  value: _fmtDate(a.createdAt)),
              if (a.isRejected && a.rejectionReason != null)
                _DetailRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Reason',
                    value: a.rejectionReason!,
                    color: _danger),

              const SizedBox(height: 20),
              Text('DOCUMENTS',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _grey,
                    letterSpacing: 0.5,
                  )),
              const SizedBox(height: 10),
              _DocTile(label: 'GST Certificate', url: a.gstUrl, onOpen: _openDoc),
              _DocTile(label: 'FSSAI License', url: a.fssaiUrl, onOpen: _openDoc),
              _DocTile(label: 'Term Sheet', url: a.termSheetUrl, onOpen: _openDoc),
              _DocTile(label: 'Agreement', url: a.agreementUrl, onOpen: _openDoc),

              const SizedBox(height: 24),
              if (a.isPending) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _openApproveSheet(a);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: _black,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text('Approve & Onboard',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _white,
                          )),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _confirmReject(a);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _danger.withOpacity(0.25)),
                    ),
                    child: Center(
                      child: Text('Reject',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _danger,
                          )),
                    ),
                  ),
                ),
              ] else if (a.isApproved)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _ok.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _ok.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: _ok, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Onboarded. Outlet #${a.createdOutletId} is live.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Approve sheet (rest_id + optional creds) ───────────────────────────────

  void _openApproveSheet(OutletApplication a) {
    final restCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final cookieCtrl = TextEditingController();
    bool advanced = false;
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            decoration: const BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Approve ${a.outletName}',
                      style: GoogleFonts.inter(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: _black,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    'Enter the Petpooja restaurant ID to connect sales sync.',
                    style: GoogleFonts.inter(fontSize: 13, color: _grey),
                  ),
                  const SizedBox(height: 18),
                  _Field(
                    controller: restCtrl,
                    label: 'Petpooja rest_id *',
                    hint: 'e.g. yk4ou3en',
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => setSheet(() => advanced = !advanced),
                    child: Row(
                      children: [
                        Icon(
                          advanced
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_right_rounded,
                          size: 20,
                          color: _grey,
                        ),
                        Text(
                          'Advanced: per-outlet Petpooja keys (optional)',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (advanced) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Leave blank to use the shared ETL Petpooja account.',
                      style: GoogleFonts.inter(
                          fontSize: 11.5, color: _grey, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 10),
                    _Field(controller: keyCtrl, label: 'app_key', hint: ''),
                    const SizedBox(height: 10),
                    _Field(controller: secretCtrl, label: 'app_secret', hint: ''),
                    const SizedBox(height: 10),
                    _Field(controller: tokenCtrl, label: 'access_token', hint: ''),
                    const SizedBox(height: 10),
                    _Field(controller: cookieCtrl, label: 'cookie', hint: ''),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: loading
                          ? null
                          : () async {
                              final restId = restCtrl.text.trim();
                              if (restId.isEmpty) {
                                _toast('rest_id is required', isError: true);
                                return;
                              }
                              setSheet(() => loading = true);
                              try {
                                final result = await ref
                                    .read(onboardingRepositoryProvider)
                                    .approve(
                                      applicationId: a.id,
                                      restId: restId,
                                      ppAppKey: keyCtrl.text.trim(),
                                      ppAppSecret: secretCtrl.text.trim(),
                                      ppAccessToken: tokenCtrl.text.trim(),
                                      ppCookie: cookieCtrl.text.trim(),
                                    );
                                ref.invalidate(
                                    applicationsProvider(widget.courtId));
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) _showApproveResult(result);
                              } catch (e) {
                                setSheet(() => loading = false);
                                _toast(_errMsg(e), isError: true);
                              }
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: _black,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: loading
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      color: _white, strokeWidth: 2))
                              : Text('Confirm Approval',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: _white,
                                  )),
                        ),
                      ),
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

  void _showApproveResult(ApproveResult r) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _ok, size: 22),
            const SizedBox(width: 8),
            Text('Approved!',
                style: GoogleFonts.antonSc(fontSize: 20, color: _black)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.emailSent
                  ? 'Outlet onboarded. A set-password email was sent to ${r.managerEmail}.'
                  : 'Outlet onboarded. Email could not be sent — share this set-password link with the owner:',
              style: GoogleFonts.inter(fontSize: 13.5, color: _black, height: 1.5),
            ),
            if (!r.emailSent) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                ),
                child: Text(r.setPasswordLink,
                    style: GoogleFonts.inter(fontSize: 11.5, color: _grey)),
              ),
            ],
          ],
        ),
        actions: [
          if (!r.emailSent)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: r.setPasswordLink));
                _toast('Link copied');
              },
              child: Text('Copy Link',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, color: _black)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: _ok)),
          ),
        ],
      ),
    );
  }

  // ─── Reject ─────────────────────────────────────────────────────────────────

  void _confirmReject(OutletApplication a) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reject application?',
            style: GoogleFonts.antonSc(fontSize: 19, color: _black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${a.outletName} — ${a.ownerName}',
                style: GoogleFonts.inter(fontSize: 13, color: _grey)),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: 14, color: _black),
              decoration: InputDecoration(
                hintText: 'Reason (optional)',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: _grey),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: _grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(onboardingRepositoryProvider).reject(
                      applicationId: a.id,
                      reason: reasonCtrl.text.trim(),
                    );
                ref.invalidate(applicationsProvider(widget.courtId));
                _toast('Application rejected');
              } catch (e) {
                _toast(_errMsg(e), isError: true);
              }
            },
            child: Text('Reject',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: _danger)),
          ),
        ],
      ),
    );
  }

  String _errMsg(Object e) {
    final s = e.toString();
    if (s.contains('409')) return 'Conflict — rest_id or email already used.';
    if (s.contains('403')) return 'Not authorized.';
    return 'Something went wrong. Try again.';
  }
}

// ─── Filter tabs ──────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  final String current;
  final int pendingCount;
  final void Function(String) onChange;
  const _FilterTabs({
    required this.current,
    required this.pendingCount,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('pending', 'Pending'),
      ('approved', 'Approved'),
      ('rejected', 'Rejected'),
      ('all', 'All'),
    ];
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: tabs.map((t) {
          final active = current == t.$1;
          final showBadge = t.$1 == 'pending' && pendingCount > 0;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChange(t.$1);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? _black : _white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: active ? _black : Colors.grey.shade300, width: 1.5),
                ),
                child: Row(
                  children: [
                    Text(t.$2,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: active ? _white : _grey,
                        )),
                    if (showBadge) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: active ? _white : _warn,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('$pendingCount',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: active ? _black : _white,
                            )),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Application card ─────────────────────────────────────────────────────────

class _AppCard extends StatelessWidget {
  final OutletApplication app;
  final VoidCallback onTap;
  const _AppCard({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(app.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.storefront_rounded, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.outletName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _black,
                      )),
                  const SizedBox(height: 3),
                  Text('${app.ownerName} · ${_fmtDate(app.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12, color: _grey)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(status: app.status),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(_statusLabel(status),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          )),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color? color;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color ?? _grey),
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              child: Text(label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _grey,
                    fontWeight: FontWeight.w600,
                  )),
            ),
            Expanded(
              child: Text(value,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: color ?? _black,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ],
        ),
      );
}

class _DocTile extends StatelessWidget {
  final String label;
  final String? url;
  final Future<void> Function(String?) onOpen;
  const _DocTile({required this.label, required this.url, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    return GestureDetector(
      onTap: has ? () => onOpen(url) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: has ? _card : const Color(0xFFFCFCFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(has ? Icons.description_rounded : Icons.block_rounded,
                size: 18, color: has ? _black : Colors.grey.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: has ? _black : Colors.grey.shade400,
                  )),
            ),
            if (has)
              const Icon(Icons.open_in_new_rounded, size: 16, color: _grey)
            else
              Text('Not provided',
                  style: GoogleFonts.inter(
                      fontSize: 11.5, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  const _Field({required this.controller, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _grey,
              )),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            style: GoogleFonts.inter(fontSize: 14, color: _black),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: _grey),
              filled: true,
              fillColor: _card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _black, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      );
}

class _EmptyView extends StatelessWidget {
  final String filter;
  const _EmptyView({required this.filter});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 70),
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text('No $filter applications',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _black,
                )),
            const SizedBox(height: 6),
            Text('Share the onboarding form link with outlet owners.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: _grey)),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 42, color: _grey),
            const SizedBox(height: 12),
            Text('Could not load applications',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _black)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                decoration: BoxDecoration(
                    color: _black, borderRadius: BorderRadius.circular(999)),
                child: Text('Retry',
                    style: GoogleFonts.inter(
                        color: _white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
}
