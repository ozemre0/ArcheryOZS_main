import 'package:brick_sqlite/brick_sqlite.dart';
import '../models/profile_model.dart' as model;

@SqliteSerializable()
class Profile {
  final String id;
  final String firstName;
  final String lastName;
  final String role;
  final DateTime birthDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? photoUrl;
  final String? address;
  final String? phoneNumber;
  final String? gender;

  const Profile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.birthDate,
    required this.createdAt,
    required this.updatedAt,
    this.photoUrl,
    this.address,
    this.phoneNumber,
    this.gender,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      role: json['role'] as String,
      birthDate: DateTime.parse(json['birth_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      photoUrl: json['photo_url'] as String?,
      address: json['address'] as String?,
      phoneNumber: json['phone_number'] as String?,
      gender: json['gender'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'role': role,
      'birth_date': birthDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'photo_url': photoUrl,
      'address': address,
      'phone_number': phoneNumber,
      'gender': gender,
    };
  }

  model.Profile toModelProfile() {
    return model.Profile(
      id: id,
      firstName: firstName,
      lastName: lastName,
      role: role,
      birthDate: birthDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
      photoUrl: photoUrl,
      address: address,
      phoneNumber: phoneNumber,
      gender: gender,
    );
  }

  static Profile fromModelProfile(model.Profile profile) {
    return Profile(
      id: profile.id,
      firstName: profile.firstName,
      lastName: profile.lastName,
      role: profile.role,
      birthDate: profile.birthDate,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
      photoUrl: profile.photoUrl,
      address: profile.address,
      phoneNumber: profile.phoneNumber,
      gender: profile.gender,
    );
  }
}
