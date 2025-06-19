import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/training_session_model.dart';
// import '../models/training_series_model.dart'; // Artık kullanılmıyor, kaldırıldı
import '../services/training_repository.dart';
import '../services/database_service.dart';
import '../services/supabase_config.dart';

/// Service that handles the synchronization of training data between
/// local SQLite database and Supabase. This ensures that the app operates in
/// an offline-first manner, with synchronization happening regularly.
class TrainingSyncService {
  final TrainingRepository _repository;
  final DatabaseService _database = DatabaseService();
  Timer? _syncTimer;
  bool _isAutoSyncEnabled = true;
  bool _isSyncing = false; // Senkronizasyonun devam edip etmediğini takip etmek için

  TrainingSyncService({required TrainingRepository repository})
      : _repository = repository {
    // Uygulaması başladığında mevcut verileri senkronize etmeye çalış
    _initializeSync();
  }

  /// Uygulama başladığında ilk senkronizasyon ve periyodik senkronizasyon ayarı
  void _initializeSync() {
    // Başlangıçta senkronizasyon yap
    syncPendingData();

    // Her 2 dakikada bir otomatik senkronizasyon ayarla (15 dakika yerine)
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_isAutoSyncEnabled) {
        syncPendingData();
      }
    });

    // İnternet tekrar gelince otomatik sync
    Connectivity().onConnectivityChanged.listen((status) {
      if (status != ConnectivityResult.none) {
        debugPrint('|10n:internet_came_back_syncing_pending_trainings');
        syncPendingData();
      }
    });
  }

  /// Set auto sync enabled/disabled
  void setAutoSync(bool isEnabled) {
    _isAutoSyncEnabled = isEnabled;
  }

  /// Belirli bir antrenman oturumu için hemen senkronizasyon yap
  /// Bu metot, özellikle sporcu bir antrenmanı güncellediğinde çağrılmalıdır
  Future<void> syncTrainingSession(TrainingSession session) async {
    try {
      // Check connectivity first
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('No internet connection, training will be synced later');
        return;
      }

      // Supabase client'ı doğrudan al
      final supabase = SupabaseConfig.client;

      // Eğer oturum zaten Supabase'de kaydedilmemişse (local_ ile başlamayan ID)
      if (!session.id.startsWith('local_')) {
        debugPrint('Immediate sync for training session: ${session.id}');

        // series_data'yı doğrudan kullanarak güncelleştirme yap
        Map<String, dynamic> seriesDataObj = {};
        if (session.seriesData != null && session.seriesData!.isNotEmpty) {
          try {
            seriesDataObj = jsonDecode(session.seriesData!);
          } catch (e) {
            debugPrint('Error parsing series_data: $e');
            seriesDataObj = {};
          }
        }

        // Toplam değerleri güncelle
        final sessionData = {
          // 'total_arrows': session.totalArrows,
          // 'total_score': session.totalScore,
          // 'average': session.average,
          // 'x_count': session.xCount,
          'series_data': session.seriesData,
        };

        debugPrint('Updating training session totals: $sessionData');

        try {
          await supabase
              .from('training_sessions')
              .update(sessionData)
              .eq('id', session.id);

          debugPrint('Successfully updated training session totals in Supabase');
        } catch (e) {
          debugPrint('Error updating training session totals: $e');
        }
      } else {
        // Henüz Supabase'e kaydedilmemiş - tüm bekleyen oturumları senkronize et
        debugPrint('Session has local ID, syncing all pending data');
        await _repository.syncPendingTrainingSessions();
      }
    } catch (e) {
      debugPrint('Error syncing specific training session: $e');
    }
  }

  /// Sync training data with Supabase
  /// This should be called whenever a training session is created or updated
  Future<void> finalizeTrainingSession(TrainingSession session) async {
    try {
      // Check connectivity first
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('No internet connection, training will be synced later');
        return;
      }

      // Sync all pending training sessions
      await _repository.syncPendingTrainingSessions();
    } catch (e) {
      debugPrint('Error syncing training data: $e');
    }
  }

  /// Manually trigger a background sync of all pending training data
  Future<void> syncPendingData() async {
    if (_isSyncing) {
      debugPrint('Sync already in progress, skipping');
      return;
    }

    try {
      _isSyncing = true;
      await _repository.syncPendingTrainingSessions();
    } catch (e) {
      debugPrint('Error syncing training data: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Supabase'den sadece son sync'ten sonra değişen antrenmanları çek ve local veritabanına kaydet (HTTP workaround)
  Future<void> syncUpdatedTrainingsFromSupabase(String userId) async {
    final dbService = DatabaseService();
    final now = DateTime.now();
    final lastSync = DatabaseService.lastSupabaseSync;
    if (_isSyncing) {
      debugPrint('Supabase delta sync: Sync already in progress, skipping.');
      return;
    }
    _isSyncing = true;
    try {
      debugPrint('Supabase delta sync: Fetching updated trainings for user $userId...');
      final supabaseUrl = '${SupabaseConfig.supabaseUrl}/rest/v1';
      final supabaseKey = SupabaseConfig.supabaseAnonKey;
      final filter = lastSync != null
          ? '&updated_at=gte.${lastSync.toIso8601String()}'
          : '';
      final url =
          '$supabaseUrl/training_sessions?user_id=eq.$userId&is_deleted=eq.false$filter&order=date.desc';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'apikey': supabaseKey,
          'Authorization': 'Bearer $supabaseKey',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          debugPrint('Supabase delta sync: ${data.length} updated trainings found. Saving to local DB...');
          final db = await dbService.database;
          for (final sessionMap in data) {
            try {
              final List<Map<String, dynamic>> localRows = await db.query(
                'training_sessions',
                where: 'id = ?',
                whereArgs: [sessionMap['id']],
              );
              if (localRows.isNotEmpty && (localRows.first['is_deleted'] == 1)) {
                debugPrint('Supabase delta sync: Skipping deleted training: ${sessionMap['id']}');
                continue;
              }
              final session = TrainingSession.fromJson(sessionMap);
              await dbService.saveTrainingSession(session);
            } catch (e) {
              debugPrint('Supabase delta sync: Error saving session: $e');
            }
          }
          debugPrint('Supabase delta sync: All updated trainings saved to local DB.');
        } else {
          debugPrint('Supabase delta sync: No updated trainings found for user.');
        }
        DatabaseService.lastSupabaseSync = now;
      } else {
        debugPrint('Supabase delta sync: HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Supabase delta sync: Error fetching updated trainings from Supabase: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Uygulama kapandığında timer'ı iptal et
  void dispose() {
    _syncTimer?.cancel();
  }
}
