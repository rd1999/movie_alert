import 'package:showtime_core/showtime_core.dart';

/// Time-of-day buckets for filtering (FR-8). Late-night shows (00:00–05:00)
/// count as night.
enum DayPart {
  morning('Morning', 'before 12'),
  afternoon('Afternoon', '12–17'),
  evening('Evening', '17–21'),
  night('Night', 'after 21');

  const DayPart(this.label, this.range);

  final String label;
  final String range;

  static DayPart of(DateTime t) => switch (t.hour) {
    < 5 => night,
    < 12 => morning,
    < 17 => afternoon,
    < 21 => evening,
    _ => night,
  };
}

/// Showtimes filter: hall features (2D/3D, screen, sound, seating…), listed
/// format, chain, time of day, max price, hide sold out. Empty sets mean
/// "any". Hall features combine as OR within a group and AND across groups
/// ("Dolby Atmos or 7.1" and "Recliners").
class ShowFilter {
  const ShowFilter({
    this.features = const {},
    this.formats = const {},
    this.chains = const {},
    this.dayParts = const {},
    this.maxPrice,
    this.hideSoldOut = false,
  });

  final Set<HallFeature> features;
  final Set<String> formats;
  final Set<String> chains;
  final Set<DayPart> dayParts;

  /// Cheapest seat class must cost at most this.
  final num? maxPrice;
  final bool hideSoldOut;

  int get activeCount =>
      features.map((f) => f.group).toSet().length +
      (formats.isEmpty ? 0 : 1) +
      (chains.isEmpty ? 0 : 1) +
      (dayParts.isEmpty ? 0 : 1) +
      (maxPrice == null ? 0 : 1) +
      (hideSoldOut ? 1 : 0);

  bool get isEmpty => activeCount == 0;

  ShowFilter copyWith({
    Set<HallFeature>? features,
    Set<String>? formats,
    Set<String>? chains,
    Set<DayPart>? dayParts,
    num? maxPrice,
    bool clearMaxPrice = false,
    bool? hideSoldOut,
  }) => ShowFilter(
    features: features ?? this.features,
    formats: formats ?? this.formats,
    chains: chains ?? this.chains,
    dayParts: dayParts ?? this.dayParts,
    maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
    hideSoldOut: hideSoldOut ?? this.hideSoldOut,
  );

  /// Chain name for a cinema: the source's chain key, else the first word
  /// of the name ("PVR Mani Square…" -> "PVR").
  static String chainOf(Cinema c) {
    final chain = c.chain?.trim();
    if (chain != null && chain.isNotEmpty) return chain;
    final first = c.name.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'Other' : first;
  }

  static num? cheapest(Show s) => s.seatClasses.isEmpty
      ? null
      : s.seatClasses.map((a) => a.price).reduce((a, b) => a < b ? a : b);

  bool matches(Cinema c, Show s) {
    if (chains.isNotEmpty && !chains.contains(chainOf(c))) return false;
    if (formats.isNotEmpty && !formats.contains(s.screenFormat)) return false;
    if (features.isNotEmpty) {
      final has = HallFeatures.of(s).toSet();
      final groups = {for (final f in features) f.group};
      for (final g in groups) {
        if (!features.any((f) => f.group == g && has.contains(f))) {
          return false;
        }
      }
    }
    if (dayParts.isNotEmpty && !dayParts.contains(DayPart.of(s.showTime))) {
      return false;
    }
    if (hideSoldOut && s.availability == SeatAvailability.soldOut) return false;
    final max = maxPrice;
    final price = cheapest(s);
    if (max != null && price != null && price > max) return false;
    return true;
  }

  List<CinemaShows> apply(List<CinemaShows> cinemas) {
    if (isEmpty) return cinemas;
    return [
      for (final cs in cinemas)
        if ([
              for (final s in cs.shows)
                if (matches(cs.cinema, s)) s,
            ]
            case final shows when shows.isNotEmpty)
          CinemaShows(cinema: cs.cinema, shows: shows),
    ];
  }
}
