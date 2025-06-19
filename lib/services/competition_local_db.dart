import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'supabase_config.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class CompetitionLocalDb {
  static final CompetitionLocalDb instance = CompetitionLocalDb._internal();
  DatabaseService? _dbService;

  CompetitionLocalDb._internal() {
    if (!kIsWeb) {
      _dbService = DatabaseService();
    }
  }

  Future<Database> get _db async {
    if (kIsWeb || _dbService == null) {
      throw Exception('|10n:competition_local_db_web_or_null_error');
    }
    return await _dbService!.database;
  }

  Future<List<Map<String, dynamic>>> getCompetitionsByAthlete(String athleteId) async {
    if (kIsWeb) {
      throw Exception('|10n:competition_local_db_web_error');
    }
    final db = await _db;
    final result = await db.query(
      'competition_records',
      where: 'athlete_id = ? AND is_deleted = 0',
      whereArgs: [athleteId],
    );
    if (result.isNotEmpty) {
      for (final row in result) {
        debugPrint('|10n:getCompetitionsByAthlete row: competition_id=${row['competition_id']}, team_type=${row['team_type']}, team_result=${row['team_result']}');
      }
    } else {
      debugPrint('|10n:getCompetitionsByAthlete: no results');
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getAllCompetitions({String? athleteId}) async {
    if (kIsWeb) {
      throw Exception('|10n:competition_local_db_web_error');
    }
    final db = await _db;
    if (athleteId != null) {
      return await db.query(
        'competition_records',
        where: 'is_deleted = 0 AND athlete_id = ?',
        whereArgs: [athleteId],
      );
    }
    return await db.query('competition_records', where: 'is_deleted = 0');
  }

  Future<List<Map<String, dynamic>>> getPendingCompetitions() async {
    if (kIsWeb) {
      throw Exception('|10n:competition_local_db_web_error');
    }
    final db = await _db;
    return await db.query('competition_records', where: 'pending_sync = 1');
  }

  Future<void> insertCompetition(Map<String, dynamic> competition, {bool pending = true}) async {
    if (kIsWeb) {
      throw Exception('|10n:competition_local_db_web_error');
    }
    final db = await _db;
    competition['pending_sync'] = pending ? 1 : 0;
    if (!competition.containsKey('team_type')) competition['team_type'] = null;
    if (!competition.containsKey('team_result')) competition['team_result'] = null;
    debugPrint('|10n:competition_local_insert_try: \x1B[1m${competition['competition_id']}\x1B[0m');
    await db.insert(
      'competition_records',
      competition,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final inserted = await db.query('competition_records', where: 'competition_id = ?', whereArgs: [competition['competition_id']]);
    if (inserted.isNotEmpty) {
      debugPrint('|10n:competition_local_inserted_row: competition_id=${inserted[0]['competition_id']}, team_type=${inserted[0]['team_type']}, team_result=${inserted[0]['team_result']}');
    }
    final all = await db.query('competition_records');
    debugPrint('|10n:competition_local_all_count: ${all.length}');
  }

  Future<void> markCompetitionSynced(String competitionId) async {
    if (kIsWeb) {
      throw Exception('|10n:competition_local_db_web_error');
    }
    final db = await _db;
    await db.update(
      'competition_records',
      {'pending_sync': 0},
      where: 'competition_id = ?',
      whereArgs: [competitionId],
    );
  }

  Future<void> deleteCompetition(String competitionId) async {
    if (kIsWeb) {
      throw Exception('|10n:competition_local_db_web_error');
    }
    final dbClient = await _db;
    await dbClient.update(
      'competition_records',
      {'is_deleted': 1, 'pending_sync': 1},
      where: 'competition_id = ?',
      whereArgs: [competitionId],
    );
  }

  // Age Group Methods
  Future<bool> isAgeGroupsTableEmpty() async {
    if (kIsWeb) return true;
    final dbClient = await _db;
    final count = Sqflite.firstIntValue(await dbClient.rawQuery('SELECT COUNT(*) FROM age_groups'));
    return count == 0;
  }

  Future<void> syncAgeGroupsFromSupabase({bool forceRefresh = false}) async {
    if (kIsWeb) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (forceRefresh && connectivity == ConnectivityResult.none) {
      debugPrint('|10n:age_groups_force_refresh_skipped_no_internet');
      return; // İnternet yoksa local tabloyu silme!
    }

    if (forceRefresh) {
      debugPrint('|10n:age_groups_force_refresh_clearing_local');
      final dbClient = await _db;
      await dbClient.delete('age_groups'); // Clear local table
    } else {
      final isLocalEmpty = await isAgeGroupsTableEmpty();
      if (!isLocalEmpty) {
        debugPrint('|10n:age_groups_local_not_empty_skipping_sync_unless_forced');
        return;
      }
    }

    debugPrint('|10n:age_groups_sync_attempt');
    try {
      // IMPORTANT: This Supabase call will fail if the MCP authorization issue persists.
      final dynamic response = await SupabaseConfig.client
          .from('age_groups')
          .select('age_group_id, age_group_en, age_group_tr'); // Fetch new columns

      if (response is List) {
        final List<Map<String, dynamic>> ageGroupsData = List<Map<String, dynamic>>.from(
          response.map((item) {
            if (item is Map<String, dynamic>) {
              return item;
            }
            return Map<String, dynamic>.from(item as Map);
          })
        );

        if (ageGroupsData.isNotEmpty) {
          final dbClient = await _db;
          final batch = dbClient.batch();
          for (var group in ageGroupsData) {
            batch.insert('age_groups', {
              'age_group_id': group['age_group_id'], 
              'age_group_en': group['age_group_en'], // Store English name
              'age_group_tr': group['age_group_tr']  // Store Turkish name
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
          debugPrint('|10n:age_groups_synced_count: ${ageGroupsData.length}');
        } else {
          debugPrint('|10n:age_groups_fetch_no_data_empty_list');
        }
      } else {
        // Handle cases where response is not a List (e.g., error object or unexpected structure)
        debugPrint('|10n:age_groups_fetch_error_unexpected_response_type: ${response.runtimeType}');
        // You might want to check for specific error types from Supabase here
        // e.g., if (response is PostgrestError) { debugPrint(response.message); }
      }
    } catch (e) {
      debugPrint('|10n:age_groups_sync_error: $e');
      // This catch block will handle network errors or if SupabaseConfig.client itself throws.
    }
  }

  Future<List<Map<String, dynamic>>> getAgeGroups() async {
    if (kIsWeb) return [];
    final dbClient = await _db;
    return await dbClient.query('age_groups', orderBy: 'age_group_id');
  }

  /// Sadece allowedAthleteIds listesinde olmayan athlete_id'lere ait kayıtları siler
  Future<void> cleanUpLocalCompetitions({required List<String> allowedAthleteIds}) async {
    if (kIsWeb) return;
    final db = await _db;
    if (allowedAthleteIds.isEmpty) return;
    final placeholders = List.filled(allowedAthleteIds.length, '?').join(',');
    await db.delete(
      'competition_records',
      where: 'athlete_id NOT IN ($placeholders)',
      whereArgs: allowedAthleteIds,
    );
  }

  /// Supabase'den gelen yarışmaları batch olarak local veritabanına ekler
  Future<void> batchInsertCompetitions(List<dynamic> remoteList) async {
    if (kIsWeb) return;
    final db = await _db;
    final batch = db.batch();
    final allowedKeys = [
      'competition_id', 'athlete_id', 'competition_date', 'competition_name',
      'distance', 'qualification_rank', 'final_rank', 'environment', 'bow_type',
      'max_score', 'created_at', 'updated_at', 'qualification_score', 'is_deleted', 'pending_sync',
      'age_group', 'team_result', 'team_type'
    ];
    for (final remote in remoteList) {
      final filtered = <String, dynamic>{};
      for (final entry in remote.entries) {
        if (allowedKeys.contains(entry.key)) {
          if (entry.key == 'is_deleted') {
            filtered['is_deleted'] = (entry.value == true) ? 1 : 0;
          } else {
            filtered[entry.key] = entry.value;
          }
        }
      }
      filtered['pending_sync'] = 0;
      debugPrint('|10n:batchInsert filtered: competition_id=${filtered['competition_id']}, team_type=${filtered['team_type']}, team_result=${filtered['team_result']}');
      await db.insert('competition_records', filtered, conflictAlgorithm: ConflictAlgorithm.replace);
      final inserted = await db.query('competition_records', where: 'competition_id = ?', whereArgs: [filtered['competition_id']]);
      if (inserted.isNotEmpty) {
        debugPrint('|10n:batchInsert inserted_row: competition_id=${inserted[0]['competition_id']}, team_type=${inserted[0]['team_type']}, team_result=${inserted[0]['team_result']}');
      }
    }
    final all = await db.query('competition_records');
    debugPrint('|10n:competition_local_all_count: ${all.length}');
  }

  // Team Types Methods
  Future<bool> isTeamTypesTableEmpty() async {
    if (kIsWeb) return true;
    final dbClient = await _db;
    final count = Sqflite.firstIntValue(await dbClient.rawQuery('SELECT COUNT(*) FROM team_types'));
    return count == 0;
  }

  Future<void> syncTeamTypesFromSupabase({bool forceRefresh = false}) async {
    if (kIsWeb) return;

    if (forceRefresh) {
      debugPrint('|10n:team_types_force_refresh_clearing_local');
      final dbClient = await _db;
      await dbClient.delete('team_types'); // Clear local table
    } else {
      final isLocalEmpty = await isTeamTypesTableEmpty();
      if (!isLocalEmpty) {
        debugPrint('|10n:team_types_local_not_empty_skipping_sync_unless_forced');
        return;
      }
    }

    debugPrint('|10n:team_types_sync_attempt');
    try {
      final dynamic response = await SupabaseConfig.client
          .from('team_types')
          .select('team_type_id, team_type_en, team_type_tr');

      if (response is List) {
        final List<Map<String, dynamic>> teamTypesData = List<Map<String, dynamic>>.from(
          response.map((item) {
            if (item is Map<String, dynamic>) {
              return item;
            }
            return Map<String, dynamic>.from(item as Map);
          })
        );

        if (teamTypesData.isNotEmpty) {
          final dbClient = await _db;
          final batch = dbClient.batch();
          for (var type in teamTypesData) {
            batch.insert('team_types', {
              'team_type_id': type['team_type_id'],
              'team_type_en': type['team_type_en'],
              'team_type_tr': type['team_type_tr']
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
          debugPrint('|10n:team_types_synced_count: \\${teamTypesData.length}');
        } else {
          debugPrint('|10n:team_types_fetch_no_data_empty_list');
        }
      } else {
        debugPrint('|10n:team_types_fetch_error_unexpected_response_type: \\${response.runtimeType}');
      }
    } catch (e) {
      debugPrint('|10n:team_types_sync_error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getTeamTypes() async {
    if (kIsWeb) return [];
    final dbClient = await _db;
    return await dbClient.query('team_types', orderBy: 'team_type_id');
  }

  /// Supabase'den kullanıcının tüm yarışmalarını çekip local veritabanına kaydeder
  Future<void> syncAllCompetitionsFromSupabase(String athleteId) async {
    final response = await SupabaseConfig.client
        .from('competition_records')
        .select('*')
        .eq('athlete_id', athleteId)
        .eq('is_deleted', 0);
    if (response is List && response.isNotEmpty) {
      final db = await _db;
      final batch = db.batch();
      // Sadece localdeki kolonları bırak
      final allowedKeys = [
        'competition_id', 'athlete_id', 'competition_name', 'max_score', 'distance',
        'environment', 'bow_type', 'competition_date', 'final_rank', 'qualification_rank',
        'qualification_score', 'age_group', 'created_at', 'updated_at', 'is_deleted', 'pending_sync',
        'team_type', 'team_result'
      ];
      for (final comp in response) {
        final filtered = <String, dynamic>{};
        for (final entry in comp.entries) {
          if (allowedKeys.contains(entry.key)) {
            filtered[entry.key] = entry.value;
          }
        }
        debugPrint('|10n:syncAllComp filtered: competition_id=${filtered['competition_id']}, team_type=${filtered['team_type']}, team_result=${filtered['team_result']}');
        batch.insert('competition_records', filtered, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Yeni sütunlar: team_result ve team_type
    if (oldVersion < 8) {
      try {
        final tableInfo = await db.rawQuery('PRAGMA table_info(competition_records)');
        final hasTeamResult = tableInfo.any((column) => column['name'] == 'team_result');
        if (!hasTeamResult) {
          await db.execute('ALTER TABLE competition_records ADD COLUMN team_result INTEGER');
        }
        final hasTeamType = tableInfo.any((column) => column['name'] == 'team_type');
        if (!hasTeamType) {
          await db.execute('ALTER TABLE competition_records ADD COLUMN team_type INTEGER');
        }
      } catch (e) {
        print('Error adding team_result/team_type columns to competition_records: $e');
      }
    }
  }

  // Diğer gerekli methodlar burada tanımlanabilir
}
