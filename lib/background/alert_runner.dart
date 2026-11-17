import 'dart:io';

import 'package:showtime_core/io.dart';
import 'package:showtime_core/showtime_core.dart';

import '../data/db/app_database.dart';

/// Where alert notifications go (implemented by NotificationService).
abstract interface class AlertNotifier {
  Future<void> alertFired(Alert alert, AlertEvent event, Uri bookingUrl);

  /// The alert just hit [AlertEngine.maxConsecutiveFailures] (FR-18).
  Future<void> alertFailing(Alert alert, Object error);
}

class RunSummary {
  const RunSummary({
    required this.checked,
    required this.fired,
    required this.failed,
    required this.pagesFetched,
  });

  final int checked;
  final int fired;
  final int failed;
  final int pagesFetched;

  @override
  String toString() =>
      'checked $checked, fired $fired, failed $failed, pages $pagesFetched';
}

/// Short human text for a failed check.
String describeCheckError(Object e) => switch (e) {
  SourceFormatChanged() => 'Data source changed — update needed',
  HttpStatusException(statusCode: 429) => 'Rate limited by the listings site',
  HttpStatusException(:final statusCode) =>
    'Listings site answered HTTP $statusCode',
  SocketException() || HttpException() => 'No connection',
  _ => '$e',
};

/// One background run (spec §10.1): expire old alerts, pick the due ones,
/// check each (city, movie) group once with [MovieChecker], evaluate,
/// notify and persist. Pure Dart apart from the injected collaborators, so
/// it runs the same from WorkManager, "Check now" and tests.
class AlertRunner {
  AlertRunner({
    required this.store,
    required this.source,
    required this.notifier,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final AlertStore store;
  final ShowtimeSource source;
  final AlertNotifier notifier;
  final DateTime Function() _now;

  /// Runs may start a little early (WorkManager is inexact), so an alert is
  /// due slightly before its full interval has passed.
  static const dueSlack = Duration(minutes: 2);

  static bool isDue(Alert a, DateTime now) {
    if (a.status != AlertStatus.active) return false;
    final last = a.lastCheckedAt;
    return last == null || now.difference(last) >= a.interval - dueSlack;
  }

  /// Estimated next check, for the alert list (FR-14).
  static DateTime? nextCheck(Alert a) {
    if (a.status != AlertStatus.active) return null;
    return a.lastCheckedAt?.add(a.interval);
  }

  /// Checks due alerts. [onlyIds] + [force] implement "Check now".
  Future<RunSummary> run({Set<String>? onlyIds, bool force = false}) async {
    final now = _now();
    var checked = 0, fired = 0, failed = 0, pages = 0;

    final due = <Alert>[];
    for (final a in await store.alerts()) {
      if (a.status == AlertStatus.active && AlertEngine.isExpired(a, now)) {
        await _save(a, a.copyWith(status: AlertStatus.expired));
        await store.addLog(
          CheckLogEntry(alertId: a.id, at: now, outcome: CheckOutcome.expired),
        );
        continue;
      }
      if (onlyIds != null && !onlyIds.contains(a.id)) continue;
      if (a.status == AlertStatus.active && (force || isDue(a, now))) {
        due.add(a);
      }
    }

    final groups = <String, List<Alert>>{};
    for (final a in due) {
      groups.putIfAbsent('${a.cityKey}:${a.movieContentId}', () => []).add(a);
    }

    for (final group in groups.values) {
      final first = group.first;
      final checker = MovieChecker(
        ({String? fmtGrpId, String? date}) => source.showtimes(
          cityKey: first.cityKey,
          movieSlug: first.movieSlug,
          contentId: first.movieContentId,
          fmtGrpId: fmtGrpId,
          date: date,
        ),
      );
      checked += group.length;
      try {
        final result = await checker.check(group, now: now);
        pages += result.pagesFetched;
        await store.saveSnapshot(
          first.cityKey,
          first.movieContentId,
          result.snapshot,
        );
        for (var i = 0; i < group.length; i++) {
          final before = group[i];
          final eval = result.evaluations[i];
          await _save(before, eval.alert);
          final event = eval.event;
          if (event == null) {
            await store.addLog(
              CheckLogEntry(
                alertId: before.id,
                at: now,
                outcome: CheckOutcome.ok,
                message:
                    'No match yet · ${result.snapshot.shows.length} shows seen',
                pagesFetched: result.pagesFetched,
              ),
            );
            continue;
          }
          fired++;
          await store.addLog(
            CheckLogEntry(
              alertId: before.id,
              at: now,
              outcome: CheckOutcome.fired,
              message: '${event.title}\n${event.body()}',
              pagesFetched: result.pagesFetched,
            ),
          );
          await notifier.alertFired(
            eval.alert,
            event,
            _bookingUrl(eval.alert, event),
          );
        }
      } catch (e) {
        failed += group.length;
        for (final a in group) {
          final updated = AlertEngine.recordFailure(a);
          await _save(a, updated);
          await store.addLog(
            CheckLogEntry(
              alertId: a.id,
              at: now,
              outcome: CheckOutcome.failed,
              message: describeCheckError(e),
            ),
          );
          if (updated.status == AlertStatus.error &&
              a.status != AlertStatus.error) {
            await notifier.alertFailing(updated, e);
          }
        }
      }
    }
    return RunSummary(
      checked: checked,
      fired: fired,
      failed: failed,
      pagesFetched: pages,
    );
  }

  Uri _bookingUrl(Alert a, AlertEvent e) => source.bookingUrl(
    cityKey: a.cityKey,
    movieSlug: a.movieSlug,
    contentId: a.movieContentId,
    fmtGrpId:
        e.shows.firstOrNull?.fmtGrpId ??
        (a.fmtGrpIds.length == 1 ? a.fmtGrpIds.single : null),
    date: e.dates.firstOrNull,
  );

  /// Saves [updated] unless the user changed the alert meanwhile: a deleted
  /// alert stays deleted and a status the user set (pause/resume) wins.
  Future<void> _save(Alert before, Alert updated) async {
    final current = await store.alert(before.id);
    if (current == null) return;
    final userChangedStatus = current.status != before.status;
    await store.saveAlert(
      userChangedStatus ? updated.copyWith(status: current.status) : updated,
    );
  }
}
