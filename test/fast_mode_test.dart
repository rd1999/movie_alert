import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/background/fast_mode_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtime_core/showtime_core.dart';

import 'support/test_app.dart';

class FakeFastMode implements FastModeGateway {
  FastModeState current = const FastModeState();
  Duration left = const Duration(hours: 6);
  final starts = <(Duration, Duration)>[];
  int stops = 0;

  @override
  bool get supported => true;

  @override
  Future<FastModeState> state() async => current;

  @override
  Future<Duration> remainingToday() async => left;

  @override
  Future<void> start({
    required Duration interval,
    required Duration length,
  }) async {
    starts.add((interval, length));
    current = FastModeState(
      endsAt: DateTime.now().add(length),
      interval: interval,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    current = const FastModeState();
  }
}

void main() {
  group('FastModeBudget (6 h per day)', () {
    test('reserve, refund, and reset the next day', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final day = DateTime(2026, 12, 17, 18);
      expect(FastModeBudget.remaining(p, day), const Duration(hours: 6));

      await FastModeBudget.reserve(p, day, const Duration(hours: 2));
      expect(FastModeBudget.remaining(p, day), const Duration(hours: 4));

      await FastModeBudget.refund(p, day, const Duration(minutes: 30));
      expect(FastModeBudget.used(p, day), const Duration(minutes: 90));

      await FastModeBudget.reserve(p, day, const Duration(hours: 5));
      expect(FastModeBudget.remaining(p, day), Duration.zero);

      expect(
        FastModeBudget.remaining(p, DateTime(2026, 12, 18, 0, 5)),
        const Duration(hours: 6),
      );
    });

    test('state round-trip and clear', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final ends = DateTime(2026, 12, 17, 21, 30);
      await p.setInt(FastModeBudget.kEndsAt, ends.millisecondsSinceEpoch);
      await p.setInt(FastModeBudget.kInterval, 300);
      final s = FastModeBudget.state(p);
      expect(s.endsAt, ends);
      expect(s.interval, const Duration(minutes: 5));
      expect(s.isRunning(DateTime(2026, 12, 17, 21)), isTrue);
      expect(s.isRunning(DateTime(2026, 12, 17, 21, 30)), isFalse);
      await FastModeBudget.clear(p);
      expect(FastModeBudget.state(p).endsAt, isNull);
    });
  });

  testWidgets('start and stop fast mode from the Alerts tab', (tester) async {
    final fast = FakeFastMode();
    final app = TestApp()..fastMode = fast;
    await app.store.saveAlert(
      Alert(
        id: 'a',
        cityKey: 'kolkata',
        movieContentId: 176735,
        movieSlug: 'test-doomsday',
        movieName: 'Test Doomsday',
        condition: const CinemaOpens({1020736}),
        createdAt: DateTime.now(),
        lastCheckedAt: DateTime.now(),
      ),
    );
    await app.pump(tester, prefs: {'city.key': 'kolkata'});
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fast mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 min'));
    await tester.tap(find.text('2 h'));
    await tester.pumpAndSettle();
    expect(find.textContaining('~60 checks'), findsOneWidget);
    await tester.tap(find.text('Start fast mode'));
    await tester.pumpAndSettle();

    expect(fast.starts.single, (
      const Duration(minutes: 2),
      const Duration(hours: 2),
    ));
    expect(find.text('Fast mode is on'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(fast.stops, 1);
    expect(find.text('Fast mode is on'), findsNothing);
  });

  testWidgets('lengths over the remaining daily budget are disabled', (
    tester,
  ) async {
    final fast = FakeFastMode()..left = const Duration(minutes: 45);
    final app = TestApp()..fastMode = fast;
    await app.store.saveAlert(
      Alert(
        id: 'a',
        cityKey: 'kolkata',
        movieContentId: 1,
        movieSlug: 'm',
        movieName: 'M',
        condition: const NewCinemaAnywhere(),
        createdAt: DateTime.now(),
        lastCheckedAt: DateTime.now(),
      ),
    );
    await app.pump(tester, prefs: {'city.key': 'kolkata'});
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fast mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 h')); // disabled: no change
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start fast mode'));
    await tester.pumpAndSettle();
    expect(fast.starts.single.$2, const Duration(minutes: 30));
  });
}
