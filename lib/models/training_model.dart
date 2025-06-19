class Training {
  final String id;
  final String athleteId;
  final String? coachId;
  final DateTime trainingDate;
  final DateTime startTime;
  final DateTime? endTime;
  final String type;
  final int distance;
  final String? notes;
  final String? weatherConditions;
  final String? location;
  final DateTime createdAt;
  final DateTime updatedAt;

  Training({
    required this.id,
    required this.athleteId,
    this.coachId,
    required this.trainingDate,
    required this.startTime,
    this.endTime,
    required this.type,
    required this.distance,
    this.notes,
    this.weatherConditions,
    this.location,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Training.fromJson(Map<String, dynamic> json) {
    return Training(
      id: json['id'] as String,
      athleteId: json['athlete_id'] as String,
      coachId: json['coach_id'] as String?,
      trainingDate: DateTime.parse(json['training_date'] as String),
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      type: json['type'] as String,
      distance: json['distance'] as int,
      notes: json['notes'] as String?,
      weatherConditions: json['weather_conditions'] as String?,
      location: json['location'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'athlete_id': athleteId,
      'coach_id': coachId,
      'training_date': trainingDate.toIso8601String(),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'type': type,
      'distance': distance,
      'notes': notes,
      'weather_conditions': weatherConditions,
      'location': location,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
