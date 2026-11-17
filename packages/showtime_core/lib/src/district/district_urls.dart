/// URL patterns for district.in (spec §6.2, re-checked 17 Nov 2026).
abstract final class DistrictUrls {
  static const host = 'https://www.district.in';

  static Uri citySitemap() =>
      Uri.parse('https://cdn.district.in/sitemap/sitemap-movies-city.xml');

  static Uri nowShowing(String cityKey) =>
      Uri.parse('$host/movies/$cityKey-movie-tickets');

  static Uri upcoming(String cityKey) =>
      Uri.parse('$host/movies/upcoming-movies-in-$cityKey');

  static Uri cinemas(String cityKey) =>
      Uri.parse('$host/movies/cinemas-in-$cityKey');

  /// Movie showtimes in a city. Without [fmtGrpId]/[date] the site picks
  /// the default language group and the first date with shows.
  static Uri movieShowtimes({
    required String movieSlug,
    required String cityKey,
    required int contentId,
    String? fmtGrpId,
    String? date,
  }) {
    final base =
        '$host/movies/$movieSlug-movie-tickets-in-$cityKey-MV$contentId';
    final query = <String, String>{
      'frmtid': ?fmtGrpId?.toLowerCase(),
      'fromdate': ?date,
    };
    final uri = Uri.parse(base);
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  /// Cinema page from the site-relative `entityUrl` found in showtimes data
  /// (e.g. `/inox-quest-mall-ballygunge-kolkata-c/1020727`). The site's own
  /// JSON-LD links these under `/movies`.
  static Uri cinemaPage(String entityPath) {
    final p = entityPath.startsWith('/') ? entityPath : '/$entityPath';
    return Uri.parse(p.startsWith('/movies/') ? '$host$p' : '$host/movies$p');
  }

  /// Splits a movie page slug like
  /// `avengers-doomsday-movie-tickets-in-kolkata-MV176735` into its parts.
  static ({String movieSlug, String cityKey, int contentId})? parseMovieSlug(
    String slug,
  ) {
    final m = RegExp(
      r'^([a-z0-9-]+)-movie-tickets-in-([a-z0-9-]+)-MV(\d+)$',
    ).firstMatch(slug);
    if (m == null) return null;
    return (
      movieSlug: m.group(1)!,
      cityKey: m.group(2)!,
      contentId: int.parse(m.group(3)!),
    );
  }
}
