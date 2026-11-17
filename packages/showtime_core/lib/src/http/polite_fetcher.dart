import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Non-200 response after retries.
class HttpStatusException implements Exception {
  HttpStatusException(this.statusCode, this.uri);

  final int statusCode;
  final Uri uri;

  @override
  String toString() => 'HTTP $statusCode for $uri';
}

/// GETs pages politely (spec §6.5, NFR-1): realistic desktop User-Agent,
/// gzip (HttpClient default), 30 s timeout, requests strictly one at a time
/// with at least [minGap] between them, exponential backoff on 429/5xx.
class PoliteFetcher {
  PoliteFetcher({
    HttpClient? client,
    this.userAgent = defaultUserAgent,
    this.minGap = const Duration(seconds: 1),
    this.timeout = const Duration(seconds: 30),
    this.maxAttempts = 3,
    this.backoffBase = const Duration(seconds: 5),
  }) : _client = client ?? HttpClient() {
    _client.userAgent = userAgent;
  }

  static const defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';

  final HttpClient _client;
  final String userAgent;
  final Duration minGap;
  final Duration timeout;
  final int maxAttempts;
  final Duration backoffBase;

  Future<void> _tail = Future.value();
  DateTime? _lastRequest;

  /// Queues a GET behind any in-flight request and returns the body.
  Future<String> get(Uri url) {
    final result = _tail.then((_) => _getWithRetry(url));
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _getWithRetry(Uri url) async {
    for (var attempt = 1; ; attempt++) {
      await _respectGap();
      final (status, body) = await _once(url);
      if (status == 200) return body;
      final retryable = status == 429 || status >= 500;
      if (!retryable || attempt >= maxAttempts) {
        throw HttpStatusException(status, url);
      }
      await Future<void>.delayed(backoffBase * (1 << (attempt - 1)));
    }
  }

  Future<void> _respectGap() async {
    final last = _lastRequest;
    if (last != null) {
      final wait = minGap - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequest = DateTime.now();
  }

  Future<(int, String)> _once(Uri url) async {
    final req = await _client.getUrl(url).timeout(timeout);
    req.headers
      ..set(HttpHeaders.acceptHeader, 'text/html,application/xml;q=0.9')
      ..set(HttpHeaders.acceptLanguageHeader, 'en-IN,en;q=0.9');
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    return (res.statusCode, body);
  }

  void close() => _client.close(force: true);
}
