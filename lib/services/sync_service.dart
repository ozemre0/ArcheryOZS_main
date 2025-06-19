import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/competition_local_db.dart';
import '../services/supabase_config.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  StreamSubscription? _subscription;

  void start() {
    _subscription = Connectivity().onConnectivityChanged.listen((status) async {
      if (status != ConnectivityResult.none) {
        await syncPendingCompetitions();
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
  }

  Future<void> syncPendingCompetitions() async {
    final pending = await CompetitionLocalDb.instance.getPendingCompetitions();
    for (final comp in pending) {
      try {
        if (comp['sync_status'] == 'pending_deleted') {
          // Supabase'den sil
          await SupabaseConfig.client
              .from('competition_records')
              .delete()
              .eq('competition_id', comp['competition_id']);
          debugPrint(
              '|10n:sync_supabase_deleted compId=${comp['competition_id']}');
          // Localden de kaldır
          await CompetitionLocalDb.instance
              .markCompetitionSynced(comp['competition_id']);
          continue;
        }
        // Supabase'de bu competition_id var mı kontrol et
        final existing = await SupabaseConfig.client
            .from('competition_records')
            .select('competition_id')
            .eq('competition_id', comp['competition_id'])
            .maybeSingle();

        if (existing != null && existing['competition_id'] != null) {
          // Supabase'den mevcut kaydı oku
          final supabaseComp = await SupabaseConfig.client
              .from('competition_records')
              .select('*')
              .eq('competition_id', comp['competition_id'])
              .maybeSingle();
          final String? localUpdated = comp['updated_at']?.toString();
          final String? remoteUpdated = supabaseComp?['updated_at']?.toString();
          debugPrint(
              '|10n:sync_conflict_check compId=${comp['competition_id']} localUpdated=$localUpdated remoteUpdated=$remoteUpdated');

          if (localUpdated != null && remoteUpdated != null) {
            final localTime = DateTime.tryParse(localUpdated);
            final remoteTime = DateTime.tryParse(remoteUpdated);
            if (localTime != null && remoteTime != null) {
              if (localTime.isAfter(remoteTime)) {
                // Local daha güncel, Supabase'i güncelle
                await SupabaseConfig.client.from('competition_records').update({
                  'competition_name': comp['competition_name'],
                  'competition_date': comp['competition_date'],
                  'environment': comp['environment'],
                  'distance': comp['distance'],
                  'bow_type': comp['bow_type'],
                  'qualification_score': comp['qualification_score'],
                  'final_rank': comp['final_rank'],
                  'qualification_rank': comp['qualification_rank'],
                  'created_at': comp['created_at'],
                  'updated_at': comp['updated_at'],
                  'is_deleted': comp['is_deleted'],
                }).eq('competition_id', comp['competition_id']);
                debugPrint(
                    '|10n:sync_supabase_updated_with_local compId=${comp['competition_id']}');
              } else if (remoteTime.isAfter(localTime)) {
                // Supabase daha güncel, local'i güncelle
                await CompetitionLocalDb.instance.insertCompetition(
                    Map<String, dynamic>.from(supabaseComp!),
                    pending: false);
                debugPrint(
                    '|10n:sync_local_updated_with_supabase compId=${comp['competition_id']}');
              } else {
                debugPrint(
                    '|10n:sync_both_equal compId=${comp['competition_id']}');
              }
            } else {
              debugPrint(
                  '|10n:sync_date_parse_error compId=${comp['competition_id']}');
            }
          } else {
            // Tarih yoksa default olarak Supabase'i güncelle
            await SupabaseConfig.client.from('competition_records').update({
              'competition_name': comp['competition_name'],
              'competition_date': comp['competition_date'],
              'environment': comp['environment'],
              'distance': comp['distance'],
              'bow_type': comp['bow_type'],
              'qualification_score': comp['qualification_score'],
              'final_rank': comp['final_rank'],
              'qualification_rank': comp['qualification_rank'],
              'created_at': comp['created_at'],
              'updated_at': comp['updated_at'],
              'is_deleted': comp['is_deleted'],
            }).eq('competition_id', comp['competition_id']);
            debugPrint(
                '|10n:sync_supabase_updated_no_date compId=${comp['competition_id']}');
          }
        } else {
          // Kayıt yoksa insert et
          await SupabaseConfig.client.from('competition_records').insert({
            'competition_id': comp['competition_id'],
            'athlete_id': comp['athlete_id'],
            'competition_name': comp['competition_name'],
            'competition_date': comp['competition_date'],
            'environment': comp['environment'],
            'distance': comp['distance'],
            'bow_type': comp['bow_type'],
            'qualification_score': comp['qualification_score'],
            'final_rank': comp['final_rank'],
            'qualification_rank': comp['qualification_rank'],
            'created_at': comp['created_at'],
            'updated_at': comp['updated_at'],
            'is_deleted': comp['is_deleted'],
          });
          debugPrint(
              '|10n:sync_supabase_inserted compId=${comp['competition_id']}');
        }
        // Her iki durumda da localde pending kaldır
        await CompetitionLocalDb.instance
            .markCompetitionSynced(comp['competition_id']);
      } catch (e) {
        // Hata yönetimi: logla veya kullanıcıya göster
      }
    }
  }
}
