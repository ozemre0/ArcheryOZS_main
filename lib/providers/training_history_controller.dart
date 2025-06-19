import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/training_session_model.dart';
import '../services/training_repository.dart';
import 'training_session_controller.dart';
import '../services/database_service.dart';
import '../services/supabase_config.dart';
import 'training_sync_provider.dart';

// Antrenman geçmişi için filtre tipleri
enum TrainingHistoryFilterType {
  none,
  indoor,
  outdoor,
  dateRange,
}

// Antrenman geçmişi için durum sınıfı
class TrainingHistoryState {
  final List<TrainingSession> sessions;
  final bool isLoading;
  final String? error;
  final TrainingHistoryFilterType filterType;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool forceRefresh; // Add flag to force refresh

  TrainingHistoryState({
    required this.sessions,
    required this.isLoading,
    this.error,
    required this.filterType,
    this.startDate,
    this.endDate,
    this.forceRefresh = false,
  });

  // Başlangıç durumu
  factory TrainingHistoryState.initial() {
    return TrainingHistoryState(
      sessions: [],
      isLoading: false,
      error: null,
      filterType: TrainingHistoryFilterType.none,
      startDate: null,
      endDate: null,
    );
  }

  TrainingHistoryState copyWith({
    List<TrainingSession>? sessions,
    bool? isLoading,
    String? error,
    TrainingHistoryFilterType? filterType,
    DateTime? startDate,
    DateTime? endDate,
    bool? forceRefresh,
  }) {
    return TrainingHistoryState(
      sessions: sessions ?? this.sessions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      filterType: filterType ?? this.filterType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      forceRefresh: forceRefresh ?? this.forceRefresh,
    );
  }
}

class TrainingHistoryController extends StateNotifier<TrainingHistoryState> {
  final TrainingRepository _repository;
  final Map<String, DateTime> _userCacheTime = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  TrainingHistoryController(this._repository)
      : super(TrainingHistoryState.initial());

  bool isCacheValid(String userId) {
    if (!_userCacheTime.containsKey(userId)) return false;
    final last = _userCacheTime[userId]!;
    return DateTime.now().difference(last) < _cacheDuration;
  }

  // Clear cache for a specific user
  void clearCacheForUser(String userId) {
    _userCacheTime.remove(userId);
  }

  // Helper: Remove duplicate sessions by type and delete extras
  Future<List<TrainingSession>> _deduplicateSessions(List<TrainingSession> sessions) async {
    final seen = <String, TrainingSession>{};
    final duplicatesToDelete = <TrainingSession>[];
    for (final s in sessions) {
      String key;
      if (s.trainingType == 'technique') {
        key = '${s.date.toIso8601String()}_${s.totalArrows}';
      } else {
        key = '${s.date.toIso8601String()}_${s.totalScore}_${s.totalArrows}';
      }
      if (!seen.containsKey(key)) {
        seen[key] = s;
      } else {
        duplicatesToDelete.add(s);
      }
    }
    // Fazlalık olanları hard delete (hem local hem Supabase)
    for (final dup in duplicatesToDelete) {
      await DatabaseService().deleteTrainingSession(dup.id);
      await SupabaseConfig.client
        .from('training_sessions')
        .delete()
        .eq('id', dup.id);
    }
    return seen.values.toList();
  }

  // Kullanıcının tüm antrenmanlarını hızlıca toplu olarak yükle
  Future<void> loadUserTrainings(String userId, {bool force = false}) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      // Tüm training oturumlarını toplu olarak çek
      final sessions = await _repository.getUserTrainingSessions(userId, force: force);
      // Silinmiş olanları filtrele
      final filteredSessions = sessions.where((s) {
        final isDeleted = (s as dynamic).is_deleted;
        return isDeleted == null || isDeleted == false || isDeleted == 0;
      }).toList();
      // Deduplicate by date and totalScore
      final dedupedSessions = await _deduplicateSessions(filteredSessions);

      // Hızlıca ekrana aktar
      state = state.copyWith(
        sessions: dedupedSessions,
        isLoading: false,
        filterType: TrainingHistoryFilterType.none,
      );
      _userCacheTime[userId] = DateTime.now();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Antrenman geçmişi yüklenemedi: \u007f\u007f${e.toString()}',
      );
    }
  }

  // Sadece indoor antrenmanları filtrele - cached filtering
  Future<void> filterByIndoor(String userId) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final sessions =
          await _repository.getTrainingSessionsByEnvironment(userId, true);
      final filteredSessions = sessions.where((s) {
        final isDeleted = (s as dynamic).is_deleted;
        return isDeleted == null || isDeleted == false || isDeleted == 0;
      }).toList();
      // Deduplicate by date and totalScore
      final dedupedSessions = await _deduplicateSessions(filteredSessions);

      state = state.copyWith(
        sessions: dedupedSessions,
        isLoading: false,
        filterType: TrainingHistoryFilterType.indoor,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Antrenmanlar filtrelenirken hata oluştu: ${e.toString()}',
      );
    }
  }

  // Sadece outdoor antrenmanları filtrele - cached filtering
  Future<void> filterByOutdoor(String userId) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final sessions =
          await _repository.getTrainingSessionsByEnvironment(userId, false);
      final filteredSessions = sessions.where((s) {
        final isDeleted = (s as dynamic).is_deleted;
        return isDeleted == null || isDeleted == false || isDeleted == 0;
      }).toList();
      // Deduplicate by date and totalScore
      final dedupedSessions = await _deduplicateSessions(filteredSessions);

      state = state.copyWith(
        sessions: dedupedSessions,
        isLoading: false,
        filterType: TrainingHistoryFilterType.outdoor,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Antrenmanlar filtrelenirken hata oluştu: ${e.toString()}',
      );
    }
  }

  // Tarih aralığına göre filtrele - cached filtering
  Future<void> filterByDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
        startDate: startDate,
        endDate: endDate,
      );

      final sessions = await _repository.getTrainingSessionsByDateRange(
        userId,
        startDate,
        endDate,
      );
      final filteredSessions = sessions.where((s) {
        final isDeleted = (s as dynamic).is_deleted;
        return isDeleted == null || isDeleted == false || isDeleted == 0;
      }).toList();
      // Deduplicate by date and totalScore
      final dedupedSessions = await _deduplicateSessions(filteredSessions);

      state = state.copyWith(
        sessions: dedupedSessions,
        isLoading: false,
        filterType: TrainingHistoryFilterType.dateRange,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Antrenmanlar filtrelenirken hata oluştu: ${e.toString()}',
      );
    }
  }

  // Tüm filtreleri temizle
  Future<void> clearFilters(String userId) async {
    await loadUserTrainings(userId);
  }

  // Bir antrenmanı sil
  Future<void> deleteTraining(String userId, String trainingId) async {
    try {
      // 1. Hemen ekrandan kaldır
      final updatedSessions = state.sessions.where((s) => s.id != trainingId).toList();
      state = state.copyWith(sessions: updatedSessions, isLoading: true, error: null);

      // 2. Arka planda silme işlemlerini yap
      await _softDeleteTrainingEverywhere(trainingId);

      // 3. (Opsiyonel) DB'den tekrar çekip state'i güncelle
      final sessions = await _repository.getUserTrainingSessions(userId);
      final filteredSessions = sessions.where((s) {
        final isDeleted = (s as dynamic).is_deleted;
        return isDeleted == null || isDeleted == false || isDeleted == 0;
      }).toList();
      final dedupedSessions = await _deduplicateSessions(filteredSessions);

      state = state.copyWith(
        sessions: dedupedSessions,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Antrenman silinemedi: ${e.toString()}',
      );
    }
  }

  // Hem local hem Supabase'de soft delete işlemi
  Future<void> _softDeleteTrainingEverywhere(String trainingId) async {
    // Localde soft delete
    await DatabaseService().softDeleteTrainingSession(trainingId);
    // Supabase'de soft delete
    await SupabaseConfig.client
        .from('training_sessions')
        .update({'is_deleted': true})
        .eq('id', trainingId);
  }

  // Performans istatistiklerini hesapla - Tüm antrenmanlar için
  Map<String, dynamic> calculateStats() {
    if (state.sessions.isEmpty) {
      return {
        'averageScore': 0.0,
        'totalArrows': 0,
        'totalSessions': 0,
        'bestSession': null,
        'indoorStats': {
          'averageScore': 0.0,
          'totalArrows': 0,
          'totalSessions': 0,
          'bestSession': null,
        },
        'outdoorStats': {
          'averageScore': 0.0,
          'totalArrows': 0,
          'totalSessions': 0,
          'bestSession': null,
        }
      };
    }

    // Only include 'score' trainings for statistics
    final scoreSessions = state.sessions.where((s) => s.trainingType == 'score').toList();

    // Genel istatistikler
    int totalArrows = 0;
    int totalScore = 0;
    TrainingSession? bestSession;
    double bestAverage = 0;

    // Indoor istatistikleri
    int indoorArrows = 0;
    int indoorScore = 0;
    TrainingSession? bestIndoorSession;
    double bestIndoorAverage = 0;
    int indoorSessionCount = 0;

    // Outdoor istatistikleri
    int outdoorArrows = 0;
    int outdoorScore = 0;
    TrainingSession? bestOutdoorSession;
    double bestOutdoorAverage = 0;
    int outdoorSessionCount = 0;

    for (var session in scoreSessions) {
      // Genel istatistikler
      totalArrows += session.totalArrows;
      totalScore += session.totalScore;

      if (session.average > bestAverage) {
        bestAverage = session.average;
        bestSession = session;
      }

      // Indoor / Outdoor ayrımı
      if (session.isIndoor) {
        indoorArrows += session.totalArrows;
        indoorScore += session.totalScore;
        indoorSessionCount++;

        if (session.average > bestIndoorAverage) {
          bestIndoorAverage = session.average;
          bestIndoorSession = session;
        }
      } else {
        outdoorArrows += session.totalArrows;
        outdoorScore += session.totalScore;
        outdoorSessionCount++;

        if (session.average > bestOutdoorAverage) {
          bestOutdoorAverage = session.average;
          bestOutdoorSession = session;
        }
      }
    }

    double overallAverage = totalArrows > 0 ? totalScore / totalArrows : 0;
    double indoorAverage = indoorArrows > 0 ? indoorScore / indoorArrows : 0;
    double outdoorAverage =
        outdoorArrows > 0 ? outdoorScore / outdoorArrows : 0;

    return {
      'averageScore': overallAverage,
      'totalArrows': totalArrows,
      // totalSessions should count all sessions, not just 'score' ones
      'totalSessions': state.sessions.length,
      'bestSession': bestSession,
      'indoorStats': {
        'averageScore': indoorAverage,
        'totalArrows': indoorArrows,
        'totalSessions': indoorSessionCount,
        'bestSession': bestIndoorSession,
      },
      'outdoorStats': {
        'averageScore': outdoorAverage,
        'totalArrows': outdoorArrows,
        'totalSessions': outdoorSessionCount,
        'bestSession': bestOutdoorSession,
      }
    };
  }

  // Hata mesajını temizle
  void clearError() {
    state = state.copyWith(error: null);
  }

  // Request sync with server in the background
  Future<void> requestBackgroundSync(String userId, WidgetRef ref) async {
    try {
      // Show loading state
      state = state.copyWith(isLoading: true, error: null);
      // Get the sync service from provider
      final syncService = ref.read(trainingSyncServiceProvider);
      // Run both upload (local→Supabase) and delta download (Supabase→local)
      await syncService.syncPendingData();
      await syncService.syncUpdatedTrainingsFromSupabase(userId);
      // Refresh local cache after sync
      await loadUserTrainings(userId, force: true);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Sync failed: ${e.toString()}',
      );
    }
  }
}

// TrainingHistory provider
final trainingHistoryProvider =
    StateNotifierProvider<TrainingHistoryController, TrainingHistoryState>(
        (ref) {
  final repository = ref.watch(trainingRepositoryProvider);
  return TrainingHistoryController(repository);
});
