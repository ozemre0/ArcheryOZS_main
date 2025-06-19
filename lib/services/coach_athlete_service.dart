import '../services/supabase_config.dart';
import '../services/database_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';

class CoachAthleteService {
  final _supabase = SupabaseConfig.client;
  final _database = DatabaseService();

  // Cache mekanizması için kullanılacak statik değişkenler
  static final Map<String, List<Map<String, dynamic>>> _athletesByCoachCache = {};
  static final Map<String, List<Map<String, dynamic>>> _coachesByAthleteCache = {};
  static final Map<String, DateTime> _lastFetchTime = {};

  static const Duration _cacheDuration = Duration(minutes: 10);

  // Cache'in geçerlilik süresinin dolup dolmadığını kontrol eder
  bool _isCacheValid(String cacheKey) {
    if (!_lastFetchTime.containsKey(cacheKey)) return false;
    final lastFetch = _lastFetchTime[cacheKey]!;
    final now = DateTime.now();
    return now.difference(lastFetch) < _cacheDuration;
  }

  // İnternet bağlantısını kontrol eden yardımcı metod
  Future<bool> _hasInternetConnection() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // SQLite veritabanında antrenör-sporcu ilişkisi tablosunun varlığını kontrol et ve yoksa oluştur
  Future<void> _ensureCoachAthleteTableExists() async {
    final db = await _database.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS coach_athlete_relations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        athlete_id TEXT NOT NULL,
        coach_id TEXT NOT NULL,
        athlete_data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(athlete_id, coach_id)
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS coach_athlete_coach_id_index ON coach_athlete_relations (coach_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS coach_athlete_athlete_id_index ON coach_athlete_relations (athlete_id)');
  }

  // Lokal veritabanına sporcu verilerini kaydet
  Future<void> _saveAthleteToLocal(String athleteId, String coachId,
      Map<String, dynamic> athleteData) async {
    await _ensureCoachAthleteTableExists();
    final db = await _database.database;

    final now = DateTime.now().toIso8601String();

    try {
      await db.insert(
          'coach_athlete_relations',
          {
            'athlete_id': athleteId,
            'coach_id': coachId,
            'athlete_data': jsonEncode(athleteData),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      print('Local storage error: $e');
      throw Exception('Yerel veritabanına kayıt başarısız oldu');
    }
  }

  // Lokal veritabanından sporcu verilerini getir
  Future<List<Map<String, dynamic>>> getAthletesByCoach(String coachId) async {
    final cacheKey = 'coach_$coachId';
    final hasInternet = await _hasInternetConnection();

    // Cache geçerliyse cache'den döndür
    if (_isCacheValid(cacheKey) &&
        _athletesByCoachCache.containsKey(cacheKey)) {
      return _athletesByCoachCache[cacheKey]!;
    }

    try {
      List<Map<String, dynamic>> athletesWithProfiles = [];

      if (hasInternet) {
        // 1. Tüm athlete_id'leri ve status bilgisini çek
        final relationResult = await _supabase
            .from('athlete_coach')
            .select('athlete_id, status')
            .eq('coach_id', coachId);

        if (relationResult.isNotEmpty) {
          // 2. Sadece status == 'accepted' olanları filtrele
          final List<String> athleteIds = relationResult
              .where((rel) => rel['status'] == 'accepted')
              .map<String>((rel) => rel['athlete_id'] as String)
              .toList();

          if (athleteIds.isNotEmpty) {
            // 3. Tüm profilleri tek sorguda çek (Supabase Dart SDK: filter('id', 'in', ...))
            final profiles = await _supabase
                .from('profiles')
                .select()
                .filter('id', 'in', '(${athleteIds.join(",")})');

            // 4. Her profili athlete_id ile eşleştir
            for (final profile in profiles) {
              final athleteId = profile['id'];
              final athleteData = {
                'athlete_id': athleteId,
                'first_name': profile['first_name'],
                'last_name': profile['last_name'],
                'email': profile['email'] ?? '',
                'phone_number': profile['phone_number'],
                'gender': profile['gender'],
                'birth_date': profile['birth_date'],
                'photo': profile['photo'],
                'photo_url': profile['photo_url'],
              };

              // Eğer photo_url varsa, Supabase URL'sini tam URL olarak oluştur
              if (profile['photo_url'] != null &&
                  profile['photo_url'].toString().isNotEmpty) {
                if (!profile['photo_url'].toString().startsWith('http')) {
                  final publicUrl = _supabase.storage
                      .from('profile_photos')
                      .getPublicUrl(profile['photo_url']);
                  athleteData['photo_url'] = publicUrl;
                }
              }

              // Yaşı hesapla
              if (profile['birth_date'] != null) {
                final birthDate = DateTime.parse(profile['birth_date']);
                final now = DateTime.now();
                int age = now.year - birthDate.year;
                if (now.month < birthDate.month ||
                    (now.month == birthDate.month && now.day < birthDate.day)) {
                  age--;
                }
                athleteData['age'] = age;
              }

              athletesWithProfiles.add(athleteData);

              // Yerel veritabanına kaydet
              await _saveAthleteToLocal(athleteId, coachId, athleteData);
            }
          }
        }
      } else {
        // İnternet yoksa yerel veritabanından al
        final db = await _database.database;
        final results = await db.query(
          'coach_athlete_relations',
          where: 'coach_id = ?',
          whereArgs: [coachId],
        );

        athletesWithProfiles = results.map((row) {
          final data = jsonDecode(row['athlete_data'] as String);
          return Map<String, dynamic>.from(data);
        }).toList();
      }

      // Cache'e kaydet
      _athletesByCoachCache[cacheKey] = athletesWithProfiles;
      _lastFetchTime[cacheKey] = DateTime.now();

      return athletesWithProfiles;
    } catch (e) {
      print('Error fetching athletes: $e');
      // Hata durumunda yerel veritabanından almayı dene
      try {
        final db = await _database.database;
        final results = await db.query(
          'coach_athlete_relations',
          where: 'coach_id = ?',
          whereArgs: [coachId],
        );

        final athletes = results.map((row) {
          final data = jsonDecode(row['athlete_data'] as String);
          return Map<String, dynamic>.from(data);
        }).toList();

        return athletes;
      } catch (localError) {
        print('Local database error: $localError');
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> getCoachesByAthlete(
      String athleteId) async {
    final cacheKey = 'athlete_$athleteId';
    final hasInternet = await _hasInternetConnection();

    // Cache geçerliyse cache'den döndür
    if (_isCacheValid(cacheKey) &&
        _coachesByAthleteCache.containsKey(cacheKey)) {
      return _coachesByAthleteCache[cacheKey]!;
    }

    try {
      List<Map<String, dynamic>> coachesWithProfiles = [];

      if (hasInternet) {
        // İnternet varsa Supabase'den çek, sadece status == 'accepted' olanları al
        final result = await _supabase
            .from('athlete_coach')
            .select(
                'coach_id, status, coaches!athlete_coach_coach_id_fkey(coach_id, profile_id)')
            .eq('athlete_id', athleteId)
            .eq('status', 'accepted');

        for (var item in result) {
          final coach = item['coaches'];
          final profile = await _supabase
              .from('profiles')
              .select()
              .eq('id', coach['profile_id'])
              .single();

          final coachData = {
            'coach_id': coach['coach_id'],
            'first_name': profile['first_name'],
            'last_name': profile['last_name'],
            'email': profile['email'] ?? '',
          };

          coachesWithProfiles.add(coachData);
        }
      } else {
        // İnternet yoksa yerel veritabanından al
        final db = await _database.database;
        final results = await db.query(
          'coach_athlete_relations',
          where: 'athlete_id = ?',
          whereArgs: [athleteId],
        );

        // If you store status locally, filter here as well
        coachesWithProfiles = results.map((row) {
          final data = jsonDecode(row['coach_data'] as String);
          // If status is stored, only add if accepted
          if (data['status'] == null || data['status'] == 'accepted') {
            return Map<String, dynamic>.from(data);
          }
          return null;
        }).whereType<Map<String, dynamic>>().toList();
      }

      // Cache'e kaydet
      _coachesByAthleteCache[cacheKey] = coachesWithProfiles;
      _lastFetchTime[cacheKey] = DateTime.now();

      return coachesWithProfiles;
    } catch (e) {
      print('Error fetching coaches: $e');
      // Hata durumunda yerel veritabanından almayı dene
      try {
        final db = await _database.database;
        final results = await db.query(
          'coach_athlete_relations',
          where: 'athlete_id = ?',
          whereArgs: [athleteId],
        );

        final coaches = results.map((row) {
          final data = jsonDecode(row['coach_data'] as String);
          if (data['status'] == null || data['status'] == 'accepted') {
            return Map<String, dynamic>.from(data);
          }
          return null;
        }).whereType<Map<String, dynamic>>().toList();

        return coaches;
      } catch (localError) {
        print('Local database error: $localError');
        return [];
      }
    }
  }

  Future<void> syncCoachAthleteData(String userId, String userRole) async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      print('Senkronizasyon için internet bağlantısı gerekli');
      return;
    }

    try {
      if (userRole == 'coach') {
        // Antrenörün sporcularını yeniden yükle ve yerel veritabanına kaydet
        await getAthletesByCoach(userId);
      } else if (userRole == 'athlete') {
        // Sporcunun antrenörlerini yeniden yükle ve yerel veritabanına kaydet
        await getCoachesByAthlete(userId);
      }

      // Cache'i temizle
      clearCache();
    } catch (e) {
      print('Senkronizasyon hatası: $e');
      throw Exception('Senkronizasyon başarısız: ${e.toString()}');
    }
  }

  // Sporcu ve antrenör bağlantısını kontrol et
  Future<void> linkAthleteToCoach(String athleteId, String coachId) async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      throw Exception('Bu işlem için internet bağlantısı gerekiyor');
    }

    try {
      // Önce sporcu ve antrenör profillerini kontrol et
      final athleteProfile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', athleteId)
          .single();

      final coachProfile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', coachId)
          .single();

      if (athleteProfile['role'] != 'athlete') {
        throw Exception('Geçersiz sporcu ID\'si');
      }

      if (coachProfile['role'] != 'coach') {
        throw Exception('Geçersiz antrenör ID\'si');
      }

      // Bağlantıyı oluştur
      await _supabase.from('athlete_coach').insert({
        'athlete_id': athleteId,
        'coach_id': coachId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Cache'i temizle
      _athletesByCoachCache.remove('coach_$coachId');
      _coachesByAthleteCache.remove('athlete_$athleteId');
    } catch (e) {
      print('Error linking athlete to coach: $e');
      throw Exception('Bağlantı oluşturulamadı: ${e.toString()}');
    }
  }

  // Sporcu ve antrenör bağlantısını kaldır
  Future<void> unlinkAthleteFromCoach(String athleteId, String coachId) async {
    try {
      final hasInternet = await _hasInternetConnection();

      if (hasInternet) {
        // Supabase'den bağlantıyı sil
        await _supabase
            .from('athlete_coach')
            .delete()
            .match({'athlete_id': athleteId, 'coach_id': coachId});
      }

      // Yerel veritabanından da sil
      final db = await _database.database;
      await db.delete(
        'coach_athlete_relations',
        where: 'athlete_id = ? AND coach_id = ?',
        whereArgs: [athleteId, coachId],
      );

      // Cache'i temizle
      _athletesByCoachCache.remove('coach_$coachId');
      _coachesByAthleteCache.remove('athlete_$athleteId');

      // Eğer çevrimdışıysak, internet geldiğinde senkronize edilmek üzere işareti koy
      if (!hasInternet) {
        // TODO: Senkronizasyon kuyruğuna ekle
      }
    } catch (e) {
      print('Error unlinking athlete from coach: $e');
      throw Exception('Bağlantı kaldırılamadı: ${e.toString()}');
    }
  }

  // Cache'i temizle
  void clearCache() {
    _athletesByCoachCache.clear();
    _coachesByAthleteCache.clear();
    _lastFetchTime.clear();
  }
}
