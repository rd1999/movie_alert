import 'alert.dart';
import 'snapshot.dart';

enum AlertEventKind {
  /// The condition was already true on the alert's first check (§10.2).
  alreadyAvailable,

  /// The condition became true since an earlier check.
  opened,
}

/// What to tell the user when an alert fires (FR-16).
class AlertEvent {
  const AlertEvent({
    required this.alertId,
    required this.kind,
    required this.movieName,
    required this.matchKeys,
    required this.shows,
    required this.dates,
  });

  final String alertId;
  final AlertEventKind kind;
  final String movieName;

  /// Newly matched keys (never notified before, FR-17).
  final Set<String> matchKeys;

  /// Shows behind the new matches, sorted by date, cinema, time. Can be
  /// empty for "date opens" when only the date list was checked.
  final List<ObservedShow> shows;

  /// Listing dates involved, sorted. Use the first one for the deep link.
  final List<String> dates;

  String get title => switch (kind) {
    AlertEventKind.alreadyAvailable => 'Already available: $movieName',
    AlertEventKind.opened => '$movieName: bookings open',
  };

  /// Short multi-line summary: cinema, date, times, format, seats left.
  String body({int maxLines = 5}) {
    if (shows.isEmpty) return 'Bookings open for ${dates.join(', ')}';
    final lines = <String>[];
    final byCinemaDate = <String, List<ObservedShow>>{};
    for (final s in shows) {
      byCinemaDate
          .putIfAbsent('${s.cinemaName}|${s.listingDate}', () => [])
          .add(s);
    }
    for (final group in byCinemaDate.values) {
      final first = group.first;
      final times = group.map((s) {
        final t = s.rawShowTime.length >= 16
            ? s.rawShowTime.substring(11, 16)
            : s.rawShowTime;
        final fmt = [s.screenFormat, s.premiumLabel].nonNulls.join(' ');
        return '$t${fmt.isEmpty ? '' : ' $fmt'} (${s.seatsAvailable} left)';
      });
      lines.add(
        '${first.cinemaName} · ${first.listingDate}: ${times.join(', ')}',
      );
    }
    if (lines.length <= maxLines) return lines.join('\n');
    return [
      ...lines.take(maxLines),
      '…and ${lines.length - maxLines} more',
    ].join('\n');
  }
}

class AlertEvaluation {
  const AlertEvaluation(this.alert, [this.event]);

  /// The alert with updated state (status, notified keys, counters).
  final Alert alert;

  /// Non-null when the user should be notified.
  final AlertEvent? event;
}

/// Pure alert logic (spec §7, §10). No I/O, no Flutter: the same code runs
/// on the phone and on a future server.
///
/// Memory between checks lives in [Alert.notifiedKeys], so evaluation only
/// needs the current [Snapshot]. Missing data (a page that wasn't fetched)
/// can only cause a missed match, never a false alert.
abstract final class AlertEngine {
  /// Consecutive failed checks before an alert is auto-paused (FR-18).
  static const maxConsecutiveFailures = 6;

  static bool isExpired(Alert alert, DateTime now) {
    final until = alert.activeUntil;
    return until != null && !now.isBefore(until);
  }

  /// Evaluates [alert] against a successful check's [snapshot].
  static AlertEvaluation evaluate(
    Alert alert,
    Snapshot snapshot, {
    required DateTime now,
  }) {
    if (alert.status != AlertStatus.active) return AlertEvaluation(alert);
    if (isExpired(alert, now)) {
      return AlertEvaluation(alert.copyWith(status: AlertStatus.expired));
    }

    final matches = _matches(alert, snapshot);
    final notified = {...alert.notifiedKeys};

    // Seats alerts re-arm when a show we notified about drops below the
    // threshold again.
    if (alert.condition case SeatsAvailable(:final minSeats)) {
      notified.removeAll([
        for (final s in snapshot.shows)
          if (s.seatsAvailable < minSeats) 'seats:${s.key}',
      ]);
    }

    final fresh = {
      for (final k in matches.keys)
        if (!notified.contains(k)) k,
    };
    var updated = alert.copyWith(
      lastCheckedAt: now,
      checkCount: alert.checkCount + 1,
      consecutiveFailures: 0,
      notifiedKeys: {...notified, ...fresh},
    );
    if (fresh.isEmpty) return AlertEvaluation(updated);

    // First check of "new cinema anywhere" only records the baseline.
    if (alert.condition is NewCinemaAnywhere && alert.isFirstCheck) {
      return AlertEvaluation(updated);
    }

    final shows =
        <String, ObservedShow>{
          for (final k in fresh)
            for (final s in matches[k]!) '${s.key}@${s.listingDate}': s,
        }.values.toList()..sort((a, b) {
          final d = a.listingDate.compareTo(b.listingDate);
          if (d != 0) return d;
          final c = a.cinemaName.compareTo(b.cinemaName);
          return c != 0 ? c : a.rawShowTime.compareTo(b.rawShowTime);
        });
    final dates = {
      ...shows.map((s) => s.listingDate),
      for (final k in fresh)
        if (k.startsWith('date:')) k.substring(5),
    }.toList()..sort();

    if (alert.mode == AlertMode.once) {
      updated = updated.copyWith(status: AlertStatus.fired);
    }
    return AlertEvaluation(
      updated,
      AlertEvent(
        alertId: alert.id,
        kind: alert.isFirstCheck
            ? AlertEventKind.alreadyAvailable
            : AlertEventKind.opened,
        movieName: alert.movieName,
        matchKeys: fresh,
        shows: shows,
        dates: dates,
      ),
    );
  }

  /// Records a failed check (network error, [SourceFormatChanged], …).
  /// After [maxConsecutiveFailures] the alert moves to
  /// [AlertStatus.error] so the app can say "can't check — tap to fix".
  static Alert recordFailure(Alert alert) {
    final failures = alert.consecutiveFailures + 1;
    return alert.copyWith(
      consecutiveFailures: failures,
      status:
          failures >= maxConsecutiveFailures &&
              alert.status == AlertStatus.active
          ? AlertStatus.error
          : null,
    );
  }

  /// Match key -> shows behind it, for the alert's condition and filters.
  static Map<String, List<ObservedShow>> _matches(Alert alert, Snapshot snap) {
    bool passes(ObservedShow s) =>
        (alert.dates.isEmpty || alert.dates.contains(s.listingDate)) &&
        (alert.fmtGrpIds.isEmpty || alert.fmtGrpIds.contains(s.fmtGrpId));
    bool atCinema(Set<int> ids, ObservedShow s) =>
        ids.isEmpty || ids.contains(s.cinemaId);

    final out = <String, List<ObservedShow>>{};
    void add(String key, ObservedShow? s) {
      final list = out.putIfAbsent(key, () => []);
      if (s != null) list.add(s);
    }

    final shows = snap.shows.where(passes);
    switch (alert.condition) {
      case CinemaOpens(:final cinemaIds):
        for (final s in shows) {
          if (cinemaIds.contains(s.cinemaId)) add('show:${s.key}', s);
        }
      case FormatOpens(:final format, :final cinemaIds):
        for (final s in shows) {
          if (atCinema(cinemaIds, s) && s.matchesFormat(format)) {
            add('show:${s.key}', s);
          }
        }
      case DateOpens(:final cinemaIds):
        final openDates = {
          for (final e in snap.sessionDatesByGroup.entries)
            if (alert.fmtGrpIds.isEmpty || alert.fmtGrpIds.contains(e.key))
              ...e.value,
        };
        for (final d in alert.dates) {
          final onDate = shows.where(
            (s) => s.listingDate == d && atCinema(cinemaIds, s),
          );
          if (cinemaIds.isEmpty && openDates.contains(d)) add('date:$d', null);
          if (cinemaIds.isEmpty && !openDates.contains(d)) continue;
          for (final s in onDate) {
            add('date:$d', s);
          }
        }
      case NewCinemaAnywhere():
        for (final s in shows) {
          add('cinema:${s.cinemaId}', s);
        }
      case SeatsAvailable(:final minSeats, :final cinemaIds):
        for (final s in shows) {
          if (atCinema(cinemaIds, s) && s.seatsAvailable >= minSeats) {
            add('seats:${s.key}', s);
          }
        }
    }
    return out;
  }
}
