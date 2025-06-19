import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../services/coach_athlete_service.dart';
import '../../services/supabase_config.dart';
import 'add_coach_screen.dart';
import 'add_athlete_screen.dart';
import 'athlete_statistics_screen.dart';
import 'athlete_training_history_screen.dart';
import '../athlete_competition_history_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../../services/competition_local_db.dart';
import '../../services/competition_sync_service.dart';

// Create a screen argument class to pre-determine the user role before navigating to the screen
class CoachAthleteListArgs {
  final String userRole;

  CoachAthleteListArgs({required this.userRole});
}

// RouteObserver for navigation events
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class CoachAthleteListScreen extends StatefulWidget {
  final CoachAthleteListArgs? args;
  final VoidCallback? onPendingChanged;

  const CoachAthleteListScreen({super.key, this.args, this.onPendingChanged});

  @override
  State<CoachAthleteListScreen> createState() => _CoachAthleteListScreenState();
}

class _CoachAthleteListScreenState extends State<CoachAthleteListScreen> with RouteAware {
  final _coachAthleteService = CoachAthleteService();
  bool _isLoading = false;
  bool _isOffline = false;
  List<Map<String, dynamic>> _connections = [];
  List<Map<String, dynamic>> _filteredConnections = [];
  String? _userRole;
  StreamSubscription? _connectivitySubscription;

  // Filtre durumları
  String? _genderFilter; // 'male', 'female' veya null (filtre yok)
  String?
      _ageGroupFilter; // 'age13to14', 'age15to17', 'age18to20', 'age20plus' veya null (filtre yok)
  String _searchText = ''; // Search text for filtering by name
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Immediately set the user role if provided through args
    if (widget.args != null) {
      _userRole = widget.args!.userRole;
    }

    // Check connectivity status initially
    _checkConnectivity();

    // Listen for connectivity changes
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      final wasOffline = _isOffline;
      final isNowOffline = result == ConnectivityResult.none;

      setState(() {
        _isOffline = isNowOffline;
      });

      // If we were offline but now online, trigger a sync
      if (wasOffline && !isNowOffline) {
        _syncData();
      }

      // Reload the connections in either case to get the most recent data
      _loadConnections();
    });

    _loadConnections();

    // Listen for changes in the search field
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text;
      });
      _applyFilters();
    });
    _checkPendingRequests();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RouteObserver ile abone ol
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    // RouteObserver'dan çık
    routeObserver.unsubscribe(this);
    _searchController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Başka bir ekrandan (örn. NotificationPage) geri dönüldüğünde listeyi yenile
    _loadConnections();
    super.didPopNext();
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _isOffline = connectivityResult == ConnectivityResult.none;
    });
  }

  // Synchronize data when coming back online
  Future<void> _syncData() async {
    if (_userRole == null) return;

    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      await _coachAthleteService.syncCoachAthleteData(user.id, _userRole!);

      // Show a snackbar to inform the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veriler senkronize edildi')),
        );
      }
    }
  }

  Future<void> _loadConnections() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        // Only fetch the user role if not already provided through args
        if (_userRole == null) {
          try {
            final profile = await SupabaseConfig.client
                .from('profiles')
                .select()
                .eq('id', user.id)
                .single();
            _userRole = profile['role'] as String;
          } catch (e) {
            // Fallback to a default role if fetching fails
            _userRole = 'athlete';
          }
        }

        if (_userRole == 'athlete') {
          _connections =
              await _coachAthleteService.getCoachesByAthlete(user.id);
        } else if (_userRole == 'coach') {
          _connections = await _coachAthleteService.getAthletesByCoach(user.id);
        }
        // accepted olmayan bağlantıları filtrele
        _connections = _connections.where((conn) {
          if (conn.containsKey('status')) {
            return conn['status'] == 'accepted';
          }
          return true;
        }).toList();
        // Bağlantılar yüklenince filtreleri uygula
        _applyFilters();
        if (mounted) setState(() => _isLoading = false);

        // --- TEMİZLİK: Koç ise sadece kendi sporcularına ait yarışmalar localde kalsın ---
        if (_userRole == 'coach' && _connections.isNotEmpty) {
          final athleteIds = _connections
              .map((conn) => conn['athlete_id'])
              .where((id) => id != null && id.toString().isNotEmpty)
              .map((id) => id.toString())
              .toList();
          if (athleteIds.isNotEmpty) {
            // Sync ve temizlik işlemini arka planda başlat
            Future(() async {
              await CompetitionSyncService.syncCompetitionsBatch(athleteIds);
              await CompetitionLocalDb.instance.cleanUpLocalCompetitions(allowedAthleteIds: athleteIds);
              if (mounted) {
                debugPrint('|10n:competition_sync_success');
              }
            });
          }
        }
        // --- TEMİZLİK SONU ---
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).error(e.toString()))),
        );
      }
    }
  }

  // Filtreleri uygulama fonksiyonu
  void _applyFilters() {
    if (_connections.isEmpty) {
      _filteredConnections = [];
      return;
    }

    // Tüm bağlantılardan başla
    _filteredConnections = List<Map<String, dynamic>>.from(_connections);

    // Sadece antrenör rolü varsa ve sporcu listesi görüntüleniyorsa filtreler uygulanır
    if (_userRole == 'coach') {
      // Search text filter
      if (_searchText.isNotEmpty) {
        _filteredConnections = _filteredConnections.where((person) {
          final fullName =
              '${person['first_name'] ?? ''} ${person['last_name'] ?? ''}'
                  .toLowerCase();
          return fullName.contains(_searchText.toLowerCase());
        }).toList();
      }

      // Cinsiyet filtresini uygula
      if (_genderFilter != null) {
        _filteredConnections = _filteredConnections
            .where((person) => person['gender'] == _genderFilter)
            .toList();
      }

      // Yaş grubu filtresini uygula
      if (_ageGroupFilter != null) {
        _filteredConnections = _filteredConnections.where((person) {
          final age = person['age'];
          if (age == null) return false;

          switch (_ageGroupFilter) {
            case 'age13to14':
              return age >= 13 && age <= 14;
            case 'age15to17':
              return age >= 15 && age <= 17;
            case 'age18to20':
              return age >= 18 && age <= 20;
            case 'age20plus':
              return age > 20;
            default:
              return true;
          }
        }).toList();
      }
    }

    setState(() {});
  }

  // Clear search
  void _clearSearch() {
    _searchController.clear();
  }

  // Filtre menüsünü göster
  void _showFilterMenu() {
    // Eğer kullanıcı antrenör değilse filtre menüsünü göstermeye gerek yok
    if (_userRole != 'coach') return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final l10n = AppLocalizations.of(context);
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.filterAthletes,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          _genderFilter = null;
                          _ageGroupFilter = null;
                        });
                      },
                      child: Text(l10n.clearFilters),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Cinsiyet Filtresi
                Text(
                  l10n.filterGender,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(l10n.filterAll),
                      selected: _genderFilter == null,
                      onSelected: (selected) {
                        setModalState(() {
                          _genderFilter = null;
                        });
                      },
                    ),
                    FilterChip(
                      label: Text(l10n.filterMale),
                      selected: _genderFilter == 'male',
                      onSelected: (selected) {
                        setModalState(() {
                          _genderFilter = selected ? 'male' : null;
                        });
                      },
                    ),
                    FilterChip(
                      label: Text(l10n.filterFemale),
                      selected: _genderFilter == 'female',
                      onSelected: (selected) {
                        setModalState(() {
                          _genderFilter = selected ? 'female' : null;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Yaş Grubu Filtresi
                Text(
                  l10n.filterAge,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(l10n.filterAll),
                      selected: _ageGroupFilter == null,
                      onSelected: (selected) {
                        setModalState(() {
                          _ageGroupFilter = null;
                        });
                      },
                    ),
                    FilterChip(
                      label: Text(l10n.age13to14),
                      selected: _ageGroupFilter == 'age13to14',
                      onSelected: (selected) {
                        setModalState(() {
                          _ageGroupFilter = selected ? 'age13to14' : null;
                        });
                      },
                    ),
                    FilterChip(
                      label: Text(l10n.age15to17),
                      selected: _ageGroupFilter == 'age15to17',
                      onSelected: (selected) {
                        setModalState(() {
                          _ageGroupFilter = selected ? 'age15to17' : null;
                        });
                      },
                    ),
                    FilterChip(
                      label: Text(l10n.age18to20),
                      selected: _ageGroupFilter == 'age18to20',
                      onSelected: (selected) {
                        setModalState(() {
                          _ageGroupFilter = selected ? 'age18to20' : null;
                        });
                      },
                    ),
                    FilterChip(
                      label: Text(l10n.age20plus),
                      selected: _ageGroupFilter == 'age20plus',
                      onSelected: (selected) {
                        setModalState(() {
                          _ageGroupFilter = selected ? 'age20plus' : null;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _applyFilters();
                    },
                    child: Text(l10n.applyFilters),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAthleteDetails(Map<String, dynamic> person, AppLocalizations l10n) {
    // Debug için verileri yazdır
    print('Athlete Details:');
    print('Age: ${person['age']}');
    print('Email: ${person['email']}');
    print('Phone: ${person['phone_number']}');
    print('Address: ${person['address']}');
    print('Gender: ${person['gender']}');
    print('Photo URL: ${person['photo_url']}');

    bool hasContactInfo = person['email']?.isNotEmpty == true ||
        person['phone_number']?.isNotEmpty == true;

    bool hasPhoto = person['photo_url']?.isNotEmpty == true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${person['first_name']} ${person['last_name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasPhoto)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.network(
                      person['photo_url'],
                      height: 150,
                      width: 150,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 150,
                          width: 150,
                          color: Colors.grey[200],
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        print('Error loading image: $error');
                        return Container(
                          height: 150,
                          width: 150,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported,
                                size: 50,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.imageNotAvailable,
                                style: TextStyle(color: Colors.grey[600]),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (person['age'] != null)
                    ListTile(
                      leading: const Icon(Icons.cake),
                      title: Text('${person['age']} ${l10n.yearsOld}'),
                      dense: true,
                    ),
                  if (person['gender'] != null && person['gender'].isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(person['gender'] == 'male'
                          ? l10n.male
                          : (person['gender'] == 'female'
                              ? l10n.female
                              : person['gender'])),
                      dense: true,
                    ),
                  if (!hasContactInfo)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        l10n.noContactInfo,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  // E-posta giriş ekranında kaydedildiği için bu değer her zaman olmalı
                  // Ancak koşullara bağlı olarak ekleyelim
                  if (person['email']?.isNotEmpty == true)
                    ListTile(
                      leading: const Icon(Icons.email),
                      title: Text(person['email']),
                      dense: true,
                    ),
                  if (person['phone_number']?.isNotEmpty == true)
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: Text(person['phone_number']),
                      dense: true,
                    ),
                  // Adres bilgisi artık gösterilmeyecek
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Widget _buildAthleteListItem(
      Map<String, dynamic> person, AppLocalizations l10n) {
    IconData genderIcon = Icons.person;
    if (person['gender'] == 'male') {
      genderIcon = Icons.man;
    } else if (person['gender'] == 'female') {
      genderIcon = Icons.woman;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          // Kartın tamamına tıklanınca aksiyon menüsünü göster
          final value = await showMenu<String>(
            context: context,
            position: const RelativeRect.fromLTRB(100, 200, 100, 200), // Pozisyon özelleştirilebilir
            items: [
              PopupMenuItem<String>(
                value: 'info',
                child: Row(
                  children: [
                    const Icon(Icons.info),
                    const SizedBox(width: 10),
                    Text(l10n.personalInfo),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'stats',
                child: Row(
                  children: [
                    const Icon(Icons.analytics),
                    const SizedBox(width: 10),
                    Text(l10n.statistics),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'history',
                child: Row(
                  children: [
                    const Icon(Icons.history),
                    const SizedBox(width: 10),
                    Text(l10n.trainingHistory),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'competition_history',
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events),
                    const SizedBox(width: 10),
                    Text(l10n.competitionHistory),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'remove',
                child: Row(
                  children: [
                    const Icon(Icons.remove_circle_outline, color: Colors.red),
                    const SizedBox(width: 10),
                    Text(l10n.removeConnection,
                        style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          );
          if (value == null) return;
          switch (value) {
            case 'info':
              _showAthleteDetails(person, l10n);
              break;
            case 'stats':
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AthleteStatisticsScreen(
                    athleteId: person['athlete_id'],
                    athleteName:
                        '${person['first_name']} ${person['last_name']}',
                  ),
                ),
              );
              break;
            case 'history':
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AthleteTrainingHistoryScreen(
                    athleteId: person['athlete_id'],
                    athleteName:
                        '${person['first_name']} ${person['last_name']}',
                  ),
                ),
              );
              break;
            case 'competition_history':
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AthleteCompetitionHistoryScreen(
                    athleteId: person['athlete_id'],
                    athleteName: '${person['first_name']} ${person['last_name']}',
                  ),
                ),
              );
              break;
            case 'remove':
              final bool? confirmDelete = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text(l10n.removeConnection),
                    content: Text(
                      l10n.confirmRemoveConnection(
                        person['first_name'],
                        person['last_name'],
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l10n.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(l10n.remove),
                      ),
                    ],
                  );
                },
              );
              if (confirmDelete == true) {
                try {
                  final user = SupabaseConfig.client.auth.currentUser;
                  if (user != null) {
                    await _coachAthleteService.unlinkAthleteFromCoach(
                        person['athlete_id'], user.id);
                    await _loadConnections();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.error(e.toString()))),
                    );
                  }
                }
              }
              break;
          }
        },
        child: ListTile(
          leading: CircleAvatar(
            child: Icon(genderIcon),
          ),
          title: Text(
            '${person['first_name'] ?? ''} ${person['last_name'] ?? ''}',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          subtitle: person['age'] != null
              ? Text('${person['age']} ${l10n.yearsOld}')
              : null,
          trailing: Tooltip(
            message: l10n.tapForOptions,
            child: const Icon(Icons.touch_app, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildCoachListItem(
      Map<String, dynamic> person, AppLocalizations l10n) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.sports_kabaddi),
      ),
      title: Row(
        children: [
          Text('${person['first_name'] ?? ''} ${person['last_name'] ?? ''}'),
          const SizedBox(width: 8),
          Text(
            l10n.coachLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      subtitle: Text(person['email'] ?? ''),
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () async {
          // Antrenör silme onay dialog'u göster
          final bool? confirmDelete = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(l10n.removeConnection),
                content: Text(
                  l10n.confirmRemoveConnection(
                    person['first_name'],
                    person['last_name'],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l10n.remove),
                  ),
                ],
              );
            },
          );

          // Kullanıcı silme işlemini onayladıysa devam et
          if (confirmDelete == true) {
            try {
              final user = SupabaseConfig.client.auth.currentUser;
              if (user != null) {
                await _coachAthleteService.unlinkAthleteFromCoach(
                    user.id, person['coach_id']);
                await _loadConnections();
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.error(e.toString()))),
                );
              }
            }
          }
        },
      ),
    );
  }

  Future<void> _checkPendingRequests() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    // Sorgu: Kullanıcıya gelen pending istekler
    final pendingRequests = await SupabaseConfig.client
        .from('athlete_coach')
        .select()
        .or('coach_id.eq.${user.id},athlete_id.eq.${user.id}')
        .eq('status', 'pending')
        .neq('requester_id', user.id);
    // Sadece ilk pending isteği göster, onay/ret sonrası tekrar kontrol et
    if (pendingRequests.isNotEmpty) {
      final req = pendingRequests[0];
      String requesterRole = req['athlete_id'] == user.id ? 'coach' : 'athlete';
      String requesterId = req['requester_id'];
      // Profil bilgisi çek
      final profile = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('id', requesterId)
          .single();
      if (!mounted) return;
      final result = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('Bağlantı isteği'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${profile['first_name']} ${profile['last_name']} sizi ${requesterRole == 'coach' ? 'sporcu' : 'koç'} olarak eklemek istiyor. Onaylıyor musunuz?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('reject'),
              child: const Text('Reddet'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('accept'),
              child: const Text('Onayla'),
            ),
          ],
        ),
      );
      if (result == 'accept') {
        final response = await SupabaseConfig.client
            .from('athlete_coach')
            .update({'status': 'accepted'})
            .eq('athlete_id', req['athlete_id'])
            .eq('coach_id', req['coach_id'])
            .select();
        if (response.isNotEmpty && response[0]['status'] == 'accepted') {
          // Başarıyla güncellendi
          // Senkronizasyonu tetikle
          final user = SupabaseConfig.client.auth.currentUser;
          if (user != null) {
            if (_userRole == 'coach') {
              await _coachAthleteService.syncCoachAthleteData(user.id, 'coach');
            } else if (_userRole == 'athlete') {
              await _coachAthleteService.syncCoachAthleteData(user.id, 'athlete');
            }
          }
          // Bildirim güncelleme callback'i çağır
          if (widget.onPendingChanged != null) widget.onPendingChanged!();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Onay işlemi başarısız. Lütfen tekrar deneyin.')),
            );
          }
        }
      } else if (result == 'reject') {
        await SupabaseConfig.client
            .from('athlete_coach')
            .delete()
            .eq('athlete_id', req['athlete_id'])
            .eq('coach_id', req['coach_id']);
        // Bildirim güncelleme callback'i çağır
        if (widget.onPendingChanged != null) widget.onPendingChanged!();
      }
      // Onay/ret sonrası tekrar kontrol et, başka pending varsa göster
      await _loadConnections();
      await _checkPendingRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isCoach = _userRole == 'coach';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(isCoach ? l10n.myAthletes : l10n.myCoaches),
            if (_isOffline)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Çevrimdışı',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
          ],
        ),
        actions: [
          // Sadece antrenör rolü için filtre butonu göster
          if (isCoach)
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: l10n.filterOptions,
              onPressed: _showFilterMenu,
            ),
          // Yenile butonu
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _loadConnections,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _connections.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(isCoach ? l10n.noAthletesYet : l10n.noCoachesYet),
                      if (_isOffline)
                        const Padding(
                          padding: EdgeInsets.only(top: 16.0),
                          child: Text(
                            'İnternet bağlantınız yok',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Search bar for athletes (only for coach)
                    if (isCoach)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: l10n.searchAthletes,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchText.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: _clearSearch,
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10.0),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8.0),
                          ),
                        ),
                      ),

                    // Show filter indicators and count
                    if (isCoach &&
                        (_genderFilter != null ||
                            _ageGroupFilter != null ||
                            _searchText.isNotEmpty))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: Theme.of(context).colorScheme.surface,
                        child: Row(
                          children: [
                            Text(
                              l10n.filteredCount(
                                _filteredConnections.length,
                              ),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _genderFilter = null;
                                  _ageGroupFilter = null;
                                  _clearSearch();
                                });
                                _applyFilters();
                              },
                              child: Text(l10n.clear),
                            ),
                          ],
                        ),
                      ),

                    Expanded(
                      child: ListView.builder(
                        itemCount: isCoach
                            ? _filteredConnections.length
                            : _connections.length,
                        itemBuilder: (context, index) {
                          final person = isCoach
                              ? _filteredConnections[index]
                              : _connections[index];
                          return isCoach
                              ? _buildAthleteListItem(person, l10n)
                              : _buildCoachListItem(person, l10n);
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isOffline
            ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Çevrimdışı modda yeni bağlantı ekleyemezsiniz')),
                );
              }
            : () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => isCoach
                        ? const AddAthleteScreen()
                        : const AddCoachScreen(),
                  ),
                );
                if (result == true) {
                  await _loadConnections();
                }
              },
        child: const Icon(Icons.add),
      ),
    );
  }
}
