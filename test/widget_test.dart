import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/data/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtime_core/showtime_core.dart';

import 'support/fake_source.dart';
import 'support/test_app.dart';

const kolkata = {'city.key': 'kolkata'};

Future<void> openMovie(WidgetTester tester) async {
  await tester.tap(find.text('Test Doomsday'));
  await tester.pumpAndSettle();
}

Future<void> openCreateAlert(WidgetTester tester) async {
  await openMovie(tester);
  await tester.tap(find.text('Alert me'));
  await tester.pumpAndSettle();
}

Future<void> tapCreate(WidgetTester tester) async {
  final button = find.text('Create alert');
  await tester.scrollUntilVisible(
    button,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> pickCinema(WidgetTester tester, String name) async {
  await tester.tap(find.text('Choose cinemas'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Done ('));
  await tester.pumpAndSettle();
}

void main() {
  group('browse', () {
    testWidgets('first launch asks for a city and remembers it', (
      tester,
    ) async {
      await TestApp().pump(tester);
      expect(find.text('Choose your city'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'kol');
      await tester.pumpAndSettle();
      expect(find.text('Agra'), findsNothing);

      await tester.tap(find.text('Kolkata'));
      await tester.pumpAndSettle();
      expect(find.text('Test Doomsday'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('city.key'), 'kolkata');
    });

    testWidgets('movie -> showtimes -> show detail', (tester) async {
      final app = TestApp();
      await app.pump(tester, prefs: kolkata);
      await openMovie(tester);

      expect(find.text('Test Mani Square'), findsOneWidget);
      expect(find.text('Cancellation available'), findsOneWidget);
      expect(find.textContaining('1 cinemas · 2 shows'), findsOneWidget);
      expect(find.text('240 left'), findsOneWidget);
      expect(find.text('Sold out'), findsOneWidget); // not colour alone
      // Late-night show listed under the 17th but playing at 01:00 on the 18th.
      expect(find.text('01:00 +1', findRichText: true), findsOneWidget);
      expect(
        app.source.calls,
        contains('showtimes:kolkata:test-doomsday:null:null'),
      );

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'PXL 3D'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show 1 shows'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 cinemas · 1 shows'), findsOneWidget);
      expect(find.text('Filters (1)'), findsOneWidget);

      await tester.tap(find.text('240 left'));
      await tester.pumpAndSettle();
      expect(find.text('RECLINER'), findsOneWidget);
      expect(find.text('₹1100'), findsOneWidget);
      expect(find.text('3 of 18 left · Almost full'), findsOneWidget);
      expect(find.text('Open booking'), findsOneWidget);
    });

    testWidgets('switching date or language fetches that page', (tester) async {
      final app = TestApp();
      await app.pump(tester, prefs: kolkata);
      await openMovie(tester);

      await tester.tap(find.text('18 Dec'));
      await tester.pumpAndSettle();
      expect(
        app.source.calls.last,
        'showtimes:kolkata:test-doomsday:en:2026-12-18',
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Hindi'));
      await tester.pumpAndSettle();
      expect(app.source.calls.last, 'showtimes:kolkata:test-doomsday:hi:null');
    });

    testWidgets('a changed data source is an error, never "no shows"', (
      tester,
    ) async {
      await TestApp(
        source: FakeSource(failWith: SourceFormatChanged('rails missing')),
      ).pump(tester, prefs: kolkata);
      expect(find.text('Data source changed — update needed'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('No movies'), findsNothing);
    });
  });

  group('alerts', () {
    testWidgets('alert on a cinema that is not showing the movie yet', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester, prefs: kolkata);
      await openCreateAlert(tester);

      await tester.tap(find.text('Choose cinemas'));
      await tester.pumpAndSettle();
      expect(find.text('Not showing it yet'), findsOneWidget);
      expect(find.text('Showing this movie now'), findsOneWidget);
      await tester.tap(find.text('Test Not Yet Cinema'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done (1)'));
      await tester.pumpAndSettle();

      await tapCreate(tester);

      final alert = app.store.byId.values.single;
      expect((alert.condition as CinemaOpens).cinemaIds, {555});
      expect(alert.cinemaNames, {555: 'Test Not Yet Cinema'});
      expect(
        alert.lastCheckedAt,
        isNotNull,
        reason: 'first check runs at once',
      );
      expect(alert.status, AlertStatus.active);
      expect(app.notifier.fired, isEmpty);
      expect(app.scheduler.synced, isNotEmpty);
      expect(find.text('Alert set. Checking every 30 min.'), findsOneWidget);
      expect(app.store.log.single.outcome, CheckOutcome.ok);
    });

    testWidgets('already-true condition notifies right away', (tester) async {
      final app = TestApp();
      await app.pump(tester, prefs: kolkata);
      await openCreateAlert(tester);
      await pickCinema(tester, 'Test Mani Square');
      await tapCreate(tester);

      expect(app.notifier.fired.single.kind, AlertEventKind.alreadyAvailable);
      expect(app.store.byId.values.single.status, AlertStatus.fired);
      expect(
        find.text('Already available! See the notification.'),
        findsOneWidget,
      );
    });

    testWidgets('validation: a cinema alert needs a cinema', (tester) async {
      final app = TestApp();
      await app.pump(tester, prefs: kolkata);
      await openCreateAlert(tester);
      await tapCreate(tester);
      expect(
        find.text('"Cinema opens" needs at least one cinema'),
        findsOneWidget,
      );
      expect(app.store.byId, isEmpty);
    });

    testWidgets('asks for notification permission with an explanation', (
      tester,
    ) async {
      final app = TestApp(permissions: FakePermissions(granted: false));
      await app.pump(tester, prefs: kolkata);
      await openCreateAlert(tester);
      await tester.tap(find.text('Any new cinema'));
      await tester.pumpAndSettle();
      await tapCreate(tester);

      expect(find.text('Allow notifications?'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(app.permissions.requests, 1);
      expect(app.store.byId.values.single.condition, isA<NewCinemaAnywhere>());
    });

    testWidgets('alerts tab: list, pause, history', (tester) async {
      final app = TestApp();
      final now = DateTime.now();
      await app.store.saveAlert(
        Alert(
          id: 'a1',
          cityKey: 'kolkata',
          movieContentId: 176735,
          movieSlug: 'test-doomsday',
          movieName: 'Test Doomsday',
          condition: const CinemaOpens({1020736}),
          cinemaNames: const {1020736: 'PVR Mani Square'},
          dates: const {'2026-12-18'},
          createdAt: now,
          lastCheckedAt: now.subtract(const Duration(minutes: 5)),
          checkCount: 3,
        ),
      );
      await app.store.addLog(
        CheckLogEntry(
          alertId: 'a1',
          at: now,
          outcome: CheckOutcome.ok,
          message: 'No match yet · 2 shows seen',
          pagesFetched: 2,
        ),
      );
      await app.pump(tester, prefs: kolkata);
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();

      expect(find.text('Shows at PVR Mani Square'), findsOneWidget);
      expect(find.text('Watching'), findsOneWidget);
      expect(find.textContaining('Checked 5 min ago'), findsOneWidget);
      expect(find.textContaining('3 checks'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(app.store.byId['a1']!.status, AlertStatus.paused);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.text('Shows at PVR Mani Square'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No match yet · 2 shows seen'),
        findsOneWidget,
      );
      expect(find.textContaining('2 page(s) fetched'), findsOneWidget);
    });
  });

  group('checks while the app is open', () {
    testWidgets('due alerts are checked on start; others are not', (
      tester,
    ) async {
      final app = TestApp()..foregroundChecks = true;
      final now = DateTime.now();
      Alert alert(String id, DateTime? last) => Alert(
        id: id,
        cityKey: 'kolkata',
        movieContentId: 176735,
        movieSlug: 'test-doomsday',
        movieName: 'Test Doomsday',
        condition: const CinemaOpens({555}),
        createdAt: now,
        lastCheckedAt: last,
      );
      await app.store.saveAlert(alert('due', null));
      await app.store.saveAlert(
        alert('fresh', now.subtract(const Duration(minutes: 1))),
      );
      await app.pump(tester, prefs: kolkata);

      expect(app.store.byId['due']!.lastCheckedAt, isNotNull);
      expect(app.store.byId['due']!.checkCount, 1);
      expect(app.store.byId['fresh']!.checkCount, 0);

      // Unmount so the periodic timer is cancelled.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
