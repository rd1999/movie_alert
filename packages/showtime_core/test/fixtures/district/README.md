# District fixtures

Real pages saved from district.in are **gitignored**. The repo is public and
we don't redistribute their data (spec §5). Tests that need them skip when
the files are missing; everything else uses the synthetic builder in
`test/support/synthetic_page.dart`.

To recreate the local fixture (one request, be polite):

```sh
dart run bin/showtimes.dart kolkata avengers-doomsday 176735 \
  --save=test/fixtures/district/doomsday_kolkata_default.html
```

| File | Source URL | Saved |
|---|---|---|
| `doomsday_kolkata_default.html` | `/movies/avengers-doomsday-movie-tickets-in-kolkata-MV176735` (no params) | 17 Nov 2026 |
