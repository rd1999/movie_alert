# Device test checklist

Everything below runs on a real Android phone (Android 13+ ideally, plus one
Xiaomi/Redmi or Realme and one Samsung if you can, per spec §12). Unit and
widget tests already cover the logic. This list covers what only a device
can show: permissions, background work, notifications, OEM battery
behaviour.

```sh
flutter run            # debug build on the connected phone
flutter run --release  # closer to real background behaviour
```

## 1. First launch and browsing

- [ ] App opens on **Choose your city**. Search "kol" → Kolkata.
- [ ] **Use my location** asks for location, then picks your city (or says
      which place name didn't match).
- [ ] Movie list shows posters, censor, duration, languages; Doomsday shows
      "Releases … · advance booking". Pull to refresh works.
- [ ] Open a movie → date chips, language chips (English/Hindi), cinema
      cards with show chips (time, format, "N left", colour + text).
- [ ] Tap a **date** and a **language** chip → the page reloads for that
      date/language. *This is the first live use of the `?fromdate=` URLs.*
      Check the shows match the District website for that date.
- [ ] **Filters**: format, chain, time of day, max price, hide sold out;
      chips appear and can be removed; counts update.
- [ ] Tap a show → seat classes and prices; **Open booking** opens the
      District app/site on that movie and date.
- [ ] Airplane mode → pull to refresh → "Offline — showing listings saved …"
      banner with the last data. Back online → banner goes away.

## 2. Alert setup

- [ ] Alerts tab → ⚙ (tune icon) **Alert setup**: allow notifications, allow
      battery exemption (system dialog), both turn "Done".
- [ ] Read the phone-specific tips for your brand and apply them.
- [ ] **Send a test alert**, lock the phone → a notification arrives in about
      a minute.

## 3. Alerts (the origin story)

- [ ] Movie → **Alert me** → Cinema opens → Choose cinemas → PVR Mani Square
      ("Not showing it yet") → dates 18–21 Dec → Create.
      Expect "Alert set. Checking every 30 min." and a history entry
      "No match yet".
- [ ] Create a second alert on a cinema that **is** showing it → expect
      "Already available!" and a notification at once.
- [ ] Notification buttons: **Open booking** opens the booking page;
      **Snooze 10 min** re-shows it ~10 min later; **Stop alert** pauses the
      alert (Alerts tab shows "Paused").
- [ ] Alerts tab: Check now, Pause/Resume, Delete, history screen.
- [ ] Close the app (don't force-stop). After 15–30 min the alert's "Checked
      … ago" has moved on (background run happened).

## 4. Forcing background runs (adb)

```sh
adb shell dumpsys jobscheduler | grep -A3 com.rd1999.movie_alert   # find job id
adb shell cmd jobscheduler run -f com.rd1999.movie_alert <jobId>
adb shell dumpsys deviceidle force-idle      # Doze; then run the job again
adb shell dumpsys deviceidle unforce
adb logcat | grep ShowWatch                  # "ShowWatch background run: …"
```

- [ ] A forced run updates "Checked … ago" and adds a history line.
- [ ] Settings → **Background checks on Wi-Fi only** on, switch to mobile
      data → forced run is deferred until Wi-Fi.

## 5. Fast mode

- [ ] Alerts tab → **Fast mode** → 2 min for 30 min → Start. A persistent
      "ShowWatch fast mode" notification appears with **Stop**.
- [ ] Every ~2 min its text updates ("Last check …"); history lines appear.
- [ ] Stop from the notification and from the app; the card goes back.
- [ ] The sheet shows the remaining daily budget (6 h minus what you used).

## 6. Settings

- [ ] Quiet hours on (set a window covering now) → test alert arrives
      silently. Alarm style on → test alert rings on the alarm stream.
- [ ] Daily data limit 10 MB → after enough checks the Alerts tab shows
      "Daily data limit reached"; background checks stop until tomorrow.
- [ ] Default interval 1 h → new alerts default to 1 h.

## 7. Failure behaviour

- [ ] Airplane mode + Check now → history shows "No connection"; after 6
      failed runs the alert shows "Can't check" and one notification says so.
- [ ] Nothing ever says "no shows" because of an error.

## If something is off

Run the contract check from `packages/showtime_core`:

```sh
dart run bin/contract_check.dart            # sitemap, movies, cinemas, showtimes
dart run bin/contract_check.dart --dated    # also one ?fromdate= page
```

"CHANGED" means District changed its page structure: update
`DistrictParser` (and bump `DistrictParser.version`).
