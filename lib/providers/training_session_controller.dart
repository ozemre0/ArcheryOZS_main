import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/training_session_model.dart';
// import '../models/training_series_model.dart'; // Artık kullanılmayan model kaldırıldı
import 'dart:convert'; // JSON encode/decode için
import '../services/training_repository.dart';
import '../services/training_history_service.dart';
import '../services/training_sync_service.dart';
import '../services/supabase_config.dart';
import '../services/database_service.dart';
import 'package:uuid/uuid.dart';
import 'training_sync_provider.dart';
import 'training_history_controller.dart';

// Antrenman oturumu için durum sınıfı
class TrainingSessionState {
  final TrainingSession? session;
  final List<int> currentArrows;
  final int currentSeriesNumber;
  final bool isLoading;
  final String? error;
  final bool isEditing; // Düzenleme modunda olup olmadığını kontrol etmek için
  final List<Map<String, dynamic>> localSeries; // Locally stored series as Map<String, dynamic>
  final bool isDirty; // Flag to track if there are unsaved changes

  TrainingSessionState({
    this.session,
    required this.currentArrows,
    required this.currentSeriesNumber,
    required this.isLoading,
    this.error,
    this.isEditing = false,
    this.localSeries = const [],
    this.isDirty = false,
  });

  // Başlangıç durumu
  factory TrainingSessionState.initial() {
    return TrainingSessionState(
      session: null,
      currentArrows: [],
      currentSeriesNumber: 1,
      isLoading: false,
      error: null,
      isEditing: false,
      localSeries: [],
      isDirty: false,
    );
  }

  TrainingSessionState copyWith({
    TrainingSession? session,
    List<int>? currentArrows,
    int? currentSeriesNumber,
    bool? isLoading,
    String? error,
    bool? isEditing,
    List<Map<String, dynamic>>? localSeries,
    bool? isDirty,
  }) {
    return TrainingSessionState(
      session: session ?? this.session,
      currentArrows: currentArrows ?? this.currentArrows,
      currentSeriesNumber: currentSeriesNumber ?? this.currentSeriesNumber,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isEditing: isEditing ?? this.isEditing,
      localSeries: localSeries ?? this.localSeries,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}

class TrainingSessionController extends StateNotifier<TrainingSessionState> {
  final TrainingRepository _repository;
  final TrainingSyncService _syncService;
  final Ref _ref;
  final _supabase = SupabaseConfig.client;
  final _trainingHistoryService = TrainingHistoryService();
  final _databaseService = DatabaseService();
  final uuid = const Uuid();

  TrainingSessionController(this._repository, this._syncService, this._ref)
      : super(TrainingSessionState.initial());

  // JSON verileri işlemek için yardımcı fonksiyonlar
  
  // Serileri JSON string olarak encode eden yardımcı fonksiyon
  String encodeSeriesDataAsJson(List<Map<String, dynamic>> seriesList) {
    final simplified = seriesList.map((s) => [s['seriesNumber'], s['arrows']]).toList();
    return jsonEncode(simplified);
  }

  // JSON string'i serilere decode eden yardımcı fonksiyon
  List<Map<String, dynamic>> decodeSeriesDataFromJson(String? seriesData) {
    if (seriesData == null || seriesData.isEmpty) return [];
    try {
      final decoded = jsonDecode(seriesData);
      if (decoded is List) {
        return decoded.map<Map<String, dynamic>>((e) => {
          'seriesNumber': e[0],
          'arrows': List<int>.from(e[1])
        }).toList();
      } else {
        return [];
      }
    } catch (e) {
      print('Error decoding seriesData: $e');
      return [];
    }
  }
  
  // Bir Map<String, dynamic> objesi oluştur (TrainingSeries modelinin yerini alan)
  Map<String, dynamic> createSeriesMap({
    required String id,
    required String trainingId,
    required int seriesNumber,
    required List<int> arrows,
  }) {
    // Toplam puanı ve X sayısını hesapla
    int totalScore = arrows.fold(0, (sum, score) => sum + score);
    int xCount = arrows.where((score) => score == 11).length;
    
    return {
      'id': id,
      'trainingId': trainingId,
      'seriesNumber': seriesNumber,
      'arrows': arrows,
      'totalScore': totalScore,
      'xCount': xCount,
    };
  }

  // Yeni bir antrenman oturumu başlat
  Future<void> initSession({
    required String userId,
    required int distance,
    required String bowType,
    required bool isIndoor,
    String? notes,
    String? training_session_name,
    String trainingType = 'score',
    required int arrowsPerSeries,
    int seriesCount = 1,
    DateTime? date,
  }) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      print('Initializing new training session for user: $userId');

      // STEP 1: Verify database connection with a simple check
      await _repository.verifyDatabaseConnection();

      // STEP 2: Create session with robust error handling
      // Yeni algoritma: Boş bir seri JSON string'i ile başlat
      if (trainingType == 'technique') {
        // Teknik antrenman için skor/seri/puan alanlarını null/boş bırak
        await _repository.createTrainingSession(
          userId: userId,
          date: date ?? DateTime.now(),
          distance: distance,
          bowType: bowType,
          isIndoor: isIndoor,
          notes: notes,
          training_session_name: training_session_name,
          trainingType: trainingType,
          arrowsPerSeries: arrowsPerSeries,
          seriesCount: seriesCount,
          seriesData: null,
        );
        return;
      }
      final session = await _repository.createTrainingSession(
        userId: userId,
        date: date ?? DateTime.now(),
        distance: distance,
        bowType: bowType,
        isIndoor: isIndoor,
        notes: notes,
        training_session_name: training_session_name,
        trainingType: trainingType,
        arrowsPerSeries: arrowsPerSeries,
        seriesData: '[]', // Boş JSON array
      );

      print('Created new training session with ID: ${session.id}');

      // Web platformunda SQLite olmadığı için farklı bir yaklaşım kullanıyoruz
      if (kIsWeb) {
        try {
          print('Loading session in web platform: ${session.id}');

          // Web platformunda Supabase'in yazma işlemini tamamlaması için kısa bir bekleme ekle
          await Future.delayed(const Duration(milliseconds: 500));

          // Birkaç deneme yapalım - Supabase'in yazma işlemini tamamlaması bazen zaman alabilir
          TrainingSession? verifiedSession;
          int retryCount = 0;
          const maxRetries = 3;

          while (retryCount < maxRetries) {
            try {
              verifiedSession = await _repository.getTrainingSession(session.id);
              break; // Başarılı olduk, döngüden çık
            } catch (e) {
              print('Retry ${retryCount + 1} failed: $e');
            }

            // Biraz daha bekle ve tekrar dene
            await Future.delayed(Duration(milliseconds: 300 * (retryCount + 1)));
            retryCount++;
          }

          // Eğer hiçbir şekilde session bulunamadıysa, doğrudan session'ı kullan
          if (verifiedSession == null) {
            print('Could not verify session after $maxRetries retries, using original session');
            verifiedSession = session;
          }

          state = state.copyWith(
            session: verifiedSession,
            currentArrows: [],
            currentSeriesNumber: 1,
            isLoading: false,
            localSeries: [],
            isDirty: false,
          );
          return;
        } catch (webError) {
          print('Web platform session verification failed after retries: $webError');

          // Hata durumunda orijinal session objesiyle devam edelim
          print('Using original session object as fallback');
          state = state.copyWith(
            session: session,
            currentArrows: [],
            currentSeriesNumber: 1,
            isLoading: false,
            localSeries: [],
            isDirty: false,
          );
          return;
        }
      }

      // Aşağıdaki kod mobil platformlar için çalışır - SQLite kullanır
      // STEP 3: Create an initialization series to ensure the session exists
      // Başlangıç serisi oluştur
      final dummySeriesData = createSeriesMap(
        id: 'init_${uuid.v4()}',
        trainingId: session.id,
        seriesNumber: 0, // 0 numaralı seri başlangıç serisi olarak işaretlenir
        arrows: [10], // Test amaçlı bir ok
      );

      // JSON veri olarak seri kaydı
      List<Map<String, dynamic>> seriesDataList = [dummySeriesData];
      final jsonSeriesData = encodeSeriesDataAsJson(seriesDataList);
      
      // İlk session'ı seriesData ile güncelle
      final sessionWithData = session.copyWith(seriesData: jsonSeriesData);
      
      try {
        // Session'ı kaydet
        if (kIsWeb) {
          await _databaseService.webSaveTrainingSession(sessionWithData);
        } else {
          await _databaseService.saveTrainingSession(sessionWithData);
        }
        print('Session saved with initialization data: ${session.id}');
        
        // Session'ı yeniden yükle
        final verifiedSession = await _repository.getTrainingSession(session.id);
        print('Session verified successfully: ${verifiedSession.id}');
        
        // Başlangıç serisini kaldır
        final updatedSeriesData = decodeSeriesDataFromJson(verifiedSession.seriesData)
            .where((s) => (s['seriesNumber'] as int? ?? 0) != 0)
            .toList();
        
        final verifiedSessionNoInit = verifiedSession.copyWith(
            seriesData: encodeSeriesDataAsJson(updatedSeriesData)
        );
        
        // Güncellenmiş session'ı kaydet
        if (kIsWeb) {
          await _databaseService.webSaveTrainingSession(verifiedSessionNoInit);
        } else {
          await _databaseService.saveTrainingSession(verifiedSessionNoInit);
        }
        
        // State'i güncelle
        state = state.copyWith(
          session: verifiedSessionNoInit,
          currentArrows: [],
          currentSeriesNumber: 1,
          isLoading: false,
          localSeries: [],
          isDirty: false,
        );
      } catch (verifyError) {
        print('⚠️ Session verification failed: $verifyError');
        
        // Oturumu düzeltmeyi dene
        try {
          print('Attempting to repair session...');
          // await _repository.forceCreateSession(session);
          
          final repairedSession = await _repository.getTrainingSession(session.id);
          print('Session repaired successfully: ${repairedSession.id}');
          
          state = state.copyWith(
            session: repairedSession,
            currentArrows: [],
            currentSeriesNumber: 1,
            isLoading: false,
            localSeries: [],
            isDirty: false,
          );
        } catch (repairError) {
          print('❌ Session repair failed: $repairError');
          throw Exception('Oturum oluşturulamadı: $repairError');
        }
      }
    } catch (e) {
      print('ERROR initializing session: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Antrenman oturumu oluşturulamadı: ${e.toString()}',
      );
    }
  }

  // Ok skorunu kaydet
  void recordArrow(int score) {
    final currentArrows = [...state.currentArrows, score];
    state = state.copyWith(currentArrows: currentArrows, isDirty: true);
  }

  // Mevcut seriyi tamamla ve bir sonraki seriyi başlat
  Future<void> completeCurrentSeries({required int arrowsPerSeries}) async {
    if (state.session == null) return;

    // Ok sayısı kontrolü
    if (state.currentArrows.length != arrowsPerSeries) {
      state = state.copyWith(
        error: 'Seri tamamlanamadı: $arrowsPerSeries ok atılması gerekiyor',
      );
      return;
    }

    try {
      // Set loading only in edit mode
      if (state.isEditing) {
        state = state.copyWith(isLoading: true, error: null);
      }

      // seriesData'dan serileri al
      List<Map<String, dynamic>> seriesDataList = [];
      if (state.session?.seriesData != null) {
        seriesDataList = decodeSeriesDataFromJson(state.session!.seriesData);
      }
      
      // Düzenleme modu için mevcut seriyi bul
      var localSeriesList = [...state.localSeries]; // Local series copy
      
      if (state.isEditing) {
        // Düzenleme modunda, seriesData'dan veya localSeries'den mevcut seriyi bul
        final existingSeriesIndex = seriesDataList.indexWhere(
          (s) => s['seriesNumber'] == state.currentSeriesNumber
        );
        
        // Eğer seriesData içinde varsa
        if (existingSeriesIndex >= 0) {
          // Mevcut seriyi güncelle
          final existingSeries = seriesDataList[existingSeriesIndex];
          final updatedSeries = createSeriesMap(
            id: (existingSeries['id'] ?? 'local_${state.currentSeriesNumber}').toString(), // Null id fallback
            trainingId: state.session!.id,
            seriesNumber: state.currentSeriesNumber,
            arrows: [...state.currentArrows],
          );
          
          // Lokal olarak sakla
          localSeriesList = localSeriesList.where(
            (s) => s['seriesNumber'] != state.currentSeriesNumber
          ).toList()..add(updatedSeries);
        } else {
          // Lokal serilerde ara
          final localSeriesIndex = localSeriesList.indexWhere(
            (s) => s['seriesNumber'] == state.currentSeriesNumber
          );
          
          if (localSeriesIndex >= 0) {
            // Lokal seriyi güncelle
            final existingSeries = localSeriesList[localSeriesIndex];
            final updatedSeries = createSeriesMap(
              id: (existingSeries['id'] ?? 'local_${state.currentSeriesNumber}').toString(), // Null id fallback
              trainingId: state.session!.id,
              seriesNumber: state.currentSeriesNumber,
              arrows: [...state.currentArrows],
            );
            
            // Lokal listeyi güncelle
            localSeriesList.removeAt(localSeriesIndex);
            localSeriesList.add(updatedSeries);
          } else {
            // Mevcut seri bulunamadı, yeni bir seri oluştur
            final newSeries = createSeriesMap(
              id: 'local_${uuid.v4()}',
              trainingId: state.session!.id,
              seriesNumber: state.currentSeriesNumber,
              arrows: [...state.currentArrows],
            );
            
            localSeriesList.add(newSeries);
          }
        }
      } else {
        // Normal mod - yeni bir local seri oluştur
        final newSeries = createSeriesMap(
          id: 'local_${uuid.v4()}',
          trainingId: state.session!.id,
          seriesNumber: state.currentSeriesNumber,
          arrows: [...state.currentArrows],
        );
        
        localSeriesList.add(newSeries);
      }
      
      // Bir sonraki seri numarasını belirle
      int nextSeriesNumber;
      if (state.isEditing) {
        // Tüm serileri birleştir
        final allSeries = [...seriesDataList, ...localSeriesList];
        
        // En yüksek seri numarasını bul
        if (allSeries.isEmpty) {
          nextSeriesNumber = 1;
        } else {
          final seriesNumbers = allSeries.map((s) => s['seriesNumber'] as int? ?? 0).toList();
          nextSeriesNumber = seriesNumbers.reduce((a, b) => a > b ? a : b) + 1;
        }
      } else {
        // Normal mod - bir sonraki seri
        nextSeriesNumber = state.currentSeriesNumber + 1;
      }

      // State güncelle
      state = state.copyWith(
        currentArrows: [],
        currentSeriesNumber: nextSeriesNumber,
        isLoading: false,
        isEditing: false,
        localSeries: localSeriesList,
        isDirty: true, // Kaydedilmemiş değişiklikler var
      );
      
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Seri kaydedilemedi: ${e.toString()}',
      );
    }
  }

  // Tüm yerel değişiklikleri veritabanına kaydet
  Future<void> saveTrainingToDatabase() async {
    if (state.session == null) return;
    
    // Eğer kaydetmek için hiç seri yoksa ve mevcut oklar da yoksa, boş antrenman kaydetmeyi engelle
    final seriesDataList = decodeSeriesDataFromJson(state.session!.seriesData);
    if (seriesDataList.isEmpty && state.localSeries.isEmpty && state.currentArrows.isEmpty) {
      print('No series to save');
      return;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);
      
      // seriesData ve localSeries'i birleştir
      final allSeries = [...seriesDataList, ...state.localSeries];
      
      // Seri numaralarına göre birleştir (aynı numaraya sahip serilerin sonuncusunu kullan)
      final Map<int, Map<String, dynamic>> uniqueSeriesByNumber = {};
      
      for (var series in allSeries) {
        final seriesNumber = series['seriesNumber'] as int? ?? 0;
        if (seriesNumber > 0) { // Sıfır seri numaralarını atla (başlangıç serileri)
          uniqueSeriesByNumber[seriesNumber] = series;
        }
      }
      
      // Birleştirilmiş serileri liste haline getir
      final mergedSeries = uniqueSeriesByNumber.values.toList();
      
      // JSON olarak encode et
      final jsonSeriesData = encodeSeriesDataAsJson(mergedSeries);
      
      print('Training update: Saving ${mergedSeries.length} series to training session ${state.session!.id}');
      
      // Session'ı güncelle
      final updatedSession = state.session!.copyWith(seriesData: jsonSeriesData);
      
      // --- WEB PLATFORMU: Doğrudan Supabase'e kaydet ---
      if (kIsWeb) {
        try {
          // Supabase'e kaydet
          await _databaseService.webSaveTrainingSession(updatedSession);
          
          // Güncel session'ı al
          final latestSession = await _repository.getTrainingSession(state.session!.id);
          
          // State'i güncelle
          state = state.copyWith(
            session: latestSession,
            localSeries: [], // Lokal serileri temizle
            isDirty: false, // Değişiklikler kaydedildi
            isLoading: false,
          );
          
          print('Web sync success');
          return;
        } catch (e) {
          print('Web sync error: $e');
          state = state.copyWith(
            isLoading: false,
            error: 'Web sync error: $e',
          );
          return;
        }
      }
      
      // --- MOBİL PLATFORMLAR: SQLite'a kaydet ---
      // Session'ı SQLite'a kaydet - yeni bir antrenman oluşturmak yerine mevcut antrenmanı güncelle
      await _databaseService.saveTrainingSession(updatedSession);
      
      // Güncel session'ı al
      final latestSession = await _repository.getTrainingSession(state.session!.id);
      
      // Senkronizasyon yap
      try {
        if (state.localSeries.isNotEmpty) {
          // Eğer oturum zaten Supabase'de kaydedilmişse, anında senkronize et
          if (!latestSession.id.startsWith('local_')) {
            print('Training update detected, syncing...');
            await _syncService.syncTrainingSession(latestSession);
          } else {
            // Henüz Supabase'e kaydedilmemiş, sadece bu antrenmanı syncle
            print('Local training, syncing only this session...');
            await _trainingHistoryService.syncSingleTrainingSession(latestSession.id);
          }
        }
      } catch (syncError) {
        print('Warning: Sync error: $syncError');
        // Senkronizasyon hatası state'i etkilememeli, bu sadece bir uyarı
      }
      
      // State'i güncelle
      state = state.copyWith(
        session: latestSession,
        localSeries: [], // Lokal serileri temizle
        isDirty: false, // Değişiklikler kaydedildi
        isLoading: false,
      );
      
      print('Training data saved successfully');
    } catch (e) {
      print('Error saving training data: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Antrenman verisi kaydedilemedi: $e',
      );
    }
  }

  // Reset current series
  void resetCurrentSeries() {
    if (state.session != null) {
      state = state.copyWith(currentArrows: [], isEditing: false);
    }
  }

  // Undo last arrow
  void undoLastArrow() {
    if (state.currentArrows.isNotEmpty) {
      final updatedArrows = [...state.currentArrows];
      updatedArrows.removeLast();
      state = state.copyWith(currentArrows: updatedArrows);
    }
  }

  // End session and clean up
  Future<void> endSession({bool forceDelete = false, bool saveChanges = false}) async {
    // Önce kaydedilmemiş değişiklikleri kaydet
    if (state.isDirty && !forceDelete && state.session != null && saveChanges) {
      await saveTrainingToDatabase();
    }

    // Sadece zorunlu silme (forceDelete) durumunda sil
    if (state.session != null && forceDelete) {
      print('Antrenman zorla siliniyor: ${state.session!.id}');
      await _repository.deleteTrainingSession(state.session!.id);
    }
    // "Kaydetmeden Çık" durumu: Sadece eğer hiç kaydedilmiş seri yoksa antrenmanı sil
    else if (state.session != null && !saveChanges) {
      // seriesData'dan serileri al
      final seriesDataList = decodeSeriesDataFromJson(state.session!.seriesData);
      final savedSeries = seriesDataList.where((s) => (s['seriesNumber'] as int? ?? 0) > 0).toList();
      
      if (savedSeries.isEmpty) {
        // Eğer kaydedilmiş seri yoksa, tüm antrenmanı sil
        print('No saved series, deleting training: ${state.session!.id}');
        await _repository.deleteTrainingSession(state.session!.id);
      } else {
        // Kaydedilmiş seriler var, sadece kaydedilmemiş lokal serileri temizle
        print('There are saved series, only clearing local series');
      }
    }
    // Sadece saveChanges=true ise ve boş antrenman değilse sakla
    else if (state.session != null && saveChanges) {
      final seriesDataList = decodeSeriesDataFromJson(state.session!.seriesData);
      
      if (!(seriesDataList.isEmpty && state.currentArrows.isEmpty && state.localSeries.isEmpty)) {
        print('Training saved, will be kept: ${state.session!.id}');
      } else {
        print('Empty training, deleting: ${state.session!.id}');
        await _repository.deleteTrainingSession(state.session!.id);
      }
    }

    state = TrainingSessionState.initial();
  }

  // Load an existing session
  Future<void> loadSession(String trainingId) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      // Oturumu yükle
      var session = await _repository.getTrainingSession(trainingId).catchError((e) {
        throw 'Antrenman oturumu bulunamadı. Oturum silinmiş olabilir.';
      });

      // seriesData'dan serileri al
      final seriesDataList = decodeSeriesDataFromJson(session.seriesData);
      
      // Seri numaralarını kontrol et
      int nextSeriesNumber = 1;
      if (seriesDataList.isNotEmpty) {
        // En yüksek seri numarasını bul
        final seriesNumbers = seriesDataList
            .map((s) => s['seriesNumber'] as int? ?? 0)
            .where((n) => n > 0) // Başlangıç serilerini atla
            .toList();
            
        if (seriesNumbers.isNotEmpty) {
          nextSeriesNumber = seriesNumbers.reduce((a, b) => a > b ? a : b) + 1;
        }
      }

      // Eğer mevcut seri varsa, ilk serinin ok sayısına göre arrows_per_series'i ayarla
      if (seriesDataList.isNotEmpty) {
        // Serileri sırala
        seriesDataList.sort((a, b) => 
          (a['seriesNumber'] as int? ?? 0).compareTo(b['seriesNumber'] as int? ?? 0)
        );
        
        // İlk gerçek seriyi bul (seriesNumber > 0)
        Map<String, dynamic>? firstRealSeries;
        for (var s in seriesDataList) {
          if ((s['seriesNumber'] as int? ?? 0) > 0) {
            firstRealSeries = s;
            break;
          }
        }
        
        if (firstRealSeries != null && (firstRealSeries['arrows'] as List?)?.isNotEmpty == true) {
          // İlk gerçek serinin ok sayısını arrows_per_series olarak belirle
          final arrows = firstRealSeries['arrows'] as List?;
          final arrowCount = arrows?.length ?? 3;
          
          print('İlk seriden alınan ok sayısı: $arrowCount');
          
          // Antrenman modelini güncelle
          session = session.copyWith(arrowsPerSeries: arrowCount);
        }
      }

      state = state.copyWith(
        session: session,
        currentArrows: [],
        currentSeriesNumber: nextSeriesNumber,
        isLoading: false,
        localSeries: [],
        isDirty: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        session: null,
        error: 'Antrenman oturumu yüklenemedi: ${e.toString()}',
      );
    }
  }

  // Load a series for editing
  Future<void> loadSeriesForEditing(String seriesId, List<int> arrows, int seriesNumber) async {
    List<int> adjustedArrows = [...arrows];

    state = state.copyWith(
      currentArrows: adjustedArrows,
      currentSeriesNumber: seriesNumber,
      isLoading: false,
      error: null,
      isEditing: true,
    );
  }

  // Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  // Navigate to previous series
  void goToPreviousSeries() {
    if (state.currentSeriesNumber > 1) {
      state = state.copyWith(
        currentSeriesNumber: state.currentSeriesNumber - 1,
      );
    }
  }

  // Navigate to next series
  void goToNextSeries() {
    final totalSeries = combinedSeries.length + 1; // Tamamlanan + mevcut seri
    if (state.currentSeriesNumber < totalSeries) {
      state = state.copyWith(
        currentSeriesNumber: state.currentSeriesNumber + 1,
      );
    }
  }

  // Undo arrow from specific series (for past series editing)
  void undoArrowFromSeries(int seriesNumber) {
    // Geçmiş serilerden son oku geri al
    final updatedLocalSeries = [...state.localSeries];
    
    // İlgili seriyi bul
    final seriesIndex = updatedLocalSeries.indexWhere((s) => s['seriesNumber'] == seriesNumber);
    
    if (seriesIndex != -1) {
      final series = updatedLocalSeries[seriesIndex];
      final arrows = List<int>.from(series['arrows'] ?? []);
      
      if (arrows.isNotEmpty) {
        // Son oku kaldır
        arrows.removeLast();
        
        // Seriyi güncelle
        final updatedSeries = Map<String, dynamic>.from(series);
        updatedSeries['arrows'] = arrows;
        updatedSeries['totalScore'] = arrows.fold<int>(0, (sum, score) => sum + score);
        
        updatedLocalSeries[seriesIndex] = updatedSeries;
        
        state = state.copyWith(
          localSeries: updatedLocalSeries,
          isDirty: true,
        );
      }
    }
  }

  // Add arrow to specific series (for past series editing)
  void addArrowToSeries(int seriesNumber, int score) {
    final updatedLocalSeries = [...state.localSeries];
    
    // İlgili seriyi bul
    final seriesIndex = updatedLocalSeries.indexWhere((s) => s['seriesNumber'] == seriesNumber);
    
    if (seriesIndex != -1) {
      final series = updatedLocalSeries[seriesIndex];
      final arrows = List<int>.from(series['arrows'] ?? []);
      
      // Yeni oku ekle
      arrows.add(score);
      
      // Seriyi güncelle
      final updatedSeries = Map<String, dynamic>.from(series);
      updatedSeries['arrows'] = arrows;
      updatedSeries['totalScore'] = arrows.fold<int>(0, (sum, score) => sum + score);
      
      updatedLocalSeries[seriesIndex] = updatedSeries;
      
      state = state.copyWith(
        localSeries: updatedLocalSeries,
        isDirty: true,
      );
    }
  }

  // Get combined series (from database and local)
  List<Map<String, dynamic>> get combinedSeries {
    if (state.session == null) return [];

    // seriesData'dan serileri al
    final seriesDataList = decodeSeriesDataFromJson(state.session!.seriesData);
    
    // Seri numaralarına göre benzersiz seri map'i oluştur
    final Map<int, Map<String, dynamic>> combinedMap = {};
    
    // Önce seriesData'dan gelen serileri ekle (başlangıç serilerini atla)
    for (var series in seriesDataList) {
      final seriesNumber = series['seriesNumber'] as int? ?? 0;
      if (seriesNumber > 0) {
        combinedMap[seriesNumber] = series;
      }
    }
    
    // Sonra lokal serileri ekleyerek üzerine yaz (başlangıç serilerini atla)
    for (var series in state.localSeries) {
      final seriesNumber = series['seriesNumber'] as int? ?? 0;
      if (seriesNumber > 0) {
        combinedMap[seriesNumber] = series;
      }
    }
    
    // Map'i listeye çevir ve seri numarasına göre sırala
    final result = combinedMap.values.toList();
    result.sort((a, b) => 
      (a['seriesNumber'] as int? ?? 0).compareTo(b['seriesNumber'] as int? ?? 0)
    );
    
    return result;
  }

  // Finalize training session and sync with Supabase
  Future<bool> endTraining({bool saveChanges = false}) async {
    try {
      if (state.session == null) {
        return false;
      }
      
      // Update state once at the beginning
      state = state.copyWith(isLoading: true, error: null);
      
      // Eğer kaydedilecek bir şey yoksa, direkt sil
      final seriesDataList = decodeSeriesDataFromJson(state.session!.seriesData);
      if (seriesDataList.isEmpty && state.localSeries.isEmpty && state.currentArrows.isEmpty) {
        // Boş antrenmanı sil
        await _repository.deleteTrainingSession(state.session!.id);
        print('Empty training deleted: ${state.session!.id}');
        
        // Reset state
        state = TrainingSessionState.initial();
        return true;
      }
      
      // Web platformu için optimizasyon
      if (kIsWeb && saveChanges) {
        try {
          // Web'de tüm serileri birleştir
          final allSeries = [...seriesDataList, ...state.localSeries];
          
          // Seri numaralarına göre birleştir
          final Map<int, Map<String, dynamic>> uniqueSeries = {};
          for (var series in allSeries) {
            final seriesNumber = series['seriesNumber'] as int? ?? 0;
            if (seriesNumber > 0) {
              uniqueSeries[seriesNumber] = series;
            }
          }
          
          // JSON olarak encode et
          final jsonSeriesData = encodeSeriesDataAsJson(uniqueSeries.values.toList());
          
          // Session'ı güncelle
          final updatedSession = state.session!.copyWith(seriesData: jsonSeriesData);
          
          // Supabase'e kaydet
          await _databaseService.webSaveTrainingSession(updatedSession);
          
          // Web'de işlem tamamlandı
          state = TrainingSessionState.initial();
          return true;
        } catch (e) {
          print('Web platform batch save error: $e');
        }
      }
      
      // Kaydedilmemiş değişiklikleri kaydet
      if (state.isDirty && saveChanges) {
        await saveTrainingToDatabase();
      }
      
      // Supabase ile senkronizasyon yap
      if (state.session != null && saveChanges) {
        await _syncService.finalizeTrainingSession(state.session!);
      }
      
      // Kullanıcının cache'ini temizle
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null && saveChanges) {
        // Clear training history service cache
        _trainingHistoryService.clearCacheForAthlete(currentUserId);
        
        // Clear training history controller cache to force refresh
        final trainingHistoryController = _ref.read(trainingHistoryProvider.notifier);
        trainingHistoryController.clearCacheForUser(currentUserId);
      }
      
      // Reset state
      state = TrainingSessionState.initial();
      return true;
      
    } catch (e) {
      print('Error ending training: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Antrenman sonlandırılamadı: $e',
      );
      return false;
    }
  }
}

// Repository provider
final trainingRepositoryProvider = Provider<TrainingRepository>((ref) {
  return TrainingRepository();
});

// TrainingSession provider
final trainingSessionProvider =
    StateNotifierProvider<TrainingSessionController, TrainingSessionState>(
        (ref) {
  final repository = ref.watch(trainingRepositoryProvider);
  final syncService = ref.watch(trainingSyncServiceProvider);
  return TrainingSessionController(repository, syncService, ref);
});
