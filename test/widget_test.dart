// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travelplanner/widgets/recommendation_status.dart';

void main() {
  testWidgets('failed nearby search offers a working retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecommendationStatus(
            message: 'Nearby places could not be loaded.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('Nearby places could not be loaded.'), findsOneWidget);
    await tester.tap(find.text('Retry nearby places'));
    expect(retries, 1);
  });
  testWidgets('missing origin explains how to enable recommendations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecommendationStatus(
            message: 'Add a starting location or accommodation.',
          ),
        ),
      ),
    );
    expect(
      find.text('Add a starting location or accommodation.'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);
  });
}
