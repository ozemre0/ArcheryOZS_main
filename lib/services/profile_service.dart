import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/profile_model.dart';
import './supabase_config.dart';

class ProfileService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final _storage = const FlutterSecureStorage();
  static const String _profileCacheKey = 'cached_profile';

  Future<void> _ensureAthleteRecord(String userId) async {
    try {
      await _supabase.from('athletes').insert({
        'athlete_id': userId,
        'user_id': userId,
        'profile_id': userId,
      });
    } catch (e) {
      // Eğer kayıt zaten varsa hata fırlatmayı görmezden gel
      if (!e
          .toString()
          .contains('duplicate key value violates unique constraint')) {
        rethrow;
      }
    }
  }

  Future<void> _ensureCoachRecord(String userId) async {
    try {
      await _supabase.from('coaches').insert({
        'coach_id': userId,
        'profile_id': userId,
      });
    } catch (e) {
      // Eğer kayıt zaten varsa hata fırlatmayı görmezden gel
      if (!e
          .toString()
          .contains('duplicate key value violates unique constraint')) {
        rethrow;
      }
    }
  }

  Future<Profile> createProfile(Profile profile) async {
    String? visibleId = profile.visibleId;

    // Eğer visibleId boş ise otomatik üret
    if (visibleId == null || visibleId.trim().isEmpty) {
      final firstInitial = profile.firstName.isNotEmpty ? profile.firstName[0].toLowerCase() : '';
      final lastInitial = profile.lastName.isNotEmpty ? profile.lastName[0].toLowerCase() : '';
      String baseId = '$firstInitial$lastInitial';
      int counter = 0;
      bool exists = true;
      while (exists) {
        final candidate = '$baseId$counter';
        final lowerCandidate = candidate.toLowerCase();
        final res = await _supabase
            .from('profiles')
            .select('id')
            .eq('visible_id', lowerCandidate)
            .maybeSingle();
        if (res == null) {
          visibleId = lowerCandidate;
          exists = false;
        } else {
          counter++;
        }
      }
    }

    final profileData = {
      'id': profile.id,
      'visible_id': visibleId,
      'first_name': profile.firstName,
      'last_name': profile.lastName,
      'role': profile.role,
      'birth_date': profile.birthDate.toIso8601String(),
      'created_at': profile.createdAt.toIso8601String(),
      'updated_at': profile.updatedAt.toIso8601String(),
      'photo_url': profile.photoUrl,
      'address': profile.address,
      'phone_number': profile.phoneNumber,
      'gender': profile.gender,
    };

    final response =
        await _supabase.from('profiles').insert(profileData).select().single();
    final createdProfile = Profile.fromJson(response);

    // Cache the new profile
    await _cacheProfile(createdProfile);

    // Role'e göre ilgili tabloya kayıt ekle
    if (profile.role == 'athlete') {
      await _ensureAthleteRecord(profile.id);
    } else if (profile.role == 'coach') {
      await _ensureCoachRecord(profile.id);
    }

    return createdProfile;
  }

  Future<Profile> updateProfile(Profile profile) async {
    final profileData = {
      'visible_id': profile.visibleId,
      'first_name': profile.firstName,
      'last_name': profile.lastName,
      'role': profile.role,
      'birth_date': profile.birthDate.toIso8601String(),
      'updated_at': profile.updatedAt.toIso8601String(),
      'photo_url': profile.photoUrl,
      'address': profile.address,
      'phone_number': profile.phoneNumber,
      'gender': profile.gender,
    };

    final currentProfile = await getProfile(profile.id);

    if (currentProfile?.role == 'coach' && profile.role != 'coach') {
      await _supabase.from('athlete_coach').delete().eq('coach_id', profile.id);
    }

    final response = await _supabase
        .from('profiles')
        .update(profileData)
        .eq('id', profile.id)
        .select()
        .single();

    final updatedProfile = Profile.fromJson(response);

    // Cache the updated profile
    await _cacheProfile(updatedProfile);

    if (profile.role == 'athlete') {
      await _ensureAthleteRecord(profile.id);
    } else if (profile.role == 'coach') {
      await _ensureCoachRecord(profile.id);
    }

    return updatedProfile;
  }

  Future<Profile?> getProfile(String userId) async {
    // Önce local'den kontrol et
    final cachedProfile = await getCachedProfile(userId);

    try {
      // Supabase'den veriyi almaya çalış (3 saniye timeout ile)
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));

      if (response != null) {
        final profile = Profile.fromJson(response);
        // Yeni veriyi cache'le
        await _cacheProfile(profile);
        return profile;
      }
    } catch (e) {
      print('Error fetching profile from Supabase: $e');
    }

    // Supabase'den veri alınamazsa cached profili döndür
    return cachedProfile;
  }

  /// Yeni: profileId ile profil arama fonksiyonu (alias)
  Future<Profile?> getProfileByProfileId(String profileId) async {
    return getProfileByVisibleId(profileId);
  }

  /// Yeni: visibleId ile profil arama fonksiyonu
  Future<Profile?> getProfileByVisibleId(String visibleId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('visible_id', visibleId)
          .maybeSingle();
      if (response != null) {
        final profile = Profile.fromJson(response);
        await _cacheProfile(profile);
        return profile;
      }
    } catch (e) {
      print('Error fetching profile by visibleId: $e');
    }
    return null;
  }

  // Cache the profile data for offline use
  Future<void> _cacheProfile(Profile profile) async {
    try {
      await _storage.write(
          key: _profileCacheKey + profile.id,
          value: jsonEncode(profile.toJson()));
    } catch (e) {
      // Handle cache error silently
      print('Error caching profile: $e');
    }
  }

  // Get profile from local cache - public method
  Future<Profile?> getCachedProfile(String userId) async {
    try {
      final cachedData = await _storage.read(key: _profileCacheKey + userId);
      if (cachedData != null) {
        return Profile.fromJson(jsonDecode(cachedData));
      }
    } catch (e) {
      print('Error reading cached profile: $e');
    }
    return null;
  }

  Stream<Profile?> streamProfile(String userId) {
    return _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((event) => event.isEmpty ? null : Profile.fromJson(event.first));
  }
}
