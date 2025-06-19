import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../main.dart';
import '../providers/theme_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'timer_screen.dart';
import '../services/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Timer settings
  final _prepTimeController = TextEditingController(text: "10");
  final _shootingTimeController = TextEditingController(text: "180");
  final _warningTimeController = TextEditingController(text: "30");
  bool _enableSound = true;
  late AppLocalizations l10n;
  
  // Storage for settings
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    try {
      final prepTime = await _storage.read(key: 'timer_prep_time');
      final shootingTime = await _storage.read(key: 'timer_shooting_time');
      final warningTime = await _storage.read(key: 'timer_warning_time');
      final sound = await _storage.read(key: 'timer_sound');
      
      if (mounted) {
        setState(() {
          _prepTimeController.text = prepTime ?? "10";
          _shootingTimeController.text = shootingTime ?? "180";
          _warningTimeController.text = warningTime ?? "30";
          _enableSound = sound == null || sound == 'true'; // Default to true
        });
      }
    } catch (e) {
      // Silently fail and use defaults
    }
  }
  
  Future<void> _saveTimerSettings() async {
    try {
      await _storage.write(key: 'timer_prep_time', value: _prepTimeController.text);
      await _storage.write(key: 'timer_shooting_time', value: _shootingTimeController.text);
      await _storage.write(key: 'timer_warning_time', value: _warningTimeController.text);
      await _storage.write(key: 'timer_sound', value: _enableSound.toString());
    } catch (e) {
      // Silently fail
    }
  }

  @override
  void dispose() {
    _prepTimeController.dispose();
    _shootingTimeController.dispose();
    _warningTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    l10n = AppLocalizations.of(context);
    final themeState = ref.watch(themeProvider);
    final isDarkMode = themeState.themeMode == ThemeMode.dark;
    
    // Get current locale to determine which language is selected
    final currentLocale = Localizations.localeOf(context).languageCode;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Language Settings Section
          _buildSectionHeader(l10n.languageSettings),
          _buildSettingsCard(
            child: Column(
              children: [
                _buildLanguageOption(
                  flag: "🇹🇷", 
                  language: "Türkçe", 
                  value: "tr",
                  currentLocale: currentLocale,
                ),
                const Divider(),
                _buildLanguageOption(
                  flag: "🇬🇧", 
                  language: "English", 
                  value: "en",
                  currentLocale: currentLocale,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Theme Settings Section
          _buildSectionHeader(l10n.themeSettings),
          _buildSettingsCard(
            child: Column(
              children: [
                _buildThemeOption(
                  icon: Icons.light_mode,
                  theme: "light",
                  title: l10n.lightTheme,
                  isDarkMode: isDarkMode,
                ),
                const Divider(),
                _buildThemeOption(
                  icon: Icons.dark_mode,
                  theme: "dark",
                  title: l10n.darkTheme,
                  isDarkMode: isDarkMode,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Timer Settings Section
          _buildSectionHeader(l10n.timerSettings),
          _buildSettingsCard(
            child: Column(
              children: [
                // Prepare Time
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.prepTime,
                        style: const TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.w500
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _prepTimeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          suffixText: l10n.seconds,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => _saveTimerSettings(),
                      ),
                    ],
                  ),
                ),
                
                // Shooting Time
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.shootingTime,
                        style: const TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.w500
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _shootingTimeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          suffixText: l10n.seconds,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => _saveTimerSettings(),
                      ),
                    ],
                  ),
                ),
                
                // Warning Time
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.warningTime,
                        style: const TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.w500
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _warningTimeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          suffixText: l10n.seconds,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => _saveTimerSettings(),
                      ),
                    ],
                  ),
                ),
                
                const Divider(),
                
                // Sound
                SwitchListTile(
                  title: Text(l10n.sound),
                  value: _enableSound,
                  onChanged: (value) {
                    setState(() {
                      _enableSound = value;
                    });
                    _saveTimerSettings();
                  },
                  secondary: const Icon(Icons.volume_up),
                ),
              ],
            ),
          ),
          
          // Password Section
          const SizedBox(height: 16),
          _buildSectionHeader(l10n.passwordSettings ?? 'Password'),
          _buildSettingsCard(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.setPassword ?? 'Set/Change Password'),
              onTap: _showSetPasswordDialog,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
  
  Widget _buildSettingsCard({required Widget child}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
  
  Widget _buildLanguageOption({
    required String flag,
    required String language,
    required String value,
    required String currentLocale,
  }) {
    return ListTile(
      leading: Text(flag, style: const TextStyle(fontSize: 24)),
      title: Text(language),
      trailing: currentLocale == value
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: () {
        MyApp.of(context).changeLanguage(Locale(value));
      },
    );
  }
  
  Widget _buildThemeOption({
    required IconData icon,
    required String theme,
    required String title,
    required bool isDarkMode,
  }) {
    // Check if this theme option is the current theme
    bool isSelected = (theme == "dark") ? isDarkMode : !isDarkMode;
    
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: () {
        // Set the theme mode based on the option selected
        if ((theme == "dark" && !isDarkMode) || (theme == "light" && isDarkMode)) {
          ref.read(themeProvider.notifier).toggleTheme();
        }
      },
    );
  }

  void _showSetPasswordDialog() {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.setPasswordTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.setPasswordNew,
                    prefixIcon: const Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.setPasswordConfirm,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPassword = newPasswordController.text.trim();
                final confirmPassword = confirmPasswordController.text.trim();
                if (newPassword != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.setPasswordMismatch)),
                  );
                  return;
                }
                // Show confirmation dialog (larger)
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => Dialog(
                    insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.8,
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.lock, size: 48, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 24),
                          Text(
                            l10n.confirmPasswordChangeTitle ?? 'Confirm Password Change',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.confirmPasswordChangeContent ?? 'Are you sure you want to change your password?',
                            style: const TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: Text(l10n.cancel, style: const TextStyle(fontSize: 16)),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: Text(l10n.setPasswordSave, style: const TextStyle(fontSize: 16)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                if (confirm != true) return;
                try {
                  // Supabase password update
                  final user = await SupabaseConfig.client.auth.updateUser(
                    UserAttributes(password: newPassword),
                  );
                  if (user.user != null) {
                    if (mounted) {
                      Navigator.of(context).pop(); // Close password dialog
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.setPasswordSuccess)),
                      );
                      // Go to HomeScreen
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const HomeScreen()),
                        (route) => false,
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.setPasswordError)),
                      );
                    }
                  }
                } catch (e) {
                  // Check if password was actually changed by trying to sign in with the new password
                  try {
                    final email = SupabaseConfig.client.auth.currentUser?.email;
                    if (email != null) {
                      final response = await SupabaseConfig.client.auth.signInWithPassword(
                        email: email,
                        password: newPassword,
                      );
                      if (response.user != null) {
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.setPasswordSuccess)),
                          );
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const HomeScreen()),
                            (route) => false,
                          );
                        }
                        return;
                      }
                    }
                  } catch (_) {}
                  if (mounted) {
                    String errorMsg = l10n.setPasswordError;
                    if (e is AuthException && e.message.isNotEmpty) {
                      errorMsg += ' (${e.message})';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(errorMsg)),
                    );
                  }
                }
              },
              child: Text(l10n.setPasswordSave),
            ),
          ],
        );
      },
    );
  }
} 