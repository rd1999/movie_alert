import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/background/alert_runner.dart';
import 'package:movie_alert/data/db/app_database.dart';
import 'package:showtime_core/showtime_core.dart';

import 'support/memory_store.dart';

const mani = 1020736;

/// Source whose cinemas per (date) can be changed between runs.
class ScriptedSource implements ShowtimeSource {
  final calls = <String>[];
  Object? failWith;

  /// date -> cinema ids showing.
  Map<String, List<int>> listing = {
    '2026-12-17': [148],
    '2026-12-18': [148],
  };

  @override
  String get id => 'scripted';

  @override
  Future<ShowtimesPage> showtimes({
    required String cityKey,
    required String movieSlug,
    required int contentId,
    String? fmtGrpId,
    String? date,
  }) async {
    calls.add('$cityKey/$contentId/${fmtGrpId ?? '-'}/${date ?? '-'}');
    if (failWith case final e?) throw e;
    final dates = listing.keys.toList()..sort();
    final d = date ?? dates.first;
    return ShowtimesPage(
      movie: MovieInfo(contentId: contentId, name: 'Doomsday'),
      languageFormats: const [
        LanguageFormatGroup(language: 'English', fmtGrpId: 'en'),
      ],
      fmtGrpId: 'en',
      listingDate: d,
      sessionDates: dates,
      cinemas: [
        for (final c in listing[d] ?? const <int>[])
          CinemaShows(
            cinema: Cinema(id: c, name: c == mani ? 'PVR Mani Square' : 'C$c'),
            shows: [
              Show(
                sessionId: '$c-$d',
                cinemaId: c,
                showTime: DateTime.parse('${d}T13:40'),
                rawShowTime: '${d}T13:40',
                seatsAvailable: 100,
                seatsTotal: 200,
                availability: SeatAvailability.available,
                screenFormat: 'PXL 3D',
              ),
            ],
          ),
      ],
    );
  }

  @override
  Uri bookingUrl({
    required String cityKey,
    required String movieSlug,
    required int contentId,
    String? fmtGrpId,
    String? date,
  }) => Uri.parse('https://example.invalid/$movieSlug?f=$fmtGrpId&d=$date');

  @override
  Future<List<City>> cities() => throw UnimplementedError();
  @override
  Future<List<Cinema>> cinemas(String cityKey) => throw UnimplementedError();
  @override
  Future<List<MovieSummary>> movies(String cityKey) =>
      throw UnimplementedError();
}

class RecordingNotifier implements AlertNotifier {
  final fired = <(Alert, AlertEvent, Uri)>[];
  final failing = <Alert>[];

  @override
  Future<void> alertFired(Alert a, AlertEvent e, Uri url) async =>
      fired.add((a, e, url));

  @override
  Future<void> alertFailing(Alert a, Object error) async => failing.add(a);
}

void main() {
  late MemoryAlertStore store;
  late ScriptedSource source;
  late RecordingNotifier notifier;
  late DateTime now;
  late AlertRunner runner;

  Alert alert(
    String id,
    AlertCondition c, {
    int contentId = 176735,
    Set<String> dates = const {'2026-12-18'},
    Duration interval = const Duration(minutes: 30),
    DateTime? until,
  }) => Alert(
    id: id,
    cityKey: 'kolkata',
    movieContentId: contentId,
    movieSlug: 'avengers-doomsday',
    movieName: 'Avengers: Doomsday',
    condition: c,
    createdAt: now,
    dates: dates,
    interval: interval,
    activeUntil: until,
  );

  setUp(() {
    store = MemoryAlertStore();
    source = ScriptedSource();
    notifier = RecordingNotifier();
    now = DateTime(2026, 11, 17, 10);
    runner = AlertRunner(
      store: store,
      source: source,
      notifier: notifier,
      clock: () => now,
    );
  });

  test(
    'origin story: quiet until Mani Square appears, then one alert',
    () async {
      await store.saveAlert(alert('mani', const CinemaOpens({mani})));

      var s = await runner.run();
      expect(s.checked, 1);
      expect(notifier.fired, isEmpty);
      expect(store.log.single.outcome, CheckOutcome.ok);
      expect(source.calls, [
        'kolkata/176735/-/-',
        'kolkata/176735/en/2026-12-18',
      ]);

      // Not due again until the interval has passed.
      now = now.add(const Duration(minutes: 10));
      s = await runner.run();
      expect(s.checked, 0);

      source.listing['2026-12-18'] = [148, mani];
      now = now.add(const Duration(minutes: 20));
      s = await runner.run();
      expect(s.fired, 1);
      final (a, event, url) = notifier.fired.single;
      expect(event.kind, AlertEventKind.opened);
      expect(event.shows.single.cinemaName, 'PVR Mani Square');
      expect(
        url.toString(),
        'https://example.invalid/avengers-doomsday?f=en&d=2026-12-18',
      );
      expect(a.status, AlertStatus.fired);
      expect(store.byId['mani']!.status, AlertStatus.fired);
      expect(store.log.last.outcome, CheckOutcome.fired);
      expect(store.snapshots, contains('kolkata:176735'));

      // Fired alerts are not checked again.
      now = now.add(const Duration(hours: 1));
      expect((await runner.run()).checked, 0);
    },
  );

  test('alerts for the same movie share one set of page fetches', () async {
    await store.saveAlert(alert('a', const CinemaOpens({mani})));
    await store.saveAlert(alert('b', const FormatOpens('IMAX')));
    await store.saveAlert(alert('c', const CinemaOpens({1}), contentId: 999));
    final s = await runner.run();
    expect(s.checked, 3);
    expect(s.pagesFetched, 4);
    expect(source.calls, [
      'kolkata/176735/-/-',
      'kolkata/176735/en/2026-12-18',
      'kolkata/999/-/-',
      'kolkata/999/en/2026-12-18',
    ]);
  });

  test('"Check now" forces only the chosen alert', () async {
    await store.saveAlert(alert('a', const CinemaOpens({mani})));
    await store.saveAlert(alert('b', const CinemaOpens({mani}), contentId: 2));
    await runner.run();
    source.calls.clear();
    final s = await runner.run(onlyIds: {'a'}, force: true);
    expect(s.checked, 1);
    expect(source.calls.first, startsWith('kolkata/176735'));
  });

  test('failures are logged, retried next run, and error after 6', () async {
    await store.saveAlert(alert('a', const CinemaOpens({mani})));
    source.failWith = SourceFormatChanged('rails missing');
    for (var i = 1; i <= 6; i++) {
      final s = await runner.run();
      expect(s.failed, 1, reason: 'run $i should still be due');
      now = now.add(const Duration(minutes: 15));
    }
    expect(store.byId['a']!.status, AlertStatus.error);
    expect(store.byId['a']!.consecutiveFailures, 6);
    expect(notifier.failing, hasLength(1));
    expect(store.log.last.message, 'Data source changed — update needed');
    expect(notifier.fired, isEmpty, reason: 'a failure is never "no shows"');
    expect((await runner.run()).checked, 0);
  });

  test('expires alerts past their end time without fetching', () async {
    await store.saveAlert(
      alert(
        'a',
        const CinemaOpens({mani}),
        until: now.subtract(const Duration(minutes: 1)),
      ),
    );
    final s = await runner.run();
    expect(s.checked, 0);
    expect(source.calls, isEmpty);
    expect(store.byId['a']!.status, AlertStatus.expired);
    expect(store.log.single.outcome, CheckOutcome.expired);
  });

  test(
    'a pause made during the run wins; a deleted alert stays deleted',
    () async {
      await store.saveAlert(alert('a', const CinemaOpens({mani})));
      await store.saveAlert(alert('b', const CinemaOpens({mani})));
      source.listing['2026-12-18'] = [mani];
      store.onRead = (id) {
        if (id == 'a' && store.byId['a']?.status == AlertStatus.active) {
          store.byId['a'] = store.byId['a']!.copyWith(
            status: AlertStatus.paused,
          );
        }
        if (id == 'b') store.byId.remove('b');
      };
      await runner.run();
      expect(store.byId['a']!.status, AlertStatus.paused);
      expect(store.byId['a']!.checkCount, 1);
      expect(store.byId.containsKey('b'), isFalse);
    },
  );

  test('isDue and nextCheck', () {
    final a = alert('a', const CinemaOpens({mani}));
    expect(AlertRunner.isDue(a, now), isTrue);
    final checked = a.copyWith(lastCheckedAt: now);
    expect(
      AlertRunner.isDue(checked, now.add(const Duration(minutes: 27))),
      isFalse,
    );
    expect(
      AlertRunner.isDue(checked, now.add(const Duration(minutes: 28))),
      isTrue,
    );
    expect(
      AlertRunner.nextCheck(checked),
      now.add(const Duration(minutes: 30)),
    );
    expect(
      AlertRunner.nextCheck(checked.copyWith(status: AlertStatus.paused)),
      isNull,
    );
  });
}
