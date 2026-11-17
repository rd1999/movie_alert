import 'package:showtime_core/showtime_core.dart';
import 'package:test/test.dart';

void main() {
  test('movie showtimes without params', () {
    expect(
      DistrictUrls.movieShowtimes(
        movieSlug: 'avengers-doomsday',
        cityKey: 'kolkata',
        contentId: 176735,
      ).toString(),
      'https://www.district.in/movies/avengers-doomsday-movie-tickets-in-kolkata-MV176735',
    );
  });

  test('movie showtimes with lowercased format group and date', () {
    expect(
      DistrictUrls.movieShowtimes(
        movieSlug: 'avengers-doomsday',
        cityKey: 'kolkata',
        contentId: 176735,
        fmtGrpId: 'Mm5dpqTqJz',
        date: '2026-12-20',
      ).toString(),
      'https://www.district.in/movies/avengers-doomsday-movie-tickets-in-kolkata-MV176735'
      '?frmtid=mm5dpqtqjz&fromdate=2026-12-20',
    );
  });

  test('city pages and sitemap', () {
    expect(
      DistrictUrls.nowShowing('kolkata').path,
      '/movies/kolkata-movie-tickets',
    );
    expect(
      DistrictUrls.upcoming('kolkata').path,
      '/movies/upcoming-movies-in-kolkata',
    );
    expect(DistrictUrls.cinemas('kolkata').path, '/movies/cinemas-in-kolkata');
    expect(DistrictUrls.citySitemap().host, 'cdn.district.in');
  });

  test('cinema page from entityUrl', () {
    expect(
      DistrictUrls.cinemaPage(
        '/inox-quest-mall-ballygunge-kolkata-c/1020727',
      ).toString(),
      'https://www.district.in/movies/inox-quest-mall-ballygunge-kolkata-c/1020727',
    );
    expect(
      DistrictUrls.cinemaPage('/movies/x-c/1').toString(),
      'https://www.district.in/movies/x-c/1',
    );
  });

  test('parseMovieSlug', () {
    final r = DistrictUrls.parseMovieSlug(
      'avengers-doomsday-movie-tickets-in-kolkata-MV176735',
    );
    expect(r?.movieSlug, 'avengers-doomsday');
    expect(r?.cityKey, 'kolkata');
    expect(r?.contentId, 176735);
    expect(DistrictUrls.parseMovieSlug('not-a-movie'), isNull);
  });
}
