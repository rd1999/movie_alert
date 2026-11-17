# ShowWatch — Starter Spec (working title)

> A Flutter app that shows every current showtime for a movie in your city, and alerts you on your phone the moment a cinema (or format, or date) that isn't listed yet opens for booking.
>
> **Status:** idea → prototype. **Spec date:** 17 Nov 2026.
> **Platforms:** Android first, iOS second (see §4 — iOS can't do reliable background alerts without a server).
> **Hand-off note for the AI assistant in the IDE:** read this whole file before writing code. Section 6 contains *verified* facts about the data source; everything marked **[VERIFY]** must be re-checked against live pages before relying on it.

---

## 1. The problem (origin story)

Big releases (e.g. *Avengers: Doomsday*, 18 Dec 2026) open bookings in waves. Premium certified screens open weeks early; other screens (e.g. PVR Mani Square's PXL in Kolkata) appear later with no announcement. Fans refresh booking apps for days and still miss good seats. Booking apps have "notify me" for a *movie*, but not for **"tell me when *this cinema* / *this format* / *this date* opens."**

## 2. Goals and non-goals

**Goals (v1)**
1. Pick a **city** (or use GPS) and a **movie** → see **all currently bookable shows**: cinema, date, time, language, screen format (3D, IMAX, Infinity Vision, etc.), sound (Dolby 7.1, Atmos), price per seat class, and **seats left**.
2. Create an **alert** for a condition that is **not true yet**, e.g. "Doomsday at PVR Mani Square on 18–21 Dec".
3. The user chooses the **check interval** and **how long the alert stays active** (until a date, or until it fires).
4. **No backend.** Everything runs on the phone.
5. Tapping the notification opens the booking page in the District app or the browser. **We never book or take payments.**

**Non-goals (v1)**
- No in-app booking, payment, login or seat selection.
- No user accounts or cloud sync.
- No iOS background alerts in v1 (iOS gets the browse screen and "check now" only; see §4).

---

## 3. Feasibility verdict: can this work with no backend?

| Capability | No backend? | Notes |
|---|---|---|
| Browse cities, movies, cinemas, showtimes, seats left | ✅ Yes | Plain HTTPS GET of public District pages. The data is embedded as JSON in the HTML (§6). |
| Alerts on **Android** at a 15 min+ interval | ✅ Mostly | WorkManager periodic work. The OS *may* delay runs (Doze, battery saver, aggressive OEMs). Good enough for "within ~15–60 min". |
| Alerts on **Android** at a 1–5 min interval | ⚠️ Limited | Needs a foreground service with a visible persistent notification. Android 15+ caps `dataSync` foreground services at **6 h per 24 h**, so only for short "watch windows". |
| Alerts on **iOS** | ❌ Not reliable | `BGAppRefreshTask` runs when iOS decides: often a few times a day, never after force-quit. Real iOS alerts need a server push (Phase 3, §11). |

**Conclusion:** build Android-first, with no backend. Design the code so a tiny optional backend (a cron job sending push notifications) can be added later without rewriting the app.

---

## 4. Platform constraints the app must respect  **[VERIFY against current docs]**

**Android**
- `WorkManager` periodic work: **minimum 15 min**. Runs are deferred in Doze or in low "App Standby Buckets". Add a `NetworkType.connected` constraint.
- Android 13+: request runtime permission `POST_NOTIFICATIONS`.
- Android 12+: exact alarms need `SCHEDULE_EXACT_ALARM`, which is **denied by default on Android 14+** for new installs. Play policy reserves `USE_EXACT_ALARM` for alarm and calendar apps. → **Don't depend on exact alarms.**
- Foreground service ("fast mode"): declare `FOREGROUND_SERVICE` plus a type (`dataSync`, or `specialUse` with a Play Console justification). Android 15 times out `dataSync` FGS after 6 h in 24 h, so handle `onTimeout`.
- OEM battery killers (Xiaomi, Oppo, Vivo, Realme, OnePlus, Samsung): onboarding must guide the user to turn off battery optimisation for the app (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` intent, plus per-OEM tips; see dontkillmyapp.com).
- Alert notifications use a high-importance channel with a custom alarm sound and an optional full-screen intent ("alarm style"). Android 14+ restricts full-screen intents to calling and alarm apps, so make it optional and fall back gracefully.

**iOS**
- `BGTaskScheduler` refresh is best-effort and not periodic. Local notifications are fine *if* the app gets to run.
- v1 on iOS: browse, plus a "Check now" button, plus "Checks while app is open". Show a clear message that background alerts are Android-only for now.

---

## 5. ⚠️ Legal and ethical constraints (read before shipping publicly)

- The data belongs to **District (Zomato/Eternal)** and the cinemas. There is **no public API**. Reading their web pages is scraping.
- `https://www.district.in/robots.txt` (checked 17 Nov 2026) **disallows `/*?`** for all user agents, i.e. every URL with a query string, including the `?fromdate=` showtime URLs this app needs. It also disallows `/checkout`, `/order`, `/bookings`, `/sgw/*` and others.
- Their Terms of Use very likely forbid automated access. **[VERIFY: read district.in terms]**
- **Implications**
  - Personal or side-project use at low request rates is low-risk. A **Play Store app with many users** is a real risk: IP blocking, a cease-and-desist, or Play removal for IP or impersonation complaints.
  - Never use District's or BookMyShow's name, logo or colours as branding. Say "Data from public cinema listings".
  - Always **deep-link back** to the official booking page. We send them traffic; we never resell or redistribute their data.
  - Keep the request rate polite: no checks under 15 min by default, sequential requests, backoff on errors, and a cache.
  - Before any public launch, contact District's partnerships team about permission or a data partnership. Keep a **source adapter** layer (§7) so other sources (official APIs, PVR, BookMyShow) can be swapped in.

---

## 6. Data source: District (district.in) — verified on 17 Nov 2026

All pages are Next.js server-rendered. **A plain GET with a desktop browser User-Agent returns HTTP 200 with the full data.** No JavaScript execution or login is needed.

### 6.1 How to extract the data
Each HTML page contains:
```html
<script id="__NEXT_DATA__" type="application/json">{ ...big JSON... }</script>
```
Parse that JSON. It is much richer and more stable than the visible HTML. A fallback exists: schema.org `ScreeningEvent` JSON-LD blocks (`<script type="application/ld+json">`) carry `startDate` and `location.name`/`url`/`geo`, but no formats or seats. **Verified 17 Nov 2026: capped at 50 events** (the page had 60 sessions), so it is not a safe fallback for alerts.

Page size is about 600–770 KB uncompressed. **Always send `Accept-Encoding: gzip`** (Dart's `HttpClient` does this by default) to keep mobile data use down.

### 6.2 URL patterns

| Purpose | URL |
|---|---|
| List of all cities (~783) | `https://cdn.district.in/sitemap/sitemap-movies-city.xml` (each `<loc>` = `.../movies/{cityKey}-movie-tickets`) |
| Now showing in city | `https://www.district.in/movies/{cityKey}-movie-tickets` |
| Upcoming in city | ~~`https://www.district.in/movies/upcoming-movies-in-{cityKey}`~~ **404 on 17 Nov 2026**; real URL unknown. Movies with advance bookings already appear in "now showing". |
| Cinemas in city | `https://www.district.in/movies/cinemas-in-{cityKey}` |
| Movie showtimes in city (default date + default language/format group) | `https://www.district.in/movies/{movieSlug}-movie-tickets-in-{cityKey}-MV{contentId}` |
| …for a specific date + language/format group | same URL `?frmtid={fmtGrpId lowercased}&fromdate=YYYY-MM-DD` |
| Cinema page | `https://www.district.in/movies/{cinemaSlug}-CD{cinemaId}` (linked from the cinemas page). Showtimes data uses a second form: `arrangedSessions[].entityUrl` = `/{cinemaSlug}-c/{cinemaId}`, linked by JSON-LD as `/movies/{cinemaSlug}-c/{cinemaId}`. Both seen 17 Nov 2026. |

Real example (Kolkata, *Avengers: Doomsday*):
`https://www.district.in/movies/avengers-doomsday-movie-tickets-in-kolkata-MV176735?frmtid=mm5dpqtqjz&fromdate=2026-12-20`
PVR Mani Square cinema id = **1020736**. On 17 Nov 2026 it was not listed for Doomsday, which makes it a perfect test case.

### 6.3 JSON paths in the movie showtimes page (verified)

Root: `props.pageProps.data.serverState`

```
movieContents[{contentId}].languageFormatGroups[]      // one per language
    .language            "English"
    .fmtGrpId            "Mm5dpqTqJz"   (use lowercase in URL + map key)
    .number_of_sessions  40

queryState { frmtid, fromdate }                        // what the page was asked for
movieSessions[queryState.frmtid + queryState.fromdate]  // e.g. "mm5dpqtqjz2026-12-20"
                                  // ⚠ no-param page: fromdate = "" → key is just "mm5dpqtqjz"
                                  //   and its shows are for sessionDates[0] (verified 17 Nov 2026)
    .entityCode                   "mm5dpqtqjz"
    .searchDate                   "" on the no-param page
    .data.sessionDates[]          ["2026-12-17","2026-12-18","2026-12-19","2026-12-20"]  // dates that have shows
    .pageData.nearbyCinemas[]     // cinemas with shows
    .pageData.farCinemas[]
    .arrangedSessions[]           // one entry per cinema
        .entityUrl                "/inox-quest-mall-ballygunge-kolkata-c/1020727"
        .data                     // cinema
            .id                   148
            .name                 "Cinepolis Acropolis Mall, Rajdanga Road, Kolkata"
            .address, .pincode, .latitude, .longitude, .cityKey, .chainKey ("Cinepolis")
            .isMerchantCancellable 0|1
            .distanceFromUser     km. Present even with no user coords sent (17 Nov 2026: 1.8 km for Acropolis), so measured from a default city point. Not meaningful as "distance from me".
            .amenities[]
        .sessions[]               // one per show
            .sid                  "7891"     session id
            .cid                  148        cinema id
            .mid                  "OBEOVX"   movie variant id
            .showTime             "2026-12-20T01:00"   (local IST, no offset)
            .audi                 "AUDI04"
            .scrnFmt              "MS INFINITY VISION 3D"   ← screen format
            .premiumLabel         "DOLBY 7.1"               ← sound / projection label
            .total / .avail       252 / 242                 ← seats total / available
            .statusColor          "G" Available | "Y" Filling Fast | "R" Almost Full | "D" Sold Out  (verified 17 Nov 2026, same codes on .areas[])
            .seatStatus           "Available"
            .maxTkt               10
            .tags[]               ["price_500_600","ms_infinity_vision_3d","12_am_to_8_am"]
            .areas[]              // seat classes
                .label            "PREMIUM"
                .price            540
                .sAvail / .sTotal 137 / 143
                .seatStatus       "Available"
```
Note: a show for "20 Dec" can have `showTime` `2026-12-20T01:00`, a late-night show listed under that date. Treat date-of-listing and showTime separately.

### 6.4 Discovery flow
1. City list ← sitemap (cache for 7 days). Verified 17 Nov 2026: 783 `<loc>` entries, all `…/movies/{cityKey}-movie-tickets`. No display names: derive from the key.
2. Movies in city ← "now showing" page. **Verified 17 Nov 2026:** `serverState.EDSResponse.rails[].items[].ItemDetails.MovieData` (rail `rail_identifier: "movies_listing_grid"`, 14 movies for Kolkata, **including advance bookings such as Doomsday**). Fields: `movie_id` (string), `name`, `censor`, `Duration`, `genres[]`, `image`, `movie_variants[{language, format}]`, `release_date` (epoch seconds, UTC midnight), `web_url` = `https://www.district.in/movies/{slug}-movie-tickets-MV{id}` (no city; the slug comes from here). Other rail items (quick links) have no `MovieData`.
3. Cinemas in city ← "cinemas" page. **Verified 17 Nov 2026:** `serverState.EDSResponse.rails[].items[].ItemDetails.CinemaData` (34 for Kolkata; the same cinemas repeat across rails, so dedupe by id). Fields: `cinema_id` (string), `cinema_name`, `address`, `lat`, `lon`, `distance`, `cancellable` (only when true), `amenities[]`. Includes **PVR Mani Square (1020736)** while it isn't showing Doomsday, so alerts can target it. These let users set alerts on cinemas that aren't showing the movie yet.
4. Showtimes ← movie page: first fetch without params to read `languageFormatGroups` and `sessionDates`, then fetch each `(fmtGrpId, date)` needed.

### 6.5 Robustness rules
- The site can change at any time. **All parsing goes through one `DistrictParser` class with saved HTML fixtures and unit tests.**
- If the expected JSON path is missing, raise `SourceFormatChanged`. Show "Data source changed — update needed" and **never silently report "no shows"** (a silent failure would make alerts miss).
- Send a realistic desktop User-Agent; timeout 30 s; exponential backoff on 429/5xx; never fetch in parallel bursts.

---

## 7. Architecture (no backend)

```
lib/
  main.dart
  app/                 router (go_router), theme, DI
  core/
    http/              HttpClient wrapper: UA, gzip, timeout, retry/backoff, rate limiter
    result/            Result/Failure types
  data/
    sources/
      showtime_source.dart        abstract ShowtimeSource  ← adapter interface
      district/
        district_source.dart      implements ShowtimeSource
        district_parser.dart      __NEXT_DATA__ → domain models (pure, unit-tested)
        district_urls.dart
    repo/                         caching repository (memory + disk TTL)
    db/                           local DB (alerts, check history, cached cities/cinemas)
  domain/
    models/                       City, Movie, Cinema, LanguageFormat, Show, SeatClass, Alert, AlertCondition, CheckResult
    alert_engine.dart             pure function: (Alert, Snapshot prevSnapshot, Snapshot now) → [AlertEvent]
  background/
    scheduler.dart                registers/cancels WorkManager tasks per alert
    worker_entrypoint.dart        @pragma('vm:entry-point') callback: load alerts → fetch → evaluate → notify → persist
    fast_mode_service.dart        optional foreground service (Android)
  notifications/                  channels, alarm sound, deep links
  features/
    onboarding/                   city, permissions, battery-optimisation guide
    browse/                       movie list → showtimes grid (filters: date, language, format, chain, time)
    show_detail/                  seat classes, seats left, prices, "Open booking" button
    alerts/                       create / edit / list / history
    settings/
test/
  fixtures/district/*.html        saved real pages (Doomsday Kolkata 20 Dec, city list, cinema list)
```

**Suggested packages** (check latest versions):
`dio` or `http` · `html` (only if needed) · `flutter_riverpod` · `go_router` · `drift` or `isar` (local DB) · `workmanager` · `flutter_local_notifications` · `flutter_foreground_task` (fast mode) · `permission_handler` · `geolocator` (nearest city) · `url_launcher` (deep links) · `freezed` + `json_serializable` · `mocktail` (tests).

**Key principle:** `alert_engine.dart` and `district_parser.dart` are **pure Dart with no Flutter imports**. They are 100 % unit-testable and reusable in a future server (Phase 3).

---

## 8. Functional requirements

### 8.1 Onboarding
- FR-1 Choose a city from a searchable list (~783 cities), or auto-detect by GPS (nearest city).
- FR-2 Request notification permission and explain why.
- FR-3 Android: battery-optimisation guide with OEM-specific instructions and a "Test alert" button that fires a sample notification after 1 minute.

### 8.2 Browse
- FR-4 Movie list for the city (Now showing + Upcoming tabs), with poster, title, certificate and languages.
- FR-5 Movie screen: date chips (only dates with shows), language/format selector, cinema list, and show chips per cinema.
- FR-6 Each show chip shows time, format (`scrnFmt`), sound (`premiumLabel`), and colour by availability (`avail/total`, `statusColor`).
- FR-7 Show detail: seat classes with price and seats left, cancellable or not, distance, and **"Open booking"** (deep link to the District movie page for that date; the official app or website handles booking).
- FR-8 Filters: chain, format (3D / IMAX / Infinity Vision / 4DX / PXL / laser…), language, time of day, max price, "has ≥ N seats together" (v2).
- FR-9 Pull-to-refresh; "last updated" timestamp; offline cached view.

### 8.3 Alerts (core feature)
- FR-10 Create an alert from the movie screen *or* from a cinema that isn't listed yet (from the city cinema list).
- FR-11 **Alert conditions** (v1):
  1. **Cinema opens:** movie M gets ≥ 1 show at cinema C (optionally on dates D1..Dn, optionally in language L).
  2. **Format opens:** movie M gets a show with format matching F (e.g. "PXL", "IMAX", "4DX", "3D") anywhere in the city, or at cinema C.
  3. **Date opens:** bookings open for movie M on date D (any cinema, or a chosen set).
  4. **New cinema anywhere:** any cinema not in the current snapshot starts showing M.
  5. (v1.1) **Seats available:** a show that was sold out, or below N seats, now has ≥ N seats (for sold-out first-day shows).
- FR-12 **Interval:** user picks 15 min / 30 min / 1 h / 3 h / 6 h (default 30 min). "Fast mode" (Android, opt-in) allows 2 / 5 / 10 min inside a user-set window (≤ 6 h/day), shown as a persistent notification.
- FR-13 **Duration:** active until a date/time (default: the day before the first wanted date), *or* "until it fires once", *or* "keep alerting on every new match" (e.g. each new show).
- FR-14 Alert list: status (active, paused, fired, expired, error), last check time, next check (estimated), number of checks, and a "Check now" button.
- FR-15 Alert history: a log of each check (timestamp, result, error) for transparency and debugging.
- FR-16 When an alert fires: a **high-priority notification** with alarm sound (user can choose normal sound or alarm style), a summary (cinema, dates, times, format, seats), and actions **[Open booking] [Snooze 10 min] [Stop alert]**.
- FR-17 De-duplication: the same match never notifies twice (store a hash of matched session ids).
- FR-18 Auto-pause after K consecutive failures (e.g. 6) with a notification "Alert X can't check — tap to fix".
- FR-19 Batch requests: if several alerts need the same `(movie, city, fmtGrpId, date)` page, fetch it once per run.

### 8.4 Settings
- FR-20 Default interval, alarm sound, quiet hours (still alert, but silently), mobile-data usage limit, Wi-Fi-only option.
- FR-21 "Data source status" screen: last successful parse and parser version.

---

## 9. Non-functional requirements
- NFR-1 **Politeness:** ≤ 1 request per second per device; ≥ 15 min default interval; backoff on 429/5xx; jitter of ±10 % on schedules.
- NFR-2 **Data use:** gzip; fetch only the dates and format groups an alert needs. Measured 17 Nov 2026: one showtimes page is **~87 KB gzipped** (vs ~600 KB raw). An alert watching 4 dates every 30 min ≈ 17 MB/day, so offer a Wi-Fi-only option and per-alert date limits.
- NFR-3 **Battery:** background run under 20 s; no wake locks outside fast mode.
- NFR-4 **Reliability:** a parser failure must surface as an error, never as "no shows".
- NFR-5 **Privacy:** no accounts, no analytics by default, all data on device. GPS only for nearest-city lookup, never sent anywhere except as needed by the source (we don't send it at all in v1).
- NFR-6 **Testability:** parser and alert engine ≥ 90 % coverage using saved real fixtures.
- NFR-7 **Accessibility:** colour is never the only availability signal (show "242 left" text too).

---

## 10. Core algorithms

### 10.1 Background run (each WorkManager tick)
```
load active alerts due now
group by (cityKey, movieContentId)
for each group:
   base = fetch movie page (no params)     → languageFormatGroups, sessionDates
   pages = for each needed (fmtGrpId, date ∈ alert.dates ∩ sessionDates OR all if "date opens"):
              fetch + parse → Snapshot (set of sessions with cinema, fmt, seats)
   for each alert in group:
       events = AlertEngine.evaluate(alert, prevSnapshot(alert), snapshot)
       if events: notify(alert, events); record fired session hashes
       save snapshot + CheckResult
expire alerts past end time; reschedule
```

### 10.2 Matching rules
- Cinema match by **cinema id** (stable). Never match by name, but display the name.
- Format match: case-insensitive "contains" on `scrnFmt` **and** `premiumLabel` (e.g. "PXL" may appear in either). Seen 17 Nov 2026: `scrnFmt` = "MS INFINITY VISION 3D", "MS INFINITY VISION 3D SCREEN X"; `premiumLabel` = "DOLBY 7.1", "2K LASER DOLBY 7.1", "LASER", "INSIGNIA", "RECLINERS" or null. So brand/premium formats appear in both fields. **[VERIFY PXL/IMAX once those screens list]**
- "Date opens": `date ∈ sessionDates` now but not in the previous snapshot.
- First run of an alert: if the condition is *already* true, notify immediately ("Already available!").

---

## 11. Roadmap

| Phase | Scope | Exit criteria |
|---|---|---|
| **0. Spike (1–2 days)** | Pure-Dart CLI: fetch the Doomsday Kolkata page, parse `__NEXT_DATA__`, print cinemas, shows, formats and seats. Save fixtures. | Output matches the website for 20 Dec. |
| **1. Browse MVP** | City picker, movie list, showtimes screen, show detail, deep link. | Usable daily for Kolkata. |
| **2. Android alerts** | Alert CRUD, WorkManager, notifications, history, onboarding battery guide, fast mode. | The Mani Square test alert fires within one interval of the cinema appearing (simulate with a fixture swap). |
| **3. Optional tiny backend** (for iOS and reliability) | Reuse the pure-Dart parser and engine in a cron job (Cloudflare Worker / GitHub Actions / Cloud Run) → push via FCM/APNs. Device registers alerts anonymously. | iOS alerts work; Android gets reliable server pushes. |
| **4. More sources** | Adapter for other ticketing sources (only with permission or official APIs). | Same UI, multiple sources. |

---

## 12. Testing plan
- **Unit:** `DistrictParser` against fixtures (`test/fixtures/district/doomsday_kolkata_2026-12-20.html`, `city_list.xml`, `cinemas_kolkata.html`). `AlertEngine` with hand-built snapshots covering every condition type, dedupe, the first-run "already available" case, and expiry.
- **Contract test (manual or CI, nightly):** hit the live pages and assert the JSON paths exist. A failure means the source changed.
- **Background:** on a real Android device, run `adb shell cmd jobscheduler run -f <pkg> <jobId>` to force WorkManager. Test Doze with `adb shell dumpsys deviceidle force-idle`.
- **OEM:** at least one Xiaomi/Redmi or Realme device and one Samsung.
- **End-to-end scenario (the origin story):** an alert for "PVR Mani Square (1020736), Doomsday, 18–21 Dec, interval 15 min". Swap in a fixture where Mani Square appears → a notification with times arrives → tapping it opens the District page.

---

## 13. Risks
| Risk | Impact | Mitigation |
|---|---|---|
| District changes page structure | Alerts silently break | Parser versioning, contract tests, loud error state (NFR-4) |
| District blocks or rate-limits | App stops working | Politeness limits, backoff; long-term: permission or partnership |
| Legal / Play Store takedown | Product dies | No branding misuse, deep-link back, seek permission before scaling, keep source adapters |
| Android OEM kills background work | Missed alerts | Onboarding guide, test-alert button, fast mode, Phase 3 server push |
| iOS limits | Half the market missing | Be explicit in UI; Phase 3 backend |

---

## 14. Open questions
1. Monetisation (if any)? Ads could look like exploiting someone else's data; a one-time "Pro" (fast mode, unlimited alerts) is cleaner.
2. Product name and branding (avoid "District", "BookMyShow" and cinema chain marks).
3. Support BookMyShow too? Its pages are harder to read (seat maps are canvas-rendered) and it has its own terms. Decide after Phase 2.
4. Should alerts consider **seats together** (e.g. 2 adjacent seats in the centre)? That needs seat-layout data from booking endpoints that are likely disallowed. Probably out of scope.

---

## 15. First prompt to paste into Claude in the IDE

> Read `SHOWWATCH_SPEC.md` fully. Start **Phase 0**: create a pure-Dart package `packages/showtime_core` with `DistrictUrls`, `DistrictParser` (parse `__NEXT_DATA__` from the movie-showtimes page into the domain models in §7) and a CLI `bin/showtimes.dart <cityKey> <movieSlug> <MVid> [YYYY-MM-DD]` that prints cinemas, show times, `scrnFmt`, `premiumLabel` and `avail/total` per show. Download one real page into `test/fixtures/district/` and write unit tests against it. Re-verify every JSON path marked [VERIFY] against the live page and update the spec if anything differs. Don't build any UI yet.
