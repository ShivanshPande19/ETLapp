// Regression test: opening the notices date picker must not overflow.
//
// The notices screen previously themed showDatePicker with Theme.of(ctx) (the
// full app theme, whose GoogleFonts display/headline text styles are large).
// The Material date picker renders its header with those styles inside a
// fixed-height dialog Column -> giant RenderFlex bottom overflow. This test
// pumps the screen with a fake repo and taps the date chip to catch it.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:etl_manager_app/core/theme/app_theme.dart';
import 'package:etl_manager_app/features/notices/data/notices_repository.dart';
import 'package:etl_manager_app/features/notices/domain/notice_model.dart';
import 'package:etl_manager_app/features/notices/presentation/notices_screen.dart';

class _FakeRepo extends NoticesRepository {
  final NoticesResult result;
  _FakeRepo(this.result) : super(Dio());
  @override
  Future<NoticesResult> getNotices({String? date, int limit = 30, int offset = 0}) async => result;
  @override
  Future<int> unreadCount() async => result.unreadCount;
  @override
  Future<void> markRead(int id) async {}
  @override
  Future<void> markAllRead() async {}
}

NoticeModel _n(int id) => NoticeModel(
      id: id,
      audience: 'manager',
      type: 'generic',
      title: 'Notice $id',
      body: 'Body $id',
      isRead: false,
      createdAt: DateTime.now(),
    );

Future<void> _pump(WidgetTester tester, NoticesResult result,
    {double textScale = 1.0}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [noticesRepositoryProvider.overrideWithValue(_FakeRepo(result))],
      child: MaterialApp(
        theme: AppTheme.dark,
        // Mirror the real app: a large accessibility text scale, which is what
        // stresses the Material date picker's fixed-height internals.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const NoticesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty notices body does not overflow', (tester) async {
    await _pump(tester, const NoticesResult(notices: [], unreadCount: 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('notices list body does not overflow', (tester) async {
    await _pump(
      tester,
      NoticesResult(notices: [for (var i = 0; i < 8; i++) _n(i)], unreadCount: 3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the date picker does not overflow', (tester) async {
    await _pump(tester, const NoticesResult(notices: [], unreadCount: 0));
    await tester.tap(find.byIcon(Icons.calendar_today_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('date picker does not overflow on a small phone + large text',
      (tester) async {
    // iPhone-ish portrait, small logical height, and a large accessibility
    // text scale — the combination that reproduces the date-picker overflow.
    tester.view.physicalSize = const Size(1170, 2100); // ~390x700 logical @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, const NoticesResult(notices: [], unreadCount: 0),
        textScale: 1.3);
    await tester.tap(find.byIcon(Icons.calendar_today_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
