// lib/features/outlets/presentation/outlet_documents_screen.dart
//
// View / upload / replace / remove an outlet's documents (GST, FSSAI, term
// sheet, agreement). Works for the outlet's owner (their outlet) and for an ETL
// manager (any outlet) — the backend scopes it. VIEWING is free; every CHANGE
// asks for the acting account's OWN password (a lightweight "unlock"). A photo
// of the document is uploaded (camera/gallery); existing PDFs still open to view.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/dio_provider.dart' show baseUrl;
import '../../../core/widgets/skeleton.dart';
import '../data/outlets_repository.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);
const _ok = Color(0xFF22C55E);
const _danger = Color(0xFFEF4444);

const _docIcons = {
  'gst': Icons.receipt_long_rounded,
  'fssai': Icons.verified_user_rounded,
  'term_sheet': Icons.description_rounded,
  'agreement': Icons.gavel_rounded,
};

class OutletDocumentsScreen extends ConsumerStatefulWidget {
  final int outletId;
  final String outletName;
  const OutletDocumentsScreen({
    super.key,
    required this.outletId,
    required this.outletName,
  });

  @override
  ConsumerState<OutletDocumentsScreen> createState() =>
      _OutletDocumentsScreenState();
}

class _OutletDocumentsScreenState
    extends ConsumerState<OutletDocumentsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool _loading = true;
  String? _error;
  List<OutletDocument> _docs = const [];
  String? _busyType; // doc_type currently uploading/removing

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
      final list =
          await ref.read(outletsRepositoryProvider).listDocuments(widget.outletId);
      if (!mounted) return;
      setState(() {
        _docs = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load documents. Pull to refresh.';
        _loading = false;
      });
    }
  }

  String _err(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['detail'] is String) return d['detail'] as String;
      if (e.response?.statusCode == 403) return 'Incorrect password.';
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

  Future<void> _openDoc(OutletDocument d) async {
    if (!d.hasFile) return;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final path = d.url!.startsWith('/') ? d.url!.substring(1) : d.url!;
    final uri = Uri.parse('$base/$path');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('Could not open the document.');
    } catch (_) {
      _snack('Could not open the document.');
    }
  }

  /// Password "unlock" prompt shown before any change. Returns the password or
  /// null if cancelled.
  Future<String?> _askPassword(String action, String label) async {
    final ctrl = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 18, color: _black),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Confirm your password',
                        style: GoogleFonts.antonSc(fontSize: 20, color: _black)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('$action the $label needs your account password.',
                  style: GoogleFonts.inter(fontSize: 13, color: _grey)),
              const SizedBox(height: 18),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                style: GoogleFonts.inter(color: _black, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Your password',
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
                onSubmitted: (_) {
                  if (ctrl.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, ctrl.text.trim());
                  }
                },
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () {
                  final pw = ctrl.text.trim();
                  if (pw.isEmpty) return;
                  Navigator.pop(ctx, pw);
                },
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text('Unlock',
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
  }

  Future<String?> _pickImagePath() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: _black),
              title: Text('Take Photo',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: _black),
              title: Text('Choose from Gallery',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final XFile? img = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );
    return img?.path;
  }

  Future<void> _upload(OutletDocument d) async {
    final pw = await _askPassword(d.hasFile ? 'Replacing' : 'Uploading', d.label);
    if (pw == null) return;
    final path = await _pickImagePath();
    if (path == null) return;
    setState(() => _busyType = d.docType);
    try {
      await ref
          .read(outletsRepositoryProvider)
          .uploadDocument(widget.outletId, d.docType, path, pw);
      HapticFeedback.mediumImpact();
      await _load();
      _snack('${d.label} updated.');
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  Future<void> _remove(OutletDocument d) async {
    final pw = await _askPassword('Removing', d.label);
    if (pw == null) return;
    setState(() => _busyType = d.docType);
    try {
      await ref
          .read(outletsRepositoryProvider)
          .deleteDocument(widget.outletId, d.docType, pw);
      HapticFeedback.mediumImpact();
      await _load();
      _snack('${d.label} removed.');
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
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
                          TextSpan(text: 'D', style: TextStyle(color: _red)),
                          TextSpan(
                              text: 'OCUMENTS',
                              style: TextStyle(color: _white)),
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
                      ? const SkeletonList(dark: false, count: 4, tileHeight: 92)
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
                                  MediaQuery.of(context).padding.bottom + 30,
                                ),
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.lock_outline_rounded,
                                          size: 14, color: _grey),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Viewing is open. Changing a document asks for your password.',
                                          style: GoogleFonts.inter(
                                              fontSize: 12, color: _grey),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  ..._docs.map(
                                    (d) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _docCard(d),
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

  Widget _docCard(OutletDocument d) {
    final busy = _busyType == d.docType;
    final has = d.hasFile;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (has ? _ok : _grey).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_docIcons[d.docType] ?? Icons.insert_drive_file_rounded,
                    size: 20, color: has ? _ok : _grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.label,
                        style: GoogleFonts.inter(
                            color: _black,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(has ? 'Uploaded' : 'Not uploaded',
                        style: GoogleFonts.inter(
                            color: has ? _ok : _grey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: _black, strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (has)
                Expanded(
                  child: _cardBtn(
                    icon: Icons.visibility_rounded,
                    label: 'View',
                    onTap: busy ? null : () => _openDoc(d),
                    filled: false,
                  ),
                ),
              if (has) const SizedBox(width: 10),
              Expanded(
                child: _cardBtn(
                  icon: has ? Icons.sync_rounded : Icons.upload_rounded,
                  label: has ? 'Replace' : 'Upload',
                  onTap: busy ? null : () => _upload(d),
                  filled: true,
                ),
              ),
              if (has) ...[
                const SizedBox(width: 10),
                _iconBtn(
                  icon: Icons.delete_outline_rounded,
                  color: _danger,
                  onTap: busy ? null : () => _remove(d),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? _black : _white,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: filled ? _white : _black),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(
                    color: filled ? _white : _black,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}
