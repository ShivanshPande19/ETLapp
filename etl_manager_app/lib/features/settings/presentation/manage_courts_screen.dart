// lib/features/staff/presentation/manage_courts_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // NEW IMPORT
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../courts/domain/courts_notifier.dart'; // NEW IMPORT
import 'staff_management_screen.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);

class ManageCourtsScreen extends ConsumerStatefulWidget {
  // CHANGED to ConsumerStatefulWidget
  const ManageCourtsScreen({super.key});
  @override
  ConsumerState<ManageCourtsScreen> createState() => _ManageCourtsScreenState();
}

class _ManageCourtsScreenState extends ConsumerState<ManageCourtsScreen> {
  bool _backPressed = false;

  @override
  Widget build(BuildContext context) {
    final courtsAsync = ref.watch(
      courtsNotifierProvider,
    ); // WATCH DYNAMIC COURTS

    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _showNewCourtSheet(context);
        },
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: _red,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: _red.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: _white, size: 20),
              const SizedBox(width: 8),
              Text(
                'New Court',
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
      body: SafeArea(
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
                      children: const [
                        TextSpan(
                          text: 'C',
                          style: TextStyle(color: _red),
                        ),
                        TextSpan(
                          text: 'OURTS',
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
                        'Select a court to manage staff',
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: RefreshIndicator(
                  color: _black,
                  backgroundColor: _white,
                  onRefresh: () async => ref.invalidate(courtsNotifierProvider),
                  child: courtsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: _black),
                    ),
                    error: (err, _) =>
                        const Center(child: Text("Failed to load courts")),
                    data: (courtsList) {
                      if (courtsList.isEmpty) {
                        return const Center(
                          child: Text("No courts active in database"),
                        );
                      }
                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          20,
                          24,
                          20,
                          MediaQuery.of(context).padding.bottom + 40,
                        ),
                        itemCount: courtsList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final court = courtsList[i];
                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StaffManagementScreen(
                                  courtId: court.id,
                                  courtName: court.name,
                                ),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE5E5E5),
                                  width: 1.5,
                                ),
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
                                    child: const Icon(
                                      Icons.store_rounded,
                                      size: 20,
                                      color: _black,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          court.name,
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: _black,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          court.location ?? 'Active ETL Court',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: _grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: _grey.withOpacity(0.5),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewCourtSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
                  'New Court',
                  style: GoogleFonts.antonSc(
                    fontSize: 22,
                    color: _black,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 20),
                _CourtField(
                  controller: nameCtrl,
                  label: 'Court Name',
                  hint: 'e.g. Central 50',
                ),
                const SizedBox(height: 12),
                _CourtField(
                  controller: locCtrl,
                  label: 'Location (optional)',
                  hint: 'e.g. Sector 50, Noida',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: loading
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;
                            setSheet(() => loading = true);
                            try {
                              await ref
                                  .read(courtsNotifierProvider.notifier)
                                  .createCourt(
                                    name: name,
                                    location: locCtrl.text.trim(),
                                  );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Court "$name" created'),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: _black,
                                  ),
                                );
                              }
                            } catch (e) {
                              setSheet(() => loading = false);
                              final dup = e.toString().contains('409');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(dup
                                        ? 'A court with this name already exists'
                                        : 'Could not create court'),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: const Color(0xFFEF4444),
                                  ),
                                );
                              }
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
                                'Create Court',
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
    );
  }
}

class _CourtField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  const _CourtField({
    required this.controller,
    required this.label,
    required this.hint,
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
