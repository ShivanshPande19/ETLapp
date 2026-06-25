// lib/features/attendance_calendar/presentation/staff_calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/calendar_repository.dart';
import 'calendar_widgets.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);

class StaffCalendarScreen extends ConsumerStatefulWidget {
  const StaffCalendarScreen({super.key});
  @override
  ConsumerState<StaffCalendarScreen> createState() => _StaffCalendarScreenState();
}

class _StaffCalendarScreenState extends ConsumerState<StaffCalendarScreen> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  String get _monthStr =>
      '${_year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _year == now.year && _month == now.month;
  }

  void _shift(int delta) {
    setState(() {
      var m = _month + delta;
      var y = _year;
      while (m < 1) {
        m += 12;
        y--;
      }
      while (m > 12) {
        m -= 12;
        y++;
      }
      _month = m;
      _year = y;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myCalendarProvider(_monthStr));

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
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
                              color: _white.withOpacity(0.9))),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.antonSc(
                      fontSize: 34, height: 0.95, letterSpacing: -0.5),
                  children: const [
                    TextSpan(text: 'MY ', style: TextStyle(color: _white)),
                    TextSpan(text: 'ATTENDANCE', style: TextStyle(color: _red)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                      20, 20, 20, MediaQuery.of(context).padding.bottom + 30),
                  children: [
                    _MonthNav(
                      label: monthLabel(_year, _month),
                      onPrev: () => _shift(-1),
                      onNext: _isCurrentMonth ? null : () => _shift(1),
                    ),
                    const SizedBox(height: 16),
                    async.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                            child: CircularProgressIndicator(color: _black)),
                      ),
                      error: (_, __) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text('Could not load calendar')),
                      ),
                      data: (cal) => Column(
                        children: [
                          MonthGrid(
                              year: _year, month: _month, byDay: cal.byDay),
                          const SizedBox(height: 18),
                          const CalendarLegend(),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              _StatPill(
                                  label: 'Present',
                                  value: cal.summary.present,
                                  color: const Color(0xFF16A34A)),
                              _StatPill(
                                  label: 'Early',
                                  value: cal.summary.early,
                                  color: const Color(0xFFE5A000)),
                              _StatPill(
                                  label: 'Missed out',
                                  value: cal.summary.autoClosed,
                                  color: const Color(0xFFEA580C)),
                              _StatPill(
                                  label: 'Absent',
                                  value: cal.summary.absent,
                                  color: _red),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthNav extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _MonthNav(
      {required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData i, VoidCallback? cb) => GestureDetector(
          onTap: cb == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  cb();
                },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cb == null ? const Color(0xFFF2F2F2) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E5E5)),
            ),
            child: Icon(i,
                size: 18, color: cb == null ? const Color(0xFFCCCCCC) : _black),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        arrow(Icons.chevron_left_rounded, onPrev),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w800, color: _black)),
        arrow(Icons.chevron_right_rounded, onNext),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Text('$value',
                  style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 10, color: _grey)),
            ],
          ),
        ),
      );
}
