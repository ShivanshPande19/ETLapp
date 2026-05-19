// lib/features/staff/presentation/staff_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../courts/domain/courts_notifier.dart'; // NEW IMPORT
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
                            text: 'S',
                            style: TextStyle(color: _red),
                          ),
                          const TextSpan(
                            text: 'TAFF',
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
                  child: state.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: _black),
                        )
                      : state.error != null
                      ? Center(
                          child: Text(
                            state.error!,
                            style: GoogleFonts.inter(color: _grey),
                          ),
                        )
                      : state.staffList.isEmpty
                      ? _EmptyState(onAdd: () => _showAddSheet(context))
                      : Column(
                          children: [
                            Expanded(
                              child: ListView.separated(
                                padding: EdgeInsets.fromLTRB(
                                  20,
                                  24,
                                  20,
                                  MediaQuery.of(context).padding.bottom + 100,
                                ),
                                itemCount: state.staffList.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) => _StaffCard(
                                  staff: state.staffList[i],
                                  onRemove: () => _confirmRemove(
                                    context,
                                    state.staffList[i],
                                  ),
                                  onReassign: () => _showReassignSheet(
                                    context,
                                    state.staffList[i],
                                  ),
                                ),
                              ),
                            ),
                          ],
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
              onTap: () => _showAddSheet(context),
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
                    const Icon(
                      Icons.person_add_rounded,
                      color: _white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Add Staff',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _showAddSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
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
                'Add New Staff',
                style: GoogleFonts.antonSc(
                  fontSize: 22,
                  color: _black,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 20),
              _SheetField(
                controller: nameCtrl,
                label: 'Full Name',
                hint: 'Rahul Sharma',
              ),
              const SizedBox(height: 12),
              _SheetField(
                controller: emailCtrl,
                label: 'Email',
                hint: 'rahul@etl.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _SheetField(
                controller: passCtrl,
                label: 'Password',
                hint: '••••••••',
                obscure: true,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: StatefulBuilder(
                  builder: (ctx, setSheet) => GestureDetector(
                    onTap: loading
                        ? null
                        : () async {
                            if (nameCtrl.text.isEmpty ||
                                emailCtrl.text.isEmpty ||
                                passCtrl.text.isEmpty)
                              return;
                            setSheet(() => loading = true);
                            final ok = await ref
                                .read(staffNotifierProvider.notifier)
                                .addStaff(
                                  name: nameCtrl.text.trim(),
                                  email: emailCtrl.text.trim(),
                                  password: passCtrl.text,
                                  courtId: widget.courtId,
                                );
                            if (context.mounted) Navigator.pop(context);
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Email already registered',
                                    style: GoogleFonts.inter(color: _white),
                                  ),
                                  backgroundColor: _black,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  margin: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
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
              ),
            ],
          ),
        ),
      ),
    );
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
          ),
          child: Center(
            child: Text(
              staff.name[0].toUpperCase(),
              style: GoogleFonts.antonSc(fontSize: 18, color: _red),
            ),
          ),
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
                style: GoogleFonts.inter(fontSize: 12, color: _grey),
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
