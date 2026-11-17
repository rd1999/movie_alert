/// Source-agnostic domain models (spec §7). Pure Dart, immutable.
library;

/// Seat availability bucket. District's `statusColor` codes map onto this;
/// [SeatAvailability.unknown] keeps the app honest when a new code appears.
enum SeatAvailability {
  available,
  fillingFast,
  almostFull,
  soldOut,
  unknown;

  /// Verified 17 Nov 2026 (session and seat-class level): `G` = "Available",
  /// `Y` = "Filling Fast", `R` = "Almost Full", `D` = "Sold Out".
  /// Unknown codes fall back to the human label.
  static SeatAvailability fromDistrictCode(String? code, {String? label}) {
    switch (code) {
      case 'G':
        return SeatAvailability.available;
      case 'Y':
        return SeatAvailability.fillingFast;
      case 'R':
        return SeatAvailability.almostFull;
      case 'D':
        return SeatAvailability.soldOut;
    }
    final l = label?.toLowerCase() ?? '';
    if (l.contains('sold')) return SeatAvailability.soldOut;
    if (l.contains('almost')) return SeatAvailability.almostFull;
    if (l.contains('fast')) return SeatAvailability.fillingFast;
    if (l.contains('available')) return SeatAvailability.available;
    return SeatAvailability.unknown;
  }
}

class MovieInfo {
  const MovieInfo({
    required this.contentId,
    required this.name,
    this.censor,
    this.durationMinutes,
    this.primaryLanguage,
    this.isReleased,
  });

  final int contentId;
  final String name;
  final String? censor;
  final int? durationMinutes;
  final String? primaryLanguage;
  final bool? isReleased;
}

/// One language (and format family) a movie is offered in.
class LanguageFormatGroup {
  const LanguageFormatGroup({
    required this.language,
    required this.fmtGrpId,
    this.sessionCount,
  });

  final String language;

  /// As delivered by the source (mixed case, e.g. `Mm5dpqTqJz`).
  final String fmtGrpId;
  final int? sessionCount;

  /// Lowercased id used in URLs and map keys.
  String get key => fmtGrpId.toLowerCase();
}

class Cinema {
  const Cinema({
    required this.id,
    required this.name,
    this.address,
    this.pincode,
    this.latitude,
    this.longitude,
    this.cityKey,
    this.chain,
    this.isCancellable,
    this.distanceKm,
    this.path,
  });

  /// Stable id. Always match on this, never on [name] (spec §10.2).
  final int id;
  final String name;
  final String? address;
  final String? pincode;
  final double? latitude;
  final double? longitude;
  final String? cityKey;
  final String? chain;
  final bool? isCancellable;
  final double? distanceKm;

  /// Site-relative path of the cinema page, e.g. `/inox-quest-mall-…-c/1020727`.
  final String? path;
}

class SeatClass {
  const SeatClass({
    required this.label,
    required this.price,
    required this.available,
    required this.total,
    required this.availability,
  });

  final String label;
  final num price;
  final int available;
  final int total;
  final SeatAvailability availability;
}

class Show {
  const Show({
    required this.sessionId,
    required this.cinemaId,
    required this.showTime,
    required this.rawShowTime,
    required this.seatsAvailable,
    required this.seatsTotal,
    required this.availability,
    this.movieVariantId,
    this.audi,
    this.screenFormat,
    this.premiumLabel,
    this.statusLabel,
    this.maxTickets,
    this.tags = const [],
    this.seatClasses = const [],
  });

  final String sessionId;
  final int cinemaId;

  /// Cinema-local wall-clock time (IST, no offset in the source). Note a
  /// late-night show can fall on the day after its listing date.
  final DateTime showTime;
  final String rawShowTime;
  final String? movieVariantId;
  final String? audi;

  /// Screen format, e.g. "MS INFINITY VISION 3D".
  final String? screenFormat;

  /// Sound / projection / seating label, e.g. "DOLBY 7.1", "INSIGNIA".
  final String? premiumLabel;
  final int seatsAvailable;
  final int seatsTotal;
  final SeatAvailability availability;
  final String? statusLabel;
  final int? maxTickets;
  final List<String> tags;
  final List<SeatClass> seatClasses;

  /// Unique within a source: used for de-duplication (FR-17).
  String get uniqueKey => '$cinemaId:$sessionId';

  /// Case-insensitive "contains" over screen format and premium label
  /// (spec §10.2).
  bool matchesFormat(String query) {
    final q = query.toLowerCase();
    return (screenFormat?.toLowerCase().contains(q) ?? false) ||
        (premiumLabel?.toLowerCase().contains(q) ?? false);
  }
}

class CinemaShows {
  const CinemaShows({required this.cinema, required this.shows});

  final Cinema cinema;
  final List<Show> shows;
}

/// Everything parsed from one movie-showtimes page: one language/format
/// group on one listing date.
class ShowtimesPage {
  const ShowtimesPage({
    required this.movie,
    required this.languageFormats,
    required this.fmtGrpId,
    required this.listingDate,
    required this.sessionDates,
    required this.cinemas,
  });

  final MovieInfo movie;
  final List<LanguageFormatGroup> languageFormats;

  /// Lowercased group id this page's sessions belong to.
  final String fmtGrpId;

  /// `YYYY-MM-DD` the shows are listed under (null when the movie has no
  /// bookable dates).
  final String? listingDate;

  /// All `YYYY-MM-DD` dates that currently have shows for [fmtGrpId].
  final List<String> sessionDates;
  final List<CinemaShows> cinemas;

  Iterable<Show> get allShows => cinemas.expand((c) => c.shows);
}
