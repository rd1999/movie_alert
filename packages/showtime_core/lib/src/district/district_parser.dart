import 'dart:convert';

import '../errors.dart';
import '../models.dart';

/// Parses district.in pages via their embedded Next.js `__NEXT_DATA__` JSON
/// (spec §6). Every structural surprise throws [SourceFormatChanged]. An
/// empty result is only returned when the page really says "no shows".
class DistrictParser {
  const DistrictParser();

  /// Bump whenever parsing logic changes (shown on the source status
  /// screen, FR-21).
  static const version = 1;

  static final _nextDataRe = RegExp(
    r'<script[^>]*\bid="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>',
  );

  /// Extracts and decodes the `__NEXT_DATA__` JSON object from [html].
  Map<String, Object?> extractNextData(String html) {
    final m = _nextDataRe.firstMatch(html);
    if (m == null) {
      throw SourceFormatChanged('No __NEXT_DATA__ script in page');
    }
    try {
      final decoded = jsonDecode(m.group(1)!);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException catch (e) {
      throw SourceFormatChanged(
        '__NEXT_DATA__ is not valid JSON: ${e.message}',
      );
    }
    throw SourceFormatChanged('__NEXT_DATA__ is not a JSON object');
  }

  /// Parses a movie-showtimes page
  /// (`/movies/{slug}-movie-tickets-in-{city}-MV{id}[?frmtid=&fromdate=]`).
  ShowtimesPage parseShowtimesPage(String html) {
    final root = _J(extractNextData(html), r'$');
    final state = root
        .obj('props')
        .obj('pageProps')
        .obj('data')
        .obj('serverState');

    // movieContents: exactly the movie this page is about.
    final contents = state.obj('movieContents');
    if (contents.map.length != 1) {
      throw SourceFormatChanged(
        'Expected 1 movieContents entry, found ${contents.map.length}',
        path: contents.path,
      );
    }
    final content = contents.obj(contents.map.keys.single);
    final movie = MovieInfo(
      contentId: content.integer('contentId'),
      name: content.string('name'),
      censor: content.optString('censor'),
      durationMinutes: content.optInt('duration'),
      primaryLanguage: content.optString('primary_language'),
      isReleased: content.optBool('isReleased'),
    );
    final groups = [
      for (final g in content.list('languageFormatGroups').objects())
        LanguageFormatGroup(
          language: g.string('language'),
          fmtGrpId: g.string('fmtGrpId'),
          sessionCount: g.optInt('number_of_sessions'),
        ),
    ];

    // movieSessions is keyed by `frmtid + fromdate` as in queryState
    // (verified 17 Nov 2026: no-param page -> key "mm5dpqtqjz").
    final sessionsByKey = state.obj('movieSessions');
    final query = state.optObj('queryState');
    final qFmt = query?.optString('frmtid') ?? '';
    final qDate = query?.optString('fromdate') ?? '';
    _J entry;
    final wanted = '${qFmt.toLowerCase()}$qDate';
    if (sessionsByKey.map.containsKey(wanted)) {
      entry = sessionsByKey.obj(wanted);
    } else if (sessionsByKey.map.length == 1) {
      entry = sessionsByKey.obj(sessionsByKey.map.keys.single);
    } else {
      throw SourceFormatChanged(
        'Cannot pick movieSessions entry "$wanted" from '
        '${sessionsByKey.map.keys.toList()}',
        path: sessionsByKey.path,
      );
    }

    final sessionDates = [
      for (final d in entry.obj('data').list('sessionDates').values)
        _date(d, entry.path),
    ];
    final fmtGrpId =
        (entry.optString('entityCode') ?? (qFmt.isEmpty ? null : qFmt))
            ?.toLowerCase();
    if (fmtGrpId == null) {
      throw SourceFormatChanged('No format group id', path: entry.path);
    }
    final searchDate = entry.optString('searchDate');
    final listingDate = qDate.isNotEmpty
        ? qDate
        : (searchDate != null && searchDate.isNotEmpty)
        ? searchDate
        : (sessionDates.isEmpty ? null : sessionDates.first);

    final cinemas = [
      for (final a in entry.list('arrangedSessions').objects()) _cinemaShows(a),
    ];

    return ShowtimesPage(
      movie: movie,
      languageFormats: groups,
      fmtGrpId: fmtGrpId,
      listingDate: listingDate,
      sessionDates: sessionDates,
      cinemas: cinemas,
    );
  }

  CinemaShows _cinemaShows(_J a) {
    final c = a.obj('data');
    final cinema = Cinema(
      id: c.integer('id'),
      name: c.string('name'),
      address: c.optString('address'),
      pincode: c.optString('pincode'),
      latitude: c.optNum('latitude')?.toDouble(),
      longitude: c.optNum('longitude')?.toDouble(),
      cityKey: c.optString('cityKey'),
      chain: c.optString('chainKey'),
      isCancellable: switch (c.optNum('isMerchantCancellable')) {
        null => null,
        final n => n != 0,
      },
      distanceKm: c.optNum('distanceFromUser')?.toDouble(),
      path: a.optString('entityUrl'),
    );
    final shows = [for (final s in a.list('sessions').objects()) _show(s)];
    return CinemaShows(cinema: cinema, shows: shows);
  }

  Show _show(_J s) {
    final raw = s.string('showTime');
    final time = DateTime.tryParse(raw);
    if (time == null) {
      throw SourceFormatChanged(
        'Bad showTime "$raw"',
        path: '${s.path}.showTime',
      );
    }
    return Show(
      sessionId: s.anyId('sid'),
      cinemaId: s.integer('cid'),
      showTime: time,
      rawShowTime: raw,
      movieVariantId: s.optString('mid'),
      audi: s.optString('audi'),
      screenFormat: _blankToNull(s.optString('scrnFmt')),
      premiumLabel: _blankToNull(s.optString('premiumLabel')),
      seatsAvailable: s.integer('avail'),
      seatsTotal: s.integer('total'),
      availability: SeatAvailability.fromDistrictCode(
        s.optString('statusColor'),
        label: s.optString('seatStatus'),
      ),
      statusLabel: s.optString('seatStatus'),
      maxTickets: s.optInt('maxTkt'),
      tags: [
        for (final t in s.optList('tags')?.values ?? const [])
          ?(t is String ? t : null),
      ],
      seatClasses: [
        for (final area in s.optList('areas')?.objects() ?? const <_J>[])
          SeatClass(
            label: area.string('label'),
            price: area.number('price'),
            available: area.integer('sAvail'),
            total: area.integer('sTotal'),
            availability: SeatAvailability.fromDistrictCode(
              area.optString('statusColor'),
              label: area.optString('seatStatus'),
            ),
          ),
      ],
    );
  }

  static String? _blankToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  static final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String _date(Object? v, String path) {
    if (v is String && _dateRe.hasMatch(v)) return v;
    throw SourceFormatChanged(
      'Bad session date "$v"',
      path: '$path.data.sessionDates',
    );
  }
}

/// Typed JSON navigator that records its path for precise error messages.
class _J {
  _J(this.map, this.path);

  final Map<String, Object?> map;
  final String path;

  Never _fail(String key, String expected) => throw SourceFormatChanged(
    'Expected $expected, found ${map.containsKey(key) ? map[key].runtimeType : 'nothing'}',
    path: '$path.$key',
  );

  _J obj(String key) {
    final v = map[key];
    if (v is Map<String, Object?>) return _J(v, '$path.$key');
    _fail(key, 'object');
  }

  _J? optObj(String key) {
    final v = map[key];
    return v is Map<String, Object?> ? _J(v, '$path.$key') : null;
  }

  _L list(String key) {
    final v = map[key];
    if (v is List<Object?>) return _L(v, '$path.$key');
    _fail(key, 'list');
  }

  _L? optList(String key) {
    final v = map[key];
    return v is List<Object?> ? _L(v, '$path.$key') : null;
  }

  String string(String key) {
    final v = map[key];
    if (v is String) return v;
    _fail(key, 'string');
  }

  String? optString(String key) {
    final v = map[key];
    return v is String ? v : null;
  }

  num number(String key) {
    final v = map[key];
    if (v is num) return v;
    if (v is String && num.tryParse(v) != null) return num.parse(v);
    _fail(key, 'number');
  }

  num? optNum(String key) {
    final v = map[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  int integer(String key) => number(key).toInt();

  int? optInt(String key) => optNum(key)?.toInt();

  bool? optBool(String key) {
    final v = map[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    return null;
  }

  /// Ids arrive as strings or numbers depending on the field.
  String anyId(String key) {
    final v = map[key];
    if (v is String && v.isNotEmpty) return v;
    if (v is num) return v.toString();
    _fail(key, 'id');
  }
}

class _L {
  _L(this.values, this.path);

  final List<Object?> values;
  final String path;

  Iterable<_J> objects() sync* {
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v is! Map<String, Object?>) {
        throw SourceFormatChanged('Expected object', path: '$path[$i]');
      }
      yield _J(v, '$path[$i]');
    }
  }
}
