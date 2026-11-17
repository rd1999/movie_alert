import '../models.dart';

/// Adapter interface for showtime data (spec §5, §7). District is the first
/// implementation; other sources (official APIs, other chains) can be
/// swapped in without touching the UI or the alert engine.
///
/// Implementations throw `SourceFormatChanged` when a page can't be
/// understood and an I/O exception when it can't be fetched. They never
/// return an empty result to hide either.
abstract interface class ShowtimeSource {
  /// Stable id stored with cached data, e.g. `district`.
  String get id;

  Future<List<City>> cities();

  /// Movies with bookings open in [cityKey].
  Future<List<MovieSummary>> movies(String cityKey);

  /// Every cinema in [cityKey], including ones not showing anything yet.
  Future<List<Cinema>> cinemas(String cityKey);

  /// One language/format group on one date. Nulls let the source pick the
  /// default group / first date with shows.
  Future<ShowtimesPage> showtimes({
    required String cityKey,
    required String movieSlug,
    required int contentId,
    String? fmtGrpId,
    String? date,
  });

  /// Official page to book on. We never book ourselves (spec §2).
  Uri bookingUrl({
    required String cityKey,
    required String movieSlug,
    required int contentId,
    String? fmtGrpId,
    String? date,
  });
}
