/// Tiny date/time formatting helpers (no intl dependency needed yet).
abstract final class Fmt {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `2026-12-20` -> `Sun 20 Dec`.
  static String listingDate(String ymd) {
    final d = DateTime.tryParse(ymd);
    if (d == null) return ymd;
    return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  }

  /// `2026-12-20` -> (`Sun`, `20 Dec`) for two-line date chips.
  static (String, String) dateChip(String ymd) {
    final d = DateTime.tryParse(ymd);
    if (d == null) return (ymd, '');
    return (_days[d.weekday - 1], '${d.day} ${_months[d.month - 1]}');
  }

  static String day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// 24 h clock, e.g. `01:00`.
  static String time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// "just now", "5 min ago", "2 h ago", or a date.
  static String ago(DateTime t, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return day(t);
  }

  /// `1100` -> `₹1,100`, `150000` -> `₹1,50,000` (Indian grouping),
  /// `540.5` -> `₹540.50`.
  static String price(num p) => '₹${_amount(p)}';

  /// Price range across seat classes: `₹540–620`, or `₹540` when every
  /// class costs the same; null when there are no prices.
  static String? priceRange(Iterable<num> prices) {
    if (prices.isEmpty) return null;
    var lo = prices.first, hi = prices.first;
    for (final p in prices) {
      if (p < lo) lo = p;
      if (p > hi) hi = p;
    }
    return lo == hi ? price(lo) : '₹${_amount(lo)}–${_amount(hi)}';
  }

  static String _amount(num p) {
    final whole = p.truncate();
    final fraction = p == whole
        ? ''
        : (p - whole).toStringAsFixed(2).substring(1);
    final digits = whole.abs().toString();
    String grouped;
    if (digits.length <= 3) {
      grouped = digits;
    } else {
      final last3 = digits.substring(digits.length - 3);
      var rest = digits.substring(0, digits.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      grouped = '${parts.join(',')},$last3';
    }
    return '${whole < 0 ? '-' : ''}$grouped$fraction';
  }
}
