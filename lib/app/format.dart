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

  static String price(num p) =>
      p == p.roundToDouble() ? '₹${p.toInt()}' : '₹${p.toStringAsFixed(2)}';
}
