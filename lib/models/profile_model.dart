class Profile {
  final String id;
  final String? visibleId;
  final String firstName;
  final String lastName;
  final String role;
  final DateTime birthDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? photoUrl;
  final String? address;
  final String? phoneNumber;
  final String? gender; // Added gender field

  Profile({
    required this.id,
    this.visibleId,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.birthDate,
    required this.createdAt,
    required this.updatedAt,
    this.photoUrl,
    this.address,
    this.phoneNumber,
    this.gender, // Added gender parameter
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      visibleId: json['visible_id'] as String?,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      role: json['role'] as String,
      birthDate: DateTime.parse(json['birth_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      photoUrl: json['photo_url'] as String?,
      address: json['address'] as String?,
      phoneNumber: json['phone_number'] as String?,
      gender: json['gender'] as String?, // Added gender from JSON
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'visible_id': visibleId,
      'first_name': firstName,
      'last_name': lastName,
      'role': role,
      'birth_date': birthDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'photo_url': photoUrl,
      'address': address,
      'phone_number': phoneNumber,
      'gender': gender, // Added gender to JSON
    };
  }

  Profile copyWith({
    String? id,
    String? visibleId,
    String? firstName,
    String? lastName,
    String? role,
    DateTime? birthDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? photoUrl,
    String? address,
    String? phoneNumber,
    String? gender, // Added gender to copyWith
  }) {
    return Profile(
      id: id ?? this.id,
      visibleId: visibleId ?? this.visibleId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      role: role ?? this.role,
      birthDate: birthDate ?? this.birthDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photoUrl: photoUrl ?? this.photoUrl,
      address: address ?? this.address,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      gender: gender ?? this.gender, // Added gender to copyWith return
    );
  }
}
