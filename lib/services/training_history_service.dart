import '../services/supabase_config.dart';
import '../models/training_session_model.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../services/database_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:async'; // Timer için gerekli

class TrainingHistoryService {
  /// Local ve Supabase arasında çift yönlü training history senkronizasyonu
  /// - Sadece localde olup Supabase'de olmayanları Supabase'e ekler
  /// - Sadece Supabase'de olup localde olmayanları local'e ekler
  /// - Web platformunda local işlemleri atlar  // Son senkronizasyon zamanını takip etmek için
  static final Map<String, DateTime> _lastSyncTime = {};
  static const Duration _minSyncInterval = Duration(minutes: 5);
  static bool _isSyncing = false;
  static DateTime? _lastGlobalSync;
  static const Duration _globalSyncCache = Duration(minutes: 10);

  // Senkronizasyon ihtiyacını kontrol et (çok sık senkronize etmeyi önle)
  bool _shouldSync(String athleteId, {bool force = false}) {
    if (kIsWeb) return false; // Web'de local sync yok
    if (force) return true;

    if (!_lastSyncTime.containsKey(athleteId)) {
      return true; // İlk senkronizasyon
    }

    final lastSync = _lastSyncTime[athleteId]!;
    final now = DateTime.now();
    return now.difference(lastSync) > _minSyncInterval;
  }

  // Senkronizasyon sonuçları için dönüş tipi değiştirildi
  Future<Map<String, dynamic>> syncTrainingHistoryWithSupabase(String athleteId,
      {bool force = false}) async {
    final now = DateTime.now();
    if (_isSyncing) {
      debugPrint('|10n:sync_already_in_progress');
      return {
        'success': false,
        'info': 'sync_already_in_progress',
        'uploadedCount': 0,
        'downloadedCount': 0
      };
    }
    if (!force && _lastGlobalSync != null && now.difference(_lastGlobalSync!) < _globalSyncCache) {
      debugPrint('|10n:sync_skipped_due_to_cache');
      return {
        'success': true,
        'info': 'sync_skipped_due_to_cache',
        'uploadedCount': 0,
        'downloadedCount': 0
      };
    }
    _isSyncing = true;
    _lastGlobalSync = now;
    if (kIsWeb) {
      debugPrint('|10n:sync_web_only');
      return {
        'success': true,
        'info': 'web_platform_skip',
        'uploadedCount': 0,
        'downloadedCount': 0
      };
    }

    if (!force && !_shouldSync(athleteId)) {
      debugPrint('Recent sync exists, skipping (use force=true to override)');
      return {
        'success': true,
        'info': 'recent_sync_exists',
        'uploadedCount': 0,
        'downloadedCount': 0
      };
    }

    _lastSyncTime[athleteId] = DateTime.now();
    await _handleDuplicateTrainingIds(athleteId);
    try {
      // Local verileri çek
      final localTrainings = await _db.getUserTrainingSessions(athleteId);
      // Supabase verilerini çek
      final supabaseTrainingsRaw = await _supabase
          .from('training_sessions')
          .select('*')
          .eq('user_id', athleteId)
          .eq('is_deleted', false); // Soft delete edilen antrenmanları gösterme
      final supabaseTrainings =
          List<Map<String, dynamic>>.from(supabaseTrainingsRaw);

      // id setleri oluştur
      final localIds = localTrainings.map((t) => t.id).toSet();
      final supabaseIds =
          supabaseTrainings.map((t) => t['id'] as String).toSet();

      debugPrint(
          'Local trainings: ${localIds.length}, Supabase trainings: ${supabaseIds.length}'); // Yerel ve Uzak (Supabase) ID'lerin çakışıp çakışmadığını denetleyelim
      // Önce çakışma durumunu loglayalım
      for (final localSession in localTrainings) {
        if (!localSession.id.startsWith('local_') &&
            supabaseIds.contains(localSession.id)) {
          debugPrint(
              '⚠️ CONFLICT DETECTED: Session ID ${localSession.id} exists both locally and in Supabase');
        }
      }

      // Yerel ID'leri filtrele ve düzenle
      // local_ ile başlayan ID'leri her zaman eklenecek olarak işaretle
      // düzgün UUID'ler için sadece Supabase'de olmayanları ekle
      final filteredLocalIds = localTrainings.where((t) {
        if (t.id.startsWith('local_')) {
          // Yerel ID'leri daima ekle
          return true;
        } else if (supabaseIds.contains(t.id)) {
          // Uzak veritabanında zaten varsa, ekleme, upsert kullanacağız
          debugPrint(
              'Session ID ${t.id} already exists in Supabase, will use upsert');
          return true; // Upsert için dahil et
        } else {
          // Düzgün UUID'dir ve Supabase'de yok, ekle
          return true;
        }
      }).toList();

      // Sadece localde olanlar (Supabase'e eklenecek)
      final onlyLocal = filteredLocalIds;

      // Sadece Supabase'de olanlar (local'e eklenecek)
      final onlySupabase =
          supabaseTrainings.where((t) => !localIds.contains(t['id'])).toList();

      debugPrint(
          'Trainings to add to Supabase: ${onlyLocal.length}, trainings to add to local: ${onlySupabase.length}');

      // --- TOPLU EKLEME/GÜNCELLEME OPTİMİZASYONU ---
      if (onlyLocal.isNotEmpty) {
        final List<Map<String, dynamic>> sessionsToInsert = [];
        final List<Map<String, dynamic>> sessionsToUpdate = [];
        for (final session in onlyLocal) {
          final sessionData = session.toJson();
          sessionData.remove('series');
          // Eğer local ID ise (yeni kayıt), id'yi kaldır
          if (session.id.startsWith('local_')) {
            sessionData.remove('id');
            sessionsToInsert.add(sessionData);
          } else {
            sessionsToUpdate.add(sessionData);
          }
        }
        // Toplu insert (yeni kayıtlar)
        if (sessionsToInsert.isNotEmpty) {
          try {
            final response = await _supabase
                .from('training_sessions')
                .insert(sessionsToInsert)
                .select();
            // Localde id'leri güncelle
            for (int i = 0; i < response.length; i++) {
              final newId = response[i]['id'] as String?;
              final oldSession = onlyLocal[i];
              if (newId != null && newId != oldSession.id) {
                await _db.markSessionAsSynced(oldSession.id, newId);
              }
            }
          } catch (e) {
            debugPrint('|10n:sync_supabase_batch_insert_error:$e');
          }
        }
        // Toplu update (mevcut kayıtlar)
        if (sessionsToUpdate.isNotEmpty) {
          try {
            await _supabase
                .from('training_sessions')
                .upsert(sessionsToUpdate)
                .select();
          } catch (e) {
            debugPrint('|10n:sync_supabase_batch_update_error:$e');
          }
        }
      }
      // Local'e ekle
      if (onlySupabase.isNotEmpty) {
        final List<TrainingSession> sessionsToSave = [];
        for (final sessionMap in onlySupabase) {
          try {
            final session = TrainingSession.fromJson({
              ...sessionMap,
              'series': sessionMap['training_series'] ?? [],
            });
            if (session.is_deleted == true) {
              debugPrint('|10n:skip_sync_deleted:${session.id}');
              continue;
            }
            sessionsToSave.add(session);
          } catch (e) {
            debugPrint('|10n:sync_local_add_error:${sessionMap['id']}:$e');
          }
        }
        // Local DB'ye toplu ekleme (mümkünse)
        for (final session in sessionsToSave) {
          await _db.saveTrainingSession(session);
          debugPrint('|10n:sync_local_add:${session.id}');
        }
      }
      // Senkronizasyon istatistikleri
      debugPrint(
          '|10n:sync_success - Added ${onlyLocal.length} sessions to Supabase, downloaded ${onlySupabase.length} sessions');
      return {
        'success': true,
        'uploadedCount': onlyLocal.length,
        'downloadedCount': onlySupabase.length,
        'error': null
      };
    } catch (e) {
      debugPrint('|10n:sync_general_error:$e');
      return {
        'success': false,
        'uploadedCount': 0,
        'downloadedCount': 0,
        'error': e.toString()
      };
    } finally {
      _isSyncing = false;
    }
  }

  final _supabase = SupabaseConfig.client;
  final DatabaseService _db = DatabaseService();

  // Cache mekanizması için kullanılacak statik değişkenler
  static final Map<String, List<Map<String, dynamic>>> _trainingHistoryCache =
      {};
  static final Map<String, DateTime> _lastFetchTime = {};

  // Cache için geçerlilik süresi (10 dakika)
  static const Duration _cacheDuration = Duration(minutes: 10);

  // Cache'in geçerlilik süresinin dolup dolmadığını kontrol eder
  bool _isCacheValid(String cacheKey) {
    if (!_lastFetchTime.containsKey(cacheKey)) {
      return false;
    }

    final lastFetch = _lastFetchTime[cacheKey]!;
    final now = DateTime.now();
    return now.difference(lastFetch) < _cacheDuration;
  }

  // Realtime subscription için listener
  void startRealtimeSubscription(String athleteId, Function() onDataChange) {
    debugPrint('Starting realtime subscription for athlete ID: $athleteId');
    _supabase
        .from('training_sessions')
        .stream(primaryKey: ['id'])
        .eq('user_id', athleteId) // filter yerine eq kullanıyoruz
        .listen((data) {
          debugPrint(
              'Received realtime update for training sessions, athleteId: $athleteId');
          clearCacheForAthlete(athleteId);
          onDataChange();
          _syncTrainingDataToLocal(data);
        });
  }

  // Etkilenen antrenmanları yenile
  Future<void> _refreshAffectedTrainings(String athleteId,
      List<String> trainingIds, Function() onDataChange) async {
    try {
      // İlgili antrenmanları doğrudan Supabase'den çek
      final response = await _supabase
          .from('training_sessions')
          .select('*')
          .inFilter('id',
              trainingIds) // in_ yerine inFilter kullanıyoruz - Supabase PostgrestFilterBuilder'da doğru metod
          .eq('user_id', athleteId);

      if (response.isNotEmpty) {
        debugPrint('Refreshed ${response.length} affected trainings');
        final trainings = List<Map<String, dynamic>>.from(response);

        // Verileri yerel veritabanına senkronize et
        await _syncTrainingDataToLocal(trainings);

        // Cache'i temizle ve callback'i çağır
        clearCacheForAthlete(athleteId);
        onDataChange();
      }
    } catch (e) {
      debugPrint('Error refreshing affected trainings: $e');
    }
  }

  // Verileri SQLite'a senkronize et
  Future<void> _syncTrainingDataToLocal(
      List<Map<String, dynamic>> trainings) async {
    final db = await _db.database;

    await db.transaction((txn) async {
      for (var training in trainings) {
        // Silinmiş antrenmanları local DB'ye yazma
        if (training['is_deleted'] == true) {
          debugPrint('|10n:skip_sync_deleted:${training['id']}');
          continue;
        }
        debugPrint('Syncing training to local DB: ${training['id']}');

        // Önce verileri işle - tutarlı hesaplamalar için
        _processTrainingData(training);

        // Training session kaydet
        await txn.insert(
          'training_sessions',
          training,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // Hem online hem de offline mod için uygun olan temel metod
  Future<List<Map<String, dynamic>>> getAthleteTrainingHistory(
    String athleteId, {
    bool? isIndoor,
    DateTime? startDate,
    DateTime? endDate,
    bool forceRefresh = false,
  }) async {
    try {
      // Local verileri çek
      final localData = await _db.getUserTrainingSessions(athleteId);
      // Sadece silinmemiş kayıtları göster (getUserTrainingSessions zaten filtreliyor)
      var filteredLocal = localData;
      // --- INDOOR/OUTDOOR FILTER ---
      if (isIndoor != null) {
        filteredLocal = filteredLocal.where((t) => t.isIndoor == isIndoor).toList();
      }
      // Online ise Supabase'den de çek
      if (await _hasInternetConnection()) {
        final response = await _supabase
            .from('training_sessions')
            .select('*')
            .eq('user_id', athleteId)
            .eq('is_deleted', false)
            .order('date', ascending: false);
        var data = List<Map<String, dynamic>>.from(response);
        // --- INDOOR/OUTDOOR FILTER ---
        if (isIndoor != null) {
          data = data.where((t) => t['is_indoor'] == isIndoor).toList();
        }
        // Sadece silinmemiş kayıtları göster
        final filteredRemote = data.where((t) => t['is_deleted'] == false || t['is_deleted'] == 0 || t['is_deleted'] == null).toList();
        // Duplicate'leri ve eski local kayıtları filtrele
        final localIds = filteredLocal.map((t) => t.id).toSet();
        final uniqueRemote = filteredRemote.where((t) => !localIds.contains(t['id'])).toList();
        // Sonuç: local + Supabase'den gelen yeni kayıtlar (duplicate yok)
        return [...filteredLocal.map((e) => e.toJson()), ...uniqueRemote];
      } else {
        return filteredLocal.map((e) => e.toJson()).toList();
      }
    } catch (e) {
      debugPrint('Error fetching athlete training history: $e');
      return [];
    }
  }

  // Aynı antrenmana ait birden fazla versiyon varsa sadece en son güncelleneni göster
  List<Map<String, dynamic>> _filterDuplicateTrainings(
      List<Map<String, dynamic>> trainings) {
    debugPrint('Filtering ${trainings.length} trainings for duplicates');

    // Create a map to store trainings by ID - this ensures each training is only shown once
    final Map<String, Map<String, dynamic>> uniqueTrainingsById = {};

    for (var training in trainings) {
      if (training['id'] == null) continue;

      final trainingId = training['id'] as String;

      // Get updated timestamp or fall back to date
      final updatedAt = training['updated_at'] != null
          ? DateTime.parse(training['updated_at'].toString())
          : DateTime.parse(training['date'].toString());

      if (uniqueTrainingsById.containsKey(trainingId)) {
        // If we already have this training ID, keep the newer version
        final existingTraining = uniqueTrainingsById[trainingId]!;
        final existingUpdatedAt = existingTraining['updated_at'] != null
            ? DateTime.parse(existingTraining['updated_at'].toString())
            : DateTime.parse(existingTraining['date'].toString());

        if (updatedAt.isAfter(existingUpdatedAt)) {
          debugPrint('Found newer version of training ID: $trainingId');
          uniqueTrainingsById[trainingId] = training;
        }
      } else {
        // First time seeing this training ID
        uniqueTrainingsById[trainingId] = training;
      }
    }

    // Get the list of unique trainings
    final filteredTrainings = uniqueTrainingsById.values.toList();

    // Sort by date (newest first)
    filteredTrainings.sort((a, b) => DateTime.parse(b['date'].toString())
        .compareTo(DateTime.parse(a['date'].toString())));

    debugPrint(
        'After filtering, ${filteredTrainings.length} unique trainings remain');
    return filteredTrainings;
  }

  // Antrenman verilerini işleyerek tutarlı hesaplamalar yapar
  void _processTrainingData(Map<String, dynamic> training) {
    // Artık training_series kullanılmıyor, sadece ana antrenman verileri işleniyor
    // total_arrows, total_score, average gibi alanlar doğrudan kullanılacak
    // Eğer bu alanlar eksikse sıfırla
    training['total_arrows'] = training['total_arrows'] ?? 0;
    training['total_score'] = training['total_score'] ?? 0;
    training['average'] = training['average'] ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> _getLocalTrainingData(
    String athleteId,
    bool? isIndoor,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    final db = await _db.database;
    var query = '''
      SELECT * FROM training_sessions WHERE user_id = ?
    ''';
    var args = [athleteId];
    if (isIndoor != null) {
      query += ' AND is_indoor = ?';
      args.add(isIndoor ? '1' : '0');
    }
    if (startDate != null && endDate != null) {
      query += ' AND date BETWEEN ? AND ?';
      args.add(startDate.toIso8601String());
      args.add(endDate.toIso8601String());
    }
    query += ' ORDER BY date DESC';
    final results = await db.rawQuery(query, args);
    debugPrint('Retrieved ${results.length} local training records for athlete $athleteId');
    return results;
  }

  // Yerel veritabanından alınan verileri işle
  List<Map<String, dynamic>> _processLocalTrainingData(
      List<Map<String, dynamic>> results) {
    // Artık training_series yok, sadece ana antrenman verileri işleniyor
    return results.where((row) {
      // is_deleted alanı hem int hem bool hem de null olabilir
      final isDeleted = row['is_deleted'];
      return isDeleted == null || isDeleted == false || isDeleted == 0;
    }).map((row) {
      final training = {
        ...Map<String, dynamic>.from(row),
        'is_indoor': row['is_indoor'] == 1 || row['is_indoor'] == true,
        'total_arrows': row['total_arrows'] ?? 0,
        'total_score': row['total_score'] ?? 0,
        'average': row['average'] ?? 0.0,
      };
      return training;
    }).toList();
  }

  // Tüm yerel antrenman listesini işleyerek daha iyi veri tutarlılığı sağla
  List<Map<String, dynamic>> _processLocalTrainingList(
      List<Map<String, dynamic>> results) {
    // Sadece ana antrenman verileri işleniyor
    final processedList = _processLocalTrainingData(results);
    for (var training in processedList) {
      _processTrainingData(training);
    }
    return processedList;
  }

  // İnternet bağlantısını kontrol et - daha güvenilir yöntem
  Future<bool> _hasInternetConnection() async {
    try {
      // Önce connectivity_plus ile kontrol et
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      // Gerçek bağlantıyı test et
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('Internet connection check failed: $e');
      return false;
    }
  }

  // Cache key oluşturma yardımcı metodu
  String _generateCacheKey(
    String athleteId,
    bool? isIndoor,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    return '$athleteId:${isIndoor?.toString() ?? "all"}:${startDate?.toIso8601String() ?? ""}:${endDate?.toIso8601String() ?? ""}';
  }

  // Belirli bir sporcu için cache'i temizle
  void clearCacheForAthlete(String athleteId) {
    debugPrint('Clearing cache for athlete: $athleteId');
    _trainingHistoryCache.removeWhere((key, _) => key.startsWith(athleteId));
    _lastFetchTime.removeWhere((key, _) => key.startsWith(athleteId));

    // Web platformunda SQLite kullanılamaz, bu nedenle bu kısmı atlıyoruz
    if (kIsWeb) {
      debugPrint(
          'Web platform: Skipping SQLite operations in clearCacheForAthlete');
      return;
    }

    // Ayrıca sporcu verileri silinirken yerel veritabanındaki serilerini de temizle (sadece mobil platformlarda)
    _db.database.then((db) async {
      try {
        // Önce bu sporcu için olan tüm antrenman ID'lerini al
        final trainingSessions = await db.query(
          'training_sessions',
          columns: ['id'],
          where: 'user_id = ?',
          whereArgs: [athleteId],
        );

        // Her bir antrenman için serileri kontrol et ve temizle
        final trainingIds =
            trainingSessions.map((row) => row['id'] as String).toList();
        if (trainingIds.isNotEmpty) {
          debugPrint(
              'Found ${trainingIds.length} training sessions for athlete, cleaning up possible duplicate series');

          // Tüm verileri güncel duruma getirecek analitik sorgu
          for (final trainingId in trainingIds) {
            await db.execute('''
              WITH ranked_series AS (
                SELECT id, training_id, series_number, 
                ROW_NUMBER() OVER (PARTITION BY training_id, series_number ORDER BY updated_at DESC) as rn
                FROM training_series
                WHERE training_id = ?
              )
              DELETE FROM training_series 
              WHERE id IN (
                SELECT id FROM ranked_series WHERE rn > 1
              )
            ''', [trainingId]);
          }

          debugPrint(
              'Series cleanup completed for ${trainingIds.length} trainings');
        }
      } catch (e) {
        debugPrint('Error during series cleanup: $e');
      }
    });
  }

  // Tarih aralığına göre antrenman verilerini getir
  Future<List<Map<String, dynamic>>> getTrainingsInDateRange(
    String athleteId,
    DateTime startDate,
    DateTime endDate, {
    bool? isIndoor,
  }) async {
    return getAthleteTrainingHistory(
      athleteId,
      isIndoor: isIndoor,
      startDate: startDate,
      endDate: endDate,
      forceRefresh: true,
    );
  }

  // Antrenör için antrenman görüntüleme - sporcu ve antrenörün aynı verileri görmesini sağlar
  Future<List<Map<String, dynamic>>> getTrainerViewOfAthleteTrainings(
    String athleteId, {
    bool? isIndoor,
    DateTime? startDate,
    DateTime? endDate,
    bool forceRefresh =
        false, // Varsayılan değeri false, gereksiz yüklemeyi önlemek için
  }) async {
    debugPrint(
        'getTrainerViewOfAthleteTrainings: athleteId=$athleteId, isIndoor=$isIndoor, startDate=$startDate, endDate=$endDate, force=$forceRefresh');

    final cacheKey = _generateCacheKey(athleteId, isIndoor, startDate, endDate);

    // Önce cache kontrolü yap
    if (!forceRefresh &&
        _trainingHistoryCache.containsKey(cacheKey) &&
        _isCacheValid(cacheKey)) {
      debugPrint('Returning cached training data for coach view');
      // Always filter out deleted trainings from cache
      final cached = _trainingHistoryCache[cacheKey]!;
      return cached.where((training) => training['is_deleted'] != true).toList();
    }

    try {
      // Verileri al
      List<Map<String, dynamic>> trainings = await getAthleteTrainingHistory(
        athleteId,
        isIndoor: isIndoor,
        startDate: startDate,
        endDate: endDate,
        forceRefresh: forceRefresh,
      );

      // Filtreleme işlemlerini manuel olarak uygula (veritabanında doğru çalışmama ihtimaline karşı)
      if (isIndoor != null) {
        debugPrint('Manually filtering for isIndoor=$isIndoor');
        trainings = trainings
            .where((training) => (training['is_indoor'] == isIndoor))
            .toList();
      }

      if (startDate != null && endDate != null) {
        debugPrint('Manually filtering for date range: $startDate to $endDate');
        trainings = trainings.where((training) {
          final trainingDate = DateTime.parse(training['date'].toString());
          // Tarih aralığını kontrol et: startDate <= trainingDate <= endDate
          return (trainingDate.isAtSameMomentAs(startDate) ||
                  trainingDate.isAfter(startDate)) &&
              (trainingDate.isAtSameMomentAs(endDate) ||
                  trainingDate.isBefore(endDate.add(const Duration(days: 1))));
        }).toList();
      }

      debugPrint('After filtering, training count: ${trainings.length}');

      // Her antrenman için tutarlı hesaplamaları garantile
      for (var training in trainings) {
        _processTrainingData(training);
      }

      // Cache'i güncelle
      _trainingHistoryCache[cacheKey] = trainings;
      _lastFetchTime[cacheKey] = DateTime.now();

      return trainings;
    } catch (e) {
      debugPrint('Error in getTrainerViewOfAthleteTrainings: $e');

      // Hata durumunda cache'de veri varsa onu kullan
      if (_trainingHistoryCache.containsKey(cacheKey)) {
        return _trainingHistoryCache[cacheKey]!;
      }

      // Cache'de de yoksa boş liste dön
      return [];
    }
  }

  // Lokal antrenman verilerini düzeltmek için - artık _processTrainingData kullanıyor
  List<Map<String, dynamic>> _correctLocalTrainingData(
      List<Map<String, dynamic>> trainings) {
    for (var training in trainings) {
      _processTrainingData(training);
    }
    return trainings;
  }

  // Antrenör için özel realtime subscription başlatma metodu
  void startCoachRealtimeSubscription(
      String athleteId, Function() onDataChange) {
    debugPrint(
        'Starting COACH realtime subscription for athlete ID: $athleteId');

    // Web platformu için özel işlem
    if (kIsWeb) {
      debugPrint(
          'Web platform: Using polling approach for coach view of athlete data');

      // Web'de Supabase streaming sorunları için polling yaklaşımı kullan
      // İlk seferde veriyi hemen yükle
      _pollAthleteTrainingData(athleteId, onDataChange);

      // Periyodik olarak kontrol et (30 saniyede bir)
      Timer.periodic(const Duration(seconds: 30), (_) {
        _pollAthleteTrainingData(athleteId, onDataChange);
      });

      return;
    }

    // Mobil platformlar için realtime subscription kullan
    // Training sessions değişikliklerini dinle
    _supabase
        .from('training_sessions')
        .stream(primaryKey: ['id'])
        .eq('user_id', athleteId)
        .listen((data) {
          debugPrint(
              'Coach Realtime: Training session changed for athlete $athleteId');

          // Verileri yerel veritabanına senkronize et
          _syncTrainingDataToLocal(data);

          // Temizle cache'i ve callback'i çağır
          clearCacheForAthlete(athleteId);
          onDataChange();
        });
  }

  Future<void> validateSeriesArrows(String trainingId, List<int> arrows) async {
    try {
      // Get training session details including arrows_per_series
      final training = await getTrainingDetailsForCoach(trainingId);
      final arrowsPerSeries =
          training['arrows_per_series'] ?? 6; // Default to 6 if not set

      if (arrows.length != arrowsPerSeries) {
        throw Exception(
            'Her seri için tam olarak $arrowsPerSeries ok girilmelidir. Şu an ${arrows.length} ok girildi.');
      }

      // Validate arrow scores (should be between -1 and 11, where -1 and 11 represent X)
      for (final arrow in arrows) {
        if (arrow < -1 || arrow > 11) {
          throw Exception(
              'Geçersiz ok puanı: $arrow. Puanlar -1 ile 11arasına olmalıdır.');
        }
      }
    } catch (e) {
      debugPrint('Error validating series arrows: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getTrainingDetailsForCoach(
      String trainingId) async {
    if (kIsWeb) {
      // Web platformunda sadece Supabase'den veri çek
      try {
        final trainingResponse = await _supabase
            .from('training_sessions')
            .select()
            .eq('id', trainingId)
            .single();
        final training = Map<String, dynamic>.from(trainingResponse);
        _processTrainingData(training);
        return training;
      } catch (e) {
        debugPrint('Error fetching training details for coach (web): $e');
        rethrow;
      }
    }
    try {
      debugPrint('Fetching training details for coach, training ID: $trainingId');
      final db = await _db.database;
      final trainingQuery = await db.query(
        'training_sessions',
        where: 'id = ?',
        whereArgs: [trainingId],
      );
      if (trainingQuery.isEmpty) {
        debugPrint('Training not found in local database, fetching from Supabase');
        if (await _hasInternetConnection()) {
          final trainingResponse = await _supabase
              .from('training_sessions')
              .select()
              .eq('id', trainingId)
              .single();
          final training = Map<String, dynamic>.from(trainingResponse);
          _processTrainingData(training);
          await _syncTrainingDataToLocal([training]);
          return training;
        } else {
          throw Exception('Antrenman verisi bulunamadı ve internet bağlantısı yok');
        }
      }
      final training = Map<String, dynamic>.from(trainingQuery.first);
      training['is_indoor'] = training['is_indoor'] == 1;
      _processTrainingData(training);
      if (await _hasInternetConnection()) {
        _refreshTrainingInBackground(trainingId);
      }
      return training;
    } catch (e) {
      debugPrint('Error fetching training details for coach: $e');
      rethrow;
    }
  }

  // Refresh training data in background without blocking
  Future<void> _refreshTrainingInBackground(String trainingId) async {
    try {
      final trainingResponse = await _supabase
          .from('training_sessions')
          .select()
          .eq('id', trainingId)
          .single();

      final training = Map<String, dynamic>.from(trainingResponse);

      // Process and save to local database
      _processTrainingData(training);
      await _syncTrainingDataToLocal([training]);

      debugPrint('Training $trainingId refreshed in background');
    } catch (e) {
      debugPrint('Background refresh error: $e');
    }
  }

  // Antrenman verilerinin hash değerini oluştur - verilerde değişiklik kontrolü için
  String _generateTrainingDataHash(
      List<Map<String, dynamic>> trainingSessions) {
    // Basit bir hash - tüm eğitim ID'lerini ve updated_at değerlerini birleştir
    final buffer = StringBuffer();

    // ID'leri ve son güncelleme zamanlarını sırala ve birleştir
    final items = [];
    for (final training in trainingSessions) {
      final id = training['id'] as String;
      final updatedAt = training['updated_at'] ?? training['date'] ?? '';
      items.add('$id:$updatedAt');
    }

    // Hash değerini oluştur
    items.sort(); // Sıralama ile tutarlılık sağla
    buffer.writeAll(items, ',');
    return buffer.toString();
  }

  // Son eğitim verileri hash değerlerini sakla
  final Map<String, String> _lastTrainingDataHashes = {};

  // Web platformu için polling yaklaşımı - Realtime subscription'ların yerine kullanılır
  Future<void> _pollAthleteTrainingData(
      String athleteId, Function() onDataChange) async {
    try {
      debugPrint('Web platform: Polling training data for athlete $athleteId');

      // Direkt olarak Supabase'den verileri çek
      final response = await _supabase
          .from('training_sessions')
          .select('*')
          .eq('user_id', athleteId)
          .order('date', ascending: false);

      final data = List<Map<String, dynamic>>.from(response);

      // Verilerin hash değerini oluştur
      final newDataHash = _generateTrainingDataHash(data);
      final lastHash = _lastTrainingDataHashes[athleteId];

      // Veriler değiştiyse veya ilk kez alınıyorsa işle
      if (lastHash == null || newDataHash != lastHash) {
        debugPrint('Web platform: Training data changed, updating UI');

        // Hash'i güncelle
        _lastTrainingDataHashes[athleteId] = newDataHash;

        debugPrint(
            'Web platform: Retrieved ${data.length} training sessions for athlete');

        // Verileri işle
        for (var training in data) {
          _processTrainingData(training);
        }

        // Web platformu için memory cache'i güncelle
        final cacheKey = _generateCacheKey(athleteId, null, null, null);
        _trainingHistoryCache[cacheKey] = data;
        _lastFetchTime[cacheKey] = DateTime.now();

        // Callback'i çağır - UI'ı güncellemek için
        onDataChange();
      } else {
        debugPrint(
            'Web platform: No changes detected in training data, skipping update');
      }
    } catch (e) {
      debugPrint('Web platform: Error polling training data: $e');
    }
  }

  // Duplicate Session ID hataları için özel fonksiyon
  // Bu fonksiyon aynı ID'ye sahip ancak içeriği farklı olan kayıtları isimleri değiştirerek çözer
  Future<void> _handleDuplicateTrainingIds(String athleteId) async {
    try {
      debugPrint('Checking for duplicate training IDs...');
      // Yerel ve Supabase verilerini al
      final localTrainings = await _db.getUserTrainingSessions(athleteId);
      final supabaseResponse = await _supabase
          .from('training_sessions')
          .select('id')
          .eq('user_id', athleteId);

      final supabaseIds = (supabaseResponse as List)
          .map((item) => item['id'] as String)
          .toSet();

      // Çakışmaları kontrol et (düzgün UUID var ve Supabase'de de var)
      final duplicateIds = localTrainings
          .where((t) =>
              !t.id.startsWith('local_') && // Yerel ID değil
              supabaseIds.contains(t.id)) // Ama Supabase'de de var
          .map((t) => t.id)
          .toSet();

      if (duplicateIds.isNotEmpty) {
        debugPrint('Found ${duplicateIds.length} duplicate training IDs!');

        // Çakışan her kayıt için lokal ID'yi değiştir (local_ önek ekle)
        for (final id in duplicateIds) {
          try {
            final newId = 'local_${DateTime.now().millisecondsSinceEpoch}_$id';
            debugPrint('Updating duplicate ID $id to $newId in local database');

            // Veritabanında ID değiştir (renaming) - markSessionAsSynced ile ID'yi değiştir
            await _db.markSessionAsSynced(id, newId);
          } catch (e) {
            debugPrint('Error renaming duplicate ID $id: $e');
          }
        }
      } else {
        debugPrint('No duplicate training IDs found.');
      }
    } catch (e) {
      debugPrint('Error handling duplicate training IDs: $e');
    }
  }

  // Yerel veritabanındaki antrenman oturumlarını görüntülemek için yardımcı fonksiyon
  Future<List<Map<String, dynamic>>> showLocalTrainingSessions(
      String userId) async {
    try {
      final db = await _db.database;

      // Antrenman oturumlarını al
      final sessions = await db.query('training_sessions',
          where: 'user_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [userId],
          orderBy: 'date DESC');

      // Her oturum için serileri al ve birleştir
      final result = <Map<String, dynamic>>[];

      for (final session in sessions) {
        result.add({
          ...session,
          'series_count': 0,
          'id_type': session['id'].toString().startsWith('local_')
              ? 'local'
              : 'remote',
          'sync_status': session['pending_sync'] == 1 ? 'pending' : 'synced',
        });
      }

      debugPrint(
          'Found ${result.length} local training sessions for user $userId');
      return result;
    } catch (e) {
      debugPrint('Error showing local training sessions: $e');
      return [];
    }
  }

  /// Manuel olarak tüm antrenman verilerini senkronize eder
  ///
  /// `userId`: Senkronize edilecek kullanıcının ID'si
  ///
  /// Dönüş Değeri: İşlem sonucu ve istatistikler
  Future<Map<String, dynamic>> manualSyncTrainingData(String userId) async {
    // Manuel senkronizasyonda her zaman force=true kullan
    return await syncTrainingHistoryWithSupabase(userId, force: true);
  }

  /// Sadece tek bir antrenman oturumunu senkronize eder
  ///
  /// `trainingId`: Senkronize edilecek antrenmanın ID'si
  /// Dönüş Değeri: Başarılı olursa true, başarısız olursa false döner
  Future<bool> syncSingleTrainingSession(String trainingId) async {
    try {
      // Eğer ID local_ ile başlıyorsa veya boşsa, toplu sync tetikle ve çık
      if (trainingId.isEmpty || trainingId.startsWith('local_')) {
        debugPrint('Single sync: Skipping invalid or local ID ($trainingId), triggering batch sync instead.');
        await syncTrainingHistoryWithSupabase(await _getCurrentUserId(), force: true);
        return false;
      }
      final db = await _db.database;
      // Antrenmanı localden al
      final sessions = await db.query(
        'training_sessions',
        where: 'id = ?',
        whereArgs: [trainingId],
      );
      if (sessions.isEmpty) {
        debugPrint('No local session found with id: $trainingId');
        return false;
      }
      final session = sessions.first;
      // --- Zero-arrow session kontrolü ---
      if (session['series_data'] == null || session['series_data'].toString().isEmpty) {
        debugPrint('Single sync: Skipping session with zero arrows: $trainingId');
        return false;
      }
      // Supabase'de var mı kontrol et
      final existing = await _supabase
          .from('training_sessions')
          .select('id')
          .eq('id', trainingId)
          .maybeSingle();
      if (existing == null) {
        // Yoksa ekle
        final insertResponse = await _supabase
            .from('training_sessions')
            .insert(session)
            .select();
        if (insertResponse.isNotEmpty) {
          final newId = insertResponse[0]['id'];
          if (newId != null && newId != trainingId) {
            await _db.markSessionAsSynced(trainingId, newId);
          }
          return true;
        }
      } else {
        // Varsa güncelle
        await _supabase
            .from('training_sessions')
            .update(session)
            .eq('id', trainingId);
        return true;
      }
    } catch (e) {
      debugPrint('Error syncing single session: $e');
    }
    return false;
  }

  // Kullanıcı ID'sini almak için yardımcı fonksiyon (gerekirse)
  Future<String> _getCurrentUserId() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) return user.id;
    } catch (_) {}
    return '';
  }
}
