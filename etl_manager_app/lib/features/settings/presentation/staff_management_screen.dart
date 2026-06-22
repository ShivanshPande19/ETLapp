// lib/features/staff/presentation/staff_management_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../app/dio_provider.dart' show baseUrl;
import '../../courts/domain/courts_notifier.dart'; // NEW IMPORT
import '../../onboarding/presentation/outlet_applications_screen.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../domain/staff_notifier.dart';
import '../domain/staff_model.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);

class StaffManagementScreen extends ConsumerStatefulWidget {
  final int courtId;
  final String courtName;
  const StaffManagementScreen({
    super.key,
    required this.courtId,
    required this.courtName,
  });
  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  bool _backPressed = false;
  int _tab = 0; // 0 = Staff, 1 = Outlets

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();

    Future.microtask(
      () => ref
          .read(staffNotifierProvider.notifier)
          .fetchByCourtId(widget.courtId),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffNotifierProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTapDown: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _backPressed = true);
                      },
                      onTapUp: (_) {
                        setState(() => _backPressed = false);
                        Navigator.of(context).pop();
                      },
                      onTapCancel: () => setState(() => _backPressed = false),
                      child: AnimatedScale(
                        scale: _backPressed ? 0.92 : 1.0,
                        duration: const Duration(milliseconds: 120),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _backPressed
                                ? _white.withOpacity(0.14)
                                : _white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _white.withOpacity(
                                _backPressed ? 0.22 : 0.12,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.west_rounded,
                                size: 14,
                                color: _white.withOpacity(0.9),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Back',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _white.withOpacity(0.9),
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.antonSc(
                          fontSize: 36,
                          height: 0.95,
                          letterSpacing: -0.5,
                        ),
                        children: [
                          const TextSpan(
                            text: 'M',
                            style: TextStyle(color: _red),
                          ),
                          const TextSpan(
                            text: 'ANAGE',
                            style: TextStyle(color: _white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppTheme.success,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.success.withOpacity(0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.courtName,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _white.withOpacity(0.45),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                        child: _SegToggle(
                          tab: _tab,
                          onChange: (i) => setState(() => _tab = i),
                        ),
                      ),
                      Expanded(
                        child: _tab == 0
                            ? _buildStaffBody()
                            : _buildOutletsBody(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _tab == 0
          ? (state.isLoading
              ? null
              : _FabButton(
                  label: 'Add Staff',
                  icon: Icons.person_add_rounded,
                  color: _black,
                  onTap: () => _showAddSheet(context),
                ))
          : _FabButton(
              label: 'Applications',
              icon: Icons.inbox_rounded,
              color: _red,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OutletApplicationsScreen(
                      courtId: widget.courtId,
                      courtName: widget.courtName,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStaffBody() {
    final state = ref.watch(staffNotifierProvider);
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator(color: _black));
    }
    if (state.error != null) {
      return Center(
        child: Text(state.error!, style: GoogleFonts.inter(color: _grey)),
      );
    }
    if (state.staffList.isEmpty) {
      return _EmptyState(onAdd: () => _showAddSheet(context));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).padding.bottom + 100,
      ),
      itemCount: state.staffList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _StaffCard(
        staff: state.staffList[i],
        onRemove: () => _confirmRemove(context, state.staffList[i]),
        onReassign: () => _showReassignSheet(context, state.staffList[i]),
      ),
    );
  }

  Widget _buildOutletsBody() {
    final async = ref.watch(courtOutletsProvider(widget.courtId));
    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: _black)),
      error: (_, __) => Center(
        child: Text('Could not load outlets',
            style: GoogleFonts.inter(color: _grey)),
      ),
      data: (outlets) {
        if (outlets.isEmpty) return const _OutletsEmpty();
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).padding.bottom + 100,
          ),
          itemCount: outlets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _OutletCard(
            outlet: outlets[i],
            onTap: () => _showOutletDocs(outlets[i]),
          ),
        );
      },
    );
  }

  Future<void> _openDoc(String? url) async {
    if (url == null || url.isEmpty) return;
    final clean = url.startsWith('/') ? url.substring(1) : url;
    final uri = Uri.parse('$baseUrl/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showOutletDocs(OutletWithDocs o) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E5E5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(o.vendorName,
                  style: GoogleFonts.inter(
                      fontSize: 20, fontWeight: FontWeight.w900, color: _black)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.tag_rounded, size: 14, color: _grey),
                const SizedBox(width: 4),
                Text('rest_id: ${o.restId}',
                    style: GoogleFonts.inter(fontSize: 12.5, color: _grey)),
              ]),
              const SizedBox(height: 18),
              if (o.ownerName != null)
                _docOwnerRow(Icons.person_rounded, 'Owner', o.ownerName!),
              if (o.ownerPhone != null)
                _docOwnerRow(Icons.phone_rounded, 'Phone', o.ownerPhone!),
              if (o.ownerEmail != null)
                _docOwnerRow(Icons.email_rounded, 'Login Email', o.ownerEmail!),
              const SizedBox(height: 16),
              Text('DOCUMENTS',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _grey,
                      letterSpacing: 0.5)),
              const SizedBox(height: 10),
              _OutletDocTile(label: 'GST Certificate', url: o.gstUrl, onOpen: _openDoc),
              _OutletDocTile(label: 'FSSAI License', url: o.fssaiUrl, onOpen: _openDoc),
              _OutletDocTile(label: 'Term Sheet', url: o.termSheetUrl, onOpen: _openDoc),
              _OutletDocTile(label: 'Agreement', url: o.agreementUrl, onOpen: _openDoc),
              if (!o.hasAnyDoc)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No documents on record for this outlet.',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: _grey,
                        fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _docOwnerRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(icon, size: 16, color: _grey),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 13, color: _grey, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: _black,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  void _showAddSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    File? photoFile;
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
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
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E5E5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Add Staff',
                    style: GoogleFonts.antonSc(
                      fontSize: 22,
                      color: _black,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'New ETL staff for ${widget.courtName}',
                    style: GoogleFonts.inter(fontSize: 13, color: _grey),
                  ),
                  const SizedBox(height: 20),

                  // Photo picker
                  Center(
                    child: GestureDetector(
                      onTap: () => _pickStaffPhoto(
                        ctx,
                        (f) => setSheet(() => photoFile = f),
                      ),
                      child: Stack(
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F2F2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE5E5E5),
                                width: 2,
                              ),
                              image: photoFile != null
                                  ? DecorationImage(
                                      image: FileImage(photoFile!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: photoFile == null
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 42,
                                    color: _grey,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _red,
                                shape: BoxShape.circle,
                                border: Border.all(color: _white, width: 2),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 15,
                                color: _white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      photoFile == null ? 'Tap to add photo' : 'Tap to change',
                      style: GoogleFonts.inter(fontSize: 12, color: _grey),
                    ),
                  ),
                  const SizedBox(height: 22),

                  _SheetField(
                    controller: nameCtrl,
                    label: 'Full Name',
                    hint: 'Rahul Sharma',
                  ),
                  const SizedBox(height: 12),
                  _SheetField(
                    controller: phoneCtrl,
                    label: 'Phone Number',
                    hint: '10-digit mobile',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _SheetField(
                    controller: emailCtrl,
                    label: 'Email (login id)',
                    hint: 'rahul@etl.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _SheetField(
                    controller: passCtrl,
                    label: 'Password (tell the staff)',
                    hint: 'min 4 characters',
                    obscure: true,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: loading
                          ? null
                          : () async {
                              if (nameCtrl.text.trim().isEmpty ||
                                  phoneCtrl.text.trim().isEmpty ||
                                  emailCtrl.text.trim().isEmpty ||
                                  passCtrl.text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Name, phone, email and password are required',
                                    ),
                                    backgroundColor: _black,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              setSheet(() => loading = true);
                              final ok = await ref
                                  .read(staffNotifierProvider.notifier)
                                  .addStaff(
                                    name: nameCtrl.text.trim(),
                                    email: emailCtrl.text.trim(),
                                    password: passCtrl.text,
                                    courtId: widget.courtId,
                                    phone: phoneCtrl.text.trim(),
                                    photoPath: photoFile?.path,
                                  );
                              if (context.mounted) Navigator.pop(context);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Staff added. Share the email & password with them.'
                                          : 'Could not add (email may already exist)',
                                    ),
                                    backgroundColor: ok ? _black : _red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _black,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: _white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'Add Staff',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _white,
                                  ),
                                ),
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

  Future<void> _pickStaffPhoto(
    BuildContext ctx,
    void Function(File) onPicked,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: ctx,
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
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: _black),
              title: Text('Choose from Gallery',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? img = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (img != null) onPicked(File(img.path));
  }

  void _confirmRemove(BuildContext context, StaffModel staff) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Access?',
          style: GoogleFonts.antonSc(fontSize: 20, color: _black),
        ),
        content: Text(
          '${staff.name}\'s access will be revoked immediately.',
          style: GoogleFonts.inter(fontSize: 14, color: _grey, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: _grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(staffNotifierProvider.notifier)
                  .removeStaff(staff.id, widget.courtId);
            },
            child: Text(
              'Remove',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: AppTheme.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReassignSheet(BuildContext context, StaffModel staff) {
    // CHANGED: Get real live courts from the notifier instead of hardcoded list
    final dynamicCourts = ref.read(courtsNotifierProvider).value ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
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
            const SizedBox(height: 20),
            Text(
              'Reassign Court',
              style: GoogleFonts.antonSc(
                fontSize: 22,
                color: _black,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Assign ${staff.name} to:',
              style: GoogleFonts.inter(fontSize: 13, color: _grey),
            ),
            const SizedBox(height: 16),
            if (dynamicCourts.isEmpty)
              const Center(child: Text("No courts available for assignment"))
            else
              ...dynamicCourts.map(
                (c) => GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    await ref
                        .read(staffNotifierProvider.notifier)
                        .reassignStaff(staff.id, c.id, widget.courtId);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.id == staff.courtId
                          ? _black
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: c.id == staff.courtId
                            ? _black
                            : const Color(0xFFE5E5E5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.store_rounded,
                          size: 18,
                          color: c.id == staff.courtId ? _white : _grey,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          c.name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.id == staff.courtId ? _white : _black,
                          ),
                        ),
                        if (c.id == staff.courtId) ...[
                          const Spacer(),
                          Text(
                            'Current',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _white.withOpacity(0.6),
                            ),
                          ),
                        ],
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
}

class _StaffCard extends StatelessWidget {
  final StaffModel staff;
  final VoidCallback onRemove;
  final VoidCallback onReassign;
  const _StaffCard({
    required this.staff,
    required this.onRemove,
    required this.onReassign,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _red.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(color: _red.withOpacity(0.2)),
            image: (staff.photoUrl != null && staff.photoUrl!.isNotEmpty)
                ? DecorationImage(
                    image: NetworkImage('$baseUrl/${staff.photoUrl}'),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: (staff.photoUrl == null || staff.photoUrl!.isEmpty)
              ? Center(
                  child: Text(
                    staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
                    style: GoogleFonts.antonSc(fontSize: 18, color: _red),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                staff.name,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                staff.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, color: _grey),
              ),
              if (staff.phone != null && staff.phone!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    staff.phone!,
                    style: GoogleFonts.inter(fontSize: 11.5, color: _grey),
                  ),
                ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onReassign,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E5E5)),
            ),
            child: const Icon(Icons.swap_horiz_rounded, size: 16, color: _grey),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onRemove,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.danger.withOpacity(0.2)),
            ),
            child: Icon(
              Icons.person_remove_rounded,
              size: 16,
              color: AppTheme.danger,
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _grey.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.people_outline_rounded,
            size: 28,
            color: _grey,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'No staff assigned',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tap + Add Staff to get started',
          style: GoogleFonts.inter(fontSize: 13, color: _grey),
        ),
      ],
    ),
  );
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final bool obscure;
  final TextInputType keyboardType;
  const _SheetField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _grey,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(fontSize: 14, color: _black),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 14, color: _grey),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
      ),
    ],
  );
}



// ─── Staff / Outlets segmented toggle ─────────────────────────────────────────

class _SegToggle extends StatelessWidget {
  final int tab;
  final void Function(int) onChange;
  const _SegToggle({required this.tab, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _seg(0, 'Staff', Icons.people_alt_rounded),
          _seg(1, 'Outlets', Icons.storefront_rounded),
        ],
      ),
    );
  }

  Widget _seg(int idx, String label, IconData icon) {
    final active = tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChange(idx);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? _black : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? _white : _grey),
              const SizedBox(width: 7),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? _white : _grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── FAB pill ──────────────────────────────────────────────────────────────────

class _FabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _FabButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _white,
                ),
              ),
            ],
          ),
        ),
      );
}

// ─── Outlet card ───────────────────────────────────────────────────────────────

class _OutletCard extends StatelessWidget {
  final OutletWithDocs outlet;
  final VoidCallback onTap;
  const _OutletCard({required this.outlet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.storefront_rounded, size: 20, color: _black),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outlet.vendorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _black,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        'rest_id: ${outlet.restId}',
                        style: GoogleFonts.inter(fontSize: 12, color: _grey),
                      ),
                      if (outlet.hasAnyDoc) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.description_rounded,
                            size: 12, color: _grey),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: _grey.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}

class _OutletsEmpty extends StatelessWidget {
  const _OutletsEmpty();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _grey.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storefront_outlined,
                  size: 28, color: _grey),
            ),
            const SizedBox(height: 16),
            Text(
              'No outlets yet',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Approve an application to add an outlet',
              style: GoogleFonts.inter(fontSize: 13, color: _grey),
            ),
          ],
        ),
      );
}

class _OutletDocTile extends StatelessWidget {
  final String label;
  final String? url;
  final Future<void> Function(String?) onOpen;
  const _OutletDocTile({
    required this.label,
    required this.url,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    return GestureDetector(
      onTap: has ? () => onOpen(url) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFAFAFA) : const Color(0xFFFCFCFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEDEDED)),
        ),
        child: Row(
          children: [
            Icon(has ? Icons.description_rounded : Icons.block_rounded,
                size: 18, color: has ? _black : Colors.grey.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: has ? _black : Colors.grey.shade400,
                ),
              ),
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
