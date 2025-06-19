import 'dart:async';

import 'package:archeryozs/services/training_history_service.dart';
import 'package:flutter/material.dart';
import 'dart:convert'; // For jsonEncode
import 'package:sqflite/sqflite.dart' if (dart.library.html) 'c:/Users/USER/Desktop/ozs_project/ArcheryOZS-main28.04.2025/lib/services/sqflite_web_stub.dart'; // Conditional import for ConflictAlgorithm
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/training_session_model.dart';
import '../services/supabase_config.dart';
import '../services/database_service.dart';

/// Completely redesigned repository to work in offline-first mode
/// All operations are done locally first, with Supabase operations
/// done in the background only when explicitly requested
/// Now using SQLite instead of Flutter Secure Storage for better data management
class TrainingRepository {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final _database = DatabaseService();
  final Uuid _uuid = const Uuid();
  // Track if a sync is already in progress
  bool _isSyncing = false;

  // Constructor
  TrainingRepository();

  /// Create a new training session (ALWAYS local first)
  Future<TrainingSession> createTrainingSession({
    required String userId,
    required DateTime date,
    required int distance,
    required String bowType,
    required bool isIndoor,
    String? notes,
    String? training_session_name,
    String trainingType = 'score',
    int arrowsPerSeries = 3,
    String? seriesData,
    int seriesCount = 1,
  }) async {
    // Generate a local ID with a prefix to identify it as a local session
    final localId = 'local_${_uuid.v4()}';

    if (trainingType == 'technique') {
      // Teknik antrenman için skor/seri/puan alanlarını null/boş bırak
      // Dummy seriesData ekle: toplam ok sayısı kadar 0 puanlı ok
      List<List<dynamic>> dummySeries = List.generate(
        seriesCount,
        (i) => [i + 1, List.filled(arrowsPerSeries, 0)],
      );
      String dummySeriesData = dummySeries.toString();
      final session = TrainingSession(
        id: localId,
        userId: userId,
        date: date,
        distance: distance,
        bowType: bowType,
        isIndoor: isIndoor,
        notes: notes,
        training_session_name: training_session_name,
        trainingType: trainingType,
        arrowsPerSeries: arrowsPerSeries,
        seriesData: dummySeriesData,
        is_deleted: false,
      );
      await _database.saveTrainingSession(session);
      return session;
    }

    // Create the training session with the local ID
    final trainingSession = TrainingSession(
      id: localId,
      userId: userId,
      date: date,
      distance: distance,
      bowType: bowType,
      isIndoor: isIndoor,
      notes: notes,
      training_session_name: training_session_name,
      trainingType: trainingType,
      arrowsPerSeries: arrowsPerSeries, // Store arrows per series
      seriesData: seriesData, // Yeni algoritma için
    );

    // Web platformunda doğrudan Supabase kullan, diğer platformlarda SQLite
    if (kIsWeb) {
      try {
        // Web platformunda doğrudan Supabase'e kaydet
        // ÖNEMLİ: webSaveTrainingSession artık güncellenmiş TrainingSession döndürüyor
        final updatedSession =
            await _database.webSaveTrainingSession(trainingSession);
        // |10n:web_training_session_created_with_series_data
        print('|10n:web_training_session_created_with_series_data');
        print('Web training session created with ID: ${updatedSession.id}');

        // Supabase'in verdiği gerçek ID ile güncellenmiş session'ı döndür
        return updatedSession;
      } catch (e) {
        print('|10n:web_platform_error_creating_training_session $e');
        rethrow;
      }
    } else {
      // Mobil platformlarda yerel SQLite veritabanına kaydet
      await _database.saveTrainingSession(trainingSession);
      // Kayıttan hemen sonra sync tetikle
      try {
        await syncPendingTrainingSessions();
        print('|10n:mobile_sync_triggered');
      } catch (e) {
        print('|10n:mobile_sync_error $e');
      }
    }

    return trainingSession;
  }

  /// Get all training sessions for a user (ALWAYS from local DB)
  Future<List<TrainingSession>> getUserTrainingSessions(String userId, {bool force = false}) async {
    try {
      // Web platformunda direkt Supabase'den al
      if (kIsWeb) {
        return await _database.webGetUserTrainingSessions(userId, force: force);
      }
      // Mobil platformlarda yerel veritabanından al
      return await _database.getUserTrainingSessions(userId);
    } catch (e) {
      print('Error getting user training sessions: $e');
      return [];
    }
  }

  /// Get a specific training session from local DB
  Future<TrainingSession> getTrainingSession(String trainingId) async {
    try {
      // Web platformunda direkt Supabase'den al
      if (kIsWeb) {
        final session = await _database.webGetTrainingSession(trainingId);
        if (session != null) {
          return session;
        }
        throw Exception('Training session not found in Supabase');
      }

      // Mobil platformlarda mevcut kodu kullan
      // First try to get from local DB
      final session = await _database.getTrainingSession(trainingId);

      if (session != null) {
        return session;
      }

      // If not found in local DB and it's not a local ID, try to fetch from Supabase
      if (!trainingId.startsWith('local_')) {
        try {
          final connectivityResult = await Connectivity().checkConnectivity();

          // Only attempt Supabase fetch if we have connectivity
          if (connectivityResult != ConnectivityResult.none) {
            print('Session not found locally, trying Supabase: $trainingId');

            // Try to fetch from Supabase
            final response = await _supabase
                .from('training_sessions')
                .select('*')
                .eq('id', trainingId)
                .single();

            // Convert to model
            final remoteSession =
                await _convertSupabaseResponseToSession(response);

            // Save to local database
            await _database.saveTrainingSession(remoteSession);

            return remoteSession;
          }
        } catch (e) {
          print('Error fetching training session from Supabase: $e');
        }
      }

      throw Exception('Training session not found');
    } catch (e) {
      print('Error getting training session: $e');
      rethrow;
    }
  }

  /// Helper method to convert Supabase response to TrainingSession object
  Future<TrainingSession> _convertSupabaseResponseToSession(
      Map<String, dynamic> response) async {
    return TrainingSession(
      id: response['id'],
      userId: response['user_id'],
      date: DateTime.parse(response['date']),
      distance: response['distance'],
      bowType: response['bow_type'],
      isIndoor: response['is_indoor'],
      notes: response['notes'],
      training_session_name: response['training_session_name'], // |10n
      trainingType: response['training_type'],
      arrowsPerSeries: response['arrows_per_series'] ?? 3, // Include arrowsPerSeries from response or use default
      is_deleted: (response['is_deleted'] == true || response['is_deleted'] == 1),
    );
  }

  /// Güncelleme yap
  Future<TrainingSession> updateTrainingSession({
    required String trainingId,
    DateTime? date,
    int? distance,
    String? bowType,
    bool? isIndoor,
    String? notes,
    String? training_session_name,
    String? trainingType,
    int? arrowsPerSeries,
  }) async {
    try {
      // Mevcut oturumu al
      final session = await getTrainingSession(trainingId);

      // Create updated session
      final updatedSession = session.copyWith(
        date: date ?? session.date,
        distance: distance ?? session.distance,
        bowType: bowType ?? session.bowType,
        isIndoor: isIndoor ?? session.isIndoor,
        notes: notes ?? session.notes,
        training_session_name:
            training_session_name ?? session.training_session_name,
        trainingType: trainingType ?? session.trainingType,
        arrowsPerSeries: arrowsPerSeries ?? session.arrowsPerSeries,
      );

      // Güncellenmiş oturumu kaydet
      await _database.saveTrainingSession(updatedSession);

      // Eğer antrenman zaten Supabase'e kaydedildiyse güncelle
      if (!trainingId.startsWith('local_')) {
        final connectivityResult = await Connectivity().checkConnectivity();

        if (connectivityResult != ConnectivityResult.none) {
          try {
            final sessionData = {
              'date': updatedSession.date.toIso8601String(),
              'distance': updatedSession.distance,
              'bow_type': updatedSession.bowType,
              'is_indoor': updatedSession.isIndoor,
              'notes': updatedSession.notes,
              'training_session_name': updatedSession.training_session_name,
              'training_type': updatedSession.trainingType,
              'arrows_per_series': updatedSession.arrowsPerSeries,
              'series_data': updatedSession.seriesData, // |10n:series_data_update
            };

            await _supabase
                .from('training_sessions')
                .update(sessionData)
                .eq('id', trainingId);

            print('Updated training session on Supabase: $trainingId');
          } catch (e) {
            print('Error updating training session on Supabase: $e');
          }
        }
      }

      return updatedSession;
    } catch (e) {
      print('Error updating training session: $e');
      rethrow;
    }
  }

  /// Filter training sessions by date range (ALWAYS from local DB)
  Future<List<TrainingSession>> getTrainingSessionsByDateRange(
      String userId, DateTime startDate, DateTime endDate) async {
    try {
      // Web platformunda direkt Supabase'den al
      if (kIsWeb) {
        return await _database.webGetTrainingSessionsByDateRange(
            userId, startDate, endDate);
      }
      // Mobil platformlarda yerel veritabanından al
      return await _database.getTrainingSessionsByDateRange(
          userId, startDate, endDate);
    } catch (e) {
      print('Error filtering sessions by date range: $e');
      return [];
    }
  }

  /// Filter training sessions by environment (indoor/outdoor) (ALWAYS from local DB)
  Future<List<TrainingSession>> getTrainingSessionsByEnvironment(
      String userId, bool isIndoor) async {
    try {
      // Web platformunda direkt Supabase'den al
      if (kIsWeb) {
        return await _database.webGetTrainingSessionsByEnvironment(
            userId, isIndoor);
      }
      // Mobil platformlarda yerel veritabanından al
      return await _database.getTrainingSessionsByEnvironment(userId, isIndoor);
    } catch (e) {
      print('Error filtering sessions by environment: $e');
      return [];
    }
  }

  /// Sync all pending training sessions with Supabase (local-first, minimal requests)
  Future<void> syncPendingTrainingSessions() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      // İnternet bağlantısını kontrol et
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('|10n:sync_no_connectivity');
        _isSyncing = false;
        return;
      }
      // Bekleyen antrenmanları getir
      final pendingSessions = await _database.getPendingTrainingSessions();
      debugPrint('|10n:sync_pending_sessions_count: [32m${pendingSessions.length}\u001b[0m');
      if (pendingSessions.isEmpty) {
        debugPrint('|10n:sync_no_pending_sessions');
        _isSyncing = false;
        return;
      }
      // Hazırlık: toplu ekleme ve güncelleme için iki ayrı liste oluştur
      final List<Map<String, dynamic>> sessionsToInsert = [];
      final List<Map<String, dynamic>> sessionsToUpsert = [];
      final Map<String, String> localIdToSupabaseId = {};
      for (final session in pendingSessions) {
        // --- YENİ: Toplam ok sayısı 0 ise Supabase'e gönderme ---
        int totalArrows = 0;
        try {
          if (session.seriesData != null && session.seriesData!.isNotEmpty) {
            final dynamic seriesDataJson = jsonDecode(session.seriesData!);
            if (seriesDataJson is List) {
              for (final item in seriesDataJson) {
                if (item is List && item.length >= 2 && item[1] is List) {
                  final arrows = List<int>.from(item[1].map((a) => a is num ? a.toInt() : 0));
                  totalArrows += arrows.length;
                }
              }
            }
          }
        } catch (_) {}
        if (totalArrows == 0) {
          debugPrint('|10n:sync_skip_zero_arrow_session: ${session.id}');
          await _database.softDeleteTrainingSession(session.id);
          continue;
        }
        // Supabase'e gönderilecek veri
        final sessionData = session.toJson();
        sessionData.remove('pending_sync'); // Supabase'e pending_sync gönderme
        // Sadece local id ise insert, uuid ise upsert
        final isLocalId = session.id.startsWith('local_');
        if (isLocalId) {
          sessionData.remove('id'); // Supabase'e yeni id üretmesi için id'yi kaldır
          sessionsToInsert.add(sessionData);
        } else if (session.id.isNotEmpty) {
          sessionsToUpsert.add(sessionData);
        }
      }
      // --- TOPLU EKLEME ---
      if (sessionsToInsert.isNotEmpty) {
        try {
          final insertResponse = await _supabase
              .from('training_sessions')
              .insert(sessionsToInsert)
              .select();
          // ID eşleştirmesi yap
          for (int i = 0; i < insertResponse.length; i++) {
            final supabaseId = insertResponse[i]['id'] as String?;
            final userId = insertResponse[i]['user_id'] as String?;
            if (supabaseId != null && userId != null) {
              // Eşleşen local session'ı bul (manual search)
              TrainingSession? localSession;
              for (final s in pendingSessions) {
                if (s.userId == userId && s.id.startsWith('local_')) {
                  localSession = s;
                  break;
                }
              }
              if (localSession != null) {
                await _database.markSessionAsSynced(localSession.id, supabaseId);
                localIdToSupabaseId[localSession.id] = supabaseId;
                debugPrint('|10n:sync_local_session_updated: \x1B[33m${localSession.id} -> $supabaseId\u001b[0m');
              }
            }
          }
        } catch (e) {
          debugPrint('|10n:sync_supabase_batch_insert_error: $e');
        }
      }
      // --- TOPLU GÜNCELLEME ---
      if (sessionsToUpsert.isNotEmpty) {
        try {
          // pending_sync alanı gönderilmiyor
          await _supabase
              .from('training_sessions')
              .upsert(sessionsToUpsert)
              .select();
          // Tüm güncellenenleri senkronize olarak işaretle
          for (final session in pendingSessions) {
            if (!session.id.startsWith('local_')) {
              await _database.markSyncComplete(session.id);
              debugPrint('|10n:sync_marked_complete: ${session.id}');
            }
          }
        } catch (e) {
          debugPrint('|10n:sync_supabase_batch_update_error: $e');
        }
      }
      debugPrint('|10n:sync_completed: ${pendingSessions.length} antrenman senkronize edildi');
    } catch (e) {
      debugPrint('|10n:sync_general_error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Verify database connection is working properly
  Future<bool> verifyDatabaseConnection() async {
    try {
      // Web platformunda SQLite kullanılmadığı için bu metodu atlayalım
      if (kIsWeb) {
        // Web platformunda Supabase bağlantısını doğrula
        try {
          await _supabase.from('profiles').select('id').limit(1);
          print('Supabase connection verified successfully');
          return true;
        } catch (e) {
          print('Supabase connection verification failed: $e');
          throw Exception('Supabase bağlantı hatası: $e');
        }
      }

      final db = await _database.database;
      // Simple test query to ensure database is accessible
      await db.rawQuery('SELECT 1');
      print('Database connection verified successfully');
      return true;
    } catch (e) {
      print('Database connection verification failed: $e');
      throw Exception('Veritabanı bağlantı hatası: $e');
    }
  }

  // Web platformu için antrenman oturumunun toplam değerlerini güncelleme
  Future<void> _updateTrainingSessionTotals(String trainingId) async {
    if (!kIsWeb) return;

    try {
      // Oturumun tüm serilerini al
      final sessionResponse = await _supabase
          .from('training_sessions')
          .select('series_data')
          .eq('id', trainingId)
          .single();

      print(
          'Web platform: Updating totals for session $trainingId with series data');

      if (sessionResponse['series_data'] != null) {
        final seriesResponse = jsonDecode(sessionResponse['series_data']);

        int totalArrows = 0;
        int totalScore = 0;
        int xCount = 0;

        // Toplam değerleri hesapla
        for (var series in seriesResponse) {
          // Okları doğru şekilde alıp işle
          final List<dynamic> rawArrows = series['arrows'] ?? [];
          final List<int> arrows =
              rawArrows.map((a) => a is int ? a : (a as num).toInt()).toList();

          // Ok sayısı
          totalArrows += arrows.length;

          // Toplam skor
          int seriesScore = 0;
          if (series['total_score'] != null) {
            // Eğer total_score varsa onu kullan ve güvenli bir şekilde int'e çevir
            final numValue = series['total_score'] as num;
            seriesScore = numValue.toInt();
          } else {
            // Yoksa okların toplamını hesapla
            seriesScore = arrows.fold<int>(0, (sum, arrow) => sum + arrow);

            // Serinin kendi puanını da güncelle
            try {
              await _supabase
                  .from('training_sessions')
                  .update({'series_data': jsonEncode(seriesResponse)}).eq('id', trainingId);
            } catch (e) {
              print('Web platform: Error updating series score: $e');
            }
          }
          totalScore += seriesScore;

          // X sayısı
          int seriesXCount = 0;
          if (series['x_count'] != null) {
            // Güvenli bir şekilde int'e çevir
            final numXCount = series['x_count'] as num;
            seriesXCount = numXCount.toInt();
          } else {
            // X sayısını oklar listesinden hesapla (10 puan alan oklar)
            seriesXCount = arrows.where((arrow) => arrow == 10).length;

            // Serinin x_count değerini güncelle
            try {
              await _supabase
                  .from('training_sessions')
                  .update({'series_data': jsonEncode(seriesResponse)}).eq('id', trainingId);
            } catch (e) {
              print('Web platform: Error updating series x_count: $e');
            }
          }
          xCount += seriesXCount;
        }

        // Ortalamayı hesapla
        double average = totalArrows > 0 ? totalScore / totalArrows : 0.0;

        // Session'ı güncelle - tek bir adımda tüm değerleri gönder
        final updateData = {
          'total_arrows': totalArrows,
          'total_score': totalScore,
          'average': average,
          'x_count': xCount,
          'series_data': jsonEncode(seriesResponse), // |10n:series_data_update
        };

        await _supabase
            .from('training_sessions')
            .update(updateData)
            .eq('id', trainingId);

        print('Web platform: Calculated new totals: $updateData');

        // Double-check that our update worked by reading back the session
        try {
          final checkResult = await _supabase
              .from('training_sessions')
              .select('total_score, total_arrows, average, x_count')
              .eq('id', trainingId)
              .single();

          print(
              'Web platform: Verified update - session now has score: ${checkResult['total_score']}');
        } catch (e) {
          print('Web platform: Verification check failed: $e');
        }
      } else {
        print('Web platform: No series found for session $trainingId');
      }
    } catch (e) {
      print('Web platform: Error updating training session totals: $e');
    }
  }

  // Clear cache for a specific user
  void clearCacheForUser(String userId) {
    // Web platformunda bu işlemi atla
    if (kIsWeb) {
      print('Web platform: Cache clearing is not needed in web platform');
      return;
    }

    // Pass the request to the training history service (only for mobile)
    final trainingHistoryService = TrainingHistoryService();
    trainingHistoryService.clearCacheForAthlete(userId);
  }

  /// Soft delete a training session (ALWAYS local first)
  Future<void> deleteTrainingSession(String trainingId) async {
    try {
      // Web platformunda direkt Supabase'de soft delete yap
      if (kIsWeb) {
        print('Web platformunda soft delete yapılıyor...');
        await _supabase
            .from('training_sessions')
            .update({'is_deleted': true}).eq('id', trainingId);
        print('Soft deleted training session from Supabase: $trainingId');
        return;
      }

      // Mobil platformlarda yerel veritabanında soft delete yap
      print('Soft delete yapılıyor: $trainingId');
      await _database.softDeleteTrainingSession(trainingId);

      // Eğer antrenman Supabase'de varsa orada da soft delete yap
      if (!trainingId.startsWith('local_')) {
        final connectivityResult = await Connectivity().checkConnectivity();

        if (connectivityResult != ConnectivityResult.none) {
          try {
            // Antrenman oturumunu soft delete yap (serilere dokunmuyoruz)
            await _supabase
                .from('training_sessions')
                .update({'is_deleted': true}).eq('id', trainingId);

            print('Soft deleted training session from Supabase: $trainingId');
          } catch (e) {
            print('Error soft deleting training session from Supabase: $e');
          }
        }
      }
    } catch (e) {
      print('Error soft deleting training session: $e');
      rethrow;
    }
  }

  /// Web platformu için antrenman sonlandırma metodu
  Future<void> webFinalizeTraining(String trainingId) async {
    if (!kIsWeb) {
      // Bu metod sadece web platformunda çalışmalı
      print(
          'webFinalizeTraining mobil platformda çağrıldı, normal senkronizasyon kullanılacak');
      return syncPendingTrainingSessions();
    }

    try {
      print('Web platformu için sonlandırma başlıyor: $trainingId');

      // Antrenman oturumunun toplam değerlerini doğrudan güncelle
      final sessionResponse = await _supabase
          .from('training_sessions')
          .select('*')
          .eq('id', trainingId)
          .single();

      // Toplam değerleri serilere bakarak hesapla
      int totalArrows = 0;
      int totalScore = 0;
      int xCount = 0;

      if (sessionResponse['series_data'] != null) {
        final seriesResponse = jsonDecode(sessionResponse['series_data']);

        for (var series in seriesResponse) {
          // Okları doğru şekilde al
          List<dynamic> arrows = series['arrows'];
          totalArrows += arrows.length;

          // Toplam skoru al - güvenli bir şekilde int'e çevir
          if (series['total_score'] != null) {
            final numScore = series['total_score'] as num;
            totalScore += numScore.toInt();
          }

          // X sayısını al - güvenli bir şekilde int'e çevir
          if (series['x_count'] != null) {
            final numXCount = series['x_count'] as num;
            xCount += numXCount.toInt();
          }
        }
      }

      // Ortalamayı hesapla
      double average = totalArrows > 0 ? totalScore / totalArrows : 0.0;

      // Session'ı güncelle - tek bir adımda tüm değerleri gönder
      final updateData = {
        'total_arrows': totalArrows,
        'total_score': totalScore,
        'average': average,
        'x_count': xCount,
        'series_data': sessionResponse['series_data'], // |10n:series_data_update
      };

      await _supabase
          .from('training_sessions')
          .update(updateData)
          .eq('id', trainingId);

      print('Web platformu: Antrenman başarıyla sonlandırıldı: $trainingId');
    } catch (e) {
      print('Web platformu sonlandırma hatası: $e');
      rethrow;
    }
  }

  /// Kullanıcıya ait localde kaç antrenman kaydı olduğunu döndürür
  Future<int> localTrainingCount(String userId) async {
    if (kIsWeb) {
      // Web platformunda local cache yok, Supabase'den sayıyı al
      final sessions = await _database.webGetUserTrainingSessions(userId);
      return sessions.length;
    } else {
      final sessions = await _database.getUserTrainingSessions(userId);
      return sessions.length;
    }
  }
}
