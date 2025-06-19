class Competition {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String location;
  final String type;
  final String? description;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Competition({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.location,
    required this.type,
    this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Competition.fromJson(Map<String, dynamic> json) {
    return Competition(
      id: json['id'] as String,
      name: json['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      location: json['location'] as String,
      type: json['type'] as String,
      description: json['description'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'location': location,
      'type': type,
      'description': description,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class CompetitionParticipant {
  final String id;
  final String competitionId;
  final String athleteId;
  final String category;
  final String status;
  final int? finalRank;
  final int? totalScore;
  final DateTime createdAt;
  final DateTime updatedAt;

  CompetitionParticipant({
    required this.id,
    required this.competitionId,
    required this.athleteId,
    required this.category,
    required this.status,
    this.finalRank,
    this.totalScore,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CompetitionParticipant.fromJson(Map<String, dynamic> json) {
    return CompetitionParticipant(
      id: json['id'] as String,
      competitionId: json['competition_id'] as String,
      athleteId: json['athlete_id'] as String,
      category: json['category'] as String,
      status: json['status'] as String,
      finalRank: json['final_rank'] as int?,
      totalScore: json['total_score'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'competition_id': competitionId,
      'athlete_id': athleteId,
      'category': category,
      'status': status,
      'final_rank': finalRank,
      'total_score': totalScore,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
