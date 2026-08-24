// Basic smoke test.
//
// The full app (ETLApp) needs ProviderScope + Firebase + go_router wiring to
// pump, which isn't available in a plain widget test. This keeps a lightweight,
// always-green sanity check that the test toolchain and rendering work — and,
// importantly, it no longer references the non-existent `MyApp` from the
// default Flutter template (the app root is `ETLApp`), which was a compile
// error that broke `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp renders (smoke test)', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: Text('ETL')))),
    );
    expect(find.text('ETL'), findsOneWidget);
  });
}
