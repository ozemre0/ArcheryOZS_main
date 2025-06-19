import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/supabase_config.dart';
import 'package:archeryozs/services/competition_local_db.dart';

import 'package:flutter/foundation.dart';
import 'add_competition_screen.dart';
import 'edit_competition_screen.dart';
import 'dart:async';

class CompetitionListScreen extends StatefulWidget {
  const CompetitionListScreen({super.key});

  @override
  State<CompetitionListScreen> createState() => _CompetitionListScreenState();
}

class _CompetitionListScreenState extends State<CompetitionListScreen> {
  // İki map'in eşitliğini karşılaştırmak için yardımcı fonksiyon
  bool _mapsEqual(Map a, Map b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  bool _isLoading = true;
  List<Map<String, dynamic>> _competitions = [];
  String _environmentFilter = 'all';

  // Map to store resolved age group names (id -> name)
  Map<int, String> _resolvedAgeGroupNames = {};

  // Toplu silme işlemi için gerekli state değişkenleri
  bool _isSelectionMode = false;
  final Set<String> _selectedCompetitions = {};

  // Connectivity listener for network status changes
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isSyncing = false; // Senkronizasyon durumunu takip etmek için

  // Date filter state variables
  DateTime? _startDate;
  DateTime? _endDate;
  bool _dateFilterActive = false;

  // Team type id -> name map
  Map<String, String> _teamTypeNames = {};

  // Bekleyen yarışma kayıtlarını senkronize et
  Future<void> _syncPendingCompetitionsToSupabase() async {
    if (_isSyncing) {
      print('Senkronizasyon zaten devam ediyor, atlanıyor...');
      return;
    }

    try {
      _isSyncing = true;
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        print('İnternet bağlantısı yok, senkronizasyon iptal edildi');
        return;
      }
      final pendingCompetitions =
          await CompetitionLocalDb.instance.getPendingCompetitions(); 
      if (pendingCompetitions.isEmpty) {
        print('Senkronize edilecek bekleyen yarışma kaydı yok');
        return;
      }
      print(
          '${pendingCompetitions.length} adet bekleyen yarışma kaydı senkronize ediliyor...');
      for (final competition in pendingCompetitions) {
        try {
          // Silme durumunu kontrol et (pending_deleted veya is_deleted = 1 ise)
          final bool isDeleted =
              competition['sync_status'] == 'pending_deleted' ||
                  competition['is_deleted'] == 1;

          // Supabase'de bu competition_id var mı kontrol et
          final existing = await SupabaseConfig.client
              .from('competition_records')
              .select('competition_id')
              .eq('competition_id', competition['competition_id'])
              .maybeSingle();

          if (isDeleted) {
            // Silinen kayıtlar için Supabase'de de is_deleted=1 yap
            print(
                'Silinen kayıt senkronize ediliyor: ${competition['competition_id']}');
            await SupabaseConfig.client.from('competition_records').update({
              'is_deleted': 1,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('competition_id', competition['competition_id']);
          } else if (existing != null && existing['competition_id'] != null) {
            // Varsa update
            await SupabaseConfig.client.from('competition_records').update({
              'competition_name': competition['competition_name'],
              'competition_date': competition['competition_date'],
              'environment': competition['environment'],
              'distance': competition['distance'],
              'bow_type': competition['bow_type'],
              'qualification_score': competition['qualification_score'],
              'max_score': competition['max_score'],
              'final_rank': competition['final_rank'],
              'qualification_rank': competition['qualification_rank'],
              'created_at': competition['created_at'],
              'updated_at': competition['updated_at'],
              'is_deleted': 0, // Güncellenirken silme işaretini kaldır
            }).eq('competition_id', competition['competition_id']);
          } else {
            // Yoksa insert
            await SupabaseConfig.client.from('competition_records').insert({
              'competition_id': competition['competition_id'],
              'athlete_id': competition['athlete_id'],
              'competition_name': competition['competition_name'],
              'competition_date': competition['competition_date'],
              'environment': competition['environment'],
              'distance': competition['distance'],
              'bow_type': competition['bow_type'],
              'qualification_score': competition['qualification_score'],
              'max_score': competition['max_score'],
              'final_rank': competition['final_rank'],
              'qualification_rank': competition['qualification_rank'],
              'created_at': competition['created_at'],
              'updated_at': competition['updated_at'],
              'is_deleted': 0, // Yeni kayıtları silindi olarak işaretleme
            });
          }
          try {
            await CompetitionLocalDb.instance.markCompetitionSynced(competition['competition_id']); 
          } catch (e) {
            print('CompetitionLocalDb markCompetitionSynced hatası: $e');
          }
          print(
              'Yarışma kaydı başarıyla senkronize edildi: ${competition['competition_name']}');
        } catch (e) {
          print('Yarışma kaydı senkronizasyonu başarısız: $e');
        }
      }
      if (mounted) {
        await _fetchCompetitions();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).competitionSyncSuccess),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Senkronizasyon sırasında hata oluştu: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _fetchCompetitions() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    debugPrint('DEBUG |10n: _fetchCompetitions started');
    await _loadAndMapAgeGroupsFromLocal();

    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      debugPrint('DEBUG |10n: No user found, returning');
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    debugPrint('DEBUG |10n: Connectivity: $connectivity');
    if (connectivity != ConnectivityResult.none) {
      debugPrint('DEBUG |10n: Syncing competitions from Supabase to local...');
      try {
        await CompetitionLocalDb.instance.syncAllCompetitionsFromSupabase(user.id);
        debugPrint('DEBUG |10n: Sync from Supabase completed');
      } catch (e) {
        debugPrint('ERROR |10n: syncAllCompetitionsFromSupabase: $e');
      }
    }

    debugPrint('DEBUG |10n: Reading competitions from local DB...');
    try {
      final competitionsData = await CompetitionLocalDb.instance.getAllCompetitions(athleteId: user.id);
      debugPrint('DEBUG |10n: competitionsData.length = ${competitionsData.length}');
      if (mounted) setState(() => _competitions = competitionsData);
    } catch (e) {
      debugPrint('ERROR |10n: getAllCompetitions: $e');
    }

    // 3. Asynchronously sync age groups from Supabase and update map if changed
    CompetitionLocalDb.instance.syncAgeGroupsFromSupabase(forceRefresh: true).then((_) async {
      if (!mounted) return;
      final newResolvedNames = await _generateAgeGroupMapFromLocal();
      if (mounted && !_mapsEqual(_resolvedAgeGroupNames, newResolvedNames)) {
        setState(() {
          _resolvedAgeGroupNames = newResolvedNames;
        });
      }
    }).catchError((e) {
      print("|10n:background_age_group_sync_failed_list_screen: $e");
    });

    debugPrint('DEBUG |10n: _fetchCompetitions finished');
    if (mounted) setState(() => _isLoading = false);
  }

  // Helper to load from local and populate _resolvedAgeGroupNames
  Future<void> _loadAndMapAgeGroupsFromLocal() async {
    final newResolvedNames = await _generateAgeGroupMapFromLocal();
    if (mounted && !_mapsEqual(_resolvedAgeGroupNames, newResolvedNames)) {
      setState(() {
        _resolvedAgeGroupNames = newResolvedNames;
      });
    }
  }

  // Helper to generate the map from local data
  Future<Map<int, String>> _generateAgeGroupMapFromLocal() async {
    final allAgeGroups = await CompetitionLocalDb.instance.getAgeGroups();
    if (!mounted) return {}; // Return empty if not mounted to avoid using context

    final locale = AppLocalizations.of(context).localeName;
    final Map<int, String> tempMap = {};

    for (var ageGroup in allAgeGroups) {
      final id = ageGroup['age_group_id'] as int?;
      if (id != null) {
        String displayName = '';
        if (locale == 'en' && ageGroup['age_group_en'] != null) {
          displayName = ageGroup['age_group_en'] as String;
        } else if (locale == 'tr' && ageGroup['age_group_tr'] != null) {
          displayName = ageGroup['age_group_tr'] as String;
        } else {
          displayName = (ageGroup['age_group_en'] ?? 
                         ageGroup['age_group_tr'] ?? 
                         id.toString())?.toString() ?? 'N/A';
        }
        tempMap[id] = displayName;
      }
    }
    return tempMap;
  }

  Future<void> _deleteCompetition(Map<String, dynamic> competition) async {
    final l10n = AppLocalizations.of(context);
    final compId = competition['competition_id'];
    if (compId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.deleteIdNull),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    try {
      final connectivity = await Connectivity().checkConnectivity();
      debugPrint(
          '|10n:delete_competition_start compId=$compId connectivity=$connectivity');

      if (connectivity != ConnectivityResult.none) {
        // 1. Supabase'de soft delete uygula
        try {
          await SupabaseConfig.client
              .from('competition_records')
              .update({'is_deleted': 1}).eq('competition_id', compId);
          debugPrint('|10n:delete_supabase_success compId=$compId');
        } catch (e) {
          debugPrint('|10n:delete_supabase_error $e');
          // Supabase'de hata olursa da yerel soft delete devam et
        }
      } else {
        debugPrint('|10n:delete_offline_supabase_skipped compId=$compId');
      }

      // 2. Yerel veritabanında soft delete uygula
      try {
        await CompetitionLocalDb.instance.deleteCompetition(compId);
        debugPrint('|10n:delete_local_success compId=$compId');
      } catch (e) {
        debugPrint('|10n:delete_local_error $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.deleteFailedLocal),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Tüm state güncellemelerini tek bir setState bloğunda yap
      if (mounted) {
        setState(() {
          _competitions.removeWhere((c) => c['competition_id'] == compId);
          // _isLoading = false; // Silme sırasında loading göstergesi açılmasın
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.competitionDeleted),
            backgroundColor: const Color.fromARGB(255, 62, 143, 65),
          ),
        );
      }
    } catch (e) {
      // Eğer hata read-only ise kullanıcıya mesaj gösterme, sadece logla
      if (e.toString().contains('read-only')) {
        debugPrint('|10n:delete_failed_readonly $e');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.deleteFailedGeneral(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmDeleteCompetition(Map<String, dynamic> competition) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteCompetitionRecordTitle),
        content: Text(l10n.confirmDeleteCompetitionRecordMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteButtonLabel, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (result == true) {
      await _deleteCompetition(competition);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchCompetitions();
    _syncPendingCompetitionsToSupabase();
    _loadTeamTypeNames();

    // Connectivity listener for network status changes
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((status) async {
      if (status != ConnectivityResult.none) {
        await _syncPendingCompetitionsToSupabase();
        print(
            'İnternet bağlantısı kuruldu (${status.name}), bekleyen yarışmaları senkronize ediliyor...');
        // _syncPendingCompetitionsToSupabase(); // Already called above
      }
    });
  }

  @override
  void dispose() {
    // Connectivity aboneliğini iptal et
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Eski local/senkronizasyon fetch fonksiyonları kaldırıldı. Sadece _fetchCompetitions fonksiyonu kullanılacak.

  void _editCompetition(Map<String, dynamic> competition) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCompetitionScreen(competition: competition),
      ),
    );

    // Düzenleme yapıldı ve kaydedildiyse listeyi yenile
    if (result == true) {
      _fetchCompetitions();
    }
  }

  // Toggle selection mode
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      // Seçim modundan çıkarken seçimleri temizle
      if (!_isSelectionMode) {
        _selectedCompetitions.clear();
      }
    });
  }

  // Select or deselect a competition
  void _toggleCompetitionSelection(String competitionId) {
    setState(() {
      if (_selectedCompetitions.contains(competitionId)) {
        _selectedCompetitions.remove(competitionId);
      } else {
        _selectedCompetitions.add(competitionId);
      }
    });
  }

  // Delete all selected competitions
  Future<void> _deleteSelectedCompetitions() async {
    if (_selectedCompetitions.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);

    // Kullanıcıya onay sor
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? theme.colorScheme.surface : Colors.white,
          title: Text(
            l10n.deleteCompetitionsTitle,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            l10n.confirmDeleteSelectedCompetitionsMessage(_selectedCompetitions.length),
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                l10n.cancelButtonLabel,
                style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[800]),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text(
                l10n.deleteButtonLabel,
                style: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );

    if (confirmed == true) {
      // Tüm seçili yarışmaları sil
      try {
        setState(() {
          _isLoading = true;
        });

        // Her bir yarışmayı sırayla sil
        for (final competitionId in _selectedCompetitions) {
          // Yarışmayı bul
          final competition = _competitions.firstWhere(
            (comp) => comp['competition_id'] == competitionId,
            orElse: () => <String, dynamic>{},
          );

          if (competition.isNotEmpty) {
            await _deleteCompetition(competition);
          }
        }

        // İşlem başarılı, bildirim göster
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  l10n.selectedCompetitionsDeleted(_selectedCompetitions.length)),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        // Hata durumunda kullanıcıya bildir
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.deleteFailedGeneral(e.toString())),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        // Seçim modunu kapat ve seçimleri temizle
        setState(() {
          _isLoading = false;
          _isSelectionMode = false;
          _selectedCompetitions.clear();
        });
      }
    }
  }

  // Helper to show date range picker
  Future<void> _showDateRangePicker() async {
    final initialDateRange = _dateFilterActive && _startDate != null && _endDate != null
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          );
    final pickedDateRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: initialDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Theme.of(context).primaryColor,
                ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDateRange != null) {
      setState(() {
        _dateFilterActive = true;
        _startDate = pickedDateRange.start;
        _endDate = pickedDateRange.end;
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _dateFilterActive = false;
      _startDate = null;
      _endDate = null;
    });
  }

  String _getDateRangeText() {
    if (_startDate == null || _endDate == null) return '';
    final formatter = DateFormat('dd/MM/yyyy');
    if (_startDate == _endDate) {
      return formatter.format(_startDate!);
    }
    return '${formatter.format(_startDate!)} - ${formatter.format(_endDate!)}';
  }

  // Unified competitions filter (date, environment, is_deleted)
  List<Map<String, dynamic>> get _filteredCompetitions {
    List<Map<String, dynamic>> comps = _competitions
        .where((comp) {
          final isDeleted = comp['is_deleted'] == true ||
              comp['is_deleted'] == 1 ||
              comp['is_deleted'] == '1' ||
              comp['is_deleted'] == 'true';
          if (isDeleted) return false;
          if (_environmentFilter != 'all' && (comp['environment'] ?? 'indoor') != _environmentFilter) {
            return false;
          }
          if (_dateFilterActive && _startDate != null && _endDate != null) {
            final compDate = DateTime.tryParse(comp['competition_date'] ?? '');
            if (compDate == null) return false;
            // Inclusive end date
            return (compDate.isAtSameMomentAs(_startDate!) || compDate.isAfter(_startDate!)) &&
                (compDate.isAtSameMomentAs(_endDate!) || compDate.isBefore(_endDate!.add(const Duration(days: 1))));
          }
          return true;
        })
        .toList();
    // Sort by date descending
    comps.sort((a, b) {
      final dateA = DateTime.tryParse(a['competition_date'] ?? '') ?? DateTime(1900);
      final dateB = DateTime.tryParse(b['competition_date'] ?? '') ?? DateTime(1900);
      return dateB.compareTo(dateA);
    });
    return comps;
  }

  Future<void> _loadTeamTypeNames() async {
    final teamTypes = await CompetitionLocalDb.instance.getTeamTypes();
    final locale = AppLocalizations.of(context).localeName;
    final Map<String, String> map = {};
    for (var t in teamTypes) {
      final id = t['team_type_id']?.toString();
      if (id != null) {
        String name = '';
        if (locale == 'en' && t['team_type_en'] != null) {
          name = t['team_type_en'] as String;
        } else if (locale == 'tr' && t['team_type_tr'] != null) {
          name = t['team_type_tr'] as String;
        } else {
          name = (t['team_type_en'] ?? t['team_type_tr'] ?? id).toString();
        }
        map[id] = name;
      }
    }
    if (mounted) setState(() => _teamTypeNames = map);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final double baseFontSize = (screenWidth * 0.045).clamp(14, 22);
    final double smallFontSize = (screenWidth * 0.034).clamp(11, 16);
    final double textScale = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.25);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          l10n.competitionRecords,
          style: TextStyle(fontSize: baseFontSize + 2),
          textScaleFactor: textScale,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedCompetitions,
            ),
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.select_all),
            onPressed: _toggleSelectionMode,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilterChip(
                            key: const ValueKey('filter_all'),
                            label: Text(
                              l10n.filterAll,
                              style: TextStyle(
                                color: _environmentFilter == 'all' ? Colors.blue : const Color.fromARGB(255, 155, 155, 155),
                                fontWeight: FontWeight.w500,
                                fontSize: smallFontSize,
                              ),
                            ),
                            selected: _environmentFilter == 'all',
                            onSelected: (_) {
                              setState(() {
                                _environmentFilter = 'all';
                              });
                            },
                            backgroundColor: isDark ? theme.colorScheme.surface : Colors.grey[100],
                            selectedColor: isDark ? Colors.blueGrey[800] : Colors.blue[100],
                            checkmarkColor: Colors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: _environmentFilter == 'all' ? Colors.blue : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                          FilterChip(
                            key: const ValueKey('filter_indoor'),
                            label: Text(
                              l10n.indoorLabel.replaceAll(' (Hall)', ''),
                              style: TextStyle(
                                color: _environmentFilter == 'indoor' ? Colors.blue : const Color.fromARGB(255, 155, 155, 155),
                                fontWeight: FontWeight.w500,
                                fontSize: smallFontSize,
                              ),
                            ),
                            avatar: Icon(
                              Icons.home_outlined,
                              size: 18,
                              color: _environmentFilter == 'indoor' ? Colors.blue : Colors.grey,
                            ),
                            selected: _environmentFilter == 'indoor',
                            onSelected: (_) {
                              setState(() {
                                _environmentFilter = 'indoor';
                              });
                            },
                            backgroundColor: isDark ? theme.colorScheme.surface : Colors.grey[100],
                            selectedColor: isDark ? Colors.blueGrey[800] : Colors.blue[100],
                            checkmarkColor: Colors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: _environmentFilter == 'indoor' ? Colors.blue : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                          FilterChip(
                            key: const ValueKey('filter_outdoor'),
                            label: Text(
                              l10n.outdoorLabel.replaceAll(' (Open Air)', ''),
                              style: TextStyle(
                                color: _environmentFilter == 'outdoor' ? Colors.green : const Color.fromARGB(255, 155, 155, 155),
                                fontWeight: FontWeight.w500,
                                fontSize: smallFontSize,
                              ),
                            ),
                            avatar: Icon(
                              Icons.landscape_outlined,
                              size: 18,
                              color: _environmentFilter == 'outdoor' ? Colors.green : Colors.grey,
                            ),
                            selected: _environmentFilter == 'outdoor',
                            onSelected: (_) {
                              setState(() {
                                _environmentFilter = 'outdoor';
                              });
                            },
                            backgroundColor: isDark ? theme.colorScheme.surface : Colors.grey[100],
                            selectedColor: isDark ? Colors.green[900] : Colors.green[100],
                            checkmarkColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: _environmentFilter == 'outdoor' ? Colors.green : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                          FilterChip(
                            key: const ValueKey('filter_date'),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.date_range, size: 16, color: _dateFilterActive ? theme.primaryColor : Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  _dateFilterActive && _startDate != null && _endDate != null
                                      ? _getDateRangeText()
                                      : l10n.dateRange,
                                  style: TextStyle(
                                    color: _dateFilterActive ? theme.primaryColor : Colors.grey,
                                    fontWeight: FontWeight.w500,
                                    fontSize: smallFontSize,
                                  ),
                                ),
                              ],
                            ),
                            selected: _dateFilterActive,
                            onSelected: (_) => _showDateRangePicker(),
                            backgroundColor: isDark ? theme.colorScheme.surface : Colors.grey[100],
                            selectedColor: isDark ? theme.primaryColorDark : theme.primaryColorLight,
                            checkmarkColor: theme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: _dateFilterActive ? theme.primaryColor : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_dateFilterActive && _startDate != null && _endDate != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            _getDateRangeText(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.clear, size: 18, color: Theme.of(context).primaryColor),
                            onPressed: _clearDateFilter,
                            tooltip: AppLocalizations.of(context).clearDateFilter,
                            padding: const EdgeInsets.only(left: 4),
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _buildBody(l10n, baseFontSize, smallFontSize, textScale, isDark, screenWidth),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const AddCompetitionScreen()),
          );
          if (result == true || result == null) {
            _fetchCompetitions();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.addCompetitionFAB, style: TextStyle(fontSize: baseFontSize)),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, double baseFontSize, double smallFontSize, double textScale, bool isDark, double screenWidth) {
    final filteredCompetitions = _filteredCompetitions;
    if (filteredCompetitions.isEmpty) {
      return Center(child: Text(l10n.noCompetitionsForFilter, style: TextStyle(fontSize: baseFontSize), textScaleFactor: textScale));
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.025, vertical: 8),
      itemCount: filteredCompetitions.length,
      itemBuilder: (context, index) {
        final comp = filteredCompetitions[index];
        final competitionDate = DateTime.tryParse(comp['competition_date'] ?? '');
        final formattedDate = competitionDate != null
            ? DateFormat('d MMM', l10n.localeName).format(competitionDate)
            : l10n.noDateAvailable;
        final isIndoor = comp['environment'] == 'indoor';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isIndoor ? Colors.blue.shade100 : Colors.orange.shade100,
              width: 0.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final selected = await showDialog<String>(
                context: context,
                builder: (context) {
                  final l10n = AppLocalizations.of(context);
                  return AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    titlePadding: const EdgeInsets.only(left: 24, top: 20, right: 8, bottom: 0),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            l10n.competitionOptionsTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: l10n.close,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(l10n.edit),
                          onTap: () {
                            Navigator.pop(context, 'edit');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline, color: Colors.red),
                          title: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
                          onTap: () {
                            Navigator.pop(context, 'delete');
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
              if (selected == 'edit') {
                _editCompetition(comp);
              } else if (selected == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l10n.deleteCompetitionTitle),
                    content: Text(l10n.deleteCompetitionConfirm),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l10n.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _deleteCompetition(comp);
                }
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: screenWidth * 0.022, horizontal: screenWidth * 0.02),
              child: Row(
                children: [
                  Icon(
                    isIndoor ? Icons.home_outlined : Icons.landscape_outlined,
                    color: isIndoor ? Colors.blue : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(
                                  comp['competition_name']?.toString().isNotEmpty == true
                                      ? comp['competition_name']
                                      : l10n.unnamedCompetitionPlaceholder,
                                  style: TextStyle(
                                    fontSize: baseFontSize,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color.fromARGB(255, 219, 219, 219) : const Color.fromARGB(255, 54, 54, 54),
                                  ),
                                  textScaleFactor: textScale,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              '$formattedDate - ${comp['distance'] ?? '-'} m',
                              style: TextStyle(
                                fontSize: smallFontSize,
                                color: isDark ? Colors.grey[300] : Colors.grey[600],
                              ),
                              textScaleFactor: textScale,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${l10n.scorePrefix}${comp['qualification_score'] ?? '-'}/${comp['max_score'] ?? '-'}',
                              style: TextStyle(
                                fontSize: smallFontSize,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : const Color.fromARGB(255, 82, 82, 82),
                              ),
                              textScaleFactor: textScale,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${l10n.rankPrefix}${comp['qualification_rank']?.toString().isNotEmpty == true ? comp['qualification_rank'].toString() : '-'}',
                                style: TextStyle(
                                  fontSize: smallFontSize,
                                  color: isDark ? Colors.amber[300] : Colors.amber[900],
                                ),
                                textScaleFactor: textScale,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${l10n.eliminationPrefix}${comp['final_rank']?.toString().isNotEmpty == true ? comp['final_rank'].toString() : '-'}',
                                style: TextStyle(
                                  fontSize: smallFontSize,
                                  color: isDark ? Colors.cyan[200] : Colors.cyan[800],
                                ),
                                textScaleFactor: textScale,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        // Ortalama satırı
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context).finishTrainingAveragePerArrow +
                                ': ' + 
                                (comp['qualification_score'] != null && comp['max_score'] != null && comp['max_score'] > 0
                                    ? ((comp['qualification_score'] / (comp['max_score'] / 10)).toStringAsFixed(1))
                                    : '-'),
                                style: TextStyle(
                                  fontSize: smallFontSize,
                                  fontWeight: FontWeight.w600,
                                  color: _getArrowAverageColor(
                                    comp['qualification_score'] != null && comp['max_score'] != null && comp['max_score'] > 0
                                      ? (comp['qualification_score'] / (comp['max_score'] / 10))
                                      : null,
                                    isDark,
                                  ),
                                ),
                                textScaleFactor: textScale,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        // Age Group Display
                        if (comp['age_group'] != null && _resolvedAgeGroupNames.containsKey(comp['age_group']))
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0), // Add some spacing
                            child: Text(
                              '${l10n.ageGroupDisplayPrefix}${_resolvedAgeGroupNames[comp['age_group']]!}',
                              style: TextStyle(
                                fontSize: smallFontSize,
                                color: isDark ? Colors.tealAccent[100] : Colors.teal[700],
                                fontWeight: FontWeight.w500,
                              ),
                              textScaleFactor: textScale,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        // Team Type & Result Display
                        if ((comp['team_type'] != null && comp['team_type'].toString().isNotEmpty) ||
                            (comp['team_result'] != null && comp['team_result'].toString().isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Row(
                              children: [
                                if (comp['team_type'] != null && comp['team_type'].toString().isNotEmpty)
                                  Text(
                                    '${l10n.teamTypeLabel}: '
                                    '${_teamTypeNames[comp['team_type'].toString()] ?? comp['team_type']}',
                                    style: TextStyle(
                                      fontSize: smallFontSize,
                                      color: isDark ? Colors.purple[100] : Colors.purple[800],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textScaleFactor: textScale,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                if (comp['team_result'] != null && comp['team_result'].toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Text(
                                      '${l10n.teamResultLabel}: ${comp['team_result']}',
                                      style: TextStyle(
                                        fontSize: smallFontSize,
                                        color: isDark ? Colors.deepOrange[100] : Colors.deepOrange[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textScaleFactor: textScale,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getArrowAverageColor(double? arrowAverage, bool isDark) {
    if (arrowAverage == null) {
      // Default color for null values based on theme
      return isDark 
          ? Colors.white70 
          : const Color.fromARGB(255, 82, 82, 82);
    }
    
    // Apply color based on range
    if (arrowAverage >= 9.0 && arrowAverage <= 10.0) {
      // Yellow for 9-10 range
      return Colors.amber;
    } else if (arrowAverage >= 7.0 && arrowAverage < 9.0) {
      // Red for 7-8.9 range
      return Colors.red;
    } else if (arrowAverage >= 5.0 && arrowAverage < 7.0) {
      // Blue for 5-6.9 range
      return Colors.blue;
    } else {
      // Default color for less than 5 based on theme
      return isDark 
          ? Colors.white70 
          : const Color.fromARGB(255, 82, 82, 82);
    }
  }
}
