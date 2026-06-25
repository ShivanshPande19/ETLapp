import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

const _present = Color(0xFF16A34A);
const _early = Color(0xFFE5A000);
const _auto = Color(0xFFEA580C);
const _absent = Color(0xFFD02128);
const _neutral = Color(0xFFEDEDED);
const _grey = Color(0xFF888888);

Color statusColor(String? status) {
  switch (status) {
    case 'present':
      return _present;
    case 'early':
      return _early;
    case 'auto_closed':
      return _auto;
    case 'absent':
      return _absent;
    default:
      return _neutral;
  }
}

String monthLabel(int year, int month) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${names[month - 1]} $year';
}

/// A month grid. [byDay] maps day-of-month → status string.
class MonthGrid extends StatelessWidget {
  final int year;
  final int month;
  final Map<int, String> byDay;
  final bool compact;
  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.byDay,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Dart: Monday=1..Sunday=7. We render Sun-first columns.
    final leadingBlanks = first.weekday % 7; // Sun=0
    final cells = <Widget>[];

    const wd = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    for (final w in wd) {
      cells.add(Center(
        child: Text(w,
            style: GoogleFonts.inter(
                fontSize: compact ? 9 : 11,
                fontWeight: FontWeight.w700,
                color: _grey)),
      ));
    }
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final status = byDay[day];
      final c = statusColor(status);
      final has = status != null;
      cells.add(Padding(
        padding: EdgeInsets.all(compact ? 1.5 : 3),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: has ? c : Colors.transparent,
              borderRadius: BorderRadius.circular(compact ? 6 : 9),
              border: has ? null : Border.all(color: _neutral),
            ),
            child: Center(
              child: Text(
                '$day',
                style: GoogleFonts.inter(
                  fontSize: compact ? 10 : 12.5,
                  fontWeight: FontWeight.w600,
                  color: has ? Colors.white : _grey,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }
}

class CalendarLegend extends StatelessWidget {
  const CalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 11,
              height: 11,
              decoration:
                  BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.inter(fontSize: 11.5, color: _grey)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        dot(_present, 'Present'),
        dot(_early, 'Early out'),
        dot(_auto, 'Forgot out'),
        dot(_absent, 'Absent'),
      ],
    );
  }
}

class MonthNavBar extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const MonthNavBar({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

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
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E5E5)),
            ),
            child: Icon(i,
                size: 18,
                color: cb == null ? const Color(0xFFCCCCCC) : const Color(0xFF0A0A0A)),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        arrow(Icons.chevron_left_rounded, onPrev),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0A0A0A))),
        arrow(Icons.chevron_right_rounded, onNext),
      ],
    );
  }
}
