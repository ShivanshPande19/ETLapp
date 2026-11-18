// The vendor sheet's Week / Month breakdown: the toggle swaps the period, the
// arrows step through periods, and each period's data is requested with the
// right date range. Also guards against layout overflow at phone width.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:etl_manager_app/features/sales/data/sales_repository.dart';
import 'package:etl_manager_app/features/sales/presentation/vendor_detail_sheet.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime get _yesterday {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - 1);
}

List<DailySnapshot> _days(DateTime from, DateTime to) {
  final out = <DailySnapshot>[];
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    // Every 6th day closed, to exercise the "no sales" rows.
    final sales = d.day % 6 == 0 ? 0.0 : 10000.0 + d.day * 900;
    out.add(DailySnapshot(
      date: _iso(d),
      totalSales: sales,
      totalBills: sales == 0 ? 0 : 40 + d.day,
    ));
  }
  return out;
}

class _FakeRepo extends SalesRepository {
  _FakeRepo() : super(Dio());

  final calls = <String>[];

  @override
  Future<VendorHistory> fetchVendorHistory({
    required String vendorName,
    required int courtId,
  }) async {
    final y = _yesterday;
    return VendorHistory(
      vendorName: vendorName,
      sourceSystem: 'Petpooja',
      totalSales: 23456,
      billCount: 80,
      avgBillValue: 293,
      lastSynced: DateTime.now().toIso8601String(),
      weekTotal: 150000,
      lastWeekTotal: 140000,
      bestDay: _iso(y),
      dailyHistory: _days(DateTime(y.year, y.month, y.day - 6), y),
    );
  }

  @override
  Future<List<DailySnapshot>> fetchVendorDaily({
    required String vendorName,
    required int courtId,
    required DateTime from,
    required DateTime to,
  }) async {
    calls.add('${_iso(from)}..${_iso(to)}');
    final end = to.isAfter(_yesterday) ? _yesterday : to;
    return _days(from, end);
  }
}

Future<_FakeRepo> _open(WidgetTester t) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final repo = _FakeRepo();
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showVendorDetail(
              context: ctx,
              vendorName: 'Sausage Saloon',
              courtId: 1,
              repo: repo,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return repo;
}

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('week view is served from the first load, no extra request',
      (t) async {
    final repo = await _open(t);
    await _scrollTo(t, find.text('Daily Breakdown'));
    expect(repo.calls, isEmpty);
    await t.drag(find.byType(Scrollable).last, const Offset(0, 400));
    await t.pumpAndSettle();
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('week arrows step back 7 days and forward again', (t) async {
    final repo = await _open(t);
    await _scrollTo(t, find.text('Breakdown'));
    await t.tap(find.bySemanticsLabel('Previous'));
    await t.pumpAndSettle();
    final y = _yesterday;
    final end = DateTime(y.year, y.month, y.day - 7);
    final start = DateTime(end.year, end.month, end.day - 6);
    expect(repo.calls, ['${_iso(start)}..${_iso(end)}']);
    expect(find.text('Last 7 days'), findsNothing);

    await t.tap(find.bySemanticsLabel('Next'));
    await t.pumpAndSettle();
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(repo.calls.length, 1); // came from the cache
  });

  testWidgets('month toggle loads the whole current month', (t) async {
    final repo = await _open(t);
    await _scrollTo(t, find.text('Breakdown'));
    await t.tap(find.text('Month'));
    await t.pumpAndSettle();
    final y = _yesterday;
    final first = DateTime(y.year, y.month, 1);
    final last = DateTime(y.year, y.month + 1, 0);
    expect(repo.calls, ['${_iso(first)}..${_iso(last)}']);
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    expect(find.text(names[y.month - 1]), findsOneWidget);
    // Next is disabled on the latest month: tapping it requests nothing.
    await t.tap(find.bySemanticsLabel('Next'));
    await t.pumpAndSettle();
    expect(repo.calls.length, 1);

    await t.tap(find.bySemanticsLabel('Previous'));
    await t.pumpAndSettle();
    final prev = DateTime(y.year, y.month - 1, 1);
    expect(repo.calls.last,
        '${_iso(prev)}..${_iso(DateTime(prev.year, prev.month + 1, 0))}');
    expect(t.takeException(), isNull);
  });
}
