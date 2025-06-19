import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:archeryozs/services/competition_local_db.dart';
import 'supabase_config.dart';
import 'package:sqflite/sqflite.dart';

class CompetitionSyncService {
  /// Syncs competitions for the given athleteId.
  /// Checks Supabase for new/updated records and inserts them into local DB if different.
  /// Returns true if sync was performed, false if no internet or already up-to-date.
  static Future<bool> syncCompetitions(String athleteId) async {
    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      debugPrint('|10n No internet connection, skipping Supabase sync.');
      return false;
    }

    // Fetch from Supabase
    final remoteList = await SupabaseConfig.client
        .from('competition_records')
        .select('*')
        .eq('athlete_id', athleteId)
        .eq('is_deleted', 0);
    debugPrint('|10n Supabase competition_records count: [1m${remoteList.length}[0m');

    // --- YENİ: Supabase'de silinmiş (is_deleted=1) yarışmaları da localde güncelle ---
    final deletedRemoteList = await SupabaseConfig.client
        .from('competition_records')
        .select('competition_id, is_deleted')
        .eq('athlete_id', athleteId)
        .eq('is_deleted', 1);
    for (final deleted in deletedRemoteList) {
      final id = deleted['competition_id'];
      // Supabase'den silinen kaydın tüm alanlarını çek
      final fullRecord = await SupabaseConfig.client
          .from('competition_records')
          .select('*')
          .eq('competition_id', id)
          .maybeSingle();
      if (fullRecord != null) {
        fullRecord['is_deleted'] = 1;
        fullRecord['pending_sync'] = 0;
        await CompetitionLocalDb.instance.insertCompetition(fullRecord, pending: false);
      } else {
        // Kayıt yoksa, en azından team_type ve team_result null olarak ekle
        await CompetitionLocalDb.instance.insertCompetition({
          'competition_id': id,
          'athlete_id': athleteId,
          'is_deleted': 1,
          'pending_sync': 0,
          'team_type': null,
          'team_result': null,
        }, pending: false);
      }
      debugPrint('|10n:competition_sync_force_local_delete: $id');
    }
    // --- YENİ SONU ---

    // Fetch from local DB
    final localList =
        await CompetitionLocalDb.instance.getCompetitionsByAthlete(athleteId);
    final localMap = {
      for (var c in localList) c['competition_id'] ?? c['id']: c
    };

    bool updated = false;
    for (final remote in remoteList) {
      final id = remote['competition_id'] ?? remote['id'];
      final local = localMap[id];
      if (local == null || !_recordsEqual(remote, local)) {
        // --- DÜZELTME BAŞLANGIÇ ---
        // Sadece localdeki alanları al ve is_deleted'ı int'e çevir
        final allowedKeys = [
          'competition_id', 'athlete_id', 'competition_date', 'competition_name',
          'distance', 'qualification_rank', 'final_rank', 'environment', 'bow_type',
          'max_score', 'created_at', 'updated_at', 'qualification_score', 'is_deleted', 'pending_sync',
          'age_group', 'team_type', 'team_result'
        ];
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
        // --- DÜZELTME SONU ---
        await CompetitionLocalDb.instance
            .insertCompetition(filtered, pending: false);
        updated = true;
        debugPrint('|10n Synced competition: $id');
      }
    }
    return updated;
  }

  static bool _recordsEqual(Map a, Map b) {
    // Compare all relevant fields (can be improved as needed)
    for (final key in a.keys) {
      if (a[key]?.toString() != b[key]?.toString()) {
        return false;
      }
    }
    return true;
  }

  /// Batch sync: Birden fazla athleteId ile toplu yarışma senkronizasyonu
  static Future<bool> syncCompetitionsBatch(List<String> athleteIds) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      debugPrint('|10n No internet connection, skipping Supabase sync.');
      return false;
    }
    if (athleteIds.isEmpty) return false;

    // Supabase'den toplu çek
    final remoteList = await SupabaseConfig.client
        .from('competition_records')
        .select('*')
        .inFilter('athlete_id', athleteIds)
        .eq('is_deleted', 0);
    debugPrint('|10n Supabase batch competition_records count: [1m${remoteList.length}[0m');

    // Silinmiş kayıtları da toplu çek
    final deletedRemoteList = await SupabaseConfig.client
        .from('competition_records')
        .select('competition_id, athlete_id, is_deleted')
        .inFilter('athlete_id', athleteIds)
        .eq('is_deleted', 1);
    for (final deleted in deletedRemoteList) {
      final id = deleted['competition_id'];
      final athleteId = deleted['athlete_id'];
      await CompetitionLocalDb.instance.insertCompetition({
        'competition_id': id,
        'athlete_id': athleteId,
        'is_deleted': 1,
        'pending_sync': 0,
      }, pending: false);
      debugPrint('|10n:competition_sync_force_local_delete: $id');
    }

    // Batch local insert (yeni public fonksiyon ile)
    await CompetitionLocalDb.instance.batchInsertCompetitions(remoteList);
    debugPrint('|10n:competition_batch_inserted: ${remoteList.length}');
    return true;
  }
}
