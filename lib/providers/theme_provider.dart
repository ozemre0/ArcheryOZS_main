import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Tema durumunu tutan sınıf
class ThemeState {
  final ThemeMode themeMode;

  ThemeState({required this.themeMode});

  ThemeState copyWith({ThemeMode? themeMode}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

// Tema kontrolcüsü
class ThemeController extends StateNotifier<ThemeState> {
  final FlutterSecureStorage _storage;

  ThemeController(this._storage)
      : super(ThemeState(themeMode: ThemeMode.light)) {
    _loadTheme();
  }

  // Kayıtlı tema tercihini yükle
  Future<void> _loadTheme() async {
    final savedTheme = await _storage.read(key: 'theme_mode');
    if (savedTheme != null) {
      final themeMode = ThemeMode.values.firstWhere(
        (element) => element.toString() == savedTheme,
        orElse: () => ThemeMode.light,
      );
      state = state.copyWith(themeMode: themeMode);
    }
  }

  // Temayı değiştir
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _storage.write(key: 'theme_mode', value: mode.toString());
  }

  // Karanlık tema mı?
  bool get isDarkMode => state.themeMode == ThemeMode.dark;

  // Temayı değiştir
  Future<void> toggleTheme() async {
    final newMode =
        state.themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setThemeMode(newMode);
  }
}

// Tema provider'ı
final themeProvider = StateNotifierProvider<ThemeController, ThemeState>((ref) {
  return ThemeController(const FlutterSecureStorage());
});
