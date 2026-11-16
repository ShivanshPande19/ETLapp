// The staff checklist screen's empty / failed states and pull-to-refresh.
//
// A failed load used to render exactly like a court with no checklist ("No
// checklist yet — This court has no housekeeping checklist configured."), and
// the screen had no way to reload. These pin the real screen, not just the
// notifier behind it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:etl_manager_app/features/staff/domain/housekeeping_notifier.dart';
import 'package:etl_manager_app/features/staff/presentation/staff_checklist_screen.dart';

class _FakeHk extends HousekeepingNotifier {
  _FakeHk(this._initial);
  final HousekeepingState _initial;
  int refreshes = 0;

  @override
  HousekeepingState build() => _initial; // no auth, no network, no timers

  @override
  Future<void> refresh() async => refreshes++;
}

String get _today => DateTime.now().toIso8601String().substring(0, 10);

const _notConfigured = 'No checklist yet';
const _couldNotLoad = "Couldn't load your checklist";

Future<_FakeHk> _pump(WidgetTester t, HousekeepingState s) async {
  final fake = _FakeHk(s);
  await t.pumpWidget(
    ProviderScope(
      overrides: [housekeepingNotifierProvider.overrideWith(() => fake)],
      child: const MaterialApp(home: StaffChecklistScreen()),
    ),
  );
  await t.pump(const Duration(milliseconds: 500)); // entrance fade
  return fake;
}

void main() {
  testWidgets('a failed load says so, and never claims "not configured"',
      (t) async {
    await _pump(
      t,
      HousekeepingState(
        date: _today,
        isInitialized: true,
        loadFailed: true,
        loadError: 'Check your internet and try again.',
      ),
    );

    expect(find.text(_couldNotLoad), findsOneWidget);
    expect(find.text('Check your internet and try again.'), findsOneWidget);
    expect(find.text(_notConfigured), findsNothing);
  });

  testWidgets("shows the server's own reason when it gave one", (t) async {
    await _pump(
      t,
      HousekeepingState(
        date: _today,
        isInitialized: true,
        loadFailed: true,
        loadError: 'No court assigned to your account.',
      ),
    );
    expect(find.text('No court assigned to your account.'), findsOneWidget);
  });

  testWidgets('Retry reloads', (t) async {
    final fake = await _pump(
      t,
      HousekeepingState(date: _today, isInitialized: true, loadFailed: true),
    );
    await t.tap(find.text('Retry'));
    await t.pump();
    expect(fake.refreshes, 1);
  });

  testWidgets('Retry is visibly busy and inert while a load runs', (t) async {
    final fake = await _pump(
      t,
      HousekeepingState(
        date: _today,
        isInitialized: true,
        loadFailed: true,
        loading: true,
      ),
    );
    expect(find.text('Checking…'), findsOneWidget);
    await t.tap(find.text('Checking…'), warnIfMissed: false);
    await t.pump();
    expect(fake.refreshes, 0);
  });

  testWidgets('a court that truly has no shifts still says "not configured"',
      (t) async {
    await _pump(t, HousekeepingState(date: _today, isInitialized: true));
    expect(find.text(_notConfigured), findsOneWidget);
    expect(find.text(_couldNotLoad), findsNothing);
  });

  testWidgets('pull-to-refresh reloads from the failed state', (t) async {
    final fake = await _pump(
      t,
      HousekeepingState(date: _today, isInitialized: true, loadFailed: true),
    );
    await t.fling(find.text(_couldNotLoad), const Offset(0, 400), 1200);
    await t.pump(); // start the refresh
    await t.pump(const Duration(seconds: 1)); // let the indicator finish
    expect(fake.refreshes, 1);
  });

  testWidgets('pull-to-refresh reloads from the empty state too', (t) async {
    final fake = await _pump(
      t,
      HousekeepingState(date: _today, isInitialized: true),
    );
    await t.fling(find.text(_notConfigured), const Offset(0, 400), 1200);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(fake.refreshes, 1);
  });
}
