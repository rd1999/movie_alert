import 'models.dart';

typedef Json = Map<String, Object?>;

/// JSON codecs for the domain models, used for the app's offline cache and
/// reusable by a future server. Kept separate so the models stay plain.
abstract final class ModelJson {
  static Json city(City c) => {'key': c.key, 'name': c.name};

  static City cityFrom(Json j) =>
      City(key: j['key'] as String, name: j['name'] as String);

  static Json movieSummary(MovieSummary m) => {
    'contentId': m.contentId,
    'name': m.name,
    'slug': m.slug,
    'censor': m.censor,
    'duration': m.durationMinutes,
    'genres': m.genres,
    'languages': m.languages,
    'formats': m.formats,
    'poster': m.posterUrl,
    'release': m.releaseDate?.toUtc().toIso8601String(),
  };

  static MovieSummary movieSummaryFrom(Json j) => MovieSummary(
    contentId: (j['contentId'] as num).toInt(),
    name: j['name'] as String,
    slug: j['slug'] as String,
    censor: j['censor'] as String?,
    durationMinutes: (j['duration'] as num?)?.toInt(),
    genres: _strings(j['genres']),
    languages: _strings(j['languages']),
    formats: _strings(j['formats']),
    posterUrl: j['poster'] as String?,
    releaseDate: j['release'] == null
        ? null
        : DateTime.parse(j['release'] as String),
  );

  static Json cinema(Cinema c) => {
    'id': c.id,
    'name': c.name,
    'address': c.address,
    'pincode': c.pincode,
    'lat': c.latitude,
    'lon': c.longitude,
    'cityKey': c.cityKey,
    'chain': c.chain,
    'cancellable': c.isCancellable,
    'distanceKm': c.distanceKm,
    'path': c.path,
  };

  static Cinema cinemaFrom(Json j) => Cinema(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String,
    address: j['address'] as String?,
    pincode: j['pincode'] as String?,
    latitude: (j['lat'] as num?)?.toDouble(),
    longitude: (j['lon'] as num?)?.toDouble(),
    cityKey: j['cityKey'] as String?,
    chain: j['chain'] as String?,
    isCancellable: j['cancellable'] as bool?,
    distanceKm: (j['distanceKm'] as num?)?.toDouble(),
    path: j['path'] as String?,
  );

  static Json seatClass(SeatClass a) => {
    'label': a.label,
    'price': a.price,
    'avail': a.available,
    'total': a.total,
    'status': a.availability.name,
  };

  static SeatClass seatClassFrom(Json j) => SeatClass(
    label: j['label'] as String,
    price: j['price'] as num,
    available: (j['avail'] as num).toInt(),
    total: (j['total'] as num).toInt(),
    availability: _availability(j['status']),
  );

  static Json show(Show s) => {
    'sid': s.sessionId,
    'cid': s.cinemaId,
    'time': s.rawShowTime,
    'mid': s.movieVariantId,
    'audi': s.audi,
    'fmt': s.screenFormat,
    'premium': s.premiumLabel,
    'avail': s.seatsAvailable,
    'total': s.seatsTotal,
    'status': s.availability.name,
    'statusLabel': s.statusLabel,
    'maxTkt': s.maxTickets,
    'tags': s.tags,
    'areas': [for (final a in s.seatClasses) seatClass(a)],
  };

  static Show showFrom(Json j) {
    final raw = j['time'] as String;
    return Show(
      sessionId: j['sid'] as String,
      cinemaId: (j['cid'] as num).toInt(),
      showTime: DateTime.parse(raw),
      rawShowTime: raw,
      movieVariantId: j['mid'] as String?,
      audi: j['audi'] as String?,
      screenFormat: j['fmt'] as String?,
      premiumLabel: j['premium'] as String?,
      seatsAvailable: (j['avail'] as num).toInt(),
      seatsTotal: (j['total'] as num).toInt(),
      availability: _availability(j['status']),
      statusLabel: j['statusLabel'] as String?,
      maxTickets: (j['maxTkt'] as num?)?.toInt(),
      tags: _strings(j['tags']),
      seatClasses: [
        for (final a in j['areas'] as List? ?? const []) seatClassFrom(_map(a)),
      ],
    );
  }

  static Json showtimesPage(ShowtimesPage p) => {
    'movie': {
      'contentId': p.movie.contentId,
      'name': p.movie.name,
      'censor': p.movie.censor,
      'duration': p.movie.durationMinutes,
      'language': p.movie.primaryLanguage,
      'released': p.movie.isReleased,
    },
    'groups': [
      for (final g in p.languageFormats)
        {
          'language': g.language,
          'fmtGrpId': g.fmtGrpId,
          'sessions': g.sessionCount,
        },
    ],
    'fmtGrpId': p.fmtGrpId,
    'listingDate': p.listingDate,
    'sessionDates': p.sessionDates,
    'cinemas': [
      for (final c in p.cinemas)
        {
          'cinema': cinema(c.cinema),
          'shows': [for (final s in c.shows) show(s)],
        },
    ],
  };

  static ShowtimesPage showtimesPageFrom(Json j) {
    final m = _map(j['movie']);
    return ShowtimesPage(
      movie: MovieInfo(
        contentId: (m['contentId'] as num).toInt(),
        name: m['name'] as String,
        censor: m['censor'] as String?,
        durationMinutes: (m['duration'] as num?)?.toInt(),
        primaryLanguage: m['language'] as String?,
        isReleased: m['released'] as bool?,
      ),
      languageFormats: [
        for (final g in j['groups'] as List)
          LanguageFormatGroup(
            language: _map(g)['language'] as String,
            fmtGrpId: _map(g)['fmtGrpId'] as String,
            sessionCount: (_map(g)['sessions'] as num?)?.toInt(),
          ),
      ],
      fmtGrpId: j['fmtGrpId'] as String,
      listingDate: j['listingDate'] as String?,
      sessionDates: _strings(j['sessionDates']),
      cinemas: [
        for (final c in j['cinemas'] as List)
          CinemaShows(
            cinema: cinemaFrom(_map(_map(c)['cinema'])),
            shows: [
              for (final s in _map(c)['shows'] as List) showFrom(_map(s)),
            ],
          ),
      ],
    );
  }

  static Json _map(Object? o) => (o as Map).cast<String, Object?>();

  static List<String> _strings(Object? o) => [
    for (final v in o as List? ?? const []) v as String,
  ];

  static SeatAvailability _availability(Object? name) =>
      SeatAvailability.values.asNameMap()[name] ?? SeatAvailability.unknown;
}
