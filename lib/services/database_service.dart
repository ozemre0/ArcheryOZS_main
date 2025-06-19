import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import '../brick/profile.dart';
import 'dart:io';
// import 'package:path_provider/path_provider.dart'; // Kullanılmayan import
import '../models/training_session_model.dart';
// import '../models/training_series_model.dart'; // Kullanılmayan import
import '../services/supabase_config.dart'; // Supabase yapılandırması için import ekliyoruz

class DatabaseService {
  static Database? _database;
  static final DatabaseService _instance = DatabaseService._internal();
  // Supabase client'ı burada tanımlıyoruz
  final _supabase = SupabaseConfig.client;

  // Web platformu için Supabase kullanılıp kullanılmayacağını belirten flag
  final bool _useSupabaseDirectly = kIsWeb;

  // --- SYNC OPTIMIZATION ---
  static DateTime? _lastSupabaseSync;
  static const Duration _minSyncInterval = Duration(minutes: 10);
  static bool _isSyncing = false;
  // --- END SYNC OPTIMIZATION ---

  // --- LOCAL CACHE FOR WEB TRAININGS ---
  final Map<String, List<TrainingSession>> _webUserTrainingCache = {};
  final Map<String, DateTime> _webUserTrainingCacheTime = {};
  static const Duration _webUserTrainingCacheDuration = Duration(minutes: 5);

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_useSupabaseDirectly) {
      throw Exception(
          'Web platformunda SQLite veritabanı kullanılamaz. Supabase API kullanılıyor.');
    }

    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Web platform check for cleaner error handling
  bool get isWebPlatform => kIsWeb;

  Future<Database> _initDatabase() async {
    // Web platformunda çalışmaz, bu kodu atla
    if (_useSupabaseDirectly) {
      throw Exception('Web platformunda SQLite veritabanı başlatılamaz.');
    }

    String path = await getDatabasesPath();
    final dbPath = join(path, 'archery_training.db');

    final db = await openDatabase(
      dbPath,
      version:
          7, // Incremented version from 6 to 7 for new age_groups schema
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );

    // is_deleted sütunu yoksa ekle (her açılışta kontrol)
    await _ensureIsDeletedColumn(db);
    // team_types tablosu yoksa ekle (her açılışta kontrol)
    await _ensureTeamTypesTable(db);

    return db;
  }

  Future<void> _ensureIsDeletedColumn(Database db) async {
    try {
      final tableInfo =
          await db.rawQuery('PRAGMA table_info(training_sessions)');
      final columnExists =
          tableInfo.any((column) => column['name'] == 'is_deleted');
      if (!columnExists) {
        await db.execute(
            'ALTER TABLE training_sessions ADD COLUMN is_deleted INTEGER DEFAULT 0');
        print('is_deleted column automatically added to training_sessions');
      }
    } catch (e) {
      print('Error ensuring is_deleted column: $e');
    }
  }

  Future<void> _ensureTeamTypesTable(Database db) async {
    final tableInfo = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='team_types'");
    if (tableInfo.isEmpty) {
      await db.execute('''
        CREATE TABLE team_types(
          team_type_id INTEGER PRIMARY KEY,
          team_type_en TEXT,
          team_type_tr TEXT
        )
      ''');
      print('team_types table created by _ensureTeamTypesTable');
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Competition records tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS competition_records(
        competition_id TEXT PRIMARY KEY,
        athlete_id TEXT NOT NULL,
        competition_name TEXT,
        max_score INTEGER,
        distance INTEGER,
        environment TEXT,
        bow_type TEXT,
        competition_date TEXT,
        final_rank TEXT,
        qualification_rank TEXT,
        qualification_score INTEGER DEFAULT 0,
        age_group INTEGER, 
        created_at TEXT,
        updated_at TEXT,
        pending_sync INTEGER DEFAULT 1,
        is_deleted INTEGER DEFAULT 0,
        team_result INTEGER,
        team_type INTEGER
      )
    ''');

    // Training sessions tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_sessions(
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        date TEXT NOT NULL,
        distance INTEGER,
        bow_type TEXT,
        is_indoor INTEGER DEFAULT 0,
        training_session_name TEXT,
        notes TEXT,
        arrows_per_series INTEGER DEFAULT 3,
        total_score INTEGER DEFAULT 0,
        total_arrows INTEGER DEFAULT 0,
        average REAL DEFAULT 0.0,
        pending_sync INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        is_deleted INTEGER DEFAULT 0,
        coach_seen INTEGER DEFAULT 0,
        training_type TEXT,
        duration INTEGER,
        arrows TEXT,
        x_count INTEGER DEFAULT 0,
        series_data TEXT
      )
    ''');

    // NOT: training_series tablosu artık kullanılmıyor, series_data kullanılıyor

    // İndexler
    await db.execute(
        'CREATE INDEX idx_training_user ON training_sessions(user_id)');
    await db
        .execute('CREATE INDEX idx_training_date ON training_sessions(date)');
    // NOT: training_series tablosu indeksi kaldırıldı

    // Age groups tablosu (Yeni Schema)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS age_groups(
        age_group_id INTEGER PRIMARY KEY,
        age_group_en TEXT,
        age_group_tr TEXT
      )
    ''');

    // Team types tablosu (Yeni Schema)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS team_types(
        team_type_id INTEGER PRIMARY KEY,
        team_type_en TEXT,
        team_type_tr TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades
    if (oldVersion < 2) {
      // Add arrows_per_series column to training_sessions if it doesn't exist
      try {
        // Check if the column exists first
        final tableInfo =
            await db.rawQuery('PRAGMA table_info(training_sessions)');
        final columnExists =
            tableInfo.any((column) => column['name'] == 'arrows_per_series');

        if (!columnExists) {
          print('Adding arrows_per_series column to training_sessions table');
          await db.execute(
              'ALTER TABLE training_sessions ADD COLUMN arrows_per_series INTEGER DEFAULT 3');
        }
      } catch (e) {
        print('Error during database migration: $e');
      }
    }

    // Version 3: Add is_deleted column for soft delete functionality
    if (oldVersion < 3) {
      try {
        // Check if the column exists first
        final tableInfo =
            await db.rawQuery('PRAGMA table_info(training_sessions)');
        final columnExists =
            tableInfo.any((column) => column['name'] == 'is_deleted');

        if (!columnExists) {
          print('Adding is_deleted column to training_sessions table');
          await db.execute(
              'ALTER TABLE training_sessions ADD COLUMN is_deleted INTEGER DEFAULT 0');
        }
      } catch (e) {
        print('Error adding is_deleted column: $e');
      }
    }

    // Version 4: Add training_session_name column for compatibility with Supabase
    if (oldVersion < 4) {
      try {
        // Check if the column exists first
        final tableInfo =
            await db.rawQuery('PRAGMA table_info(training_sessions)');
        final columnExists = tableInfo
            .any((column) => column['name'] == 'training_session_name');

        if (!columnExists) {
          print(
              'Adding training_session_name column to training_sessions table');
          await db.execute(
              'ALTER TABLE training_sessions ADD COLUMN training_session_name TEXT');

          // Copy data from name to training_session_name
          print('Migrating data from name to training_session_name');
          await db.execute(
              'UPDATE training_sessions SET training_session_name = name');
        }
      } catch (e) {
        print('Error adding training_session_name column: $e');
      }
    }
    
    // Version 5: Add x_count column for compatibility with Supabase
    if (oldVersion < 5) {
      try {
        // Check if the column exists first
        final tableInfo =
            await db.rawQuery('PRAGMA table_info(training_sessions)');
        final columnExists = tableInfo
            .any((column) => column['name'] == 'x_count');

        if (!columnExists) {
          print('Adding x_count column to training_sessions table');
          await db.execute(
              'ALTER TABLE training_sessions ADD COLUMN x_count INTEGER DEFAULT 0');
          
          print('Running database migration to x_count...');
        }
      } catch (e) {
        print('Error adding x_count column: $e');
      }
    }

    if (oldVersion < 6) {
      // Add age_groups table (previous version of schema)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS age_groups(
          age_group_id INTEGER PRIMARY KEY,
          age_group_name TEXT NOT NULL
        )
      ''');
      print('age_groups table created during upgrade (old schema).');

      // Add age_group column to competition_records if it doesn't exist
      try {
        final tableInfoCompetition = await db.rawQuery('PRAGMA table_info(competition_records)');
        final columnExistsCompetition = tableInfoCompetition.any((column) => column['name'] == 'age_group');
        if (!columnExistsCompetition) {
          await db.execute('ALTER TABLE competition_records ADD COLUMN age_group INTEGER');
          print('age_group column added to competition_records table during upgrade.');
        }
      } catch (e) {
        print('Error adding age_group column to competition_records during upgrade: $e');
      }
    }

    if (oldVersion < 7) {
      // Migrate age_groups table to new schema (age_group_en, age_group_tr)
      // Safest way is to drop if exists and recreate
      await db.execute('DROP TABLE IF EXISTS age_groups');
      await db.execute('''
        CREATE TABLE age_groups(
          age_group_id INTEGER PRIMARY KEY,
          age_group_en TEXT,
          age_group_tr TEXT
        )
      ''');
      print('age_groups table migrated to new schema (en/tr columns) during upgrade.');

      // Team types table migration (same as above)
      await db.execute('DROP TABLE IF EXISTS team_types');
      await db.execute('''
        CREATE TABLE team_types(
          team_type_id INTEGER PRIMARY KEY,
          team_type_en TEXT,
          team_type_tr TEXT
        )
      ''');
      print('team_types table migrated to new schema (en/tr columns) during upgrade.');
    }
  }

  // Veritabanını temizle
  Future<void> clearDatabase() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('training_sessions');
    });
  }

  // Veritabanını kapat
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> exportDatabaseToDownloads(String dbPath) async {
    try {
      // Veritabanı dosyası
      final File dbFile = File(dbPath);

      // External depolama alanını al (Downloads klasörü için)
      final downloadDir = Directory('/storage/emulated/0/Download');

      // Hedef dosya yolu
      final String targetPath = join(downloadDir.path, 'archery_ozs_export.db');

      // Veritabanı dosyasını kopyala
      if (await dbFile.exists()) {
        await dbFile.copy(targetPath);
        debugPrint('Database copied to Downloads folder: $targetPath');
      } else {
        debugPrint('Database file not found at path: $dbPath');
      }
    } catch (e) {
      debugPrint('Error exporting database: $e');
    }
  }

  // Manuel olarak çağrılabilecek dışa aktarma metodu
  Future<String?> exportDatabase() async {
    try {
      final db = await database;
      await db.close();
      _database = null;

      String dbPath = join(await getDatabasesPath(), 'archery_ozs.db');
      final File dbFile = File(dbPath);

      final downloadDir = Directory('/storage/emulated/0/Download');
      final String targetPath = join(downloadDir.path, 'archery_ozs_export.db');

      if (await dbFile.exists()) {
        await dbFile.copy(targetPath);
        debugPrint('Database exported to: $targetPath');

        // Veritabanını tekrar aç
        _database = await _initDatabase();

        return targetPath;
      }
      return null;
    } catch (e) {
      debugPrint('Error manually exporting database: $e');
      return null;
    }
  }

  // Veritabanı dosya yolunu al
  Future<String> getDatabasePath() async {
    String path = await getDatabasesPath();
    return join(path, 'archery_training.db');
  }

  // Profil işlemleri
  Future<void> saveProfile(Profile profile) async {
    final db = await database;
    await db.insert(
      'profiles',
      profile.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Profile?> getProfile(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return Profile.fromJson(maps.first);
  }

  Future<void> deleteProfile(String id) async {
    final db = await database;
    await db.delete(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Antrenman işlemleri
  Future<void> saveTraining(Map<String, dynamic> training) async {
    final db = await database;
    await db.insert(
      'trainings',
      training,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAthleteTrainings(
      String athleteId) async {
    final db = await database;
    return await db.query(
      'trainings',
      where: 'athlete_id = ?',
      whereArgs: [athleteId],
      orderBy: 'training_date DESC',
    );
  }

  // Yarışma işlemleri
  Future<void> saveCompetition(Map<String, dynamic> competition) async {
    final db = await database;
    await db.insert(
      'competitions',
      competition,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllCompetitions() async {
    final db = await database;
    return await db.query(
      'competitions',
      orderBy: 'start_date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAthleteCompetitions(
      String athleteId) async {
    final db = await database;
    const query = '''
      SELECT c.* 
      FROM competitions c
      INNER JOIN competition_participants cp ON c.id = cp.competition_id
      WHERE cp.athlete_id = ?
      ORDER BY c.start_date DESC
    ''';
    return await db.rawQuery(query, [athleteId]);
  }

  // Antrenman Oturumları (Training Sessions) İşlemleri
  // --- YENİ: Seriler sadece series_data üzerinden yönetilecek ---
  // TrainingSession kaydederken series_data alanını da ekle
  Future<void> saveTrainingSession(TrainingSession session) async {
    final db = await database;

    final Map<String, dynamic> sessionData = {
      'id': session.id,
      'user_id': session.userId,
      'date': session.date.toIso8601String(),
      'distance': session.distance,
      'bow_type': session.bowType,
      'is_indoor': session.isIndoor ? 1 : 0,
      'notes': session.notes,
      'training_session_name': session.training_session_name,
      'arrows_per_series': session.arrowsPerSeries, // Save arrows per series
      'training_type': session.trainingType,
      'pending_sync': 1,
      'is_deleted': 0, // Her zaman false olarak kaydet
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'series_data': session.seriesData, // <-- JSON ok verisi
    };

    await db.insert(
      'training_sessions',
      sessionData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // TrainingSession okuma işlemlerinde sadece series_data kullanılacak
  Future<List<TrainingSession>> getUserTrainingSessions(String userId) async {
    final db = await database;

    // Önce oturumları al - soft delete edilmemiş olanları filtrele
    final List<Map<String, dynamic>> sessionMaps = await db.query(
      'training_sessions',
      where: 'user_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [userId],
      orderBy: 'date DESC',
    );

    List<TrainingSession> sessions = [];

    // Her oturum için serileri al
    for (var sessionMap in sessionMaps) {
      // Oturumu oluştur
      sessions.add(TrainingSession(
        id: sessionMap['id'],
        userId: sessionMap['user_id'],
        date: DateTime.parse(sessionMap['date']),
        distance: sessionMap['distance'],
        bowType: sessionMap['bow_type'],
        isIndoor: sessionMap['is_indoor'] == 1,
        notes: sessionMap['notes'],
        training_session_name: sessionMap['training_session_name'],
        arrowsPerSeries: sessionMap['arrows_per_series'] ??
            3, // Add arrowsPerSeries with default
        trainingType: (sessionMap['training_type'] as String?) ?? 'score',
        seriesData: sessionMap['series_data'],
      ));
    }

    return sessions;
  }

  Future<TrainingSession?> getTrainingSession(String sessionId) async {
    final db = await database;

    final List<Map<String, dynamic>> sessionMaps = await db.query(
      'training_sessions',
      where: 'id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [sessionId],
    );

    if (sessionMaps.isEmpty) return null;

    final sessionMap = sessionMaps.first;

    // Oturumu oluştur
    return TrainingSession(
      id: sessionMap['id'],
      userId: sessionMap['user_id'],
      date: DateTime.parse(sessionMap['date']),
      distance: sessionMap['distance'],
      bowType: sessionMap['bow_type'],
      isIndoor: sessionMap['is_indoor'] == 1,
      notes: sessionMap['notes'],
      training_session_name: sessionMap['training_session_name'],
      arrowsPerSeries:
          sessionMap['arrows_per_series'] ?? 3, // Get arrows per series from db
      trainingType: (sessionMap['training_type'] as String?) ?? 'score',
      seriesData: sessionMap['series_data'],
    );
  }

  Future<List<TrainingSession>> getTrainingSessionsByDateRange(
      String userId, DateTime startDate, DateTime endDate) async {
    final db = await database;

    final String startDateStr = startDate.toIso8601String();
    final String endDateStr = endDate.toIso8601String();

    final List<Map<String, dynamic>> sessionMaps = await db.query(
      'training_sessions',
      where:
          'user_id = ? AND date >= ? AND date <= ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [userId, startDateStr, endDateStr],
      orderBy: 'date DESC',
    );

    List<TrainingSession> sessions = [];

    for (var sessionMap in sessionMaps) {
      sessions.add(TrainingSession(
        id: sessionMap['id'],
        userId: sessionMap['user_id'],
        date: DateTime.parse(sessionMap['date']),
        distance: sessionMap['distance'],
        bowType: sessionMap['bow_type'],
        isIndoor: sessionMap['is_indoor'] == 1,
        notes: sessionMap['notes'],
        training_session_name: sessionMap['training_session_name'],
        arrowsPerSeries:
            sessionMap['arrows_per_series'] ?? 3, // Include arrowsPerSeries
        trainingType: (sessionMap['training_type'] as String?) ?? 'score',
        seriesData: sessionMap['series_data'],
      ));
    }

    return sessions;
  }

  Future<List<TrainingSession>> getTrainingSessionsByEnvironment(
      String userId, bool isIndoor) async {
    final db = await database;

    final List<Map<String, dynamic>> sessionMaps = await db.query(
      'training_sessions',
      where:
          'user_id = ? AND is_indoor = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [userId, isIndoor ? 1 : 0],
      orderBy: 'date DESC',
    );

    List<TrainingSession> sessions = [];

    for (var sessionMap in sessionMaps) {
      sessions.add(TrainingSession(
        id: sessionMap['id'],
        userId: sessionMap['user_id'],
        date: DateTime.parse(sessionMap['date']),
        distance: sessionMap['distance'],
        bowType: sessionMap['bow_type'],
        isIndoor: sessionMap['is_indoor'] == 1,
        notes: sessionMap['notes'],
        training_session_name: sessionMap['training_session_name'],
        arrowsPerSeries:
            sessionMap['arrows_per_series'] ?? 3, // Include arrowsPerSeries
        trainingType: (sessionMap['training_type'] as String?) ?? 'score',
        seriesData: sessionMap['series_data'],
      ));
    }

    return sessions;
  }

  Future<void> deleteTrainingSession(String sessionId) async {
    final db = await database;

    // Soft delete: sadece is_deleted alanını güncelle
    await db.update(
      'training_sessions',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // Soft delete işlemi için yeni metod - kayıtları gerçekten silmez, sadece işaretler
  Future<void> softDeleteTrainingSession(String sessionId) async {
    final db = await database;

    // Oturumu is_deleted = true olarak işaretle
    await db.update(
      'training_sessions',
      {
        'is_deleted': 1, // SQLite'da boolean değerleri 1 ve 0 olarak saklanır
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    print('Training session soft deleted: $sessionId');
  }

  Future<void> markSessionAsSynced(String localId, String supabaseId) async {
    final db = await database;
    // 1. Get the local session row
    final rows = await db.query('training_sessions', where: 'id = ?', whereArgs: [localId]);
    if (rows.isEmpty) return;
    final session = rows.first;
    // 2. Delete the old local row
    await db.delete('training_sessions', where: 'id = ?', whereArgs: [localId]);
    // 3. Insert a new row with the Supabase ID, mark as synced
    final newSession = Map<String, dynamic>.from(session);
    newSession['id'] = supabaseId;
    newSession['pending_sync'] = 0;
    newSession['updated_at'] = DateTime.now().toIso8601String();
    await db.insert('training_sessions', newSession, conflictAlgorithm: ConflictAlgorithm.replace);
    print('Training session marked as synced: $localId -> $supabaseId');
  }

  Future<void> markSyncComplete(String sessionId) async {
    final db = await database;

    await db.update(
      'training_sessions',
      {
        'pending_sync': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    
    print('Training session marked as synced: $sessionId');
  }

  Future<List<TrainingSession>> getPendingTrainingSessions() async {
    final db = await database;

    final List<Map<String, dynamic>> sessionMaps = await db.query(
      'training_sessions',
      where: 'pending_sync = 1',
    );

    List<TrainingSession> sessions = [];

    for (var sessionMap in sessionMaps) {
      sessions.add(TrainingSession(
        id: sessionMap['id'],
        userId: sessionMap['user_id'],
        date: DateTime.parse(sessionMap['date']),
        distance: sessionMap['distance'],
        bowType: sessionMap['bow_type'],
        isIndoor: sessionMap['is_indoor'] == 1,
        notes: sessionMap['notes'],
        training_session_name: sessionMap['training_session_name'],
        arrowsPerSeries: sessionMap['arrows_per_series'] ??
            3, // Add arrowsPerSeries with default value
        trainingType: (sessionMap['training_type'] as String?) ?? 'score',
        seriesData: sessionMap['series_data'],
      ));
    }

    return sessions;
  }

  // Web platformu için doğrudan Supabase kullanımını sağlayan metotlar
  // Bu metotlar sadece web platformunda çağrılmalıdır

  // Web platform için training session kaydetme
  Future<TrainingSession> webSaveTrainingSession(
      TrainingSession session) async {
    if (!kIsWeb) return saveTrainingSession(session).then((_) => session);

    try {
      // Eğer yerel ID'ye sahipse, yeni bir antrenman oturumu oluştur
      if (session.id.startsWith('local_')) {
        final trainingData = {
          'user_id': session.userId,
          'date': session.date.toIso8601String(),
          'distance': session.distance,
          'bow_type': session.bowType,
          'is_indoor': session.isIndoor,
          'notes': session.notes,
          'training_session_name': session.training_session_name,
          'arrows_per_series': session.arrowsPerSeries,
          'training_type': session.trainingType,
          'series_data': session.seriesData, // |10n:series_data_update
          'is_deleted': session.is_deleted, // |10n:soft_delete_flag
        };

        // Supabase'e upsert ile ekle
        final response = await _supabase
            .from('training_sessions')
            .upsert(trainingData)
            .select();

        if (response.isNotEmpty) {
          final newId = response[0]['id'];
          print(
              'Web platform: Created/Upserted training session in Supabase with ID: $newId');

          // Yeni ID ile güncellenmiş session'ı döndür
          final updatedSession = session.copyWith(id: newId);
          return updatedSession;
        }
        print('Web platform: Created/Upserted training session in Supabase');
        return session;
      }
      // Yerel ID'ye sahip değilse, mevcut antrenman oturumunu güncelle
      else {
        final trainingData = {
          'id': session.id,
          'user_id': session.userId,
          'date': session.date.toIso8601String(),
          'distance': session.distance,
          'bow_type': session.bowType,
          'is_indoor': session.isIndoor,
          'notes': session.notes,
          'training_session_name': session.training_session_name,
          'arrows_per_series': session.arrowsPerSeries,
          'training_type': session.trainingType,
          'series_data': session.seriesData, // Yeni algoritma için
          'is_deleted': session.is_deleted, // Add is_deleted field
        };

        // Supabase'de upsert ile güncelle
        await _supabase.from('training_sessions').upsert(trainingData).select();

        print('Web platform: Upserted training session in Supabase');
        return session;
      }
    } catch (e) {
      print('Web platform: Error saving training session to Supabase: $e');
      rethrow;
    }
  }

  // Web platform için series_data yaklaşımını kullanarak seri kaydetme
  Future<void> webSaveSeriesData(
      String trainingId, Map<String, dynamic> seriesData) async {
    if (!kIsWeb) return;

    try {
      final trainingSession = await _supabase
          .from('training_sessions')
          .select()
          .eq('id', trainingId)
          .single();

      if (trainingSession != null) {
        // Training session'ı series_data ile güncelle
        await _supabase
            .from('training_sessions')
            .update({
              'series_data': seriesData,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', trainingId);

        print('Web platform: Updated training session with series_data');
      }
    } catch (e) {
      print('Web platform: Error saving series data to Supabase: $e');
      rethrow;
    }
  }

  // Web platform için kullanıcının antrenman oturumlarını getirme
  Future<List<TrainingSession>> webGetUserTrainingSessions(
      String userId, {bool force = false}) async {
    if (!kIsWeb) return getUserTrainingSessions(userId);

    final now = DateTime.now();
    if (!force &&
        _webUserTrainingCache.containsKey(userId) &&
        _webUserTrainingCacheTime.containsKey(userId) &&
        now.difference(_webUserTrainingCacheTime[userId]!) < _webUserTrainingCacheDuration) {
      print('Web platform: Returning cached training sessions for $userId');
      return _webUserTrainingCache[userId]!;
    }
    try {
      // Tüm antrenman oturumlarını al - soft delete edilmemiş olanları filtrele
      final response = await _supabase
          .from('training_sessions')
          .select('id, user_id, date, distance, bow_type, is_indoor, notes, training_session_name, arrows_per_series, total_arrows, total_score, average, x_count, training_type')
          .eq('user_id', userId)
          .eq('is_deleted', false) // Soft delete edilmişleri filtrele
          .order('date', ascending: false);

      // Yanıtı TrainingSession nesnelerine dönüştür
      List<TrainingSession> sessions = [];
      for (var sessionData in response) {
        // Oturumu oluştur
        sessions.add(TrainingSession(
          id: sessionData['id'],
          userId: sessionData['user_id'],
          date: DateTime.parse(sessionData['date']),
          distance: sessionData['distance'],
          bowType: sessionData['bow_type'],
          isIndoor: sessionData['is_indoor'],
          notes: sessionData['notes'],
          training_session_name: sessionData['training_session_name'],
          arrowsPerSeries: sessionData['arrows_per_series'] ?? 3,
          trainingType: sessionData['training_type'] ?? 'score',
        ));
      }

      // Cache the result
      _webUserTrainingCache[userId] = sessions;
      _webUserTrainingCacheTime[userId] = now;

      print(
          'Web platform: Retrieved \u001b[32m${sessions.length}[0m training sessions from Supabase');
      return sessions;
    } catch (e) {
      print(
          'Web platform: Error getting user training sessions from Supabase: $e');
      return [];
    }
  }

  // Web platform için belirli bir antrenman oturumunu getirme
  Future<TrainingSession?> webGetTrainingSession(String sessionId) async {
    if (!kIsWeb) return getTrainingSession(sessionId);

    try {
      // Yerel ID'ye sahipse null döndür
      if (sessionId.startsWith('local_')) {
        print(
            'Web platform: Cannot get training session with local ID from Supabase');
        return null;
      }

      // Antrenman oturumunu al - soft delete edilmemiş olan
      final response = await _supabase
          .from('training_sessions')
          .select()
          .eq('id', sessionId)
          .eq('is_deleted', false) // Soft delete edilmişleri filtrele
          .single();

      // Oturumu oluştur
      return TrainingSession(
        id: response['id'],
        userId: response['user_id'],
        date: DateTime.parse(response['date']),
        distance: response['distance'],
        bowType: response['bow_type'],
        isIndoor: response['is_indoor'],
        notes: response['notes'],
        training_session_name: response['training_session_name'],
        arrowsPerSeries: response['arrows_per_series'] ?? 3,
        trainingType: response['training_type'] ?? 'score',
      );
    } catch (e) {
      print('Web platform: Error getting training session from Supabase: $e');
      return null;
    }
  }

  // Web platform için antrenman oturumunu silme
  Future<void> webDeleteTrainingSession(String sessionId) async {
    if (!kIsWeb) {
      return softDeleteTrainingSession(sessionId); // Soft delete metodunu çağır
    }

    try {
      // Yerel ID'ye sahipse işlem yapma
      if (sessionId.startsWith('local_')) {
        print(
            'Web platform: Cannot soft delete training session with local ID from Supabase');
        return;
      }

      // Antrenman oturumunu soft delete yap (is_deleted=true)
      await _supabase
          .from('training_sessions')
          .update({'is_deleted': true}).eq('id', sessionId);

      print(
          'Web platform: Training session soft deleted in Supabase: $sessionId');
    } catch (e) {
      print(
          'Web platform: Error soft deleting training session in Supabase: $e');
      rethrow;
    }
  }

  // Web platform için seriyi silme
  Future<void> webDeleteSeries(String seriesId) async {
    if (!kIsWeb) return;

    try {
      // Yerel ID'ye sahipse işlem yapma
      if (seriesId.startsWith('local_')) {
        print('Web platform: Cannot delete series with local ID from Supabase');
        return;
      }

      // Seriyi sil
      await _supabase.from('training_series').delete().eq('id', seriesId);

      print('Web platform: Deleted series from Supabase');
    } catch (e) {
      print('Web platform: Error deleting series from Supabase: $e');
      rethrow;
    }
  }

  // Web platform için tarih aralığına göre antrenman oturumlarını getirme
  Future<List<TrainingSession>> webGetTrainingSessionsByDateRange(
      String userId, DateTime startDate, DateTime endDate) async {
    if (!kIsWeb) {
      return getTrainingSessionsByDateRange(userId, startDate, endDate);
    }

    try {
      final startDateStr = startDate.toIso8601String();
      final endDateStr = endDate.toIso8601String();

      // Tarih aralığına göre antrenman oturumlarını al - soft delete edilmemiş olanları filtrele
      final response = await _supabase
          .from('training_sessions')
          .select('id, user_id, date, distance, bow_type, is_indoor, notes, training_session_name, arrows_per_series, total_arrows, total_score, average, x_count, training_type')
          .eq('user_id', userId)
          .eq('is_deleted', false) // Soft delete edilmişleri filtrele
          .gte('date', startDateStr)
          .lte('date', endDateStr)
          .order('date', ascending: false);

      // Yanıtı TrainingSession nesnelerine dönüştür
      List<TrainingSession> sessions = [];
      for (var sessionData in response) {
        // Oturumu oluştur
        sessions.add(TrainingSession(
          id: sessionData['id'],
          userId: sessionData['user_id'],
          date: DateTime.parse(sessionData['date']),
          distance: sessionData['distance'],
          bowType: sessionData['bow_type'],
          isIndoor: sessionData['is_indoor'],
          notes: sessionData['notes'],
          training_session_name: sessionData['training_session_name'],
          arrowsPerSeries: sessionData['arrows_per_series'] ?? 3,
          trainingType: sessionData['training_type'] ?? 'score',
        ));
      }

      print(
          'Web platform: Retrieved ${sessions.length} training sessions by date range from Supabase');
      return sessions;
    } catch (e) {
      print(
          'Web platform: Error getting training sessions by date range from Supabase: $e');
      return [];
    }
  }

  // Web platform için ortama göre antrenman oturumlarını getirme
  Future<List<TrainingSession>> webGetTrainingSessionsByEnvironment(
      String userId, bool isIndoor) async {
    if (!kIsWeb) return getTrainingSessionsByEnvironment(userId, isIndoor);

    try {
      // Ortama göre antrenman oturumlarını al - soft delete edilmemiş olanları filtrele
      final response = await _supabase
          .from('training_sessions')
          .select('id, user_id, date, distance, bow_type, is_indoor, notes, training_session_name, arrows_per_series, total_arrows, total_score, average, x_count, training_type')
          .eq('user_id', userId)
          .eq('is_indoor', isIndoor)
          .eq('is_deleted', false) // Soft delete edilmişleri filtrele
          .order('date', ascending: false);

      // Yanıtı TrainingSession nesnelerine dönüştür
      List<TrainingSession> sessions = [];
      for (var sessionData in response) {
        // Oturumu oluştur
        sessions.add(TrainingSession(
          id: sessionData['id'],
          userId: sessionData['user_id'],
          date: DateTime.parse(sessionData['date']),
          distance: sessionData['distance'],
          bowType: sessionData['bow_type'],
          isIndoor: sessionData['is_indoor'],
          notes: sessionData['notes'],
          training_session_name: sessionData['training_session_name'],
          arrowsPerSeries: sessionData['arrows_per_series'] ?? 3,
          trainingType: sessionData['training_type'] ?? 'score',
        ));
      }

      print(
          'Web platform: Retrieved ${sessions.length} training sessions by environment from Supabase');
      return sessions;
    } catch (e) {
      print(
          'Web platform: Error getting training sessions by environment from Supabase: $e');
      return [];
    }
  }

  // Supabase'den tüm antrenmanları çekip local veritabanına kaydeder
  Future<void> syncAllTrainingsFromSupabase(String userId) async {
    final now = DateTime.now();
    if (_isSyncing) {
      print('Supabase sync: Sync already in progress, skipping.');
      return;
    }
    if (_lastSupabaseSync != null && now.difference(_lastSupabaseSync!) < _minSyncInterval) {
      print('Supabase sync: Skipping, last sync was too recent.');
      return;
    }
    _isSyncing = true;
    _lastSupabaseSync = now;
    try {
      print('Supabase sync: Fetching all trainings for user $userId...');
      final supabase = SupabaseConfig.client;
      final response = await supabase
          .from('training_sessions')
          .select('*')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .order('date', ascending: false);

      if (response is List && response.isNotEmpty) {
        print('Supabase sync: ${response.length} trainings found. Saving to local DB...');
        final db = await database;
        for (final sessionMap in response) {
          try {
            final List<Map<String, dynamic>> localRows = await db.query(
              'training_sessions',
              where: 'id = ?',
              whereArgs: [sessionMap['id']],
            );
            if (localRows.isNotEmpty && (localRows.first['is_deleted'] == 1)) {
              print('Supabase sync: Skipping deleted training: ${sessionMap['id']}');
              continue;
            }
            final session = TrainingSession.fromJson(sessionMap);
            await saveTrainingSession(session);
          } catch (e) {
            print('Supabase sync: Error saving session: $e');
          }
        }
        print('Supabase sync: All trainings saved to local DB.');
      } else {
        print('Supabase sync: No trainings found for user.');
      }
    } catch (e) {
      print('Supabase sync: Error fetching trainings from Supabase: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  // Public getter/setter for lastSupabaseSync
  static DateTime? get lastSupabaseSync => _lastSupabaseSync;
  static set lastSupabaseSync(DateTime? value) => _lastSupabaseSync = value;
}
