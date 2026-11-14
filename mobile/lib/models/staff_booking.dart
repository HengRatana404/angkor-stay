import '../core/format.dart';

class Person {
  final int id;
  final String name;
  const Person(this.id, this.name);

  static Person? from(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return Person(json['id'] as int, json['name'] as String);
  }
}

class GuestInfo {
  final int id;
  final String name;
  final String? phone;
  final String email;
  const GuestInfo({required this.id, required this.name, required this.phone, required this.email});
}

class StaffPayment {
  final int id;
  final double amount;
  final String method; // khqr | cash | card | online
  final String status; // paid | refunded
  final Person? receivedBy;
  final DateTime? paidAt;

  const StaffPayment({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    required this.receivedBy,
    required this.paidAt,
  });

  factory StaffPayment.fromJson(Map<String, dynamic> json) => StaffPayment(
        id: json['id'] as int,
        amount: (json['amount'] as num).toDouble(),
        method: json['method'] as String,
        status: json['status'] as String,
        receivedBy: Person.from(json['received_by']),
        paidAt: json['paid_at'] == null ? null : DateTime.parse(json['paid_at'] as String),
      );
}

/// What staff may do with a booking right now. The server decides.
class BookingActions {
  final bool canTakePayment;
  final bool canCheckIn;
  final String? checkInProblem;
  final bool canCheckOut;

  const BookingActions({
    required this.canTakePayment,
    required this.canCheckIn,
    required this.checkInProblem,
    required this.canCheckOut,
  });

  factory BookingActions.fromJson(Map<String, dynamic> json) => BookingActions(
        canTakePayment: json['can_take_payment'] as bool,
        canCheckIn: json['can_check_in'] as bool,
        checkInProblem: json['check_in_problem'] as String?,
        canCheckOut: json['can_check_out'] as bool,
      );
}

class StaffBooking {
  final int id;
  final String code;
  final String status;
  final String roomNumber;
  final String roomTypeName;
  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final int guestCount;
  final double pricePerNight;
  final double totalPrice;
  final String? paymentChoice;
  final bool paid;
  final int discountPercent;
  final double discountAmount;
  final int? holdSecondsLeft;
  final GuestInfo? guest;
  final List<StaffPayment> payments;
  final DateTime? checkedInAt;
  final Person? checkedInBy;
  final DateTime? checkedOutAt;
  final Person? checkedOutBy;
  final BookingActions actions;

  const StaffBooking({
    required this.id,
    required this.code,
    required this.status,
    required this.roomNumber,
    required this.roomTypeName,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.guestCount,
    required this.pricePerNight,
    required this.totalPrice,
    required this.paymentChoice,
    required this.paid,
    required this.holdSecondsLeft,
    required this.guest,
    required this.payments,
    required this.checkedInAt,
    required this.checkedInBy,
    required this.checkedOutAt,
    required this.checkedOutBy,
    required this.actions,
    this.discountPercent = 0,
    this.discountAmount = 0,
  });

  factory StaffBooking.fromJson(Map<String, dynamic> json) {
    final guest = json['guest'] as Map<String, dynamic>?;
    final type = json['room_type'] as Map<String, dynamic>?;

    return StaffBooking(
      id: json['id'] as int,
      code: json['code'] as String,
      status: json['status'] as String,
      roomNumber: (json['room_number'] ?? '') as String,
      roomTypeName: (type?['name'] ?? '') as String,
      checkIn: parseDate(json['check_in_date'] as String),
      checkOut: parseDate(json['check_out_date'] as String),
      nights: json['nights'] as int,
      guestCount: json['guests'] as int,
      pricePerNight: (json['price_per_night'] as num).toDouble(),
      totalPrice: (json['total_price'] as num).toDouble(),
      paymentChoice: json['payment_choice'] as String?,
      paid: json['paid'] as bool,
      discountPercent: (json['discount_percent'] as num?)?.toInt() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      holdSecondsLeft: json['hold_seconds_left'] as int?,
      guest: guest == null
          ? null
          : GuestInfo(
              id: guest['id'] as int,
              name: guest['name'] as String,
              phone: guest['phone'] as String?,
              email: guest['email'] as String,
            ),
      payments: ((json['payments'] as List?) ?? const [])
          .map((p) => StaffPayment.fromJson(p as Map<String, dynamic>))
          .toList(),
      checkedInAt: json['checked_in_at'] == null ? null : DateTime.parse(json['checked_in_at'] as String),
      checkedInBy: Person.from(json['checked_in_by']),
      checkedOutAt: json['checked_out_at'] == null ? null : DateTime.parse(json['checked_out_at'] as String),
      checkedOutBy: Person.from(json['checked_out_by']),
      actions: BookingActions.fromJson(json['actions'] as Map<String, dynamic>),
    );
  }

  String get guestName => guest?.name ?? 'Unknown guest';

  /// The guest has begun paying online but has not finished.
  bool get isPayingOnline => status == 'pending' && paymentChoice == 'online' && !paid;
}
