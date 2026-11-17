# ShowWatch (working title)

A Flutter app that shows every current showtime for a movie in your city and
alerts you on your phone the moment a cinema, format or date that isn't
listed yet opens for booking. Android first, no backend.

Full spec: [docs/SHOWWATCH_SPEC.md](docs/SHOWWATCH_SPEC.md).

> Data from public cinema listings. This project is not affiliated with any
> ticketing platform or cinema chain. It never books tickets or takes
> payments. It only deep-links to the official booking page. See spec §5.

## Layout

```
packages/showtime_core/   Pure Dart (no Flutter), reusable by a future server:
                          models, ShowtimeSource + District adapter/parser,
                          alert engine + batched checker, CLI.
                          `io.dart` adds the polite dart:io HTTP fetcher.
lib/
  app/                    router, theme, formatting, shared widgets
  core/http, core/prefs   shared polite fetcher, SharedPreferences
  core/result             Result/Failure types
  data/sources/           active ShowtimeSource (District adapter from core)
  data/repo/              in-memory TTL cache, shared in-flight requests
  domain/                 re-exports of showtime_core models
  features/onboarding/    city picker (+ permissions/battery guide, Phase 2)
  features/browse/        movie list, showtimes (date/language/format)
  features/show_detail/   seat classes sheet, "Open booking" deep link
  background/, notifications/, features/alerts, features/settings  Phase 2
docs/                     spec and notes
```

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 0 | Pure-Dart parser + CLI + fixtures/tests | parser, URLs, CLI, 27 tests done; dated-page (`?fromdate=`) check pending |
| 1 | Browse MVP (city, movies, showtimes, deep link) | done: city picker, movie list, showtimes, show detail, booking link. GPS city + offline cache pending |
| 2 | Android alerts (WorkManager, notifications, history) | engine done (pure Dart) |
| 3 | Optional tiny backend for iOS / push | — |

## Development

```sh
flutter pub get
flutter test                       # app tests
cd packages/showtime_core
dart pub get
dart test                          # parser / engine tests
```
