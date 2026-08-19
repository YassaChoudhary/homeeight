import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homeeight/data/mock_listing_repository.dart';
import 'package:homeeight/main.dart';

void main() {
  testWidgets('App boots to the splash screen', (WidgetTester tester) async {
    // Zero latency so async surfaces settle deterministically in tests.
    await tester.pumpWidget(
      Home8App(repository: MockListingRepository(latency: Duration.zero)),
    );

    expect(find.text('Find, trust & close on a home'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the splash timer fire so nothing is left pending at teardown.
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();
  });
}
