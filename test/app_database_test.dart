import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/data/db/app_database.dart';
import 'package:showtime_core/showtime_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqfliteAlertStore store;
  var n = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Fresh database per test.
    store = await SqfliteAlertStore.open(
      name: 'test_${DateTime.now().microsecondsSinceEpoch}_${n++}.db',
    );
  });

  final t0 = DateTime.utc(2026, 11, 17, 10);
  Alert alert(String id, {DateTime? created}) => Alert(
    id: id,
    cityKey: 'kolkata',
    movieContentId: 176735,
    movieSlug: 'avengers-doomsday',
    movieName: 'Avengers: Doomsday',
    condition: const FormatOpens('PXL', cinemaIds: {1020736}),
    cinemaNames: const {1020736: 'PVR Mani Square'},
    dates: const {'2026-12-18', '2026-12-20'},
    createdAt: created ?? t0,
  );

  test('alerts: save, read back, update, newest first, delete', () async {
    await store.saveAlert(alert('a'));
    await store.saveAlert(
      alert('b', created: t0.add(const Duration(hours: 1))),
    );
    expect((await store.alerts()).map((a) => a.id), ['b', 'a']);

    final a = (await store.alert('a'))!;
    expect(a.toJson(), alert('a').toJson());

    await store.saveAlert(
      a.copyWith(status: AlertStatus.paused, checkCount: 4),
    );
    expect((await store.alert('a'))!.status, AlertStatus.paused);
    expect((await store.alerts()), hasLength(2));

    await store.addLog(
      CheckLogEntry(alertId: 'a', at: t0, outcome: CheckOutcome.ok),
    );
    await store.deleteAlert('a');
    expect(await store.alert('a'), isNull);
    expect(await store.logs('a'), isEmpty);
  });

  test('check log: newest first, capped per alert', () async {
    for (var i = 0; i < SqfliteAlertStore.logLimitPerAlert + 5; i++) {
      await store.addLog(
        CheckLogEntry(
          alertId: 'a',
          at: t0.add(Duration(minutes: i)),
          outcome: i.isEven ? CheckOutcome.ok : CheckOutcome.failed,
          message: 'run $i',
          pagesFetched: 2,
        ),
      );
    }
    await store.addLog(
      CheckLogEntry(alertId: 'b', at: t0, outcome: CheckOutcome.fired),
    );
    final logs = await store.logs('a', limit: 1000);
    expect(logs, hasLength(SqfliteAlertStore.logLimitPerAlert));
    expect(logs.first.message, 'run ${SqfliteAlertStore.logLimitPerAlert + 4}');
    expect(logs.first.pagesFetched, 2);
    expect((await store.logs('b')).single.outcome, CheckOutcome.fired);
  });

  test('snapshots round-trip per (city, movie)', () async {
    final s = Snapshot(
      takenAt: t0,
      sessionDatesByGroup: const {
        'en': ['2026-12-18'],
      },
      shows: const [
        ObservedShow(
          cinemaId: 1,
          cinemaName: 'C',
          sessionId: '9',
          fmtGrpId: 'en',
          listingDate: '2026-12-18',
          rawShowTime: '2026-12-18T10:00',
          seatsAvailable: 5,
          seatsTotal: 10,
        ),
      ],
    );
    await store.saveSnapshot('kolkata', 176735, s);
    expect((await store.snapshot('kolkata', 176735))!.toJson(), s.toJson());
    expect(await store.snapshot('kolkata', 1), isNull);
  });

  test('page cache: read/write, max age and max entries', () async {
    await store.write('k', '{"a":1}', t0);
    final (json, at) = (await store.read('k'))!;
    expect(json, '{"a":1}');
    expect(at, t0.toLocal());
    expect(await store.read('missing'), isNull);

    // Entries older than the max age are dropped on the next write.
    await store.write(
      'new',
      '{}',
      t0.add(SqfliteAlertStore.pageCacheMaxAge + const Duration(minutes: 1)),
    );
    expect(await store.read('k'), isNull);

    for (var i = 0; i < SqfliteAlertStore.pageCacheMaxEntries + 5; i++) {
      await store.write('p$i', '{}', t0.add(Duration(days: 8, minutes: i)));
    }
    expect(await store.read('p0'), isNull);
    expect(
      await store.read('p${SqfliteAlertStore.pageCacheMaxEntries + 4}'),
      isNotNull,
    );
  });
}
