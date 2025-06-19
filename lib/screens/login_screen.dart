import 'package:flutter/material.dart';
import '../services/supabase_config.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'profile/profile_setup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _showEmailVerificationAlert() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.emailVerificationRequiredTitle),
          content: Text(l10n.emailVerificationLoginContent),
          actions: <Widget>[
            TextButton(
              child: Text(l10n.emailVerificationRequiredOk),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final response = await SupabaseConfig.client.auth.signInWithPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (response.user != null) {
        if (response.user!.emailConfirmedAt == null) {
          if (mounted) {
            _showEmailVerificationAlert();
          }
          return;
        }

        try {
          // Email doğrulanmış, profil kontrolü yapalım
          await SupabaseConfig.client
              .from('profiles')
              .select()
              .eq('id', response.user!.id)
              .single();

          if (mounted) {
            // Profil var, ana sayfaya yönlendir
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
        } catch (e) {
          // Profil bulunamadı, profile setup ekranına yönlendir
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => const ProfileSetupScreen()),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final currentSession = SupabaseConfig.client.auth.currentSession;
      final currentUser = SupabaseConfig.client.auth.currentUser;
      if (currentSession != null && currentUser != null) {
        print('|10n:user_already_signed_in');
        if (mounted) {
          // PROFIL KONTROLÜ: Google ile girişte de profil setup kontrolü
          try {
            final profile = await SupabaseConfig.client
                .from('profiles')
                .select()
                .eq('id', currentUser.id)
                .maybeSingle();
            if (profile == null) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const ProfileSetupScreen()),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomeScreen(),
                ),
              );
            }
          } catch (e) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => const ProfileSetupScreen()),
            );
          }
        }
        return;
      }
      final result = await SupabaseConfig.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'io.supabase.archeryozs://login-callback',
      );
      if (result) {
        print('|10n:google_auth_redirect_successful');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          final session = SupabaseConfig.client.auth.currentSession;
          final user = SupabaseConfig.client.auth.currentUser;
          if (session != null && user != null) {
            // PROFIL KONTROLÜ: Google ile giriş sonrası profil setup kontrolü
            try {
              final profile = await SupabaseConfig.client
                  .from('profiles')
                  .select()
                  .eq('id', user.id)
                  .maybeSingle();
              if (profile == null) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ProfileSetupScreen()),
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HomeScreen(),
                  ),
                );
              }
            } catch (e) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const ProfileSetupScreen()),
              );
            }
          }
        }
      } else {
        print('|10n:google_auth_redirect_failed');
      }
    } catch (e) {
      print('|10n:google_sign_in_error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkAndNavigateUser(String userId) async {
    try {
      // Profil kontrolü
      await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ProfileSetupScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginTitle)),
      resizeToAvoidBottomInset: true, // Klavye açıldığında ekranı yeniden boyutlandır
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400), // Responsive için
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: l10n.emailLabel,
                    prefixIcon: const Icon(Icons.email),
                  ),
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.passwordLabel,
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isLoading ? null : _signIn,
                    child: _isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                          )
                        : Text(l10n.loginButton),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    icon: Image.asset(
                      'assets/images/googlle (1).png',
                      height: 24,
                    ),
                    label: Text(
                      l10n.localeName == 'tr' ? 'Google ile Giriş Yap' : 'Sign in with Google',
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const RegisterScreen()),
                            );
                          },
                    child: Text(l10n.register),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
