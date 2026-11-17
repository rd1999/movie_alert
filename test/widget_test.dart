import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/app/app.dart';
import 'package:movie_alert/core/prefs/prefs.dart';
import 'package:movie_alert/data/sources/showtime_source.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtime_core/showtime_core.dart';

import 'support/fake_source.dart';

Future<FakeSource> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  FakeSource? source,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final fake = source ?? FakeSource();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        showtimeSourceProvider.overrideWithValue(fake),
      ],
      retry: (_, _) => null,
      child: const ShowWatchApp(),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('first launch asks for a city and remembers it', (tester) async {
    await pumpApp(tester);
    expect(find.text('Choose your city'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'kol');
    await tester.pumpAndSettle();
    expect(find.text('Agra'), findsNothing);

    await tester.tap(find.text('Kolkata'));
    await tester.pumpAndSettle();
    expect(find.text('Test Doomsday'), findsOneWidget);
    expect(find.text('Kolkata'), findsOneWidget); // city button in app bar

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('city.key'), 'kolkata');
  });

  testWidgets('movie -> showtimes -> show detail', (tester) async {
    final fake = await pumpApp(tester, prefs: {'city.key': 'kolkata'});
    await tester.tap(find.text('Test Doomsday'));
    await tester.pumpAndSettle();

    expect(find.text('Test Mani Square'), findsOneWidget);
    expect(find.text('Cancellation available'), findsOneWidget);
    expect(find.textContaining('1 cinemas · 2 shows'), findsOneWidget);
    expect(find.text('240 left'), findsOneWidget);
    expect(
      find.text('Sold out'),
      findsOneWidget,
    ); // colour is not the only signal
    // Late-night show listed under the 17th but playing at 01:00 on the 18th.
    expect(find.text('01:00 +1', findRichText: true), findsOneWidget);
    expect(fake.calls, contains('showtimes:kolkata:test-doomsday:null:null'));

    // Format filter.
    await tester.tap(find.widgetWithText(FilterChip, 'PXL 3D'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 cinemas · 1 shows'), findsOneWidget);

    // Show detail sheet.
    await tester.tap(find.text('240 left'));
    await tester.pumpAndSettle();
    expect(find.text('RECLINER'), findsOneWidget);
    expect(find.text('₹1100'), findsOneWidget);
    expect(find.text('3 of 18 left · Almost full'), findsOneWidget);
    expect(find.text('Open booking'), findsOneWidget);
  });

  testWidgets('switching date or language fetches that page', (tester) async {
    final fake = await pumpApp(tester, prefs: {'city.key': 'kolkata'});
    await tester.tap(find.text('Test Doomsday'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('18 Dec'));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'showtimes:kolkata:test-doomsday:en:2026-12-18');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Hindi'));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'showtimes:kolkata:test-doomsday:hi:null');
  });

  testWidgets('a changed data source is an error, never "no shows"', (
    tester,
  ) async {
    await pumpApp(
      tester,
      prefs: {'city.key': 'kolkata'},
      source: FakeSource(failWith: SourceFormatChanged('rails missing')),
    );
    expect(find.text('Data source changed — update needed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('No movies'), findsNothing);
  });
}
