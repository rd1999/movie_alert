import 'dart:io';

import 'package:showtime_core/io.dart';
import 'package:test/test.dart';

/// Local loopback server only — never the real site.
void main() {
  late HttpServer server;
  late List<(DateTime, String, String?)> hits;
  late List<int> statuses;

  setUp(() async {
    hits = [];
    statuses = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      hits.add((
        DateTime.now(),
        req.uri.path,
        req.headers.value(HttpHeaders.userAgentHeader),
      ));
      final status = statuses.isEmpty ? 200 : statuses.removeAt(0);
      req.response.statusCode = status;
      req.response.write('body ${req.uri.path}');
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  PoliteFetcher fetcher({Duration gap = const Duration(milliseconds: 150)}) =>
      PoliteFetcher(minGap: gap, backoffBase: const Duration(milliseconds: 20));

  test('returns the body and sends a desktop User-Agent', () async {
    final f = fetcher();
    expect(await f.get(url('/a')), 'body /a');
    expect(hits.single.$3, PoliteFetcher.defaultUserAgent);
    f.close();
  });

  test('requests run one at a time with a minimum gap', () async {
    final f = fetcher();
    final bodies = await Future.wait([
      f.get(url('/1')),
      f.get(url('/2')),
      f.get(url('/3')),
    ]);
    expect(bodies, ['body /1', 'body /2', 'body /3']);
    expect(hits.map((h) => h.$2), ['/1', '/2', '/3']);
    for (var i = 1; i < hits.length; i++) {
      expect(
        hits[i].$1.difference(hits[i - 1].$1).inMilliseconds,
        greaterThanOrEqualTo(140),
      );
    }
    f.close();
  });

  test('retries 429/5xx with backoff, then succeeds', () async {
    statuses = [429, 503];
    final f = fetcher(gap: Duration.zero);
    expect(await f.get(url('/r')), 'body /r');
    expect(hits, hasLength(3));
    f.close();
  });

  test('gives up after maxAttempts and does not retry 404', () async {
    statuses = [500, 500, 500];
    final f = fetcher(gap: Duration.zero);
    await expectLater(
      f.get(url('/x')),
      throwsA(
        isA<HttpStatusException>().having((e) => e.statusCode, 'status', 500),
      ),
    );
    expect(hits, hasLength(3));

    statuses = [404];
    await expectLater(f.get(url('/y')), throwsA(isA<HttpStatusException>()));
    expect(hits, hasLength(4));

    // A failure doesn't jam the queue.
    expect(await f.get(url('/z')), 'body /z');
    f.close();
  });
}
