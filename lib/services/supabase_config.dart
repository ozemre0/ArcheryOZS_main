import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://xxxxxxxxxxxxxxx.supabase.co';
  static const String supabaseAnonKey =
      'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

  static final client = Supabase.instance.client;
}
