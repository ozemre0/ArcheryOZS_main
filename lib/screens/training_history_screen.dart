import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/training_session_model.dart';
import '../providers/training_history_controller.dart';
import '../providers/training_session_controller.dart';
import '../services/supabase_config.dart';
import 'training_session_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/scoring_rules.dart';
import 'training_config_screen.dart';

class TrainingHistoryScreen extends ConsumerStatefulWidget {
  const TrainingHistoryScreen({super.key});

  @override
  ConsumerState<TrainingHistoryScreen> createState() =>
      _TrainingHistoryScreenState();
}

class _TrainingHistoryScreenState extends ConsumerState<TrainingHistoryScreen> {
  int _chartTrainingCount = 10;
  final List<int> _chartTrainingCountOptions = [5, 10, 20, 30];
  static const int _allTrainings = -1;
  final dateFormat = DateFormat('dd/MM/yyyy - HH:mm');
  DateTime? _startDate;
  DateTime? _endDate;
  String? _userId;
  int _selectedFilterIndex = 0; // 0: All, 1: Indoor, 2: Outdoor
  bool _isOffline = false; // Çevrimdışı modda olup olmadığını belirtir

  // Toplu silme işlemi için gerekli state değişkenleri
  bool _isSelectionMode = false;
  final Set<String> _selectedTrainings = {};

  // Connectivity listener for network status changes
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Ekranda aynı anda birden fazla senkronizasyonu engellemek için flag
  bool _isSyncing = false;

  // FAB konumu için state
  Offset? _fabOffset; // Varsayılan konum artık null, ilk build'da ayarlanacak
  Offset? _fabInitialOffset; // FAB'ın ilk konumu (alt sınır)
  final GlobalKey _stackKey = GlobalKey(); // Stack için key

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ekran boyutunu al ve FAB'ı sağ alt köşeye yerleştir (biraz daha sola ve yukarıda)
      final context = this.context;
      final Size screenSize = MediaQuery.of(context).size;
      final double fabSize = 56;
      final double margin = 20;
      final double offsetY = 32; // Alttan aynı kalsın
      final double bottomPadding = MediaQuery.of(context).padding.bottom;
      final double rightPadding = MediaQuery.of(context).padding.right;
      final Offset initialOffset = Offset(
        screenSize.width - fabSize - margin - rightPadding,
        screenSize.height - fabSize - margin - bottomPadding - kToolbarHeight - offsetY,
      );
      setState(() {
        _fabOffset = initialOffset;
        _fabInitialOffset = initialOffset;
      });
      await _loadUserTrainings();
      // Kullanıcı sync servisini başlat
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId != null) {
        await ref.read(trainingHistoryProvider.notifier).requestBackgroundSync(userId, ref);
      }
    });
  }

  @override
  void dispose() {
    // Cancel the connectivity subscription when the widget is disposed
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Responsive font size helper
  double responsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    // 375 iPhone 11 referans alınarak, orantılı büyütme/küçültme
    return baseSize * (width / 375).clamp(0.85, 1.25);
  }

  // Toggle selection mode
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      // Seçim modundan çıkarken seçimleri temizle
      if (!_isSelectionMode) {
        _selectedTrainings.clear();
      }
    });
  }

  // Select or deselect a training
  void _toggleTrainingSelection(String trainingId) {
    setState(() {
      if (_selectedTrainings.contains(trainingId)) {
        _selectedTrainings.remove(trainingId);
      } else {
        _selectedTrainings.add(trainingId);
      }
    });
  }

  // Delete all selected trainings
  Future<void> _deleteSelectedTrainings() async {
    final l10n = AppLocalizations.of(context);
    if (_userId == null || _selectedTrainings.isEmpty) {
      return;
    }

    // Kullanıcıya onay sor
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? theme.colorScheme.surface : Colors.white,
          title: Text(
            l10n.deleteTraining,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            '${_selectedTrainings.length} ${l10n.totalSessions} ${l10n.deleteTrainingConfirm}',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                l10n.cancel,
                style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[800]),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text(
                l10n.deleteTraining,
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
      try {
        setState(() {
          // Silme işlemi başlıyor, bir yükleniyor göstergesi gösterilebilir
        });

        // Tüm silme işlemlerini paralel başlat
        await Future.wait(_selectedTrainings.map((trainingId) =>
          ref.read(trainingHistoryProvider.notifier).deleteTraining(_userId!, trainingId)
        ));

        // Silme sonrası provider'dan güncel listeyi tekrar çek
        await ref.read(trainingHistoryProvider.notifier).loadUserTrainings(_userId!);

        // İşlem başarılı, bildirim göster
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${_selectedTrainings.length} ${l10n.trainingDeleted}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        // Hata durumunda kullanıcıya bildir
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.error(e.toString())),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        // Seçim modunu kapat ve seçimleri temizle
        setState(() {
          _isSelectionMode = false;
          _selectedTrainings.clear();
        });
      }
    }
  }

  Future<void> _loadUserTrainings({bool force = false}) async {
    final l10n = AppLocalizations.of(context);
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userNotFound)),
      );
      return;
    }
    final controller = ref.read(trainingHistoryProvider.notifier);
    // Eğer localde hiç veri yoksa force true yap
    final trainingRepo = ref.read(trainingRepositoryProvider);
    final localCount = await trainingRepo.localTrainingCount(currentUserId);
    if (localCount == 0) {
      force = true;
    }
    if (!force && controller.isCacheValid(currentUserId)) {
      print('TrainingHistoryScreen: Using cached trainings for $currentUserId');
      _userId = currentUserId;
      return;
    }
    setState(() { _isOffline = false; });
    await controller.loadUserTrainings(currentUserId, force: force);
    _userId = currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    final historyState = ref.watch(trainingHistoryProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Size screenSize = MediaQuery.of(context).size;
    // FAB konum hesaplamaları için ortak sabitler
    const double fabSize = 56;
    const double margin = 20;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double rightPadding = MediaQuery.of(context).padding.right;

    // Hata durumunu kontrol et
    if (historyState.error != null && historyState.sessions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(historyState.error!),
            backgroundColor: Colors.red,
          ),
        );
        ref.read(trainingHistoryProvider.notifier).clearError();
      });
    }

    // İstatistikleri hesapla
    final stats = ref.read(trainingHistoryProvider.notifier).calculateStats();

    // Antrenman oturumlarını tarihe göre sırala (en yeniden en eskiye)
    final sortedSessions = List<TrainingSession>.from(historyState.sessions);
    sortedSessions.sort((a, b) => b.date.compareTo(a.date)); // En yeniden en eskiye sırala

    // --- GROUPING LOGIC ---
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final List<TrainingSession> todaySessions = [];
    final List<TrainingSession> yesterdaySessions = [];
    final List<TrainingSession> earlierSessions = [];
    for (final session in sortedSessions) {
      final sessionDay = DateTime(session.date.year, session.date.month, session.date.day);
      if (sessionDay == today) {
        todaySessions.add(session);
      } else if (sessionDay == yesterday) {
        yesterdaySessions.add(session);
      } else {
        earlierSessions.add(session);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trainingHistory,
            style: TextStyle(fontSize: responsiveFontSize(context, 18))),
        elevation: isDark ? 1 : 0,
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Çevrimdışı göstergesi
          if (_isOffline)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Tooltip(
                message: 'Çevrimdışı mod - Veriler önbellekten yüklendi',
                child: Icon(
                  Icons.offline_bolt,
                  color: Colors.amber,
                ),
              ),
            ),
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedTrainings,
            ),
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.select_all),
            onPressed: _toggleSelectionMode,
          ),
          // Yenileme butonu
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _manualSync,
            tooltip: l10n.refresh,
          ),
        ],
      ),
      body: Stack(
        key: _stackKey, // Stack'e key ver
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
            child: Container(
              color:
                  isDark ? theme.scaffoldBackgroundColor : theme.colorScheme.surface,
              child: historyState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Scrollbar(
                      thumbVisibility: true,
                      thickness: 6,
                      radius: const Radius.circular(10),
                      interactive: true,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Çevrimdışı uyarı banner'ı
                            if (_isOffline)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 16),
                                color: Colors.amber.withOpacity(0.2),
                                child: Row(
                                  children: [
                                    const Icon(Icons.offline_bolt, color: Colors.amber),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Çevrimdışı mod - Son kaydedilen veriler gösteriliyor',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.amber[200]
                                              : Colors.amber[800],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Filtre butonları
                            _buildFilterButtons(l10n, theme, isDark),

                            // Ana istatistikler
                            _buildSummaryCard(stats, l10n, theme, isDark),

                            // Performans grafiği
                            _buildPerformanceChart(
                                historyState.sessions, l10n, theme, isDark),

                            // Heading for training list + New Training button
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 16, top: 24, bottom: 8, right: 16),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final minFontSize = responsiveFontSize(context, 18) * 0.85;
                                  final baseFontSize = responsiveFontSize(context, 18) * 0.85; // 15% smaller
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Tüm antrenmanlar yazısı responsive font ile
                                      Container(
                                        constraints: BoxConstraints(
                                          maxWidth: constraints.maxWidth * 0.55,
                                        ),
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween<double>(begin: baseFontSize, end: baseFontSize),
                                          duration: Duration(milliseconds: 200),
                                          builder: (context, value, child) {
                                            return Text(
                                              l10n.allTrainings,
                                              style: TextStyle(
                                                fontSize: value,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                              softWrap: false,
                                              overflow: TextOverflow.visible,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Buton her zaman tam okunur ve sabit boyutta
                                      Card(
                                        elevation: isDark ? 4 : 2,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        color: theme.colorScheme.primary,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(14),
                                          onTap: () async {
                                            final result = await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => const TrainingConfigScreen(),
                                              ),
                                            );
                                            if (result == true) {
                                              await _loadUserTrainings();
                                            }
                                          },
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: MediaQuery.of(context).size.width * 0.025,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.add, color: Colors.white, size: 20),
                                                const SizedBox(width: 8),
                                                Text(
                                                  l10n.trainingSystem,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: responsiveFontSize(context, 14),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),

                            // Antrenman listesi - Sıralanmış oturumları kullan
                            (todaySessions.isEmpty && yesterdaySessions.isEmpty && earlierSessions.isEmpty)
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32.0),
                                      child: Column(
                                        children: [
                                          Icon(Icons.history_outlined,
                                              size: 64,
                                              color: isDark
                                                  ? Colors.grey[400]
                                                  : Colors.grey[400]),
                                          const SizedBox(height: 16),
                                          Text(
                                            l10n.noTrainingsYet,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: isDark
                                                  ? Colors.grey[400]
                                                  : Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (todaySessions.isNotEmpty) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
                                          child: Text(
                                            l10n.today,
                                            style: TextStyle(
                                              fontSize: responsiveFontSize(context, 16),
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        ...todaySessions.map((session) => _buildTrainingItemCard(
                                              context,
                                              session,
                                              l10n,
                                              isDark,
                                              theme,
                                            )),
                                        Divider(height: 32, thickness: 1, indent: 16, endIndent: 16),
                                      ],
                                      if (yesterdaySessions.isNotEmpty) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
                                          child: Text(
                                            l10n.yesterday,
                                            style: TextStyle(
                                              fontSize: responsiveFontSize(context, 16),
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        ...yesterdaySessions.map((session) => _buildTrainingItemCard(
                                              context,
                                              session,
                                              l10n,
                                              isDark,
                                              theme,
                                            )),
                                        if (earlierSessions.isNotEmpty)
                                          Divider(height: 32, thickness: 1, indent: 16, endIndent: 16),
                                      ],
                                      if (earlierSessions.isNotEmpty) ...[
                                        ...earlierSessions.map((session) => _buildTrainingItemCard(
                                              context,
                                              session,
                                              l10n,
                                              isDark,
                                              theme,
                                            )),
                                      ],
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButtons(
      AppLocalizations l10n, ThemeData theme, bool isDark) {
    final Color chipBackground =
        isDark ? theme.colorScheme.surface : Colors.grey[100]!;
    final Color selectedChipColor =
        isDark ? theme.colorScheme.primary.withOpacity(0.3) : Colors.blue[100]!;
    final Color textColor = isDark ? Colors.white70 : Colors.black87;
    final Color selectedTextColor =
        isDark ? theme.colorScheme.primary : Colors.blue;
    final Color iconColor = isDark ? Colors.grey : Colors.grey;
    final Color selectedIconColor =
        isDark ? theme.colorScheme.primary : Colors.blue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              selected: _selectedFilterIndex == 0,
              label: Text(
                l10n.allTrainings,
                style: TextStyle(
                  color:
                      _selectedFilterIndex == 0 ? selectedTextColor : textColor,
                ),
              ),
              onSelected: (bool selected) {
                if (selected) {
                  setState(() {
                    _selectedFilterIndex = 0;
                  });
                  _loadUserTrainings();
                }
              },
              backgroundColor: chipBackground,
              selectedColor: selectedChipColor,
              checkmarkColor: selectedTextColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _selectedFilterIndex == 0
                      ? selectedTextColor
                      : isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _selectedFilterIndex == 1,
              label: Text(
                l10n.indoorOnly,
                style: TextStyle(
                  color:
                      _selectedFilterIndex == 1 ? selectedTextColor : textColor,
                ),
              ),
              avatar: Icon(
                Icons.home_outlined,
                size: 18,
                color:
                    _selectedFilterIndex == 1 ? selectedIconColor : iconColor,
              ),
              onSelected: (bool selected) {
                if (selected && _userId != null) {
                  setState(() {
                    _selectedFilterIndex = 1;
                  });
                  ref
                      .read(trainingHistoryProvider.notifier)
                      .filterByIndoor(_userId!);
                }
              },
              backgroundColor: chipBackground,
              selectedColor: selectedChipColor,
              checkmarkColor: selectedTextColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _selectedFilterIndex == 1
                      ? selectedTextColor
                      : isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _selectedFilterIndex == 2,
              label: Text(
                l10n.outdoorOnly,
                style: TextStyle(
                  color:
                      _selectedFilterIndex == 2 ? selectedTextColor : textColor,
                ),
              ),
              avatar: Icon(
                Icons.landscape_outlined,
                size: 18,
                color:
                    _selectedFilterIndex == 2 ? selectedIconColor : iconColor,
              ),
              onSelected: (bool selected) {
                if (selected && _userId != null) {
                  setState(() {
                    _selectedFilterIndex = 2;
                  });
                  ref
                      .read(trainingHistoryProvider.notifier)
                      .filterByOutdoor(_userId!);
                }
              },
              backgroundColor: chipBackground,
              selectedColor: selectedChipColor,
              checkmarkColor: selectedTextColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _selectedFilterIndex == 2
                      ? selectedTextColor
                      : isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _selectedFilterIndex == 3,
              label: Text(
                l10n.dateRange,
                style: TextStyle(
                  color:
                      _selectedFilterIndex == 3 ? selectedTextColor : textColor,
                ),
              ),
              avatar: Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color:
                    _selectedFilterIndex == 3 ? selectedIconColor : iconColor,
              ),
              onSelected: (bool selected) {
                if (selected && _userId != null) {
                  setState(() {
                    _selectedFilterIndex = 3;
                  });
                  _showDateRangePicker(_userId!);
                }
              },
              backgroundColor: chipBackground,
              selectedColor: selectedChipColor,
              checkmarkColor: selectedTextColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _selectedFilterIndex == 3
                      ? selectedTextColor
                      : isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> stats, AppLocalizations l10n,
      ThemeData theme, bool isDark) {
    final averageScore = stats['averageScore'] as double;
    final totalSessions = stats['totalSessions'] as int;
    final bestSession = stats['bestSession'] as TrainingSession?;

    double bestAverage = bestSession?.average ?? 0.0;

    final backgroundColor = isDark ? theme.colorScheme.surface : Colors.white;
    final textColor = isDark ? Colors.white : Colors.grey[800]!;

    return Center(
      child: Card(
        elevation: isDark ? 2 : 1,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: backgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.trainingStatistics,
                style: TextStyle(
                  fontSize: responsiveFontSize(context, 18),
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Flexible(
                      flex: 1,
                      fit: FlexFit.tight,
                      child: _buildStatBox(
                        title: averageScore.toStringAsFixed(2),
                        subtitle: l10n.average,
                        icon: Icons.score,
                        color: Colors.blue,
                        isDark: isDark,
                        textColor: textColor,
                      ),
                    ),
                    Flexible(
                      flex: 1,
                      fit: FlexFit.tight,
                      child: _buildStatBox(
                        title: '$totalSessions',
                        subtitle: l10n.totalSessions,
                        icon: Icons.calendar_today,
                        color: Colors.green,
                        isDark: isDark,
                        textColor: textColor,
                      ),
                    ),
                    if (bestSession != null)
                      Flexible(
                        flex: 1,
                        fit: FlexFit.tight,
                        child: _buildStatBox(
                          title: bestAverage.toStringAsFixed(2),
                          subtitle: l10n.bestTraining.replaceAll(':', ''),
                          icon: Icons.emoji_events,
                          color: Colors.amber,
                          isDark: isDark,
                          textColor: textColor,
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
  }

  Widget _buildStatBox({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required Color textColor,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(isDark ? 0.2 : 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isDark ? color.withOpacity(0.9) : color,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: responsiveFontSize(context, 18),
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: responsiveFontSize(context, 12),
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceChart(List<TrainingSession> sessions,
      AppLocalizations l10n, ThemeData theme, bool isDark) {
    // Eğer antrenman yoksa, grafik gösterme
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sadece skor antrenmanlarını dahil et
    final scoreSessions = sessions.where((s) => s.trainingType == 'score').toList();
    if (scoreSessions.isEmpty) {
      return const SizedBox.shrink();
    }

    int count = _chartTrainingCount == _allTrainings
        ? scoreSessions.length
        : _chartTrainingCount;
    final chartSessions =
        scoreSessions.length > count ? scoreSessions.sublist(0, count) : scoreSessions;
    chartSessions
        .sort((a, b) => a.date.compareTo(b.date)); // Tarihe göre sırala

    final spots = <FlSpot>[];

    for (var i = 0; i < chartSessions.length; i++) {
      spots.add(FlSpot(i.toDouble(), chartSessions[i].average));
    }

    final backgroundColor = isDark ? theme.colorScheme.surface : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final gridColor = isDark ? Colors.grey[700] : Colors.grey[300];

    return Card(
      elevation: isDark ? 2 : 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.performanceGraph,
                  style: TextStyle(
                    fontSize: responsiveFontSize(context, 16),
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                DropdownButton<int>(
                  value: _chartTrainingCount,
                  items: [
                    ..._chartTrainingCountOptions
                        .map((count) => DropdownMenuItem(
                              value: count,
                              child: Text(count.toString()),
                            )),
                    const DropdownMenuItem(
                      value: _allTrainings,
                      child: Text('Tümü'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _chartTrainingCount = value;
                      });
                    }
                  },
                  underline: const SizedBox(),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  dropdownColor: backgroundColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  _chartTrainingCount == _allTrainings
                      ? 'Tüm antrenmanlar'
                      : l10n.lastTrainings(chartSessions.length),
                  style: TextStyle(
                    fontSize: responsiveFontSize(context, 14),
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: gridColor,
                        strokeWidth: 0.5,
                        dashArray: [5, 5],
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(0),
                            style: TextStyle(
                              color: isDark ? Colors.grey[300] : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: gridColor!, width: 1),
                      left: BorderSide(color: gridColor, width: 1),
                    ),
                  ),
                  minY: 0,
                  maxY: 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: theme.colorScheme.primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(
                        show: true,
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: theme.colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Yeni antrenman kart tasarımı
  Widget _buildTrainingItemCard(BuildContext context, TrainingSession session,
      AppLocalizations l10n, bool isDark, ThemeData theme) {
    final isIndoor = session.isIndoor;
    final bool isTechnique = session.trainingType == 'technique';
    final icon = isIndoor ? Icons.home : Icons.landscape;
    final iconColor = isIndoor ? Colors.blue : Colors.green;
    final backgroundColor = isDark ? theme.colorScheme.surface : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    // Calculate values directly from the series data
    final totalArrows = session.totalArrows;
    final screenWidth = MediaQuery.of(context).size.width;
    final metricFontSize = screenWidth * 0.038;
    final metricLabelFontSize = screenWidth * 0.027;
    final leftFontSize = responsiveFontSize(context, 14) * 1.05;
    final leftSmallFontSize = responsiveFontSize(context, 11) * 1.05;
    final leftDetailFontSize = responsiveFontSize(context, 12) * 1.05;

    return Card(
      elevation: isDark ? 1 : 0,
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      color: backgroundColor,
      child: InkWell(
        onTap: () {
          if (!isTechnique) {
            _openTrainingSession(context, session);
          } else {
            // Teknik antrenman için detay modalı veya hiçbir şey
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(l10n.trainingType),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l10n.bowType}: ${getLocalizedBowType(session.bowType, l10n)}'),
                    Text('${l10n.distance}: ${session.distance} ${l10n.meters}'),
                    Text('${l10n.arrows}: ${session.totalArrows}'),
                    if (session.notes != null && session.notes!.isNotEmpty)
                      Text('${l10n.notes}: ${session.notes}'),
                  ],
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
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              // İkon
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              // Antrenman bilgileri
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (session.training_session_name != null &&
                        session.training_session_name!.isNotEmpty)
                      Text(
                        session.training_session_name!,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: leftFontSize,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      dateFormat.format(session.date),
                      style: TextStyle(
                        fontWeight: session.training_session_name == null ||
                                session.training_session_name!.isEmpty
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: session.training_session_name == null ||
                                session.training_session_name!.isEmpty
                            ? leftSmallFontSize
                            : leftSmallFontSize * 0.91, // orantılı küçültme
                        color: session.training_session_name == null ||
                                session.training_session_name!.isEmpty
                            ? textColor
                            : isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                      ),
                    ),
                    Text(
                      '${getLocalizedBowType(session.bowType, l10n)} | ${session.distance} ${l10n.meters}',
                      style: TextStyle(
                        fontSize: leftDetailFontSize,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // Teknik antrenman kartı
              if (isTechnique)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.technique,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildCompactMetric(
                          value: totalArrows.toString(),
                          label: l10n.arrows,
                          isDark: isDark,
                          textColor: textColor,
                          fontSize: metricFontSize,
                          labelFontSize: metricLabelFontSize,
                        ),
                        if (session.notes != null && session.notes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              session.notes!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[300] : Colors.grey[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              // Skor antrenman kartı
              else if (session.trainingType == 'score')
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.scoreLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    session.totalScore.toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: metricFontSize * 1.1,
                                      color: textColor,
                                      height: 1.0,
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                    height: 2,
                                    width: metricFontSize * 1.5,
                                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                                  ),
                                  Text(
                                    (session.totalArrows > 0 ? (session.totalArrows * 10).toString() : '0'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.normal,
                                      fontSize: metricFontSize * 0.95,
                                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                                      height: 1.0,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    l10n.total,
                                    style: TextStyle(
                                      fontSize: metricLabelFontSize,
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: screenWidth * 0.03),
                            Expanded(
                              child: _buildCompactMetric(
                                value: (session.totalArrows > 0 ? (session.totalScore / session.totalArrows).toStringAsFixed(2) : '0.00'),
                                label: l10n.average,
                                isDark: isDark,
                                textColor: textColor,
                                fontSize: metricFontSize,
                                labelFontSize: metricLabelFontSize,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            session.totalScore.toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: metricFontSize * 1.1,
                              color: textColor,
                              height: 1.0,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            height: 2,
                            width: metricFontSize * 1.5,
                            color: isDark ? Colors.grey[700] : Colors.grey[400],
                          ),
                          Text(
                            (session.totalArrows > 0 ? (session.totalArrows * 10).toString() : '0'),
                            style: TextStyle(
                              fontWeight: FontWeight.normal,
                              fontSize: metricFontSize * 0.95,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                              height: 1.0,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            l10n.total,
                            style: TextStyle(
                              fontSize: metricLabelFontSize,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.03),
                    Expanded(
                      child: _buildCompactMetric(
                          value: (session.totalArrows > 0 ? (session.totalScore / session.totalArrows).toStringAsFixed(2) : '0.00'),
                        label: l10n.average,
                        isDark: isDark,
                        textColor: textColor,
                        fontSize: metricFontSize,
                        labelFontSize: metricLabelFontSize,
                      ),
                    ),
                  ],
                ),
              ),
              // Silme butonu veya diğer trailing widgetlar
              if (_isSelectionMode)
                Checkbox(
                  value: _selectedTrainings.contains(session.id),
                  onChanged: (bool? selected) {
                    _toggleTrainingSelection(session.id);
                  },
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: isDark ? Colors.red[300] : Colors.red,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _confirmDeleteTraining(
                      context, session.id, l10n, isDark, theme),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactMetric({
    required String value,
    required String label,
    required bool isDark,
    required Color textColor,
    double? fontSize,
    double? labelFontSize,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: fontSize ?? responsiveFontSize(context, 13) * 0.8, // %20 küçült
            color: textColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: labelFontSize ?? responsiveFontSize(context, 10) * 0.8, // %20 küçült
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _confirmDeleteTraining(BuildContext context, String trainingId,
      AppLocalizations l10n, bool isDark, ThemeData theme) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? theme.colorScheme.surface : Colors.white,
          title: Text(l10n.deleteTraining,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
              )),
          content: Text(
            l10n.deleteTrainingConfirm,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                l10n.cancel,
                style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[800]),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                l10n.deleteTraining,
                style: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                if (_userId != null) {
                  _deleteTraining(trainingId);
                }
              },
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  // Antrenmanı sil
  void _deleteTraining(String trainingId) {
    final l10n = AppLocalizations.of(context);
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.userNotFound),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ref
        .read(trainingHistoryProvider.notifier)
        .deleteTraining(_userId!, trainingId)
        .then((_) async {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.trainingDeleted),
          backgroundColor: Colors.green,
        ),
      );
      // Silme sonrası listeyi güncelle
      await _loadUserTrainings();
    });
  }

  // Tarih aralığı seçim penceresini göster
  Future<void> _showDateRangePicker(String userId) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: theme.colorScheme.primary,
                    onPrimary: Colors.white,
                    surface: theme.colorScheme.surface,
                    onSurface: Colors.white,
                  )
                : ColorScheme.light(
                    primary: theme.colorScheme.primary,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black87,
                  ),
            dialogBackgroundColor:
                isDark ? theme.colorScheme.surface : Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      _startDate = picked.start;
      _endDate = picked.end;

      ref.read(trainingHistoryProvider.notifier).filterByDateRange(
            userId,
            _startDate!,
            _endDate!,
          );
    }
  }

  // Seçilen antrenman oturumunu aç
  void _openTrainingSession(BuildContext context, TrainingSession session) {
    // Oturumu yükle
    ref.read(trainingSessionProvider.notifier).loadSession(session.id);

    // Skor girişi ekranına git
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TrainingSessionScreen(),
      ),
    );
  }

  // Function to check for and sync locally saved trainings to Supabase
  Future<void> _syncPendingTrainingsToSupabase() async {
    if (_isSyncing) {
      // Zaten bir senkronizasyon devam ediyorsa tekrar başlatma
      return;
    }
    _isSyncing = true;
    try {
      final trainingRepository = ref.read(trainingRepositoryProvider);
      final currentUser = SupabaseConfig.client.auth.currentUser;

      if (currentUser == null) {
        print('Kullanıcı oturum açmamış, senkronizasyon yapılamıyor');
        _isSyncing = false;
        return;
      }

      // İnternet bağlantısını kontrol et
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        print('İnternet bağlantısı yok, senkronizasyon erteleniyor');
        setState(() {
          _isOffline = true;
        });
        _isSyncing = false;
        return;
      }

      // İnternet bağlantısını daha güvenilir bir şekilde doğrula
      try {
        final result = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        if (result.isEmpty || result[0].rawAddress.isEmpty) {
          print(
              'İnternet bağlantısı yok (DNS sorgusu başarısız), senkronizasyon erteleniyor');
          setState(() {
            _isOffline = true;
          });
          _isSyncing = false;
          return;
        }
      } on SocketException catch (_) {
        print(
            'İnternet bağlantısı yok (Socket hatası), senkronizasyon erteleniyor');
        setState(() {
          _isOffline = true;
        });
        _isSyncing = false;
        return;
      } on TimeoutException catch (_) {
        print(
            'İnternet bağlantısı zayıf veya yok (zaman aşımı), senkronizasyon erteleniyor');
        setState(() {
          _isOffline = true;
        });
        _isSyncing = false;
        return;
      }

      // İnternet bağlantısı var, çevrimdışı durumunu kaldır
      setState(() {
        _isOffline = false;
      });

      print(
          'İnternet bağlantısı var, bekleyen antrenmanlar senkronize ediliyor...');

      // Bekleyen tüm antrenmanları senkronize et
      await trainingRepository.syncPendingTrainingSessions();

      // Senkronizasyon durumunu bildir
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('|10n:training_data_synced'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Antrenman listesini yenile
      if (_userId != null) {
        await ref.read(trainingHistoryProvider.notifier).loadUserTrainings(
              _userId!,
              force: true,
            );
      }
    } catch (e) {
      print('Senkronizasyon sırasında hata oluştu: $e');
      // Kullanıcıya hata bildirimini gösterme, çünkü bu arka planda çalışan bir işlem
    } finally {
      _isSyncing = false;
    }
  }

  // Sync button for user to manually trigger sync (upload + delta download)
  Future<void> _manualSync() async {
    if (_isSyncing) return;
    setState(() { _isSyncing = true; });
    try {
      final userId = _userId ?? SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).userNotFound)),
        );
        setState(() { _isSyncing = false; });
        return;
      }
      await ref.read(trainingHistoryProvider.notifier).requestBackgroundSync(userId, ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).syncCompleted),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() { _isSyncing = false; });
    }
  }

  String getLocalizedBowType(String? bowType, AppLocalizations l10n) {
    switch (bowType) {
      case 'Recurve':
        return l10n.bowTypeRecurve;
      case 'Compound':
        return l10n.bowTypeCompound;
      case 'Barebow':
        return l10n.bowTypeBarebow;
      default:
        return bowType ?? '-';
    }
  }
}
