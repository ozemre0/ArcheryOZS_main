import 'dart:async';
import 'dart:io' as io show Platform, InternetAddress, SocketException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Gesture işlemleri için gerekli
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_config.dart';
import 'services/database_service.dart'; // Veritabanı migrasyon işlemleri için
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/profile_setup_screen.dart';
import 'providers/theme_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'widgets/utils/touch_handler_widget.dart'; // Yeni eklenen dokunmatik ekran optimizasyon widget'ı
import 'screens/coach/coach_athlete_list_screen.dart';

// RouteObserver for navigation events (global, tek bir defa tanımlanır)
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// Dokunmatik ekran kilitlenmelerini önlemek için touch event'leri yeniden yapılandıran metod
void _configureSystemSettings() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  // Web platformunda çalışmayan özellikleri kontrol et
  if (!kIsWeb) { 
    // Touch geri bildirimi açık (haptic feedback)
    SystemChannels.platform.invokeMethod('HapticFeedback.vibrate');

    // Dokunmatik girişlerle ilgili ayarlar
    GestureBinding.instance.resamplingEnabled =
        true; // Daha akıcı dokunmatik tepkiler

    // Android'e özel dokunmatik ayarlar - io.Platform sadece web dışında çalışır
    try {
      if (io.Platform.isAndroid) {
        SystemChannels.platform
            .invokeMethod('SystemChrome.setSystemGestureExclusionRects', []);
      }
    } catch (e) {
      // Platform özelliği kullanılamadığında sessizce devam et
      debugPrint('Platform detection failed: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sadece portre moduna izin ver (yan çevirmeyi engelle)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Dokunmatik ekran ayarlarını yapılandır
  _configureSystemSettings();

  // App'deki olası kilitlenmeleri önlemek için error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    print('FLUTTER ERROR: ${details.exception}');
    print('STACK TRACE: ${details.stack}');
  };

  // Web platformunda yeniden yüklemeler sırasında Supabase'in tekrar
  // initialize edilmesini önlemek için kontrol eklendi
  if (kIsWeb) {
    try {
      // Supabase zaten initialize edilmiş mi kontrol et
      Supabase.instance.client; // Sadece erişerek kontrol et, değişkene atama
      print('Supabase already initialized, reusing instance');
    } catch (e) {
      // Henüz initialize edilmemiş, ilk kez initialize et
      print('Initializing Supabase for the first time');
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
        debug: false, // Web'de debug false yaparak gereksiz log'ları azalt
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
    }
  } else {
    // Mobil platformlarda normal initialize işlemi
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      debug: true,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  // Veritabanı migrasyonu
  try {
    print('Running database migration to series_data...');
    // await DatabaseService().migrateToSeriesDataOnly();
    print('Database migration completed successfully');
  } catch (e) {
    print('Error during database migration: $e');
    // Migrasyon hatası uygulamayı çökertmemeli
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static MyAppState of(BuildContext context) {
    return context.findAncestorStateOfType<MyAppState>()!;
  }

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  Key _appKey = UniqueKey();
  bool _initialized = false;
  Widget? _initialScreen;
  late final StreamSubscription<AuthState> _authSubscription;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _storage = const FlutterSecureStorage();
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _setupAuthAndInitialScreen();
    _loadSavedLocale();
  }

  // Internet bağlantısını kontrol eden fonksiyon
  Future<bool> _checkInternetConnection() async {
    if (kIsWeb) {
      // Web platformunda bağlantı kontrolü
      try {
        // Web için basit bir HTTP isteği ile bağlantı kontrolü
        final response =
            await Future.delayed(const Duration(seconds: 1), () => true);
        return response;
      } catch (_) {
        return false;
      }
    } else {
      // Mobil platformlarda bağlantı kontrolü
      try {
        final result = await io.InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } on io.SocketException catch (_) {
        return false;
      } on TimeoutException catch (_) {
        return false;
      }
    }
  }

  // Web'de tekrar eden oturum değişikliklerini önleyen koruma
  bool _isHandlingAuth = false;
  DateTime? _lastAuthTime;

  Future<void> _setupAuthAndInitialScreen() async {
    // Web için optimizasyon: Auth değişikliklerini önlemek için debounce
    _authSubscription =
        SupabaseConfig.client.auth.onAuthStateChange.listen((data) {
      // Web platformunda çoklu auth eventlerini filtrele
      if (kIsWeb) {
        // Son auth işlemi 1000ms içinde olduysa yoksay (500ms'den 1000ms'e çıkarıldı)
        final now = DateTime.now();
        if (_lastAuthTime != null &&
            now.difference(_lastAuthTime!).inMilliseconds < 1000) {
          print('Web platform: Ignoring duplicate auth event');
          return;
        }
        _lastAuthTime = now;

        // Eğer zaten bir auth işlemi devam ediyorsa, yeni istekleri engelle
        if (_isHandlingAuth) {
          print(
              'Web platform: Auth process already in progress, ignoring duplicate event');
          return;
        }

        // Auth işlem bayrağını ayarla
        _isHandlingAuth = true;

        // Auth işlemini gerçekleştir ve bittiğinde bayrağı temizle
        Future.microtask(() async {
          try {
            await _handleAuthStateChange(data.event, data.session);
          } finally {
            _isHandlingAuth = false;
          }
        });

        return; // Web'de async işleme geçtik, burada return edelim
      }

      // Mobil platformlarda normal davranış devam ediyor
      _handleAuthStateChange(data.event, data.session);
    });

    await _checkInitialSession();
  }

  Future<void> _checkInitialSession() async {
    try {
      bool isTimedOut = false;
      Timer timer = Timer(const Duration(seconds: 2), () {
        isTimedOut = true;
        print('|10n:session_check_timeout');
        if (mounted) {
          _navigateToScreen(const LoginScreen());
        }
      });
      final session = SupabaseConfig.client.auth.currentSession;
      timer.cancel();
      if (!isTimedOut) {
        if (session != null) {
          // PROFIL KONTROLÜ: HomeScreen'e geçmeden önce profil setup var mı bak
          final user = session.user;
          try {
            final profileData = await SupabaseConfig.client
                .from('profiles')
                .select()
                .eq('id', user.id)
                .maybeSingle();
            if (profileData == null) {
              _navigateToScreen(const ProfileSetupScreen());
            } else {
              _navigateToScreen(const HomeScreen());
            }
          } catch (e) {
            // PROFIL ÇEKİLEMEDİ (ör. internet yok): YİNE DE HomeScreen'e yönlendir!
            print('|10n:profile_load_error_but_session_exists: '
                '[38;5;1m$e[0m');
            _navigateToScreen(const HomeScreen());
          }
          _backgroundAuthCheck(session); // Arka planda sync devam etsin
        } else if (mounted) {
          setState(() {
            _initialScreen = const LoginScreen();
            _initialized = true;
          });
        }
      }
    } catch (e) {
      print('|10n:session_check_error: $e');
      if (mounted) {
        setState(() {
          _initialScreen = const LoginScreen();
          _initialized = true;
        });
      }
    }
  }

  // Arka planda auth kontrolü yapan yeni metod
  Future<void> _backgroundAuthCheck(Session session) async {
    try {
      final hasInternet = await _checkInternetConnection();
      final user = session.user;
      if (hasInternet && user != null) {
        Future.microtask(() async {
          try {
            print('|10n:background_sync_started');
            final trainingHistoryService = DatabaseService();
            await trainingHistoryService.syncAllTrainingsFromSupabase(user.id);
            print('|10n:background_sync_completed');
          } catch (e) {
            print('|10n:background_sync_error: $e');
          }
        });
        // PROFIL KONTROLÜ: Eğer profil yoksa ProfileSetupScreen'e yönlendir
        Future.microtask(() async {
          try {
            final profileData = await SupabaseConfig.client
                .from('profiles')
                .select()
                .eq('id', user.id)
                .maybeSingle()
                .timeout(const Duration(seconds: 3));
            if (profileData == null && mounted) {
              _navigateToScreen(const ProfileSetupScreen());
            }
          } catch (e) {
            print('|10n:background_profile_check_error: $e');
          }
        });
      }
    } catch (e) {
      print('|10n:background_auth_check_error: $e');
    }
  }

  Future<void> _handleAuthStateChange(
      AuthChangeEvent event, Session? session) async {
    print('|10n:auth_state_changed: $event, session: [38;5;2m${session?.user.email}[0m');
    if (event == AuthChangeEvent.signedIn && session != null) {
      // PROFIL KONTROLÜ: HomeScreen'e geçmeden önce profil setup var mı bak
      final user = session.user;
      final profileData = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (profileData == null) {
        _navigateToScreen(const ProfileSetupScreen());
      } else {
        _navigateToScreen(const HomeScreen());
      }
      _backgroundAuthCheck(session); // Arka planda sync devam etsin
    } else if (event == AuthChangeEvent.signedOut) {
      print('|10n:user_signed_out');
      _navigateToScreen(const LoginScreen());
    }
  }

  void _navigateToScreen(Widget screen) {
    if (!mounted) return;

    setState(() {
      _initialScreen = screen;
      _initialized = true;
    });

    // Use PageRouteBuilder for smoother transitions
    if (_navigatorKey.currentState != null) {
      _navigatorKey.currentState!.pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => screen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 200),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _loadSavedLocale() async {
    final String? languageCode = await _storage.read(key: 'language');
    if (languageCode != null && mounted) {
      setState(() {
        _locale = Locale(languageCode);
      });
    }
  }

  Future<void> changeLanguage(Locale newLocale) async {
    await _storage.write(key: 'language', value: newLocale.languageCode);
    if (mounted) {
      setState(() {
        _locale = newLocale;
        _appKey = UniqueKey(); // This will force the entire app to rebuild
      });
    }
  }

  void restartApp() {
    setState(() {
      _appKey = UniqueKey();
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final themeState = ref.watch(themeProvider);

      // TouchOptimizedApp ve MaterialApp'i AnimatedTheme ile sarmala
      return KeyedSubtree(
        key: _appKey,
        child: AnimatedTheme(
          data: themeState.themeMode == ThemeMode.dark
              ? ThemeData(
                  colorScheme: ColorScheme.dark(
                    primary: Colors.blue.shade300,
                    secondary: Colors.blueAccent.shade100,
                    background: Colors.grey[900]!,
                    surface: Colors.grey[850]!,
                  ),
                  useMaterial3: true,
                  appBarTheme: AppBarTheme(
                    backgroundColor: Colors.grey[900],
                    foregroundColor: Colors.white,
                  ),
                  scaffoldBackgroundColor: Colors.grey[900],
                )
              : ThemeData(
                  colorScheme: ColorScheme.light(
                    primary: Colors.blue,
                    secondary: Colors.blueAccent,
                    surface: Colors.white,
                    // background yerine surface kullanıldı
                  ),
                  useMaterial3: true,
                  appBarTheme: const AppBarTheme(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                ),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          child: TouchOptimizedApp(
            materialApp: MaterialApp(
              navigatorKey: _navigatorKey,
              title: 'Archery OZS',
              debugShowCheckedModeBanner: false,
              locale: _locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('en'),
                Locale('tr'),
              ],
              localeResolutionCallback: (locale, supportedLocales) {
                if (locale == null) {
                  return const Locale('en');
                }
                for (final supportedLocale in supportedLocales) {
                  if (supportedLocale.languageCode == locale.languageCode) {
                    return supportedLocale;
                  }
                }
                return const Locale('en');
              },
              builder: (context, child) {
                final mediaQuery = MediaQuery.of(context);
                return MediaQuery(
                  data: mediaQuery,
                  child: child ?? const SizedBox.shrink(),
                );
              },
              theme: ThemeData(
                colorScheme: ColorScheme.light(
                  primary: Colors.blue,
                  secondary: Colors.blueAccent,
                  surface: Colors.white,
                ),
                useMaterial3: true,
                appBarTheme: const AppBarTheme(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.dark(
                  primary: Colors.blue.shade300,
                  secondary: Colors.blueAccent.shade100,
                  background: Colors.grey[900]!,
                  surface: Colors.grey[850]!,
                ),
                useMaterial3: true,
                appBarTheme: AppBarTheme(
                  backgroundColor: Colors.grey[900],
                  foregroundColor: Colors.white,
                ),
                scaffoldBackgroundColor: Colors.grey[900],
              ),
              themeMode: themeState.themeMode,
              home: !_initialized
                  ? const Center(child: CircularProgressIndicator())
                  : (_initialScreen ??
                      Scaffold(
                        body: Center(
                          child: Text(
                            'Ana ekran yüklenemedi. Lütfen internet bağlantınızı ve Supabase ayarlarınızı kontrol edin.',
                            style: TextStyle(color: Colors.red, fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )),
              navigatorObservers: [routeObserver],
            ),
          ),
        ),
      );
    });
  }
}

// Profil ekranını AppBar ve çıkış butonu ile sarmalayan widget
class ProfileScreenWrapper extends StatelessWidget {
  const ProfileScreenWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTab),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: const ProfileScreen(),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await SupabaseConfig.client.auth.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }
}
