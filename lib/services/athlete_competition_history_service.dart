import 'package:archeryozs/services/competition_local_db.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'package:flutter/foundation.dart';

class AthleteCompetitionHistoryService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final CompetitionLocalDb _localDb = CompetitionLocalDb.instance;

  Future<List<Map<String, dynamic>>> getCompetitionHistory(
      String athleteId) async {
    if (kIsWeb) {
      try {
        final remote = await _supabase
            .from('competition_records')
            .select('*')
            .eq('athlete_id', athleteId);
        return remote.cast<Map<String, dynamic>>();
      } catch (e) {
        throw Exception('|10n competition_supabase_fetch_error');
      }
    } else {
      // Önce local, sonra Supabase
      final local = await _localDb.getCompetitionsByAthlete(athleteId);
      try {
        final remote = await _supabase
            .from('competition_records')
            .select('*')
            .eq('athlete_id', athleteId);
        return remote.cast<Map<String, dynamic>>();
      } catch (e) {
        return local;
      }
    }
  }
}
