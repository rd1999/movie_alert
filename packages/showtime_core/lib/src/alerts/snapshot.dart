import '../models.dart';

/// The minimum about one show that alerts need, flattened with the page
/// context (language group, listing date) it was seen on.
class ObservedShow {
  const ObservedShow({
    required this.cinemaId,
    required this.cinemaName,
    required this.sessionId,
    required this.fmtGrpId,
    required this.listingDate,
    required this.rawShowTime,
    required this.seatsAvailable,
    required this.seatsTotal,
    this.screenFormat,
    this.premiumLabel,
  });

  factory ObservedShow.fromShow(
    Show s, {
    required Cinema cinema,
    required String fmtGrpId,
    required String listingDate,
  }) => ObservedShow(
    cinemaId: cinema.id,
    cinemaName: cinema.name,
    sessionId: s.sessionId,
    fmtGrpId: fmtGrpId,
    listingDate: listingDate,
    rawShowTime: s.rawShowTime,
    seatsAvailable: s.seatsAvailable,
    seatsTotal: s.seatsTotal,
    screenFormat: s.screenFormat,
    premiumLabel: s.premiumLabel,
  );

  final int cinemaId;
  final String cinemaName;
  final String sessionId;

  /// Lowercased language/format group id.
  final String fmtGrpId;

  /// `YYYY-MM-DD` the show is listed under (can differ from the date in
  /// [rawShowTime] for late-night shows).
  final String listingDate;
  final String rawShowTime;
  final int seatsAvailable;
  final int seatsTotal;
  final String? screenFormat;
  final String? premiumLabel;

  String get key => '$cinemaId:$sessionId';

  bool matchesFormat(String query) {
    final q = query.toLowerCase();
    return (screenFormat?.toLowerCase().contains(q) ?? false) ||
        (premiumLabel?.toLowerCase().contains(q) ?? false);
  }

  Map<String, Object?> toJson() => {
    'c': cinemaId,
    'cn': cinemaName,
    's': sessionId,
    'g': fmtGrpId,
    'd': listingDate,
    't': rawShowTime,
    'a': seatsAvailable,
    'n': seatsTotal,
    if (screenFormat != null) 'f': screenFormat,
    if (premiumLabel != null) 'p': premiumLabel,
  };

  factory ObservedShow.fromJson(Map<String, Object?> j) => ObservedShow(
    cinemaId: (j['c'] as num).toInt(),
    cinemaName: j['cn'] as String,
    sessionId: j['s'] as String,
    fmtGrpId: j['g'] as String,
    listingDate: j['d'] as String,
    rawShowTime: j['t'] as String,
    seatsAvailable: (j['a'] as num).toInt(),
    seatsTotal: (j['n'] as num).toInt(),
    screenFormat: j['f'] as String?,
    premiumLabel: j['p'] as String?,
  );
}

/// Everything observed for one movie in one city during one check, merged
/// from one or more showtimes pages.
class Snapshot {
  const Snapshot({
    required this.takenAt,
    required this.sessionDatesByGroup,
    required this.shows,
  });

  factory Snapshot.fromPages(
    Iterable<ShowtimesPage> pages, {
    required DateTime takenAt,
  }) {
    final dates = <String, Set<String>>{};
    final shows = <String, ObservedShow>{};
    for (final p in pages) {
      dates.putIfAbsent(p.fmtGrpId, () => {}).addAll(p.sessionDates);
      final listing = p.listingDate;
      if (listing == null) continue;
      for (final cs in p.cinemas) {
        for (final s in cs.shows) {
          final o = ObservedShow.fromShow(
            s,
            cinema: cs.cinema,
            fmtGrpId: p.fmtGrpId,
            listingDate: listing,
          );
          shows['${o.key}@$listing'] = o;
        }
      }
    }
    return Snapshot(
      takenAt: takenAt,
      sessionDatesByGroup: {
        for (final e in dates.entries) e.key: (e.value.toList()..sort()),
      },
      shows: shows.values.toList(),
    );
  }

  final DateTime takenAt;

  /// Lowercased group id -> dates that have shows in that group.
  final Map<String, List<String>> sessionDatesByGroup;
  final List<ObservedShow> shows;

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toUtc().toIso8601String(),
    'dates': sessionDatesByGroup,
    'shows': [for (final s in shows) s.toJson()],
  };

  factory Snapshot.fromJson(Map<String, Object?> j) => Snapshot(
    takenAt: DateTime.parse(j['takenAt'] as String),
    sessionDatesByGroup: {
      for (final e in (j['dates'] as Map).entries)
        e.key as String: [for (final d in e.value as List) d as String],
    },
    shows: [
      for (final s in j['shows'] as List)
        ObservedShow.fromJson((s as Map).cast<String, Object?>()),
    ],
  );
}
