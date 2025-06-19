import 'package:archeryozs/services/training_repository.dart';
import '../models/training_session_model.dart';

class AthleteStatisticsService {
  final TrainingRepository _repository = TrainingRepository();

  Future<Map<String, dynamic>> getAthleteStatistics(
    String athleteId, {
    bool? isIndoor,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Filtreye göre local DB'den antrenmanları çek
    List<TrainingSession> sessions;
    if (startDate != null && endDate != null) {
      sessions = await _repository.getTrainingSessionsByDateRange(
        athleteId, startDate, endDate,
      );
      if (isIndoor != null) {
        sessions = sessions.where((s) => s.isIndoor == isIndoor).toList();
      }
    } else if (isIndoor != null) {
      sessions = await _repository.getTrainingSessionsByEnvironment(
        athleteId, isIndoor,
      );
    } else {
      sessions = await _repository.getUserTrainingSessions(athleteId);
    }
    // Silinmişleri çıkar
    sessions = sessions.where((s) => s.is_deleted != true).toList();

    // Only include 'score' trainings for statistics, but count all for totalSessions
    final scoreSessions = sessions.where((s) => s.trainingType == 'score').toList();
    int totalArrows = 0;
    int totalScore = 0;
    double bestScore = 0;
    int indoorArrows = 0;
    int indoorScore = 0;
    double bestIndoorScore = 0;
    int outdoorArrows = 0;
    int outdoorScore = 0;
    double bestOutdoorScore = 0;

    for (var session in scoreSessions) {
      final arrows = session.totalArrows;
      final score = session.totalScore;
      final sessionIsIndoor = session.isIndoor;
      final double average = arrows > 0 ? (score / arrows).toDouble() : 0;

      totalArrows += arrows;
      totalScore += score;
      if (average > bestScore) bestScore = average;

      if (sessionIsIndoor) {
        indoorArrows += arrows;
        indoorScore += score;
        if (average > bestIndoorScore) bestIndoorScore = average;
      } else {
        outdoorArrows += arrows;
        outdoorScore += score;
        if (average > bestOutdoorScore) bestOutdoorScore = average;
      }
    }

    final statistics = {
      'overall': {
        'totalSessions': sessions.length, // all sessions
        'totalArrows': totalArrows,
        'averageScore': totalArrows > 0 ? (totalScore / totalArrows).toDouble() : 0.0,
        'bestScore': bestScore,
      },
      'indoor': {
        'totalSessions': scoreSessions.where((s) => s.isIndoor).length,
        'totalArrows': indoorArrows,
        'averageScore': indoorArrows > 0 ? (indoorScore / indoorArrows).toDouble() : 0.0,
        'bestScore': bestIndoorScore,
      },
      'outdoor': {
        'totalSessions': scoreSessions.where((s) => !s.isIndoor).length,
        'totalArrows': outdoorArrows,
        'averageScore': outdoorArrows > 0 ? (outdoorScore / outdoorArrows).toDouble() : 0.0,
        'bestScore': bestOutdoorScore,
      },
    };

    return statistics;
  }

  // Artık cache yok, bu fonksiyonlar gereksiz
  void clearCache() {}
  void clearCacheForAthlete(String athleteId) {}
}
