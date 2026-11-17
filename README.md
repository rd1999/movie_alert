![CI](https://github.com/rd1999/movie_alert/actions/workflows/ci.yml/badge.svg)

# ShowWatch (working title)

A Flutter app that shows every current showtime for a movie in your city and
alerts you on your phone the moment a cinema, format or date that isn't
listed yet opens for booking. Android first, no backend.

Full spec: [docs/SHOWWATCH_SPEC.md](docs/SHOWWATCH_SPEC.md) ·
device test checklist: [docs/TESTING.md](docs/TESTING.md).

> Data from public cinema listings. This project is not affiliated with any
> ticketing platform or cinema chain. It never books tickets or takes
> payments. It only deep-links to the official booking page. See spec §5.

## Features (v1)

- **Browse:** pick a city (search or "Use my location"), see movies with
  bookings open, and see every show by date and language. Each show lists
  format, sound, seats left and price per seat class. Filters cover
  format, chain, time of day, max price and sold out. If the network
  fails, the last saved listings are shown.
- **Alerts:** "tell me when…" a cinema opens (including cinemas not
  showing the movie yet), a format opens (PXL, IMAX…), a date opens, any
  new cinema appears, or seats free up. Each alert has its own dates,
  languages, interval (15 min–6 h), end date and once/every-match mode.
  The first check runs right away ("Already available").
- **Background checks (Android):** one WorkManager task checks due alerts;
  each page is fetched once for all alerts. Notifications have Open
  booking / Snooze 10 min / Stop, an optional alarm style and quiet hours.
  Every check is logged.
- **Fast mode (Android):** a foreground service that checks every 2/5/10
  minutes for up to 6 h a day.
- **While the app is open:** due alerts are checked every minute (this is
  the only automatic check on iOS).
- **Settings:** default interval, Wi-Fi only, daily data limit, quiet
  hours, alarm style, data source status.

Failures never look like "no shows": a changed page format shows "Data
source changed — update needed", and an alert that can't check for 6 runs
in a row says so.

## Layout

```
packages/showtime_core/   Pure Dart (no Flutter), reusable by a future server:
                          models + JSON, ShowtimeSource + District
                          adapter/parser, alert engine + batched checker.
                          bin/showtimes.dart (CLI), bin/contract_check.dart.
                          `io.dart` adds the polite dart:io HTTP fetcher.
lib/
  app/                    router (Browse / Alerts tabs), theme, shared widgets
  core/                   polite fetcher provider, prefs, settings + data usage
  data/sources/           active ShowtimeSource (District adapter from core)
  data/repo/              TTL cache + offline copy, shared in-flight requests
  data/db/                SQLite: alerts, check log, snapshots, page cache, lock
  background/             AlertRunner, WorkManager scheduler + worker,
                          in-app checker, fast mode service
  notifications/          channels, alarm style, quiet hours, actions,
                          permissions (incl. battery channel in MainActivity)
  features/browse/        movie list, showtimes, filters
  features/show_detail/   seat classes sheet, "Open booking" deep link
  features/alerts/        create, list, history, fast mode card
  features/onboarding/    city picker (+ GPS), alert setup
  features/settings/      settings screen
docs/                     spec, device test checklist
```

## Status

| Phase | Scope | Status |
|---|---|---|
| 0 | Pure-Dart parser + CLI + fixtures/tests | done; dated-page (`?fromdate=`) contract check is opt-in (see below) |
| 1 | Browse MVP | done, incl. GPS city, offline view and filters |
| 2 | Android alerts | done, incl. fast mode, settings and in-app checks; **needs real-device testing** ([checklist](docs/TESTING.md)) |
| 3 | Optional tiny backend for iOS / push | not started (optional per spec) |

## Development

```sh
flutter pub get
flutter test                        # app tests
cd packages/showtime_core
dart pub get
dart test                           # parser / engine tests
dart run bin/showtimes.dart kolkata avengers-doomsday 176735
dart run bin/contract_check.dart    # live structure check (4 requests)
dart run bin/contract_check.dart --dated   # + one ?fromdate= page
```

The app icon is drawn from code: `dart run tool/generate_icon.dart`, then
`dart run flutter_launcher_icons` (sources in `assets/icon/`).

Real District pages used as test fixtures are kept locally and gitignored
([why](packages/showtime_core/test/fixtures/district/README.md)); CI runs on
synthetic pages only and never contacts the site.
