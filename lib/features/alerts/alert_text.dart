import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';

/// Human-readable descriptions of alerts for lists and headers.
abstract final class AlertText {
  static String cinemas(Alert a, Set<int> ids) => ids.isEmpty
      ? 'any cinema'
      : ids.map((id) => a.cinemaNames[id] ?? 'Cinema $id').join(', ');

  static String condition(Alert a) => switch (a.condition) {
    CinemaOpens(:final cinemaIds) => 'Shows at ${cinemas(a, cinemaIds)}',
    FormatOpens(:final format, :final cinemaIds) =>
      '"$format" shows at ${cinemas(a, cinemaIds)}',
    DateOpens(:final cinemaIds) => 'Bookings open at ${cinemas(a, cinemaIds)}',
    NewCinemaAnywhere() => 'Any new cinema starts showing it',
    SeatsAvailable(:final minSeats, :final cinemaIds) =>
      '$minSeats+ seats free at ${cinemas(a, cinemaIds)}',
  };

  static String dates(Alert a) {
    if (a.dates.isEmpty) return 'Any date';
    final sorted = a.dates.toList()..sort();
    return sorted.map(Fmt.listingDate).join(', ');
  }

  static String interval(Duration d) =>
      d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h';

  static String status(AlertStatus s) => switch (s) {
    AlertStatus.active => 'Watching',
    AlertStatus.paused => 'Paused',
    AlertStatus.fired => 'Fired',
    AlertStatus.expired => 'Expired',
    AlertStatus.error => "Can't check",
  };
}
