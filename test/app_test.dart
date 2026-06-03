import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordplay/main.dart';

void main() {
  // Boot the app at a given size + theme, let the word lists load, and make
  // sure the board renders with no layout-overflow errors. This stands in for
  // eyeballing the UI on different screens.
  Future<void> bootAt(WidgetTester tester, Size size, String theme) async {
    SharedPreferences.setMockInitialValues(
        {'theme': theme, 'seenIntro': true});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(const WordplayApp());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.text('WORDPLAY'), findsOneWidget);
    expect(find.text('ENTER'), findsOneWidget); // keyboard => game ready
    expect(find.text('Unlimited'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow / render errors
  }

  final sizes = {
    'narrow phone': const Size(320, 640),
    'phone': const Size(390, 844),
    'tablet/desktop': const Size(1280, 900),
  };

  for (final entry in sizes.entries) {
    for (final theme in ['dark', 'light']) {
      testWidgets('renders on ${entry.key} ($theme)', (tester) async {
        await bootAt(tester, entry.value, theme);
      });
    }
  }

  testWidgets('renders in daily mode', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'mode': 'daily', 'seenIntro': true});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(const WordplayApp());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('ENTER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
