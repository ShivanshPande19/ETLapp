// lib/features/attendance_calendar/presentation/manager_attendance_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/calendar_models.dart';
import '../data/calendar_repository.dart';
import 'calendar_widgets.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);

class ManagerAttendanceScreen extends ConsumerStatefulWidget {
  const ManagerAttendanceScreen({super.key});
  @override
  ConsumerState<ManagerAttendanceScreen> createState() =>
      _ManagerAttendanceScreenState();
}

class _ManagerAttendanceScreenState
    extends ConsumerState<ManagerAttendanceScreen> {
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
    final async = ref.watch(courtCalendarProvider(_monthStr));

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
                      fontSize: 32, height: 0.95, letterSpacing: -0.5),
                  children: const [
                    TextSpan(text: 'STAFF ', style: TextStyle(color: _white)),
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
                child: RefreshIndicator(
                  color: _black,
                  onRefresh: () async =>
                      ref.invalidate(courtCalendarProvider(_monthStr)),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        20, 20, 20, MediaQuery.of(context).padding.bottom + 30),
                    children: [
                      MonthNavBar(
                        label: monthLabel(_year, _month),
                        onPrev: () => _shift(-1),
                        onNext: _isCurrentMonth ? null : () => _shift(1),
                      ),
                      const SizedBox(height: 14),
                      const CalendarLegend(),
                      const SizedBox(height: 18),
                      async.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                              child: CircularProgressIndicator(color: _black)),
                        ),
                        error: (_, __) => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child:
                              Center(child: Text('Could not load attendance')),
                        ),
                        data: (courts) {
                          if (courts.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: Text('No courts found')),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final court in courts)
                                _CourtSection(
                                  court: court,
                                  year: _year,
                                  month: _month,
                                ),
                            ],
                          );
                        },
                      ),
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

class _CourtSection extends StatelessWidget {
  final CourtCalendar court;
  final int year;
  final int month;
  const _CourtSection(
      {required this.court, required this.year, required this.month});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                    color: _red, borderRadius: BorderRadius.circular(999)),
              ),
              const SizedBox(width: 8),
              Text(court.courtName.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _black,
                      letterSpacing: 0.6)),
              if (court.dayCutoffHour > 0) ...[
                const SizedBox(width: 8),
                Text('· overnight',
                    style: GoogleFonts.inter(fontSize: 11, color: _grey)),
              ],
            ],
          ),
        ),
        if (court.staff.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('No staff in this court',
                style: GoogleFonts.inter(fontSize: 12.5, color: _grey)),
          )
        else
          for (final s in court.staff)
            _StaffExpandable(staff: s, year: year, month: month),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _StaffExpandable extends StatelessWidget {
  final StaffCalendar staff;
  final int year;
  final int month;
  const _StaffExpandable(
      {required this.staff, required this.year, required this.month});

  @override
  Widget build(BuildContext context) {
    final shift = (staff.shiftStart != null && staff.shiftEnd != null)
        ? '${staff.shiftStart} – ${staff.shiftEnd}'
        : 'No shift set';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: _red.withOpacity(0.1),
            child: Text(
              staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
              style: GoogleFonts.antonSc(fontSize: 15, color: _red),
            ),
          ),
          title: Text(staff.name,
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _black)),
          subtitle: Text(shift,
              style: GoogleFonts.inter(fontSize: 11.5, color: _grey)),
          trailing: _MiniCounts(summary: staff.summary),
          children: [
            MonthGrid(
                year: year, month: month, byDay: staff.byDay, compact: true),
          ],
        ),
      ),
    );
  }
}

class _MiniCounts extends StatelessWidget {
  final CalSummary summary;
  const _MiniCounts({required this.summary});

  @override
  Widget build(BuildContext context) {
    Widget chip(int v, Color c) => Container(
          margin: const EdgeInsets.only(left: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6)),
          child: Text('$v',
              style: GoogleFonts.inter(
                  fontSize: 11, fontWeight: FontWeight.w800, color: c)),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip(summary.present, const Color(0xFF16A34A)),
        chip(summary.absent, _red),
        const SizedBox(width: 4),
        const Icon(Icons.expand_more_rounded, size: 20, color: _grey),
      ],
    );
  }
}
