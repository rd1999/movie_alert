// Contract check (spec §12): confirm the live pages still have the structure
// the parsers expect. Run by hand; it makes 4 polite requests (5 with
// --dated), one at a time.
//
//   dart run bin/contract_check.dart [cityKey] [movieSlug] [MVid] [--dated]
//
// Defaults: kolkata avengers-doomsday 176735.
//
// --dated also fetches one `?frmtid=&fromdate=` page. District's robots.txt
// disallows query-string URLs (spec §5), so this is opt-in.
//
// Exit code 0 = all good, 1 = a page changed (update the parser), 2 = a
// page couldn't be fetched.
import 'dart:io';

import 'package:showtime_core/io.dart';
import 'package:showtime_core/showtime_core.dart';

Future<void> main(List<String> argv) async {
  final dated = argv.contains('--dated');
  final args = [
    for (final a in argv)
      if (!a.startsWith('--')) a,
  ];
  final city = args.isNotEmpty ? args[0] : 'kolkata';
  final slug = args.length > 1 ? args[1] : 'avengers-doomsday';
  final id = args.length > 2
      ? int.parse(args[2].replaceFirst('MV', ''))
      : 176735;

  final fetcher = PoliteFetcher(minGap: const Duration(seconds: 2));
  final source = DistrictSource(fetcher.get);
  var changed = 0, failed = 0;

  Future<void> check(String name, Future<String> Function() run) async {
    stdout.write('${name.padRight(34)} ');
    try {
      stdout.writeln('OK   ${await run()}');
    } on SourceFormatChanged catch (e) {
      changed++;
      stdout.writeln('CHANGED  $e');
    } catch (e) {
      failed++;
      stdout.writeln('FETCH FAILED  $e');
    }
  }

  try {
    await check('City sitemap', () async {
      final cities = await source.cities();
      if (!cities.any((c) => c.key == city)) {
        throw SourceFormatChanged(
          '"$city" missing from ${cities.length} cities',
        );
      }
      return '${cities.length} cities';
    });
    await check('Movies in $city', () async {
      final movies = await source.movies(city);
      return '${movies.length} movies';
    });
    await check('Cinemas in $city', () async {
      final cinemas = await source.cinemas(city);
      if (cinemas.isEmpty) throw SourceFormatChanged('no cinemas parsed');
      return '${cinemas.length} cinemas';
    });
    ShowtimesPage? base;
    await check('Showtimes $slug (default)', () async {
      base = await source.showtimes(
        cityKey: city,
        movieSlug: slug,
        contentId: id,
      );
      final p = base!;
      final unknown = p.allShows
          .where((s) => s.availability == SeatAvailability.unknown)
          .length;
      return '${p.cinemas.length} cinemas, ${p.allShows.length} shows, '
          'dates ${p.sessionDates.join(',')}'
          '${unknown > 0 ? ' · $unknown unknown status codes!' : ''}';
    });
    if (dated && base != null && base!.sessionDates.length > 1) {
      final p = base!;
      final date = p.sessionDates.last;
      await check('Showtimes $slug ($date, ${p.fmtGrpId})', () async {
        final d = await source.showtimes(
          cityKey: city,
          movieSlug: slug,
          contentId: id,
          fmtGrpId: p.fmtGrpId,
          date: date,
        );
        if (d.listingDate != date) {
          throw SourceFormatChanged('asked for $date, got ${d.listingDate}');
        }
        return '${d.cinemas.length} cinemas, ${d.allShows.length} shows';
      });
    }
  } finally {
    fetcher.close();
  }

  stdout.writeln(
    changed > 0
        ? '\n$changed page(s) changed structure: update DistrictParser.'
        : failed > 0
        ? '\n$failed page(s) could not be fetched.'
        : '\nAll pages match the parser.',
  );
  exitCode = changed > 0 ? 1 : (failed > 0 ? 2 : 0);
}
