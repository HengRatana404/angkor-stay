const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A calendar day without a time. Uses UTC so daylight saving can never
/// move a date by one day.
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime parseDate(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

/// "2026-11-05"
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "Thu 5 Nov"
String formatShortDate(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "$15" or "$12.50"
String formatMoney(double value) {
  final whole = value == value.roundToDouble();
  return '\$${value.toStringAsFixed(whole ? 0 : 2)}';
}

/// "Thu 5 Nov 14:05", in the phone's own time zone.
String formatDateTime(DateTime d) {
  final local = d.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '${formatShortDate(local)} $h:$m';
}

/// The words staff and guests see for a booking status.
String statusLabel(String status) => switch (status) {
      'pending' => 'Waiting for payment',
      'confirmed' => 'Confirmed',
      'checked_in' => 'Checked in',
      'checked_out' => 'Checked out',
      'cancelled' => 'Cancelled',
      'no_show' => 'No-show',
      _ => status,
    };

String methodLabel(String method) => switch (method) {
      'khqr' => 'KHQR',
      'cash' => 'Cash',
      'card' => 'Card',
      'online' => 'Online',
      _ => method,
    };

/// "1 night" or "3 nights"
String nightsText(int nights) => nights == 1 ? '1 night' : '$nights nights';

/// The online discount on a price, in whole cents so nothing drifts.
/// 30.00 at 15% -> discount 4.50, due 25.50.
({double discount, double due}) onlinePrice(double total, int percent) {
  final cents = (total * 100).round();
  final discountCents = (cents * percent / 100).round();
  return (discount: discountCents / 100, due: (cents - discountCents) / 100);
}

/// 275 seconds -> "4:35"
String formatCountdown(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Formats a luxury booking confirmation reference, e.g. "AS-2026-0006".
/// Keeps compatibility with existing raw IDs and strings.
String formatConfirmationCode(int id) {
  final padded = id.toString().padLeft(4, '0');
  return 'AS-2026-$padded';
}

/// "CONFIRMATION #AS-2026-0006"
String fullConfirmationLabel(int id) => 'CONFIRMATION #${formatConfirmationCode(id)}';

/// 'admin' becomes 'Admin'. Used for role labels (no all-caps tracked text).
String titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
