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
  app/                    router (Browse / Alerts tabs), theme, shared widgets
  core/http, core/prefs   shared polite fetcher, SharedPreferences
  data/sources/           active ShowtimeSource (District adapter from core)
  data/repo/              in-memory TTL cache, shared in-flight requests
  data/db/                SQLite: alerts, check history, latest snapshots
  background/             AlertRunner (one run), WorkManager scheduler,
                          worker entrypoint; fast mode (planned)
  notifications/          channels, alarm style, actions, permissions
  features/browse/        movie list, showtimes (date/language/format)
  features/show_detail/   seat classes sheet, "Open booking" deep link
  features/alerts/        create, list, history
  features/onboarding/    city picker, alert setup (permissions, battery,
                          OEM tips, alarm style, test alert, source status)
docs/                     spec and notes
```

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 0 | Pure-Dart parser + CLI + fixtures/tests | parser, URLs, CLI, 27 tests done; dated-page (`?fromdate=`) check pending |
| 1 | Browse MVP (city, movies, showtimes, deep link) | done: city picker, movie list, showtimes, show detail, booking link. GPS city + offline cache pending |
| 2 | Android alerts (WorkManager, notifications, history) | done except fast mode (foreground service); needs real-device testing |
| 3 | Optional tiny backend for iOS / push | — |

## How alerts run

One periodic WorkManager task (every 15 min or the shortest alert interval,
network required) wakes the app. `AlertRunner` checks only the alerts that
are due, fetching each `(movie, language, date)` page once for all of them,
evaluates them with the core `AlertEngine`, notifies and logs each check.
A failed check never counts as "no shows"; after 6 failures in a row the
alert shows "Can't check" and you get one notification about it.

### Testing on a device

```sh
flutter run                                          # Android device
adb shell cmd jobscheduler run -f com.rd1999.movie_alert 0   # see below
adb shell dumpsys deviceidle force-idle              # Doze test
```

WorkManager's job id varies; `adb shell dumpsys jobscheduler | grep
movie_alert` lists it. The **Alert setup** screen has a "Send a test alert"
button that goes through the same background scheduler.

## Development

```sh
flutter pub get
flutter test                       # app tests
cd packages/showtime_core
dart pub get
dart test                          # parser / engine tests
```
