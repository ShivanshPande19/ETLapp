// lib/features/settings/presentation/outlet_staff_management_screen.dart
//
// Outlet manager: manage their own outlet's staff (create outlet_staff with a
// simple photo + phone form, view, and remove). Mirrors the ETL-manager staff
// flow but scoped to the manager's outlet.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/dio_provider.dart' show baseUrl;
import '../domain/staff_notifier.dart';
import '../domain/staff_model.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);
const _danger = Color(0xFFEF4444);

class OutletStaffManagementScreen extends ConsumerStatefulWidget {
  final int outletId;
  final String outletName;
  const OutletStaffManagementScreen({
    super.key,
    required this.outletId,
    required this.outletName,
  });

  @override
  ConsumerState<OutletStaffManagementScreen> createState() =>
      _OutletStaffManagementScreenState();
}

class _OutletStaffManagementScreenState
    extends ConsumerState<OutletStaffManagementScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

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
          .fetchByOutletId(widget.outletId),
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
                          TextSpan(text: 'S', style: TextStyle(color: _red)),
                          TextSpan(text: 'TAFF', style: TextStyle(color: _white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            size: 13, color: _grey),
                        const SizedBox(width: 6),
                        Text(widget.outletName,
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
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: state.isLoading
                      ? const SkeletonList(
                          dark: false, count: 5, tileHeight: 76)
                      : state.error != null
                          ? Center(
                              child: Text(state.error!,
                                  style: GoogleFonts.inter(color: _grey)))
                          : state.staffList.isEmpty
                              ? _empty()
                              : ListView.separated(
                                  padding: EdgeInsets.fromLTRB(
                                      20, 22, 20,
                                      MediaQuery.of(context).padding.bottom +
                                          100),
                                  itemCount: state.staffList.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, i) => _StaffCard(
                                    staff: state.staffList[i],
                                    onRemove: () =>
                                        _confirmRemove(state.staffList[i]),
                                  ),
                                ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: state.isLoading
          ? null
          : GestureDetector(
              onTap: _showAddSheet,
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
                    Text('Add Staff',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _white,
                        )),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _empty() => Center(
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
              child: const Icon(Icons.people_outline_rounded,
                  size: 28, color: _grey),
            ),
            const SizedBox(height: 16),
            Text('No staff yet',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _black,
                )),
            const SizedBox(height: 6),
            Text('Tap + Add Staff to onboard your team',
                style: GoogleFonts.inter(fontSize: 13, color: _grey)),
          ],
        ),
      );

  Future<void> _pickPhoto(
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

  void _showAddSheet() {
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
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                  Text('Add Staff',
                      style: GoogleFonts.antonSc(
                          fontSize: 22, color: _black, letterSpacing: -0.3)),
                  const SizedBox(height: 3),
                  Text('New staff for ${widget.outletName}',
                      style: GoogleFonts.inter(fontSize: 13, color: _grey)),
                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: () => _pickPhoto(
                          ctx, (f) => setSheet(() => photoFile = f)),
                      child: Stack(
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F2F2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFFE5E5E5), width: 2),
                              image: photoFile != null
                                  ? DecorationImage(
                                      image: FileImage(photoFile!),
                                      fit: BoxFit.cover)
                                  : null,
                            ),
                            child: photoFile == null
                                ? const Icon(Icons.person_rounded,
                                    size: 42, color: _grey)
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
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 15, color: _white),
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
                        style: GoogleFonts.inter(fontSize: 12, color: _grey)),
                  ),
                  const SizedBox(height: 22),
                  _Field(controller: nameCtrl, label: 'Full Name', hint: 'Rahul Sharma'),
                  const SizedBox(height: 12),
                  _Field(
                      controller: phoneCtrl,
                      label: 'Phone Number',
                      hint: '10-digit mobile',
                      keyboardType: TextInputType.phone),
                  const SizedBox(height: 12),
                  _Field(
                      controller: emailCtrl,
                      label: 'Email (login id)',
                      hint: 'rahul@etl.com',
                      keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _Field(
                      controller: passCtrl,
                      label: 'Password (tell the staff)',
                      hint: 'min 4 characters',
                      obscure: true),
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
                                  const SnackBar(
                                    content: Text(
                                        'Name, phone, email and password are required'),
                                  ),
                                );
                                return;
                              }
                              setSheet(() => loading = true);
                              final ok = await ref
                                  .read(staffNotifierProvider.notifier)
                                  .addOutletStaff(
                                    name: nameCtrl.text.trim(),
                                    email: emailCtrl.text.trim(),
                                    password: passCtrl.text,
                                    outletId: widget.outletId,
                                    phone: phoneCtrl.text.trim(),
                                    photoPath: photoFile?.path,
                                  );
                              if (context.mounted) Navigator.pop(context);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? 'Staff added. Share the email & password with them.'
                                        : 'Could not add (email may already exist)'),
                                    backgroundColor: ok ? null : _danger,
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
                                      color: _white, strokeWidth: 2),
                                )
                              : Text('Add Staff',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
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

  void _confirmRemove(StaffModel staff) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove access?',
            style: GoogleFonts.antonSc(fontSize: 20, color: _black)),
        content: Text(
          "${staff.name}'s access will be revoked immediately.",
          style: GoogleFonts.inter(fontSize: 14, color: _grey, height: 1.5),
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
              await ref
                  .read(staffNotifierProvider.notifier)
                  .removeOutletStaff(staff.id, widget.outletId);
            },
            child: Text('Remove',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: _danger)),
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final StaffModel staff;
  final VoidCallback onRemove;
  const _StaffCard({required this.staff, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = staff.photoUrl != null && staff.photoUrl!.isNotEmpty;
    return Container(
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
              image: hasPhoto
                  ? DecorationImage(
                      image: NetworkImage('$baseUrl/${staff.photoUrl}'),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasPhoto
                ? null
                : Center(
                    child: Text(
                      staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
                      style: GoogleFonts.antonSc(fontSize: 18, color: _red),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _black,
                    )),
                const SizedBox(height: 2),
                Text(staff.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: _grey)),
                if (staff.phone != null && staff.phone!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(staff.phone!,
                        style:
                            GoogleFonts.inter(fontSize: 11.5, color: _grey)),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _danger.withOpacity(0.2)),
              ),
              child: const Icon(Icons.person_remove_rounded,
                  size: 16, color: _danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final bool obscure;
  final TextInputType keyboardType;
  const _Field({
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
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _grey,
                letterSpacing: 0.3,
              )),
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            ),
          ),
        ],
      );
}
