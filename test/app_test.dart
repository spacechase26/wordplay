import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordplay/main.dart';

void main() {
  testWidgets('boots, loads words and shows the board', (tester) async {
    SharedPreferences.setMockInitialValues({});

    // runAsync lets the real asset I/O (loading the word lists) complete;
    // plain pump runs in fake-async and never would.
    await tester.runAsync(() async {
      await tester.pumpWidget(const WordplayApp());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.text('WORDPLAY'), findsOneWidget);
    expect(find.text('ENTER'), findsOneWidget); // keyboard => game is ready
    expect(find.text('Unlimited'), findsOneWidget); // mode control rendered
  });
}
