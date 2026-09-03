import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sales_repository.dart';

enum SalesLoadStatus { idle, loading, loaded, error }

/// Granularity of the sales view:
///   day    → a single business day
///   week   → a calendar week (Mon–Sun)
///   month  → a calendar month
///   year   → a calendar year
///   custom → an arbitrary from–to range
///
/// For day/week/month/year the "anchor" date sits inside the selected period,
/// and prev/next navigation moves the anchor by one unit — so the user can go
/// to LAST week / LAST month / a specific day, etc. `custom` is picked via a
/// date-range picker and has no prev/next.
enum SalesPeriod { day, week, month, year, custom }

const _monthsShort = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _monthsLong = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _yesterday() =>
    _dateOnly(DateTime.now()).subtract(const Duration(days: 1));
String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A resolved date window plus a human label for the header.
class SalesRange {
  final DateTime from;
  final DateTime to;
  final String label;
  const SalesRange({required this.from, required this.to, required this.label});
  String get fromStr => _iso(from);
  String get toStr => _iso(to);
}

String _dayLabel(DateTime d) => '${d.day} ${_monthsShort[d.month]} ${d.year}';

String _spanLabel(DateTime a, DateTime b) {
  if (a.year == b.year && a.month == b.month) {
    return '${a.day}–${b.day} ${_monthsShort[a.month]} ${a.year}';
  }
  if (a.year == b.year) {
    return '${a.day} ${_monthsShort[a.month]} – ${b.day} ${_monthsShort[b.month]} ${a.year}';
  }
  return '${a.day} ${_monthsShort[a.month]} ${a.year} – ${b.day} ${_monthsShort[b.month]} ${b.year}';
}

/// Shift an anchor by `dir` units of the given granularity.
DateTime _shiftAnchor(SalesPeriod g, DateTime anchor, int dir) {
  switch (g) {
    case SalesPeriod.day:
      return _dateOnly(anchor).add(Duration(days: dir));
    case SalesPeriod.week:
      return _dateOnly(anchor).add(Duration(days: 7 * dir));
    case SalesPeriod.month:
      return DateTime(anchor.year, anchor.month + dir, 1);
    case SalesPeriod.year:
      return DateTime(anchor.year + dir, 1, 1);
    case SalesPeriod.custom:
      return anchor; // custom doesn't navigate
  }
}

/// Resolve the concrete window for a granularity + anchor (or custom range).
/// The window is always clipped so it never extends past yesterday (today's
/// sales aren't synced yet). The label keeps the natural period name.
SalesRange _computeRange(
  SalesPeriod g,
  DateTime anchor,
  DateTime? customFrom,
  DateTime? customTo,
) {
  final cap = _yesterday();
  DateTime from;
  DateTime to;
  String label;

  switch (g) {
    case SalesPeriod.day:
      from = _dateOnly(anchor);
      to = from;
      label = _dayLabel(from);
      break;
    case SalesPeriod.week:
      final monday =
          _dateOnly(anchor).subtract(Duration(days: anchor.weekday - 1));
      final sunday = monday.add(const Duration(days: 6));
      from = monday;
      to = sunday;
      label = _spanLabel(monday, sunday);
      break;
    case SalesPeriod.month:
      from = DateTime(anchor.year, anchor.month, 1);
      to = DateTime(anchor.year, anchor.month + 1, 0); // last day of month
      label = '${_monthsLong[anchor.month]} ${anchor.year}';
      break;
    case SalesPeriod.year:
      from = DateTime(anchor.year, 1, 1);
      to = DateTime(anchor.year, 12, 31);
      label = '${anchor.year}';
      break;
    case SalesPeriod.custom:
      from = _dateOnly(customFrom ?? cap);
      to = _dateOnly(customTo ?? from);
      if (to.isBefore(from)) {
        final t = from;
        from = to;
        to = t;
      }
      label = from == to ? _dayLabel(from) : _spanLabel(from, to);
      break;
  }

  if (to.isAfter(cap)) to = cap;
  if (from.isAfter(cap)) from = cap;
  return SalesRange(from: from, to: to, label: label);
}

class SalesState {
  final SalesLoadStatus status;
  final SalesSummary? summary;
  final SalesTrend? trend;
  final String? error;
  final int? selectedCourtId;
  final int? selectedOutletId;
  final bool allCourts;
  final SalesPeriod period;
  final SalesRange range;
  final bool canGoPrev;
  final bool canGoNext;

  const SalesState({
    this.status = SalesLoadStatus.idle,
    this.summary,
    this.trend,
    this.error,
    this.selectedCourtId,
    this.selectedOutletId,
    this.allCourts = true,
    this.period = SalesPeriod.day,
    required this.range,
    this.canGoPrev = true,
    this.canGoNext = false,
  });
}

class _CachedSales {
  final SalesSummary summary;
  final SalesTrend? trend;
  const _CachedSales(this.summary, this.trend);
}

class SalesNotifier extends Notifier<SalesState> {
  final Map<String, _CachedSales> _cache = {};
  int _reqCounter = 0;

  // Current selection (source of truth; drives every fetch).
  SalesPeriod _granularity = SalesPeriod.day;
  DateTime _anchor = _yesterday();
  DateTime? _customFrom;
  DateTime? _customTo;
  int? _courtId;
  int? _outletId;
  bool _allCourts = true;

  @override
  SalesState build() {
    Future.microtask(_load);
    return SalesState(
      status: SalesLoadStatus.loading,
      range: _computeRange(_granularity, _anchor, _customFrom, _customTo),
    );
  }

  // ── Public API used by the screens ─────────────────────────────────────────

  /// Switch granularity (Day/Week/Month/Year). Anchor resets to the most recent
  /// completed period (i.e. anchored on yesterday). Use [selectCustomRange] for
  /// custom. Optionally re-scope to a court / outlet / all courts.
  Future<void> selectPeriod(
    SalesPeriod g, {
    int? courtId,
    int? outletId,
    bool? allCourts,
  }) async {
    _applyScope(courtId: courtId, outletId: outletId, allCourts: allCourts);
    _granularity = g;
    if (g != SalesPeriod.custom) {
      _anchor = _yesterday();
      _customFrom = null;
      _customTo = null;
    }
    await _load();
  }

  /// Move the current period by one unit: -1 = previous, +1 = next.
  Future<void> shift(int direction) async {
    if (_granularity == SalesPeriod.custom) return;
    final candidate = _shiftAnchor(_granularity, _anchor, direction);
    // Don't move into the future (no data past yesterday).
    final r = _computeRange(_granularity, candidate, null, null);
    if (direction > 0 && r.from.isAfter(_yesterday())) return;
    _anchor = candidate;
    await _load();
  }

  /// Pick an arbitrary from–to range (custom).
  Future<void> selectCustomRange(
    DateTime from,
    DateTime to, {
    int? courtId,
    int? outletId,
    bool? allCourts,
  }) async {
    _applyScope(courtId: courtId, outletId: outletId, allCourts: allCourts);
    _granularity = SalesPeriod.custom;
    _customFrom = from;
    _customTo = to;
    await _load();
  }

  /// Re-scope (e.g. court tab switch / outlet switch) keeping the current
  /// period + anchor.
  Future<void> selectScope({
    int? courtId,
    int? outletId,
    bool? allCourts,
  }) async {
    _applyScope(courtId: courtId, outletId: outletId, allCourts: allCourts);
    await _load();
  }

  void _applyScope({int? courtId, int? outletId, bool? allCourts}) {
    // Scopes are mutually exclusive. Crucially we CLEAR the others so a stale
    // scope can't leak — e.g. an outlet manager's outlet_id must not survive
    // into an ETL manager's court view on the shared, app-lifetime notifier.
    if (outletId != null) {
      // Outlet-scoped view (outlet manager): exactly one outlet, no court.
      _outletId = outletId;
      _courtId = null;
      _allCourts = false;
    } else if (allCourts == true) {
      // All courts (ETL manager): clear any court/outlet scope.
      _allCourts = true;
      _courtId = null;
      _outletId = null;
    } else if (courtId != null) {
      // Specific court (ETL manager): clear any stale outlet scope.
      _allCourts = false;
      _courtId = courtId;
      _outletId = null;
    }
    // No args → no scope change (used by refresh / retry).
  }

  // ── Core fetch ──────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final range = _computeRange(_granularity, _anchor, _customFrom, _customTo);
    final cap = _yesterday();
    final canPrev = _granularity != SalesPeriod.custom;
    final canNext = _granularity != SalesPeriod.custom &&
        !_computeRange(_granularity, _shiftAnchor(_granularity, _anchor, 1),
                null, null)
            .from
            .isAfter(cap);

    final courtId = _allCourts ? null : _courtId;
    final outletId = _outletId;

    // Trend window: for a single day show the last 7 days ending on that day
    // (a useful context chart); otherwise the trend matches the summary range.
    final DateTime trendFrom;
    final DateTime trendTo;
    if (_granularity == SalesPeriod.day) {
      trendTo = range.to;
      trendFrom = range.to.subtract(const Duration(days: 6));
    } else {
      trendFrom = range.from;
      trendTo = range.to;
    }

    final key =
        '${range.fromStr}|${range.toStr}|${courtId ?? 'all'}|o${outletId ?? 'all'}';
    final reqId = ++_reqCounter;

    SalesState base({
      required SalesLoadStatus status,
      SalesSummary? summary,
      SalesTrend? trend,
      String? error,
    }) =>
        SalesState(
          status: status,
          summary: summary,
          trend: trend,
          error: error,
          selectedCourtId: courtId,
          selectedOutletId: outletId,
          allCourts: _allCourts,
          period: _granularity,
          range: range,
          canGoPrev: canPrev,
          canGoNext: canNext,
        );

    // 1) Instant paint from cache, else keep current data visible.
    final cached = _cache[key];
    if (cached != null) {
      state = base(
        status: SalesLoadStatus.loaded,
        summary: cached.summary,
        trend: cached.trend,
      );
    } else {
      state = base(
        status: SalesLoadStatus.loading,
        summary: state.summary,
        trend: state.trend,
      );
    }

    final repo = ref.read(salesRepositoryProvider);

    final summaryFut = repo.getSalesSummary(
      courtId: courtId,
      outletId: outletId,
      period: _granularity.name,
      dateFrom: range.fromStr,
      dateTo: range.toStr,
    );
    final Future<SalesTrend?> trendFut = repo
        .getSalesTrend(
          courtId: courtId,
          outletId: outletId,
          period: _granularity.name,
          dateFrom: _iso(trendFrom),
          dateTo: _iso(trendTo),
        )
        .then<SalesTrend?>((t) => t)
        .catchError((_) => null);

    SalesSummary summary;
    try {
      summary = await summaryFut;
    } catch (e) {
      if (reqId != _reqCounter) return;
      if (cached != null) return;
      state = base(
        status: SalesLoadStatus.error,
        error: e.toString(),
        trend: state.trend,
      );
      return;
    }
    if (reqId != _reqCounter) return;

    state = base(
      status: SalesLoadStatus.loaded,
      summary: summary,
      trend: cached?.trend ?? state.trend,
    );

    final trend = await trendFut;
    if (reqId != _reqCounter) return;
    state = base(status: SalesLoadStatus.loaded, summary: summary, trend: trend);
    _cache[key] = _CachedSales(summary, trend);
  }
}

final salesNotifierProvider = NotifierProvider<SalesNotifier, SalesState>(
  SalesNotifier.new,
);
