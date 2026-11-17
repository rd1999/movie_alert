import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/io.dart';

/// One shared polite fetcher for the whole app: requests are queued one at a
/// time with >= 1 s between them, gzip, 30 s timeout, backoff on 429/5xx
/// (spec §6.5, NFR-1).
final politeFetcherProvider = Provider<PoliteFetcher>((ref) {
  final fetcher = PoliteFetcher();
  ref.onDispose(fetcher.close);
  return fetcher;
});
