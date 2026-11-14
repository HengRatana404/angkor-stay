import '../core/format.dart';

class Booking {
  final int id;

  /// The short number the guest tells the front desk, such as AS-0012.
  final String code;
  final String status;
  final String roomNumber;
  final String roomTypeName;
  final String? coverImage;
  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final int guests;
  final double pricePerNight;
  final double totalPrice;

  /// The online discount saved on this booking (0 when not paying online).
  final int discountPercent;
  final double discountAmount;

  /// What the guest has to pay. Null on an old answer: then it is the total price.
  final double? amountDue;

  /// "hotel" or "online" once the guest chose how to pay, otherwise null.
  final String? paymentChoice;
  final bool paid;
  final String? paymentMethod;

  /// What the guest paid with, for example "Visa ending 4242" or "KHQR". Only for online payments.
  final String? paymentDetail;

  /// Money already given back (online payments cancelled by the guest).
  final double refundedAmount;

  /// May the guest cancel in the app? The server decides.
  final bool canCancel;

  /// Seconds the room is still held, counted by the server when this
  /// answer was made. Null when the booking is not a running hold.
  final int? holdSecondsLeft;

  const Booking({
    required this.id,
    required this.status,
    required this.roomNumber,
    required this.roomTypeName,
    required this.coverImage,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.guests,
    required this.pricePerNight,
    required this.totalPrice,
    required this.holdSecondsLeft,
    this.code = '',
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.amountDue,
    this.paymentChoice,
    this.paid = false,
    this.paymentMethod,
    this.paymentDetail,
    this.refundedAmount = 0,
    this.canCancel = false,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    final type = json['room_type'] as Map<String, dynamic>?;
    return Booking(
      id: json['id'] as int,
      code: (json['code'] ?? '') as String,
      status: json['status'] as String,
      roomNumber: (json['room_number'] ?? '') as String,
      roomTypeName: (type?['name'] ?? '') as String,
      coverImage: type?['cover_image'] as String?,
      checkIn: parseDate(json['check_in_date'] as String),
      checkOut: parseDate(json['check_out_date'] as String),
      nights: json['nights'] as int,
      guests: json['guests'] as int,
      pricePerNight: (json['price_per_night'] as num).toDouble(),
      totalPrice: (json['total_price'] as num).toDouble(),
      discountPercent: (json['discount_percent'] as num?)?.toInt() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      amountDue: (json['amount_due'] as num?)?.toDouble(),
      paymentChoice: json['payment_choice'] as String?,
      paid: (json['paid'] ?? false) as bool,
      paymentMethod: json['payment_method'] as String?,
      paymentDetail: json['payment_detail'] as String?,
      refundedAmount: (json['refunded_amount'] as num?)?.toDouble() ?? 0,
      canCancel: (json['can_cancel'] ?? false) as bool,
      holdSecondsLeft: json['hold_seconds_left'] as int?,
    );
  }

  /// What the guest has to pay now.
  double get toPay => amountDue ?? totalPrice;

  bool get hasDiscount => discountAmount > 0;

  /// Paid and confirmed.
  bool get isPaidAndConfirmed => paid && status != 'pending' && status != 'cancelled';

  /// The guest chose to pay at the hotel, so the room is kept with no countdown.
  bool get isKeptForHotel =>
      status == 'pending' && paymentChoice == 'hotel' && holdSecondsLeft == null;
}
