import 'dart:convert';

/// Fake EDS-style page (city movies / cinemas), same shape as district.in on
/// 17 Nov 2026 but invented content.
String syntheticEdsPage(List<List<Map<String, Object?>>> rails) {
  final next = {
    'props': {
      'pageProps': {
        'data': {
          'serverState': {
            'EDSResponse': {
              'rails': [
                for (final items in rails)
                  {'rail_id': 'r', 'snippet_type': 'x', 'items': items},
              ],
            },
          },
        },
      },
    },
  };
  return '<html><body><script id="__NEXT_DATA__" type="application/json">'
      '${jsonEncode(next)}</script></body></html>';
}

Map<String, Object?> movieItem(
  int id,
  String name,
  String slug, {
  String? webUrl,
  List<Map<String, String>> variants = const [
    {'language': 'English', 'format': '3D'},
    {'language': 'Hindi', 'format': '3D'},
    {'language': 'English', 'format': 'IMAX 3D'},
  ],
}) => {
  'entity_id': '$id',
  'entity_type': 'movie',
  'ItemDetails': {
    'MovieData': {
      'movie_id': '$id',
      'name': name,
      'genres': ['Action'],
      'Duration': 165,
      'image': 'https://example.invalid/$id.jpg',
      'movie_variants': variants,
      'censor': 'UA13+',
      'release_date': '1797465600', // 2026-12-17 UTC
      'web_url':
          webUrl ?? 'https://www.district.in/movies/$slug-movie-tickets-MV$id',
    },
  },
};

Map<String, Object?> quickLink(String id) => {
  'entity_id': id,
  'entity_type': 'ql',
  'ItemDetails': {
    'EditorialData': {'id': id},
  },
};

Map<String, Object?> cinemaItem(int id, String name, {bool? cancellable}) => {
  'entity_id': '$id',
  'entity_type': 'cinema',
  'ItemDetails': {
    'CinemaData': {
      'cinema_id': '$id',
      'cinema_name': name,
      'distance': 2.4199,
      'address': '1 Test Road',
      'lat': 22.5,
      'lon': 88.3,
      'cancellable': ?cancellable,
    },
  },
  'children': [
    {
      'ItemDetails': {
        'MovieData': {'movie_id': '1', 'name': 'Child movie'},
      },
    },
  ],
};

const syntheticSitemap = '''<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
<url><loc>https://www.district.in/movies/kolkata-movie-tickets</loc><lastmod>2026-11-16</lastmod></url>
<url><loc>https://www.district.in/movies/navi-mumbai-movie-tickets</loc></url>
<url><loc>https://www.district.in/movies/agra-movie-tickets</loc></url>
<url><loc>https://www.district.in/movies/kolkata-movie-tickets</loc></url>
<url><loc>https://www.district.in/events/not-a-city</loc></url>
</urlset>''';
