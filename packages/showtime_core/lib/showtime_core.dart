/// Pure-Dart core for ShowWatch: domain models, source parsers and the
/// alert engine. No Flutter imports allowed (spec §7).
library;

export 'src/alerts/alert.dart';
export 'src/alerts/alert_engine.dart';
export 'src/alerts/movie_checker.dart';
export 'src/alerts/snapshot.dart';
export 'src/district/district_parser.dart';
export 'src/district/district_source.dart';
export 'src/district/district_urls.dart';
export 'src/errors.dart';
export 'src/model_json.dart';
export 'src/models.dart';
export 'src/sources/showtime_source.dart';
