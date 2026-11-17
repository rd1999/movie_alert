import '../models.dart';
import 'alert.dart';
import 'alert_engine.dart';
import 'snapshot.dart';

/// Fetches and parses one showtimes page. `null` arguments mean "let the
/// site pick" (default group / first date with shows).
typedef PageFetcher =
    Future<ShowtimesPage> Function({String? fmtGrpId, String? date});

/// Decides which pages a group of alerts needs (FR-19: each page once).
abstract final class CheckPlanner {
  /// Lowercased group ids any of [alerts] cares about, limited to [groups]
  /// that exist. An alert with no language filter needs every group.
  static List<String> groupsFor(
    Iterable<Alert> alerts,
    List<LanguageFormatGroup> groups,
  ) {
    final available = [for (final g in groups) g.key];
    if (alerts.any((a) => a.fmtGrpIds.isEmpty)) return available;
    final wanted = {for (final a in alerts) ...a.fmtGrpIds};
    return [
      for (final g in available)
        if (wanted.contains(g)) g,
    ];
  }

  /// Dates of group [fmtGrpId] whose pages are needed, given the dates that
  /// currently have shows. "Date opens" with no cinema filter only needs
  /// the date list, not the pages.
  static Set<String> datesFor(
    Iterable<Alert> alerts,
    String fmtGrpId,
    List<String> sessionDates,
  ) {
    final out = <String>{};
    for (final a in alerts) {
      if (a.fmtGrpIds.isNotEmpty && !a.fmtGrpIds.contains(fmtGrpId)) continue;
      if (a.condition case DateOpens(:final cinemaIds) when cinemaIds.isEmpty) {
        continue;
      }
      out.addAll(
        a.dates.isEmpty ? sessionDates : sessionDates.where(a.dates.contains),
      );
    }
    return out;
  }
}

/// Result of checking one movie in one city for a group of alerts.
class MovieCheckResult {
  const MovieCheckResult({
    required this.snapshot,
    required this.evaluations,
    required this.pagesFetched,
  });

  final Snapshot snapshot;
  final List<AlertEvaluation> evaluations;
  final int pagesFetched;
}

/// One background run for one (city, movie) group (spec §10.1). Fetches
/// sequentially (politeness, NFR-1). Any fetch or parse error fails the
/// whole check so a partial snapshot is never mistaken for "no shows".
class MovieChecker {
  const MovieChecker(this.fetch);

  final PageFetcher fetch;

  Future<MovieCheckResult> check(
    List<Alert> alerts, {
    required DateTime now,
  }) async {
    final active = [
      for (final a in alerts)
        if (a.status == AlertStatus.active && !AlertEngine.isExpired(a, now)) a,
    ];
    final pages = <ShowtimesPage>[];
    if (active.isNotEmpty) {
      final base = await fetch();
      pages.add(base);
      for (final g in CheckPlanner.groupsFor(active, base.languageFormats)) {
        final groupBase = g == base.fmtGrpId
            ? base
            : await fetch(fmtGrpId: g); // [VERIFY] ?frmtid= without date
        if (!identical(groupBase, base)) pages.add(groupBase);
        final dates =
            CheckPlanner.datesFor(active, g, groupBase.sessionDates).toList()
              ..remove(groupBase.listingDate)
              ..sort();
        for (final d in dates) {
          pages.add(await fetch(fmtGrpId: g, date: d));
        }
      }
    }
    final snapshot = Snapshot.fromPages(pages, takenAt: now);
    return MovieCheckResult(
      snapshot: snapshot,
      evaluations: [
        for (final a in alerts) AlertEngine.evaluate(a, snapshot, now: now),
      ],
      pagesFetched: pages.length,
    );
  }
}
