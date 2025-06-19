import 'package:flutter/foundation.dart';

class CompetitionHistory {
  final String? id; // UUID oluşturulacak
  final String userId;
  final String? name;
  final DateTime competitionDate;
  final String environment; // 'indoor' veya 'outdoor'
  final int distance;
  final String bowType; // 'recurve', 'compound', 'barebow'
  final int maxScore;
  final DateTime createdAt;
  final DateTime updatedAt;

  CompetitionHistory({
    this.id,
    required this.userId,
    this.name,
    required this.competitionDate,
    required this.environment,
    required this.distance,
    required this.bowType,
    required this.maxScore,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CompetitionHistory.fromJson(Map<String, dynamic> json) {
    return CompetitionHistory(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      name: json['name'] as String?,
      competitionDate: DateTime.parse(json['competition_date'] as String),
      environment: json['environment'] as String,
      distance: json['distance'] as int,
      bowType: json['bow_type'] as String,
      maxScore: json['max_score'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      if (name != null) 'name': name,
      'competition_date': competitionDate.toIso8601String(),
      'environment': environment,
      'distance': distance,
      'bow_type': bowType,
      'max_score': maxScore,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  CompetitionHistory copyWith({
    String? id,
    String? userId,
    String? name,
    DateTime? competitionDate,
    String? environment,
    int? distance,
    String? bowType,
    int? maxScore,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompetitionHistory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      competitionDate: competitionDate ?? this.competitionDate,
      environment: environment ?? this.environment,
      distance: distance ?? this.distance,
      bowType: bowType ?? this.bowType,
      maxScore: maxScore ?? this.maxScore,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
