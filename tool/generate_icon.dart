// Generates ShowWatch's app icon (a cinema ticket with an alert bell) from
// vector shapes, with no image libraries: signed distance fields for crisp
// anti-aliased edges, and a tiny PNG encoder.
//
//   dart run tool/generate_icon.dart
//   dart run flutter_launcher_icons
//
// Outputs:
//   assets/icon/icon.png             1024² full icon (iOS, legacy Android)
//   assets/icon/icon_foreground.png  1024² adaptive-icon foreground layer
//   assets/icon/icon_monochrome.png  1024² Android 13+ themed icon
//   android/.../drawable-*/ic_stat_showwatch.png  white status-bar icon
//
// Neutral branding on purpose: no ticketing-platform or cinema-chain colours
// or marks (spec §5).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// Palette (matches the app theme seed 0xFF3F51B5).
const _bgTop = (0x5C, 0x6B, 0xC0); // indigo 400
const _bgBottom = (0x28, 0x35, 0x93); // indigo 800
const _white = (0xFF, 0xFF, 0xFF);
const _amber = (0xFF, 0xC1, 0x07);

typedef Vec = ({double x, double y});

double _len(double x, double y) => math.sqrt(x * x + y * y);

double _circle(Vec p, double cx, double cy, double r) =>
    _len(p.x - cx, p.y - cy) - r;

double _box(Vec p, double cx, double cy, double hw, double hh, double r) {
  final qx = (p.x - cx).abs() - hw + r;
  final qy = (p.y - cy).abs() - hh + r;
  return _len(math.max(qx, 0), math.max(qy, 0)) +
      math.min(math.max(qx, qy), 0) -
      r;
}

/// Signed distance to a polygon (Inigo Quilez's sdPolygon).
double _polygon(Vec p, List<Vec> v) {
  var d = double.infinity;
  var s = 1.0;
  for (var i = 0, j = v.length - 1; i < v.length; j = i, i++) {
    final ex = v[j].x - v[i].x, ey = v[j].y - v[i].y;
    final wx = p.x - v[i].x, wy = p.y - v[i].y;
    final t = ((wx * ex + wy * ey) / (ex * ex + ey * ey)).clamp(0.0, 1.0);
    final bx = wx - ex * t, by = wy - ey * t;
    d = math.min(d, bx * bx + by * by);
    final c1 = p.y >= v[i].y, c2 = p.y < v[j].y, c3 = ex * wy > ey * wx;
    if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
  }
  return s * math.sqrt(d);
}

/// Symbol space: centred at 0,0, about ±360 wide, tilted 10°.
const _tilt = -10 * math.pi / 180;

Vec _toSymbol(double x, double y) {
  final c = math.cos(-_tilt), s = math.sin(-_tilt);
  return (x: x * c - y * s, y: x * s + y * c);
}

double _bell(Vec p) {
  // Scaled-down bell centred in the ticket.
  const k = 0.78;
  final q = (x: p.x / k, y: p.y / k - 6);
  // Sides start where they touch the dome at a tangent, so the outline
  // flows from dome to flare without a corner.
  final body = _polygon(q, const [
    (x: -94.1, y: -63.8),
    (x: 94.1, y: -63.8),
    (x: 150.0, y: 92.0),
    (x: -150.0, y: 92.0),
  ]);
  final dome = _circle(q, 0, -30, 100);
  final rim = _box(q, 0, 108, 178, 24, 20);
  final clapper = _circle(q, 0, 160, 38);
  final knob = _circle(q, 0, -146, 26);
  final d = [body, dome, rim, clapper, knob].reduce(math.min);
  return d * k;
}

class _Layers {
  _Layers(this.ticket, this.dot);

  /// Coverage 0..1 of the white ticket (with the bell cut out) and the
  /// amber dot.
  final double ticket;
  final double dot;
}

/// [aa] is the width of one pixel in symbol units.
_Layers _symbol(Vec p, double aa) {
  double cover(double d) => (0.5 - d / aa).clamp(0.0, 1.0);

  final ticketShape = math.max(
    _box(p, 0, 0, 330, 225, 52),
    -math.min(_circle(p, -330, 0, 58), _circle(p, 330, 0, 58)),
  );
  const dotX = 285.0, dotY = -190.0;
  final ring = _circle(p, dotX, dotY, 104);
  final dot = _circle(p, dotX, dotY, 74);
  final ticket = math.max(math.max(ticketShape, -_bell(p)), -ring);
  return _Layers(cover(ticket), cover(dot));
}

/// Renders a size×size RGBA image. [scale] maps symbol units to pixels.
Uint8List _render(
  int size, {
  required double scale,
  required bool background,
  required bool mono,
  double offsetY = 0,
}) {
  final out = Uint8List(size * size * 4);
  final aa = 1 / scale;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final sx = (x + 0.5 - size / 2) / scale;
      final sy = (y + 0.5 - size / 2) / scale - offsetY;
      final l = _symbol(_toSymbol(sx, sy), aa);

      double r = 0, g = 0, b = 0, a = 0;
      if (background) {
        final t = ((x + y) / (2 * size)).clamp(0.0, 1.0);
        r = _bgTop.$1 + (_bgBottom.$1 - _bgTop.$1) * t;
        g = _bgTop.$2 + (_bgBottom.$2 - _bgTop.$2) * t;
        b = _bgTop.$3 + (_bgBottom.$3 - _bgTop.$3) * t;
        a = 1;
      }
      void over((int, int, int) c, double cov) {
        if (cov <= 0) return;
        final na = cov + a * (1 - cov);
        r = (c.$1 * cov + r * a * (1 - cov)) / na;
        g = (c.$2 * cov + g * a * (1 - cov)) / na;
        b = (c.$3 * cov + b * a * (1 - cov)) / na;
        a = na;
      }

      over(_white, l.ticket);
      over(mono ? _white : _amber, l.dot);
      final i = (y * size + x) * 4;
      out[i] = r.round().clamp(0, 255);
      out[i + 1] = g.round().clamp(0, 255);
      out[i + 2] = b.round().clamp(0, 255);
      out[i + 3] = (a * 255).round().clamp(0, 255);
    }
  }
  return out;
}

// ---- Minimal PNG encoder (RGBA, 8-bit, no filtering) ----

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final len = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc(body));
  return [...len.buffer.asUint8List(), ...body, ...crc.buffer.asUint8List()];
}

List<int> _png(int size, Uint8List rgba) {
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6); // RGBA
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // filter: none
    raw.add(Uint8List.sublistView(rgba, y * size * 4, (y + 1) * size * 4));
  }
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    ..._chunk('IHDR', header.buffer.asUint8List()),
    ..._chunk('IDAT', ZLibEncoder(level: 9).convert(raw.takeBytes())),
    ..._chunk('IEND', const []),
  ];
}

void _write(String path, int size, Uint8List rgba) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(_png(size, rgba));
  stdout.writeln('wrote $path');
}

void main() {
  // Full icon: symbol ~70% of the canvas.
  _write(
    'assets/icon/icon.png',
    1024,
    _render(1024, scale: 1.0, background: true, mono: false, offsetY: 6),
  );
  // Adaptive foreground: flutter_launcher_icons insets this layer by 16%
  // per side, so the image already maps to the visible area; keep a little
  // margin for circular masks.
  _write(
    'assets/icon/icon_foreground.png',
    1024,
    _render(1024, scale: 0.9, background: false, mono: false),
  );
  _write(
    'assets/icon/icon_monochrome.png',
    1024,
    _render(1024, scale: 0.9, background: false, mono: true),
  );
  // Status-bar icon: white silhouette on transparent, 24dp with ~2dp padding.
  const densities = {
    'mdpi': 24,
    'hdpi': 36,
    'xhdpi': 48,
    'xxhdpi': 72,
    'xxxhdpi': 96,
  };
  for (final MapEntry(key: dpi, value: px) in densities.entries) {
    _write(
      'android/app/src/main/res/drawable-$dpi/ic_stat_showwatch.png',
      px,
      _render(px, scale: px / 920, background: false, mono: true),
    );
  }
}
