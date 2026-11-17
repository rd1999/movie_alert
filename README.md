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
packages/showtime_core/   Pure Dart (no Flutter). Domain models, source URLs and
                          parser, alert engine, CLI. Reusable by a future server.
lib/
  app/                    router, theme
  core/http, core/result  polite HTTP client, Result/Failure types
  data/sources/           ShowtimeSource adapter interface + District adapter
  data/repo, data/db      caching repository, local DB
  domain/                 app-side re-exports of showtime_core models
  background/             WorkManager scheduler, worker entrypoint, fast mode
  notifications/          channels, alarm sound, deep links
  features/               onboarding, browse, show_detail, alerts, settings
docs/                     spec and notes
```

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 0 | Pure-Dart parser + CLI + fixtures/tests | parser, URLs, CLI, 27 tests done; dated-page (`?fromdate=`) check pending |
| 1 | Browse MVP (city, movies, showtimes, deep link) | — |
| 2 | Android alerts (WorkManager, notifications, history) | — |
| 3 | Optional tiny backend for iOS / push | — |

## Development

```sh
flutter pub get
flutter test                       # app tests
cd packages/showtime_core
dart pub get
dart test                          # parser / engine tests
```
