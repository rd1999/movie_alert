/// Alert definitions (spec §8.3). Immutable; the engine returns updated
/// copies. Hand-written JSON so the core package needs no codegen.
library;

enum AlertMode {
  /// Fire once, then the alert becomes [AlertStatus.fired].
  once,

  /// Keep alerting on every new match (e.g. each new show) until expiry.
  everyNewMatch,
}

enum AlertStatus { active, paused, fired, expired, error }

/// What the user is waiting for (FR-11). Filters common to every condition
/// (dates, language groups) live on [Alert].
sealed class AlertCondition {
  const AlertCondition();

  Map<String, Object?> toJson();

  static AlertCondition fromJson(Map<String, Object?> j) {
    Set<int> ids() => {
      for (final v in (j['cinemaIds'] as List? ?? const [])) (v as num).toInt(),
    };
    return switch (j['type']) {
      'cinemaOpens' => CinemaOpens(ids()),
      'formatOpens' => FormatOpens(j['format'] as String, cinemaIds: ids()),
      'dateOpens' => DateOpens(cinemaIds: ids()),
      'newCinemaAnywhere' => const NewCinemaAnywhere(),
      'seatsAvailable' => SeatsAvailable(
        (j['minSeats'] as num).toInt(),
        cinemaIds: ids(),
      ),
      final t => throw FormatException('Unknown alert condition type: $t'),
    };
  }
}

/// Movie gets >= 1 show at any of [cinemaIds].
final class CinemaOpens extends AlertCondition {
  const CinemaOpens(this.cinemaIds);

  final Set<int> cinemaIds;

  @override
  Map<String, Object?> toJson() => {
    'type': 'cinemaOpens',
    'cinemaIds': cinemaIds.toList()..sort(),
  };
}

/// Movie gets a show whose screen format or premium label contains
/// [format] (case-insensitive), anywhere or at [cinemaIds].
final class FormatOpens extends AlertCondition {
  const FormatOpens(this.format, {this.cinemaIds = const {}});

  final String format;
  final Set<int> cinemaIds;

  @override
  Map<String, Object?> toJson() => {
    'type': 'formatOpens',
    'format': format,
    'cinemaIds': cinemaIds.toList()..sort(),
  };
}

/// Bookings open on any of the alert's dates ([Alert.dates], required),
/// anywhere or at [cinemaIds].
final class DateOpens extends AlertCondition {
  const DateOpens({this.cinemaIds = const {}});

  final Set<int> cinemaIds;

  @override
  Map<String, Object?> toJson() => {
    'type': 'dateOpens',
    'cinemaIds': cinemaIds.toList()..sort(),
  };
}

/// Any cinema that wasn't showing the movie at the first check starts
/// showing it.
final class NewCinemaAnywhere extends AlertCondition {
  const NewCinemaAnywhere();

  @override
  Map<String, Object?> toJson() => {'type': 'newCinemaAnywhere'};
}

/// (v1.1) A show has >= [minSeats] seats available (e.g. a sold-out
/// first-day show frees up). Re-arms when the show drops below again.
final class SeatsAvailable extends AlertCondition {
  const SeatsAvailable(this.minSeats, {this.cinemaIds = const {}});

  final int minSeats;
  final Set<int> cinemaIds;

  @override
  Map<String, Object?> toJson() => {
    'type': 'seatsAvailable',
    'minSeats': minSeats,
    'cinemaIds': cinemaIds.toList()..sort(),
  };
}

class Alert {
  const Alert({
    required this.id,
    required this.cityKey,
    required this.movieContentId,
    required this.movieSlug,
    required this.movieName,
    required this.condition,
    required this.createdAt,
    this.dates = const {},
    this.fmtGrpIds = const {},
    this.mode = AlertMode.once,
    this.interval = const Duration(minutes: 30),
    this.activeUntil,
    this.status = AlertStatus.active,
    this.notifiedKeys = const {},
    this.lastCheckedAt,
    this.checkCount = 0,
    this.consecutiveFailures = 0,
    this.cinemaNames = const {},
  });

  final String id;
  final String cityKey;
  final int movieContentId;
  final String movieSlug;
  final String movieName;
  final AlertCondition condition;

  /// Listing dates (`YYYY-MM-DD`) to watch. Empty = any date. Required for
  /// [DateOpens].
  final Set<String> dates;

  /// Lowercased language/format group ids to watch. Empty = all languages.
  final Set<String> fmtGrpIds;
  final AlertMode mode;

  /// Check interval (FR-12). Background runs can't go below 15 min.
  final Duration interval;

  /// Alert expires after this instant (FR-13). Null = until it fires.
  final DateTime? activeUntil;
  final DateTime createdAt;
  final AlertStatus status;

  /// Match keys already notified (FR-17). Also the alert's memory between
  /// checks (e.g. the baseline for [NewCinemaAnywhere]).
  final Set<String> notifiedKeys;
  final DateTime? lastCheckedAt;
  final int checkCount;
  final int consecutiveFailures;

  /// Display names for cinema ids in the condition. Matching always uses
  /// ids (spec §10.2); names are only for showing the alert.
  final Map<int, String> cinemaNames;

  bool get isFirstCheck => lastCheckedAt == null;

  /// Problems that make the alert impossible to evaluate; empty when valid.
  List<String> validate() => [
    if (condition is DateOpens && dates.isEmpty)
      '"Date opens" needs at least one date',
    if (condition case CinemaOpens(:final cinemaIds) when cinemaIds.isEmpty)
      '"Cinema opens" needs at least one cinema',
    if (condition case FormatOpens(:final format) when format.trim().isEmpty)
      '"Format opens" needs a format',
    if (condition case SeatsAvailable(:final minSeats) when minSeats < 1)
      'Minimum seats must be at least 1',
    for (final d in dates)
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) 'Bad date "$d"',
  ];

  Alert copyWith({
    AlertStatus? status,
    Set<String>? notifiedKeys,
    DateTime? lastCheckedAt,
    int? checkCount,
    int? consecutiveFailures,
    Set<String>? dates,
    Set<String>? fmtGrpIds,
    AlertMode? mode,
    Duration? interval,
    DateTime? activeUntil,
    bool clearActiveUntil = false,
  }) => Alert(
    id: id,
    cityKey: cityKey,
    movieContentId: movieContentId,
    movieSlug: movieSlug,
    movieName: movieName,
    condition: condition,
    createdAt: createdAt,
    dates: dates ?? this.dates,
    fmtGrpIds: fmtGrpIds ?? this.fmtGrpIds,
    mode: mode ?? this.mode,
    interval: interval ?? this.interval,
    activeUntil: clearActiveUntil ? null : (activeUntil ?? this.activeUntil),
    status: status ?? this.status,
    notifiedKeys: notifiedKeys ?? this.notifiedKeys,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    checkCount: checkCount ?? this.checkCount,
    consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    cinemaNames: cinemaNames,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'cityKey': cityKey,
    'movieContentId': movieContentId,
    'movieSlug': movieSlug,
    'movieName': movieName,
    'condition': condition.toJson(),
    'dates': dates.toList()..sort(),
    'fmtGrpIds': fmtGrpIds.toList()..sort(),
    'mode': mode.name,
    'intervalMinutes': interval.inMinutes,
    'activeUntil': activeUntil?.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'notifiedKeys': notifiedKeys.toList()..sort(),
    'lastCheckedAt': lastCheckedAt?.toUtc().toIso8601String(),
    'checkCount': checkCount,
    'consecutiveFailures': consecutiveFailures,
    'cinemaNames': {for (final e in cinemaNames.entries) '${e.key}': e.value},
  };

  factory Alert.fromJson(Map<String, Object?> j) {
    Set<String> strings(String k) => {
      for (final v in (j[k] as List? ?? const [])) v as String,
    };
    DateTime? time(String k) =>
        j[k] == null ? null : DateTime.parse(j[k] as String);
    return Alert(
      id: j['id'] as String,
      cityKey: j['cityKey'] as String,
      movieContentId: (j['movieContentId'] as num).toInt(),
      movieSlug: j['movieSlug'] as String,
      movieName: j['movieName'] as String,
      condition: AlertCondition.fromJson(
        (j['condition'] as Map).cast<String, Object?>(),
      ),
      dates: strings('dates'),
      fmtGrpIds: strings('fmtGrpIds'),
      mode: AlertMode.values.byName(j['mode'] as String),
      interval: Duration(minutes: (j['intervalMinutes'] as num).toInt()),
      activeUntil: time('activeUntil'),
      createdAt: time('createdAt')!,
      status: AlertStatus.values.byName(j['status'] as String),
      notifiedKeys: strings('notifiedKeys'),
      lastCheckedAt: time('lastCheckedAt'),
      checkCount: (j['checkCount'] as num? ?? 0).toInt(),
      consecutiveFailures: (j['consecutiveFailures'] as num? ?? 0).toInt(),
      cinemaNames: {
        for (final e in (j['cinemaNames'] as Map? ?? const {}).entries)
          int.parse(e.key as String): e.value as String,
      },
    );
  }
}
