/// The settings the admin can change.
class HotelSettings {
  final int onlineDiscountPercent;
  final String checkInTime; // "14:00"
  final String checkOutTime; // "12:00"
  final bool staffLoginRestricted;
  final List<String> allowedNetworks;
  final bool demoPaymentMode;

  const HotelSettings({
    required this.onlineDiscountPercent,
    required this.checkInTime,
    required this.checkOutTime,
    required this.staffLoginRestricted,
    required this.allowedNetworks,
    required this.demoPaymentMode,
  });

  factory HotelSettings.fromJson(Map<String, dynamic> json) => HotelSettings(
        onlineDiscountPercent: (json['online_discount_percent'] as num).toInt(),
        checkInTime: json['check_in_time'] as String,
        checkOutTime: json['check_out_time'] as String,
        staffLoginRestricted: json['staff_login_restricted'] as bool,
        allowedNetworks: (json['allowed_networks'] as List).cast<String>(),
        demoPaymentMode: json['demo_payment_mode'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'online_discount_percent': onlineDiscountPercent,
        'check_in_time': checkInTime,
        'check_out_time': checkOutTime,
        'staff_login_restricted': staffLoginRestricted,
        'allowed_networks': allowedNetworks,
        'demo_payment_mode': demoPaymentMode,
      };
}

/// Settings plus the address the server sees this phone coming from.
class SettingsResult {
  final HotelSettings settings;
  final String yourIp;
  const SettingsResult(this.settings, this.yourIp);
}

/// The network of a device: 192.168.123.6 -> "192.168.123.0/24".
/// An address on this very PC (127.x) or an IPv6 address is kept as one device.
String networkForIp(String ip) {
  if (ip.contains(':')) return '$ip/128';
  final parts = ip.split('.');
  if (parts.length != 4 || ip.startsWith('127.')) return '$ip/32';
  return '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
}
