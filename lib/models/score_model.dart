import 'dart:convert';

class TrainingScore {
  final String id;
  final String trainingId;
  final int setNumber;
  final List<int> arrowScores;
  final int totalScore;
  final DateTime createdAt;
  final DateTime updatedAt;

  TrainingScore({
    required this.id,
    required this.trainingId,
    required this.setNumber,
    required this.arrowScores,
    required this.totalScore,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TrainingScore.fromJson(Map<String, dynamic> json) {
    return TrainingScore(
      id: json['id'] as String,
      trainingId: json['training_id'] as String,
      setNumber: json['set_number'] as int,
      arrowScores: List<int>.from(jsonDecode(json['arrow_scores'] as String)),
      totalScore: json['total_score'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'training_id': trainingId,
      'set_number': setNumber,
      'arrow_scores': jsonEncode(arrowScores),
      'total_score': totalScore,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class CompetitionScore {
  final String id;
  final String participantId;
  final int roundNumber;
  final int setNumber;
  final List<int> arrowScores;
  final int totalScore;
  final DateTime createdAt;
  final DateTime updatedAt;

  CompetitionScore({
    required this.id,
    required this.participantId,
    required this.roundNumber,
    required this.setNumber,
    required this.arrowScores,
    required this.totalScore,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CompetitionScore.fromJson(Map<String, dynamic> json) {
    return CompetitionScore(
      id: json['id'] as String,
      participantId: json['participant_id'] as String,
      roundNumber: json['round_number'] as int,
      setNumber: json['set_number'] as int,
      arrowScores: List<int>.from(jsonDecode(json['arrow_scores'] as String)),
      totalScore: json['total_score'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participant_id': participantId,
      'round_number': roundNumber,
      'set_number': setNumber,
      'arrow_scores': jsonEncode(arrowScores),
      'total_score': totalScore,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
