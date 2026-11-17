import 'models.dart';

enum HallFeatureGroup {
  dimension('2D / 3D'),
  screen('Screen'),
  sound('Sound'),
  seating('Seating'),
  hall('Premium hall'),
  access('Access'),
  other('Other labels');

  const HallFeatureGroup(this.label);

  final String label;
}

/// A recognisable hall/show property, derived from what the listing already
/// says about a show: screen format, premium label, tags and seat-class
/// names. Detection is by keyword, so it works across chains without
/// knowing every brand.
class HallFeature {
  const HallFeature(this.id, this.label, this.group, [this.pattern]);

  final String id;
  final String label;
  final HallFeatureGroup group;

  /// Matched against the show's upper-cased description; null for features
  /// computed specially (2D) or raw labels.
  final RegExp? pattern;

  @override
  bool operator ==(Object other) => other is HallFeature && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => label;
}

abstract final class HallFeatures {
  static RegExp _w(String p) => RegExp('(?<![A-Z0-9])(?:$p)(?![A-Z0-9])');

  static final threeD = HallFeature(
    '3d',
    '3D',
    HallFeatureGroup.dimension,
    _w('3D'),
  );
  static const twoD = HallFeature('2d', '2D', HallFeatureGroup.dimension);

  /// Known features, in display order. Only ones present on a page are
  /// offered as filters.
  static final known = <HallFeature>[
    threeD,
    twoD,
    // Screen / projection
    HallFeature('imax', 'IMAX', HallFeatureGroup.screen, _w('IMAX')),
    HallFeature('4dx', '4DX', HallFeatureGroup.screen, _w('4DX')),
    HallFeature('mx4d', 'MX4D', HallFeatureGroup.screen, _w('MX4D')),
    HallFeature(
      'screenx',
      'ScreenX',
      HallFeatureGroup.screen,
      _w(r'SCREEN ?X'),
    ),
    HallFeature('pxl', 'PXL', HallFeatureGroup.screen, _w(r'P\[?XL\]?')),
    HallFeature(
      'dolby-cinema',
      'Dolby Cinema',
      HallFeatureGroup.screen,
      _w('DOLBY CINEMA'),
    ),
    HallFeature(
      'infinity',
      'Infinity Vision',
      HallFeatureGroup.screen,
      _w('INFINITY VISION'),
    ),
    HallFeature('onyx', 'Onyx LED', HallFeatureGroup.screen, _w('ONYX')),
    HallFeature('ice', 'ICE', HallFeatureGroup.screen, _w('ICE')),
    HallFeature('epiq', 'EPIQ', HallFeatureGroup.screen, _w('EPIQ')),
    HallFeature('laser', 'Laser', HallFeatureGroup.screen, _w('LASER')),
    HallFeature('4k', '4K', HallFeatureGroup.screen, _w('4K')),
    // Sound
    HallFeature('atmos', 'Dolby Atmos', HallFeatureGroup.sound, _w('ATMOS')),
    HallFeature(
      'dolby-7-1',
      'Dolby 7.1',
      HallFeatureGroup.sound,
      _w(r'(?:DOLBY )?7\.1'),
    ),
    HallFeature(
      'dolby-5-1',
      'Dolby 5.1',
      HallFeatureGroup.sound,
      _w(r'(?:DOLBY )?5\.1'),
    ),
    HallFeature(
      'dtsx',
      'DTS:X',
      HallFeatureGroup.sound,
      _w(r'DTS(?:[: -]?X)?'),
    ),
    HallFeature(
      'auro',
      'Auro 3D',
      HallFeatureGroup.sound,
      _w(r'AURO(?: ?11\.1| ?3D)?'),
    ),
    HallFeature(
      'immersive',
      'Immersive sound',
      HallFeatureGroup.sound,
      _w('IMMERSIVE'),
    ),
    // Seating
    HallFeature(
      'recliner',
      'Recliners',
      HallFeatureGroup.seating,
      _w(r'RECLINERS?'),
    ),
    HallFeature('sofa', 'Sofas', HallFeatureGroup.seating, _w(r'SOFAS?')),
    HallFeature(
      'couple',
      'Couple seats',
      HallFeatureGroup.seating,
      _w(r'COUPLE(?: SEATS?)?'),
    ),
    HallFeature(
      'bed',
      'Beds / lounger',
      HallFeatureGroup.seating,
      _w(r'BEDS?|LOUNGERS?'),
    ),
    // Premium hall brands
    HallFeature('insignia', 'INSIGNIA', HallFeatureGroup.hall, _w('INSIGNIA')),
    HallFeature('gold', 'Gold', HallFeatureGroup.hall, _w('GOLD(?: CLASS)?')),
    HallFeature('luxe', 'LUXE', HallFeatureGroup.hall, _w('LUXE')),
    HallFeature(
      'directors-cut',
      "Director's Cut",
      HallFeatureGroup.hall,
      _w(r"DIRECTOR'?S CUT"),
    ),
    HallFeature(
      'signature',
      'Signature',
      HallFeatureGroup.hall,
      _w('SIGNATURE'),
    ),
    HallFeature(
      'playhouse',
      'Playhouse (kids)',
      HallFeatureGroup.hall,
      _w('PLAYHOUSE'),
    ),
    HallFeature('vip', 'VIP', HallFeatureGroup.hall, _w('VIP')),
    // Access
    HallFeature(
      'wheelchair',
      'Wheelchair friendly',
      HallFeatureGroup.access,
      _w('WHEELCHAIR FRIENDLY'),
    ),
  ];

  /// Everything the listing says about a show, upper-cased.
  static String describe(Show s) => [
    ?s.screenFormat,
    ?s.premiumLabel,
    for (final t in s.tags) t.replaceAll('_', ' '),
    for (final a in s.seatClasses) a.label,
  ].join(' | ').toUpperCase();

  /// Features of [s]. Premium labels that match nothing known are kept as
  /// raw "other" features so new brands still show up as filters.
  static List<HallFeature> of(Show s) {
    final text = describe(s);
    final out = <HallFeature>[
      for (final f in known)
        if (f.pattern?.hasMatch(text) ?? false) f,
    ];
    if (!out.contains(threeD) && !_w('4D|MX4D|4DX').hasMatch(text)) {
      out.add(twoD);
    }
    final label = s.premiumLabel?.trim().toUpperCase();
    if (label != null &&
        label.isNotEmpty &&
        !known.any((f) => f.pattern?.hasMatch(label) ?? false)) {
      out.add(HallFeature('label:$label', label, HallFeatureGroup.other));
    }
    return out;
  }
}
