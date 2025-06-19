import 'package:supabase_flutter/supabase_flutter.dart';

class VersionService {
  static String? _cachedMinVersion;

  static Future<String?> fetchMinimumRequiredVersion({bool forceRefresh = false}) async {
    if (_cachedMinVersion != null && !forceRefresh) {
      return _cachedMinVersion;
    }
    final response = await Supabase.instance.client
        .from('settings')
        .select('value')
        .eq('key', 'minimum_required_version')
        .single();
    _cachedMinVersion = response?['value'] as String?;
    return _cachedMinVersion;
  }
} 