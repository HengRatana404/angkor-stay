class StaffMember {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final bool isActive;

  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.isActive,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        isActive: json['is_active'] as bool,
      );
}
