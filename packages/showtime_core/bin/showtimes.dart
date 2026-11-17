// Phase 0 spike CLI: print every show for a movie in a city.
//
//   dart run bin/showtimes.dart <cityKey> <movieSlug> <MVid> [YYYY-MM-DD]
//       [--fmt=<fmtGrpId>] [--file=<saved.html>] [--save=<out.html>]
//
// Example:
//   dart run bin/showtimes.dart kolkata avengers-doomsday 176735
//
// One request per run. Be polite: don't loop this faster than every 15 min.
import 'dart:async';
import 'dart:io';

import 'package:showtime_core/io.dart';
import 'package:showtime_core/showtime_core.dart';

Future<void> main(List<String> argv) async {
  final flags = <String, String>{};
  final args = <String>[];
  for (final a in argv) {
    if (a.startsWith('--')) {
      final i = a.indexOf('=');
      flags[i < 0 ? a.substring(2) : a.substring(2, i)] = i < 0
          ? ''
          : a.substring(i + 1);
    } else {
      args.add(a);
    }
  }

  String html;
  if (flags['file'] case final path?) {
    html = await File(path).readAsString();
  } else {
    if (args.length < 3 || flags.containsKey('help')) {
      stderr.writeln(
        'usage: showtimes <cityKey> <movieSlug> <MVid> [YYYY-MM-DD] '
        '[--fmt=<fmtGrpId>] [--file=<saved.html>] [--save=<out.html>]',
      );
      exitCode = 64;
      return;
    }
    final contentId = int.tryParse(args[2].replaceFirst(RegExp('^MV'), ''));
    if (contentId == null) {
      stderr.writeln('MVid must be a number, e.g. 176735');
      exitCode = 64;
      return;
    }
    final url = DistrictUrls.movieShowtimes(
      movieSlug: args[1],
      cityKey: args[0],
      contentId: contentId,
      fmtGrpId: flags['fmt'],
      date: args.length > 3 ? args[3] : null,
    );
    stderr.writeln('GET $url');
    html = await _fetch(url);
    if (flags['save'] case final out?) {
      await File(out).writeAsString(html);
      stderr.writeln('saved to $out');
    }
  }

  try {
    _print(const DistrictParser().parseShowtimesPage(html));
  } on SourceFormatChanged catch (e) {
    stderr.writeln('Data source changed — update needed.\n$e');
    exitCode = 2;
  }
}

/// One polite GET (desktop UA, gzip, 30 s timeout, backoff on 429/5xx).
Future<String> _fetch(Uri url) async {
  final fetcher = PoliteFetcher();
  try {
    return await fetcher.get(url);
  } finally {
    fetcher.close();
  }
}

void _print(ShowtimesPage page) {
  final m = page.movie;
  final lang = page.languageFormats
      .where((g) => g.key == page.fmtGrpId)
      .map((g) => g.language)
      .firstOrNull;
  stdout
    ..writeln(
      '${m.name} (${m.censor ?? '?'}, ${m.durationMinutes ?? '?'} min) — '
      '${lang ?? page.fmtGrpId} [${page.fmtGrpId}] — listed for '
      '${page.listingDate ?? 'no dates'}',
    )
    ..writeln('Dates with shows: ${page.sessionDates.join(', ')}');
  final others = page.languageFormats.where((g) => g.key != page.fmtGrpId);
  if (others.isNotEmpty) {
    stdout.writeln(
      'Other groups: ${others.map((g) => '${g.language} (${g.key}, ${g.sessionCount ?? '?'} shows)').join('; ')}',
    );
  }
  final total = page.allShows.length;
  stdout.writeln('${page.cinemas.length} cinemas, $total shows\n');

  for (final cs in page.cinemas) {
    final c = cs.cinema;
    final dist = c.distanceKm == null
        ? ''
        : ', ${c.distanceKm!.toStringAsFixed(1)} km';
    stdout.writeln('${c.name}  [id ${c.id}$dist]');
    for (final s in cs.shows) {
      final t = s.rawShowTime.length >= 16
          ? s.rawShowTime.substring(11, 16)
          : s.rawShowTime;
      final day =
          page.listingDate != null &&
              !s.rawShowTime.startsWith(page.listingDate!)
          ? ' (${s.rawShowTime.substring(0, 10)})'
          : '';
      final fmt = [s.screenFormat, s.premiumLabel].nonNulls.join(' · ');
      final classes = s.seatClasses
          .map((a) => '${a.label} ₹${a.price} ${a.available}/${a.total}')
          .join(' | ');
      stdout.writeln(
        '  $t$day  ${fmt.padRight(42)} ${'${s.seatsAvailable}/${s.seatsTotal}'.padLeft(7)} left  '
        '${(s.statusLabel ?? s.availability.name).padRight(12)} $classes',
      );
    }
    stdout.writeln();
  }
}
