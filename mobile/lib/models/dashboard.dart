import '../core/format.dart';

/// A booking waiting for the front desk to be paid.
class PendingItem {
  final int id;
  final String code;
  final String guest;
  final String roomNumber;
  final DateTime checkIn;
  final DateTime checkOut;
  final double amountDue;

  const PendingItem({
    required this.id,
    required this.code,
    required this.guest,
    required this.roomNumber,
    required this.checkIn,
    required this.checkOut,
    required this.amountDue,
  });

  factory PendingItem.fromJson(Map<String, dynamic> j) => PendingItem(
        id: j['id'] as int,
        code: j['code'] as String,
        guest: (j['guest'] ?? '') as String,
        roomNumber: (j['room_number'] ?? '') as String,
        checkIn: parseDate(j['check_in_date'] as String),
        checkOut: parseDate(j['check_out_date'] as String),
        amountDue: (j['amount_due'] as num).toDouble(),
      );
}

/// One day of the 7-day chart.
class DayStat {
  final DateTime date;
  final int bookings;
  final double money;
  const DayStat({required this.date, required this.bookings, required this.money});

  factory DayStat.fromJson(Map<String, dynamic> j) => DayStat(
        date: parseDate(j['date'] as String),
        bookings: j['bookings'] as int,
        money: (j['money'] as num).toDouble(),
      );
}

/// The numbers on the admin dashboard, all counted by the server.
class Dashboard {
  final int checkIns;
  final int checkedInSoFar;
  final int checkOuts;
  final int checkedOutSoFar;
  final int roomsTotal;
  final int roomsOccupied;
  final int roomsFree;
  final int roomsMaintenance;
  final double moneyToday;
  final double moneyMonth;
  final double moneyMonthOnline;
  final double moneyMonthHotel;
  final double moneyMonthRefunded;
  final int pendingCount;
  final List<PendingItem> pending;
  final List<DayStat> days;

  const Dashboard({
    required this.checkIns,
    required this.checkedInSoFar,
    required this.checkOuts,
    required this.checkedOutSoFar,
    required this.roomsTotal,
    required this.roomsOccupied,
    required this.roomsFree,
    required this.roomsMaintenance,
    required this.moneyToday,
    required this.moneyMonth,
    required this.moneyMonthOnline,
    required this.moneyMonthHotel,
    required this.moneyMonthRefunded,
    required this.pendingCount,
    required this.pending,
    required this.days,
  });

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final today = j['today'] as Map<String, dynamic>;
    final rooms = j['rooms'] as Map<String, dynamic>;
    final money = j['money'] as Map<String, dynamic>;
    final pending = j['pending'] as Map<String, dynamic>;
    double m(String k) => (money[k] as num).toDouble();

    return Dashboard(
      checkIns: today['check_ins'] as int,
      checkedInSoFar: today['checked_in_so_far'] as int,
      checkOuts: today['check_outs'] as int,
      checkedOutSoFar: today['checked_out_so_far'] as int,
      roomsTotal: rooms['total'] as int,
      roomsOccupied: rooms['occupied'] as int,
      roomsFree: rooms['free'] as int,
      roomsMaintenance: rooms['maintenance'] as int,
      moneyToday: m('today'),
      moneyMonth: m('month'),
      moneyMonthOnline: m('month_online'),
      moneyMonthHotel: m('month_hotel'),
      moneyMonthRefunded: m('month_refunded'),
      pendingCount: pending['count'] as int,
      pending: (pending['items'] as List)
          .map((e) => PendingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      days: (j['last_7_days'] as List)
          .map((e) => DayStat.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
