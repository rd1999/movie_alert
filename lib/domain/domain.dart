/// App-side domain layer: the source-agnostic models and alert logic live in
/// the pure-Dart `showtime_core` package so a future server can reuse them.
library;

export 'package:showtime_core/showtime_core.dart'
    show
        Alert,
        AlertCondition,
        AlertEngine,
        AlertEvent,
        AlertStatus,
        Cinema,
        CinemaShows,
        City,
        LanguageFormatGroup,
        MovieInfo,
        MovieSummary,
        SeatAvailability,
        SeatClass,
        Show,
        ShowtimesPage,
        SourceFormatChanged;
