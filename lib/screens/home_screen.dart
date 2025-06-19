import 'package:flutter/material.dart';
import '../services/supabase_config.dart';
import '../services/profile_service.dart';
import 'login_screen.dart';
import 'profile/profile_screen.dart';
import '../widgets/settings_menu.dart';
import 'training_config_screen.dart';
import 'training_history_screen.dart';
import 'coach/coach_athlete_list_screen.dart';
import 'competition/competition_list_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'competition/active_competitions_screen.dart';
import 'competition/coach_competitions_screen.dart';
import 'timer_screen.dart';
import 'package:archeryozs/screens/notification_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'about_screen.dart';
import 'settings_screen.dart';
import '../services/version_service.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String? _userRole;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _retryCount = 0;
  static const int _maxRetryCount = 3;
  int _pendingRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _fetchPendingRequests();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVersionAndShowDialog(context);
    });
  }

  Future<void> _loadUserRole() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Kısa bir gecikme ekleyerek auth state'in doğru şekilde yüklenmesini sağla
      if (_retryCount > 0) {
        await Future.delayed(Duration(milliseconds: 300 * _retryCount));
      }
      
      final user = SupabaseConfig.client.auth.currentUser;
      
      // User null ise yeniden dene
      if (user == null) {
        print('|10n:home_screen_user_null');
        
        if (_retryCount < _maxRetryCount) {
          _retryCount++;
          print('|10n:retrying_load_user_role: $_retryCount');
          _loadUserRole();
          return;
        } else {
          // Maksimum deneme sayısına ulaşıldı
          throw Exception('|10n:user_not_found_after_retries');
        }
      }
      
      // Kullanıcı varsa profil bilgilerini al
      final profileService = ProfileService();
      final profile = await profileService.getProfile(user.id);
      
      if (mounted) {
        setState(() {
          _userRole = profile?.role;
          _isLoading = false;
          _hasError = false;
          _errorMessage = '';
          _retryCount = 0; // başarılı olduğunda retry sayacını sıfırla
        });
      }
    } catch (e) {
      print('|10n:error_loading_user_role: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = '|10n:error_loading_profile';
        });
        
        // Hata durumunda 3 saniye sonra otomatik olarak yeniden dene
        if (_retryCount < _maxRetryCount) {
          _retryCount++;
          Future.delayed(Duration(seconds: 2), () {
            if (mounted) _loadUserRole();
          });
        }
      }
    }
  }

  Future<void> _fetchPendingRequests() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _pendingRequestCount = 0);
      return;
    }
    final response = await SupabaseConfig.client
        .from('athlete_coach')
        .select()
        .or('coach_id.eq.${user.id},athlete_id.eq.${user.id}')
        .eq('status', 'pending');
    final filtered = response.where((notif) => notif['requester_id'] != user.id).toList();
    if (!mounted) return;
    setState(() {
      _pendingRequestCount = filtered.length;
    });
  }

  Future<void> _signOut(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.signOut),
        content: Text(l10n.signOutConfirm ?? 'Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SupabaseConfig.client.auth.signOut();
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  Future<void> _checkVersionAndShowDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final minVersion = await VersionService.fetchMinimumRequiredVersion();
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    if (minVersion != null && _compareVersion(currentVersion, minVersion) < 0) {
      print('[VERSION CHECK] Update required: current=$currentVersion, minimum=$minVersion');
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(l10n.updateRequired),
          content: Text(l10n.pleaseUpdateApp),
          actions: [
            TextButton(
              onPressed: () async {
                final url = 'https://play.google.com/store/apps/details?id=com.yourapp.id';
                if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url));
                }
              },
              child: Text(l10n.updateNow),
            ),
          ],
        ),
      );
    } else {
      print('[VERSION CHECK] Version check successful: current=$currentVersion, minimum=$minVersion');
    }
  }

  int _compareVersion(String v1, String v2) {
    List<int> parseParts(String v) =>
        v.split('.').map((e) {
          final numeric = RegExp(r'^(\d+)').firstMatch(e)?.group(0);
          return int.tryParse(numeric ?? '0') ?? 0;
        }).toList();
    final v1Parts = parseParts(v1);
    final v2Parts = parseParts(v2);
    for (int i = 0; i < v1Parts.length; i++) {
      if (v1Parts[i] > v2Parts[i]) return 1;
      if (v1Parts[i] < v2Parts[i]) return -1;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Hata durumunda retry butonu göster
    if (_hasError) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.appName),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48, 
                color: isDark ? Colors.redAccent : Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadUserRole,
                icon: Icon(Icons.refresh),
                label: Text('|10n:try_again'),
              ),
            ],
          ),
        ),
      );
    }

    final List<Widget> pages = [
      SingleChildScrollView(
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    // Sadece sporcu rolüne sahip kullanıcılar için antrenman özelliklerini göster
                    if (_userRole == 'athlete') ...[
                      // _buildFeatureCard(
                      //   context,
                      //   l10n.trainingSystem,
                      //   l10n.trainingSystemDesc,
                      //   Icons.sports_score,
                      //   () => Navigator.push(
                      //     context,
                      //     MaterialPageRoute(
                      //       builder: (context) => const TrainingConfigScreen(),
                      //     ),
                      //   ),
                      // ),
                      // const SizedBox(height: 16),
                      _buildFeatureCard(
                        context,
                        l10n.trainingHistory,
                        l10n.trainingHistoryDesc,
                        Icons.history,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TrainingHistoryScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureCard(
                        context,
                        l10n.competitionRecords,
                        l10n.competitionRecordsDesc,
                        Icons.emoji_events,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CompetitionListScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureCard(
                        context,
                        l10n.myCompetitionsTitle,
                        l10n.myCompetitionsDesc,
                        Icons.event_available,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ActiveCompetitionsScreen(),
                            ),
                          );
                        },
                      ),
                    ],

                    // Koç rolüne sahip kullanıcılar için Sporcularım ve Yarışmalar özelliklerini göster
                    if (_userRole == 'coach') ...[
                      _buildFeatureCard(
                        context,
                        l10n.myAthletes,
                        l10n.manageAthletesDesc,
                        Icons.people,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CoachAthleteListScreen(
                              args: CoachAthleteListArgs(userRole: 'coach'),
                              onPendingChanged: _fetchPendingRequests,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureCard(
                        context,
                        l10n.myCompetitionsTitle,
                        l10n.myCompetitionsDesc,
                        Icons.emoji_events,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const CoachCompetitionsScreen(),
                            ),
                          );
                        },
                      ),
                    ],

                    // Sporcu veya koç olmayanlar için bilgi mesajı göster
                    if (_userRole != 'athlete' &&
                        _userRole != 'coach' &&
                        _userRole != null)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          l10n.trainingOnlyAthlete,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: l10n.options,
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(l10n.appName),
      ),
      drawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.6, // responsive yarım sayfa
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  l10n.options,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: Text(l10n.timerTitle),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TimerScreen()),
                  );
                },
              ),
              ListTile(
                leading: Stack(
                  children: [
                    const Icon(Icons.notifications),
                    if (_pendingRequestCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '$_pendingRequestCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(l10n.notificationsTitle),
                onTap: () async {
                  Navigator.pop(context);
                  final user = SupabaseConfig.client.auth.currentUser;
                  if (user == null) return;
                  final response = await SupabaseConfig.client
                      .from('athlete_coach')
                      .select()
                      .or('coach_id.eq.${user.id},athlete_id.eq.${user.id}')
                      .eq('status', 'pending');
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NotificationPage(
                        notifications: response,
                        onAccept: (notif) async {
                          await SupabaseConfig.client
                              .from('athlete_coach')
                              .update({'status': 'accepted'})
                              .match({
                                'athlete_id': notif['athlete_id'],
                                'coach_id': notif['coach_id'],
                              });
                          _fetchPendingRequests();
                        },
                        onReject: (notif) async {
                          await SupabaseConfig.client
                              .from('athlete_coach')
                              .delete()
                              .match({
                                'athlete_id': notif['athlete_id'],
                                'coach_id': notif['coach_id'],
                              });
                          _fetchPendingRequests();
                        },
                      ),
                    ),
                  );
                  if (result == true) {
                    setState(() {});
                  }
                },
              ),
              if (_userRole == 'athlete')
                ListTile(
                  leading: const Icon(Icons.sports_kabaddi),
                  title: Text(l10n.myCoaches),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CoachAthleteListScreen(
                          args: CoachAthleteListArgs(userRole: 'athlete'),
                        ),
                      ),
                    );
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(l10n.settings),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.about),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AboutScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.signOut),
                onTap: () => _signOut(context),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: l10n.homeTab,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: l10n.profileTab,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context, String title,
      String description, IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final textColor = isDark ? Colors.white70 : Colors.grey[600];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: primaryColor,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor,
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: isDark ? Colors.white30 : Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AboutSectionWidget extends StatelessWidget {
  const AboutSectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.hasData ? snapshot.data!.version : '-';
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // App Logo (replace with your asset if available)
              CircleAvatar(
                radius: 36,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                child: Icon(Icons.architecture, size: 40, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.appName,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.aboutDescription,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.developer,
                style: theme.textTheme.bodySmall?.copyWith(color: isDark ? Colors.grey[400] : Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.version(version),
                style: theme.textTheme.bodySmall?.copyWith(color: isDark ? Colors.grey[400] : Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
