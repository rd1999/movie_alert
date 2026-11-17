import 'dart:convert';

/// Builds a fake district.in movie page with the same `__NEXT_DATA__` shape
/// as the real one (verified 17 Nov 2026), but invented cinemas and numbers.
/// Real pages are not committed to this public repo (spec §5).
String syntheticMoviePage({
  String fmtQuery = 'mm5dpqtqjz',
  String dateQuery = '',
  List<String> sessionDates = const [
    '2026-12-17',
    '2026-12-18',
    '2026-12-19',
    '2026-12-20',
  ],
  List<Map<String, Object?>>? arranged,
  Map<String, Object?>? extraSessionEntries,
  Map<String, Object?> Function(Map<String, Object?> nextData)? mutate,
}) {
  final entry = {
    'serverTime': 1794909272,
    'meta': <String, Object?>{},
    'pageData': {'nearbyCinemas': <Object?>[], 'farCinemas': <Object?>[]},
    'entityCode': 'mm5dpqtqjz',
    'searchDate': '',
    'arrangedSessions': arranged ?? defaultArranged(),
    'farCinemasCount': 0,
    'nearbyCinemasCount': 2,
    'data': {'sessionDates': sessionDates},
  };
  var nextData = <String, Object?>{
    'props': {
      'pageProps': {
        'type': 'movie',
        'data': {
          'serverState': {
            'movieContents': {
              '176735': {
                'languageFormatGroups': [
                  {
                    'language': 'English',
                    'format': 'Mm5dpqTqJz',
                    'number_of_sessions': 4,
                    'lang': 'English',
                    'fmtGrpId': 'Mm5dpqTqJz',
                  },
                  {
                    'language': 'Hindi',
                    'format': 'zdwDdFFDqQ',
                    'number_of_sessions': 1,
                    'lang': 'Hindi',
                    'fmtGrpId': 'zdwDdFFDqQ',
                  },
                ],
                'isReleased': true,
                'censor': 'TBA',
                'contentId': 176735,
                'name': 'Test Movie: Doomsday',
                'duration': 165,
                'primary_language': 'English',
              },
            },
            'movieSessions': {
              '$fmtQuery$dateQuery': entry,
              ...?extraSessionEntries,
            },
            'queryState': {'frmtid': fmtQuery, 'fromdate': dateQuery},
          },
        },
      },
    },
    'page': '/[slug]',
  };
  if (mutate != null) nextData = mutate(nextData);
  return '<!DOCTYPE html><html><head><title>t</title></head><body>'
      '<div id="__next"></div>'
      '<script id="__NEXT_DATA__" type="application/json">'
      '${jsonEncode(nextData)}</script></body></html>';
}

Map<String, Object?> cinema(
  int id,
  String name,
  List<Map<String, Object?>> sessions,
) => {
  'data': {
    'id': id,
    'name': name,
    'address': '1 Test Road',
    'pincode': '700001',
    'latitude': 22.5,
    'longitude': 88.3,
    'cityKey': 'kolkata',
    'chainKey': 'TestChain',
    'isMerchantCancellable': 1,
    'distanceFromUser': 2.25,
    'amenities': ['1'],
  },
  'entityCode': id,
  'entityName': name,
  'sessions': sessions,
  'entityUrl': '/test-cinema-c/$id',
};

Map<String, Object?> session({
  required String sid,
  required int cid,
  required String showTime,
  String scrnFmt = 'MS INFINITY VISION 3D',
  String? premiumLabel = 'DOLBY 7.1',
  int avail = 242,
  int total = 252,
  String statusColor = 'G',
  String seatStatus = 'Available',
}) => {
  'sid': sid,
  'pid': 1,
  'cid': cid,
  'mid': 'TESTMV',
  'showTime': showTime,
  'areas': [
    {
      'label': 'PREMIUM',
      'sAvail': 137,
      'sTotal': 143,
      'price': 540,
      'statusColor': 'G',
      'seatStatus': 'Available',
    },
    {
      'label': 'RECLINER',
      'sAvail': 0,
      'sTotal': 18,
      'price': 1100.5,
      'statusColor': 'D',
      'seatStatus': 'Sold Out',
    },
  ],
  'total': total,
  'avail': avail,
  'audi': 'AUDI04',
  'premiumLabel': premiumLabel,
  'maxTkt': 10,
  'scrnFmt': scrnFmt,
  'statusColor': statusColor,
  'tags': ['price_500_600', 'ms_infinity_vision_3d'],
  'seatStatus': seatStatus,
};

List<Map<String, Object?>> defaultArranged() => [
  cinema(148, 'Test Cinema One, Kolkata', [
    session(sid: '7868', cid: 148, showTime: '2026-12-17T10:15'),
    session(
      sid: '7869',
      cid: 148,
      showTime: '2026-12-18T01:00',
      statusColor: 'Y',
      seatStatus: 'Filling Fast',
      premiumLabel: '',
    ),
  ]),
  cinema(2001, 'Test Cinema Two, Kolkata', [
    session(
      sid: '501',
      cid: 2001,
      showTime: '2026-12-17T21:30',
      scrnFmt: 'PXL 3D',
      premiumLabel: 'DOLBY ATMOS',
      avail: 5,
      statusColor: 'R',
      seatStatus: 'Almost Full',
    ),
    session(
      sid: '502',
      cid: 2001,
      showTime: '2026-12-17T23:59',
      avail: 0,
      statusColor: 'D',
      seatStatus: 'Sold Out',
    ),
  ]),
];
