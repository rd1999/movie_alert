import 'package:showtime_core/showtime_core.dart';

/// In-memory [ShowtimeSource] for widget tests. Records every call.
class FakeSource implements ShowtimeSource {
  FakeSource({this.failWith});

  /// When set, every call throws this.
  Object? failWith;
  final calls = <String>[];

  @override
  String get id => 'fake';

  Future<T> _answer<T>(String call, T value) async {
    calls.add(call);
    if (failWith case final e?) throw e;
    return value;
  }

  @override
  Future<List<City>> cities() => _answer('cities', const [
    City(key: 'agra', name: 'Agra'),
    City(key: 'kolkata', name: 'Kolkata'),
    City(key: 'navi-mumbai', name: 'Navi Mumbai'),
  ]);

  @override
  Future<List<MovieSummary>> movies(String cityKey) =>
      _answer('movies:$cityKey', const [
        MovieSummary(
          contentId: 176735,
          name: 'Test Doomsday',
          slug: 'test-doomsday',
          censor: 'UA13+',
          durationMinutes: 165,
          languages: ['English', 'Hindi'],
          formats: ['3D'],
        ),
      ]);

  @override
  Future<List<Cinema>> cinemas(String cityKey) =>
      _answer('cinemas:$cityKey', const [
        Cinema(id: 1020736, name: 'Test Mani Square'),
        Cinema(id: 555, name: 'Test Not Yet Cinema'),
      ]);

  @override
  Future<ShowtimesPage> showtimes({
    required String cityKey,
    required String movieSlug,
    required int contentId,
    String? fmtGrpId,
    String? date,
  }) {
    final fmt = fmtGrpId ?? 'en';
    final listing = date ?? '2026-12-17';
    return _answer(
      'showtimes:$cityKey:$movieSlug:$fmtGrpId:$date',
      ShowtimesPage(
        movie: const MovieInfo(contentId: 176735, name: 'Test Doomsday'),
        languageFormats: const [
          LanguageFormatGroup(language: 'English', fmtGrpId: 'EN'),
          LanguageFormatGroup(language: 'Hindi', fmtGrpId: 'HI'),
        ],
        fmtGrpId: fmt,
        listingDate: listing,
        sessionDates: const ['2026-12-17', '2026-12-18'],
        cinemas: [
          CinemaShows(
            cinema: const Cinema(
              id: 1020736,
              name: 'Test Mani Square',
              address: '1 Test Road',
              isCancellable: true,
            ),
            shows: [
              _show(
                '1',
                '${listing}T10:15',
                'PXL 3D',
                SeatAvailability.available,
                240,
              ),
              _show(
                '2',
                '2026-12-18T01:00',
                'MS 3D',
                SeatAvailability.soldOut,
                0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Show _show(
    String sid,
    String time,
    String fmt,
    SeatAvailability a,
    int avail,
  ) => Show(
    sessionId: sid,
    cinemaId: 1020736,
    showTime: DateTime.parse(time),
    rawShowTime: time,
    seatsAvailable: avail,
    seatsTotal: 252,
    availability: a,
    screenFormat: fmt,
    premiumLabel: 'DOLBY ATMOS',
    maxTickets: 10,
    seatClasses: const [
      SeatClass(
        label: 'RECLINER',
        price: 1100,
        available: 3,
        total: 18,
        availability: SeatAvailability.almostFull,
      ),
    ],
  );

  @override
  Uri bookingUrl({
    required String cityKey,
    required String movieSlug,
    required int contentId,
    String? fmtGrpId,
    String? date,
  }) => Uri.parse('https://example.invalid/$movieSlug/$cityKey/$date');
}
