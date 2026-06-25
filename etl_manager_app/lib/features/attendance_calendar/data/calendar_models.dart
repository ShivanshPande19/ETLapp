// Attendance calendar models (shared by staff & manager views).

class CalDay {
  final DateTime date;
  final String status; // present | early | auto_closed | absent
  const CalDay({required this.date, required this.status});

  factory CalDay.fromJson(Map<String, dynamic> j) => CalDay(
        date: DateTime.parse(j['date'] as String),
        status: j['status'] as String? ?? 'absent',
      );
}

class CalSummary {
  final int present;
  final int early;
  final int autoClosed;
  final int absent;
  const CalSummary({
    this.present = 0,
    this.early = 0,
    this.autoClosed = 0,
    this.absent = 0,
  });

  factory CalSummary.fromJson(Map<String, dynamic>? j) => CalSummary(
        present: (j?['present'] ?? 0) as int,
        early: (j?['early'] ?? 0) as int,
        autoClosed: (j?['auto_closed'] ?? 0) as int,
        absent: (j?['absent'] ?? 0) as int,
      );
}

class AttendanceCalendar {
  final String month; // "YYYY-MM"
  final List<CalDay> days;
  final CalSummary summary;

  AttendanceCalendar({
    required this.month,
    required this.days,
    required this.summary,
  });

  /// day-of-month → status, for quick grid lookup.
  Map<int, String> get byDay => {for (final d in days) d.date.day: d.status};

  factory AttendanceCalendar.fromJson(Map<String, dynamic> j) =>
      AttendanceCalendar(
        month: j['month'] as String? ?? '',
        days: (j['days'] as List? ?? [])
            .map((e) => CalDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        summary: CalSummary.fromJson(j['summary'] as Map<String, dynamic>?),
      );
}

class StaffCalendar {
  final int staffId;
  final String name;
  final String? shiftStart;
  final String? shiftEnd;
  final String? photoUrl;
  final List<CalDay> days;
  final CalSummary summary;

  StaffCalendar({
    required this.staffId,
    required this.name,
    this.shiftStart,
    this.shiftEnd,
    this.photoUrl,
    required this.days,
    required this.summary,
  });

  Map<int, String> get byDay => {for (final d in days) d.date.day: d.status};

  factory StaffCalendar.fromJson(Map<String, dynamic> j) => StaffCalendar(
        staffId: j['staff_id'] as int,
        name: j['name'] as String? ?? '',
        shiftStart: j['shift_start'] as String?,
        shiftEnd: j['shift_end'] as String?,
        photoUrl: j['photo_url'] as String?,
        days: (j['days'] as List? ?? [])
            .map((e) => CalDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        summary: CalSummary.fromJson(j['summary'] as Map<String, dynamic>?),
      );
}

class CourtCalendar {
  final int courtId;
  final String courtName;
  final int dayCutoffHour;
  final List<StaffCalendar> staff;

  CourtCalendar({
    required this.courtId,
    required this.courtName,
    required this.dayCutoffHour,
    required this.staff,
  });

  factory CourtCalendar.fromJson(Map<String, dynamic> j) => CourtCalendar(
        courtId: j['court_id'] as int,
        courtName: j['court_name'] as String? ?? 'Court',
        dayCutoffHour: (j['day_cutoff_hour'] ?? 0) as int,
        staff: (j['staff'] as List? ?? [])
            .map((e) => StaffCalendar.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
