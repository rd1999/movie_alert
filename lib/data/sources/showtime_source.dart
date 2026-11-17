import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../core/http/polite_http_client.dart';

export 'package:showtime_core/showtime_core.dart' show ShowtimeSource;

/// The active showtime source. District for now; swap the adapter here to
/// use another source (spec §5, §7).
final showtimeSourceProvider = Provider<ShowtimeSource>(
  (ref) => DistrictSource(ref.watch(politeFetcherProvider).get),
);
