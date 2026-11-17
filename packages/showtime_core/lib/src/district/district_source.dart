import '../models.dart';
import '../sources/showtime_source.dart';
import 'district_parser.dart';
import 'district_urls.dart';

/// Fetches a URL and returns the body; throws on failure.
typedef TextFetcher = Future<String> Function(Uri url);

/// [ShowtimeSource] backed by district.in public pages. The fetcher is
/// injected so tests run offline and the app can use its own HTTP stack.
class DistrictSource implements ShowtimeSource {
  const DistrictSource(
    this._get, {
    DistrictParser parser = const DistrictParser(),
  }) : _parser = parser;

  final TextFetcher _get;
  final DistrictParser _parser;

  @override
  String get id => 'district';

  @override
  Future<List<City>> cities() async =>
      _parser.parseCitySitemap(await _get(DistrictUrls.citySitemap()));

  @override
  Future<List<MovieSummary>> movies(String cityKey) async =>
      _parser.parseMoviesPage(await _get(DistrictUrls.nowShowing(cityKey)));

  @override
  Future<List<Cinema>> cinemas(String cityKey) async =>
      _parser.parseCinemasPage(await _get(DistrictUrls.cinemas(cityKey)));

  @override
  Future<ShowtimesPage> showtimes({
    required String cityKey,
    required String movieSlug,
    required int contentId,
    String? fmtGrpId,
    String? date,
  }) async => _parser.parseShowtimesPage(
    await _get(
      DistrictUrls.movieShowtimes(
        movieSlug: movieSlug,
        cityKey: cityKey,
        contentId: contentId,
        fmtGrpId: fmtGrpId,
        date: date,
      ),
    ),
  );

  @override
  Uri bookingUrl({
    required String cityKey,
    required String movieSlug,
    required int contentId,
    String? fmtGrpId,
    String? date,
  }) => DistrictUrls.movieShowtimes(
    movieSlug: movieSlug,
    cityKey: cityKey,
    contentId: contentId,
    fmtGrpId: fmtGrpId,
    date: date,
  );
}
