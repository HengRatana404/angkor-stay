/// The settings every guest may see: the online discount and the times.
class PublicSettings {
  final int onlineDiscountPercent;
  final String checkInTime;
  final String checkOutTime;

  const PublicSettings({
    required this.onlineDiscountPercent,
    required this.checkInTime,
    required this.checkOutTime,
  });

  factory PublicSettings.fromJson(Map<String, dynamic> json) => PublicSettings(
        onlineDiscountPercent: (json['online_discount_percent'] as num).toInt(),
        checkInTime: json['check_in_time'] as String,
        checkOutTime: json['check_out_time'] as String,
      );
}
