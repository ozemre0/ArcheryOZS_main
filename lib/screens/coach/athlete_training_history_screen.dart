import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/training_history_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../models/training_session_model.dart';
import '../../models/scoring_rules.dart';
import 'dart:convert';
import '../../services/database_service.dart';
import '../../services/supabase_config.dart';

class AthleteTrainingHistoryScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;

  const AthleteTrainingHistoryScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
  });

  @override
  State<AthleteTrainingHistoryScreen> createState() =>
      _AthleteTrainingHistoryScreenState();
}

class _AthleteTrainingHistoryScreenState
    extends State<AthleteTrainingHistoryScreen> {
  // ...
  int _chartTrainingCount = 10;
  final List<int> _chartTrainingCountOptions = [5, 10, 20, 30];
  static const int _allTrainings = -1;

  final dateFormat = DateFormat('dd/MM/yyyy - HH:mm');
  final shortDateFormat = DateFormat('dd/MM/yyyy');
  final _trainingHistoryService = TrainingHistoryService();
  bool _isLoading = true;
  List<TrainingSession> _trainingSessions = [];
  int _selectedFilterIndex = 0;
  bool _isIndoor = false;

  // Date filter variables
  DateTime? _startDate;
  DateTime? _endDate;
  bool _dateFilterActive = false;

  @override
  void initState() {
    super.initState();
    _loadTrainingHistory();

    // Start realtime subscription for the athlete's data changes
    _startRealtimeSubscription();
  }

  // Setup realtime subscription to listen for changes to athlete's training data
  void _startRealtimeSubscription() {
    _trainingHistoryService.startCoachRealtimeSubscription(
      widget.athleteId,
      () {
        // This callback is executed when data changes in Supabase
        if (mounted) {
          print(
              'Coach received realtime update for athlete ${widget.athleteId}');
          // Reload training history data when we get a notification about changes
          _loadTrainingHistory();
        }
      },
    );
  }

  @override
  void dispose() {
    // Subscription'ı temizle
    _trainingHistoryService.clearCacheForAthlete(widget.athleteId);
    super.dispose();
  }

  // Verinin tutarlı olduğundan emin olmak için antrenör ekranında da mükerrer hesaplama sorununu önle
  // This function directly uses database values without recalculating
  Future<void> _loadTrainingHistory() async {
    // Çevrimdışı kontrolü
    final connectivity = await Connectivity().checkConnectivity();
    final isOffline = connectivity == ConnectivityResult.none;
    if (!mounted) return;
    if (mounted) setState(() => _isLoading = true);
    bool? indoorFilter;
    if (_selectedFilterIndex == 1) {
      indoorFilter = true;
    } else if (_selectedFilterIndex == 2) {
      indoorFilter = false;
    } else {
      indoorFilter = null;
    }
    print('Filtreleme: indoorFilter=\u001b[38;5;2m\u001b[0m$indoorFilter, dateFilter=$_dateFilterActive, startDate=$_startDate, endDate=$_endDate');
    List<Map<String, dynamic>> trainingsRaw;
    try {
      // Her zaman cache'den yükle (forceRefresh: true)
      if (_dateFilterActive && _startDate != null && _endDate != null) {
        trainingsRaw = await _trainingHistoryService.getAthleteTrainingHistory(
          widget.athleteId,
          isIndoor: indoorFilter,
          startDate: _startDate!,
          endDate: _endDate!,
          forceRefresh: true,
        );
      } else {
        trainingsRaw = await _trainingHistoryService.getAthleteTrainingHistory(
          widget.athleteId,
          isIndoor: indoorFilter,
          forceRefresh: true,
        );
      }
      // Map -> TrainingSession dönüşümü
      final trainings = trainingsRaw.map((e) => TrainingSession.fromJson(e)).toList();
      // Deduplicate by date and totalScore
      final dedupedTrainings = _deduplicateSessions(trainings);
      print('Filtreleme sonrası antrenman sayısı: ${dedupedTrainings.length}');
      if (mounted) {
        setState(() {
          _trainingSessions = dedupedTrainings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _trainingSessions = [];
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _filterTrainings(int filterIndex) async {
    if (_selectedFilterIndex != filterIndex) {
      setState(() {
        _selectedFilterIndex = filterIndex;
        // Filter indeksine göre indoor/outdoor değerini ayarla
        if (filterIndex == 1) {
          // Indoor seçildi
          _isIndoor = true;
        } else if (filterIndex == 2) {
          // Outdoor seçildi
          _isIndoor = false;
        } else {
          // Tüm antrenmanlar (filterIndex == 0)
          _isIndoor =
              false; // Bu değerin ne olduğu önemli değil çünkü aşağıda null geçeceğiz
        }
      });

      // Yeni filtreleri uygula ve verileri yeniden yükle
      await _loadTrainingHistory();
    }
  }

  // İki tarihin aynı gün olup olmadığını kontrol eden yardımcı fonksiyon
  bool _isSameDay(DateTime? date1, DateTime? date2) {
    if (date1 == null || date2 == null) return false;
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // --- GROUPING LOGIC ---
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final List<TrainingSession> todaySessions = [];
    final List<TrainingSession> yesterdaySessions = [];
    final List<TrainingSession> earlierSessions = [];
    for (final session in _trainingSessions) {
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
        title: Text('${widget.athleteName} - ${l10n.trainingHistory}'),
        actions: [
          // Tarih filtresi butonu
          IconButton(
            icon: Icon(
              Icons.date_range,
              color: _dateFilterActive ? theme.colorScheme.primary : null,
            ),
            tooltip: l10n.filterByDate,
            onPressed: _showDateRangePicker,
          ),
          // Yenileme butonu ekle
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: _manualRefresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterButtons(l10n, theme, isDark),
                // Aktif tarih filtresi göstergesi
                if (_dateFilterActive && _startDate != null && _endDate != null)
                  _buildActiveDateFilterIndicator(theme, isDark),
                Expanded(
                  child: _trainingSessions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.sports_score,
                                size: 64,
                                color: isDark
                                    ? Colors.grey[600]
                                    : Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                l10n.noTrainingsYet,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[700],
                                ),
                              ),
                              if (_dateFilterActive) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _isSameDay(_startDate, _endDate)
                                      ? l10n.noTrainingOnDate
                                      : l10n.noTrainingInRange,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.grey[500]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ]
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            // Performans grafiği - her zaman göster
                            if (_trainingSessions.any((s) => s.trainingType == 'score'))
                              _buildPerformanceChart(context, l10n, theme, isDark),
                            if (todaySessions.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
                                child: Text(
                                  l10n.today,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                              ...todaySessions.map((session) => _buildTrainingCard(
                                    context,
                                    session,
                                    theme,
                                    isDark,
                                    l10n,
                                  )),
                              Divider(height: 32, thickness: 1, indent: 16, endIndent: 16),
                            ],
                            if (yesterdaySessions.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
                                child: Text(
                                  l10n.yesterday,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                              ...yesterdaySessions.map((session) => _buildTrainingCard(
                                    context,
                                    session,
                                    theme,
                                    isDark,
                                    l10n,
                                  )),
                              if (earlierSessions.isNotEmpty)
                                Divider(height: 32, thickness: 1, indent: 16, endIndent: 16),
                            ],
                            if (earlierSessions.isNotEmpty) ...[
                              ...earlierSessions.map((session) => _buildTrainingCard(
                                    context,
                                    session,
                                    theme,
                                    isDark,
                                    l10n,
                                  )),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  // Aktif tarih filtre göstergesi
  Widget _buildActiveDateFilterIndicator(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.date_range,
            size: 16,
            color: isDark ? theme.colorScheme.primary : theme.primaryColor,
          ),
          const SizedBox(width: 8),
          Text(
            _isSameDay(_startDate, _endDate)
                ? shortDateFormat.format(_startDate!)
                : '${shortDateFormat.format(_startDate!)} - ${shortDateFormat.format(_endDate!)}',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? theme.colorScheme.primary : theme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.clear,
                size: 16,
                color: isDark ? theme.colorScheme.primary : theme.primaryColor),
            onPressed: _clearDateFilter,
            tooltip: AppLocalizations.of(context).clearDateFilter,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          )
        ],
      ),
    );
  }

  // Tarih filtresini temizleme
  void _clearDateFilter() {
    print('Clearing date filter');
    _trainingHistoryService.clearCacheForAthlete(widget.athleteId);
    setState(() {
      _dateFilterActive = false;
      _startDate = null;
      _endDate = null;
    });
    _loadTrainingHistory();
  }

  // Debug menüsü göster
  void _showDebugMenu(AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.today),
            title: Text(l10n.noTrainingOnDate),
            onTap: () {
              Navigator.pop(context);
              _testTodayFilter();
            },
          ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: Text(l10n.dateRange),
            onTap: () {
              Navigator.pop(context);
              _testDateRangeFilter();
            },
          ),
          ListTile(
            leading: const Icon(Icons.all_inclusive),
            title: Text(l10n.allTrainings),
            onTap: () {
              Navigator.pop(context);
              _debugShowAllTrainings(l10n);
            },
          ),
        ],
      ),
    );
  }

  // Bugünün antrenmanlarını gösteren test fonksiyonu
  Future<void> _testTodayFilter() async {
    final now = DateTime.now();
    setState(() {
      _startDate = now;
      _endDate = now;
      _dateFilterActive = true;
    });
    await _loadTrainingHistory();
  }

  // Belli bir tarih aralığını gösteren test fonksiyonu
  Future<void> _testDateRangeFilter() async {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    setState(() {
      _startDate = startOfWeek;
      _endDate = endOfWeek;
      _dateFilterActive = true;
    });
    await _loadTrainingHistory();
  }

  // Tüm antrenmanları gösteren debug fonksiyonu
  Future<void> _debugShowAllTrainings(AppLocalizations l10n) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final trainings = await _trainingHistoryService.getAthleteTrainingHistory(
        widget.athleteId,
        isIndoor: _isIndoor,
      );
      final sessionList = trainings.map((e) => TrainingSession.fromJson(e)).toList();
      final dedupedTrainings = _deduplicateSessions(sessionList);
      setState(() {
        _trainingSessions = dedupedTrainings;
        _isLoading = false;
        _dateFilterActive = false;
        _startDate = null;
        _endDate = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${dedupedTrainings.length} ${l10n.totalSessions}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // Manual refresh function for the refresh button
  Future<void> _manualRefresh() async {
    final l10n = AppLocalizations.of(context);

    print('Coach: Performing manual refresh for athlete: ${widget.athleteId}');

    // Clear cache for the athlete
    _trainingHistoryService.clearCacheForAthlete(widget.athleteId);

    // Reload training history data
    await _loadTrainingHistory();

    // Show a confirmation message if needed
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.refresh)),
      );
    }
  }

  // Tarih aralığı seçici
  Future<void> _showDateRangePicker() async {
    // Cache'i önceden temizleyelim
    _trainingHistoryService.clearCacheForAthlete(widget.athleteId);
    // Seçici için başlangıç tarihleri
    final initialDateRange =
        _dateFilterActive && _startDate != null && _endDate != null
            ? DateTimeRange(start: _startDate!, end: _endDate!)
            : DateTimeRange(
                start: DateTime.now().subtract(const Duration(days: 7)),
                end: DateTime.now(),
              );
    // Tarih aralığı göstergesi
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
      print(
          'Date range picked: ${pickedDateRange.start} to ${pickedDateRange.end}');
      setState(() {
        _startDate = pickedDateRange.start;
        _endDate = pickedDateRange.end;
        _dateFilterActive = true;
      });
      // Verileri yeniden yükle
      await _loadTrainingHistory();
    }
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
                  _filterTrainings(0);
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
                if (selected) {
                  _filterTrainings(1);
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
                if (selected) {
                  _filterTrainings(2);
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
          ],
        ),
      ),
    );
  }

  // Performance chart widget
  Widget _buildPerformanceChart(BuildContext context, AppLocalizations l10n,
      ThemeData theme, bool isDark) {
    // Only show 'score' trainings in the chart
    final scoreSessions = _trainingSessions.where((s) => s.trainingType == 'score').toList();
    if (scoreSessions.isEmpty) {
      return const SizedBox.shrink();
    }
    int count = _chartTrainingCount == _allTrainings ? scoreSessions.length : _chartTrainingCount;
    final List<TrainingSession> chartSessions =
        scoreSessions.length > count
            ? scoreSessions.sublist(0, count)
            : List.from(scoreSessions);
    chartSessions.sort((a, b) =>
        a.date.compareTo(b.date));
    final spots = <FlSpot>[];
    for (var i = 0; i < chartSessions.length; i++) {
      final average = chartSessions[i].average;
      spots.add(FlSpot(i.toDouble(), average));
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.performanceGraph,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                DropdownButton<int>(
                  value: _chartTrainingCount,
                  items: [
                    ..._chartTrainingCountOptions.map((count) => DropdownMenuItem(
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
                    fontSize: 14,
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

  Widget _buildTrainingCard(BuildContext context, TrainingSession session,
      ThemeData theme, bool isDark, AppLocalizations l10n) {
    final isIndoor = session.isIndoor;
    final bool isTechnique = session.trainingType == 'technique';
    final icon = isIndoor ? Icons.home : Icons.landscape;
    final iconColor = isIndoor ? Colors.blue : Colors.green;
    final backgroundColor = isDark ? theme.colorScheme.surface : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final totalArrows = session.totalArrows;
    final totalScore = session.totalScore;
    final average = totalArrows > 0 ? totalScore / totalArrows : 0.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final metricFontSize = screenWidth * 0.038;
    final metricLabelFontSize = screenWidth * 0.027;
    final metricSpacing = screenWidth * 0.03;
    final leftFontSize = 14 * 1.05;
    final leftSmallFontSize = 11 * 1.05;
    final leftDetailFontSize = 12 * 1.05;

    return Card(
      elevation: isDark ? 1 : 0,
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      color: backgroundColor,
      child: InkWell(
        onTap: () => _navigateToTrainingDetails(context, session),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              // Icon
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
              // Info
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
                            : leftSmallFontSize * 0.91,
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
              // Metrics
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
                                    totalScore.toString(),
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
                                    (totalArrows > 0 ? (totalArrows * 10).toString() : '0'),
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
                            SizedBox(width: metricSpacing),
                            Expanded(
                              child: _buildCompactMetric(
                                value: average.toStringAsFixed(2),
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
                      child: _buildCompactMetric(
                        value: totalScore.toString(),
                        label: l10n.total,
                        isDark: isDark,
                        textColor: textColor,
                        fontSize: metricFontSize,
                        labelFontSize: metricLabelFontSize,
                      ),
                    ),
                    SizedBox(width: metricSpacing),
                    Expanded(
                      child: _buildCompactMetric(
                        value: average.toStringAsFixed(2),
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
              const Icon(Icons.chevron_right, color: Colors.grey),
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
            fontSize: fontSize ?? 13,
            color: textColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: labelFontSize ?? 10,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _navigateToTrainingDetails(
      BuildContext context, TrainingSession session) {
    print('Antrenman detaylarına gidiliyor, session: ${session.toJson()}');
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrainingDetailsScreen(session: session),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Detaylar açılırken hata: ${e.toString()}")),
      );
    }
  }

  // Veri tutarlılığını doğrula - sadece debug modunda kullanılıyor
  void _validateTrainingData(Map<String, dynamic> training) {
    // Cache olarak kullanmak için hesaplamaları bir kez yap
    if (training.containsKey('series_data') &&
        training['series_data'] != null) {
      try {
        // SeriesData'dan okları çıkar
        List<List<int>> allSeries = [];
        final seriesData = jsonDecode(training['series_data'] as String);
        
        if (seriesData is List) {
          for (var item in seriesData) {
            if (item is List && item.length >= 2 && item[1] is List) {
              final arrows = List<int>.from(item[1]);
              allSeries.add(arrows);
            }
          }
        }
        
        // Toplam ok sayısı ve toplam puanı hesapla
        int totalArrows = 0;
        int totalScore = 0;
        int totalXCount = 0;

        for (var arrows in allSeries) {
          totalArrows += arrows.length;
          
          for (var arrow in arrows) {
            if (arrow == -1 || arrow == 11) {
              // X için 10 puan
              totalScore += 10;
              totalXCount++;
            } else if (arrow >= 0 && arrow <= 10) {
              totalScore += arrow;
            }
          }
        }

        // Antrenman değerlerini doğrula
        if (training['total_arrows'] != null &&
            training['total_arrows'] as int != totalArrows) {
          print(
              'Coach: Total arrows mismatch! Expected: $totalArrows, Got: ${training['total_arrows']}');
        }

        if (training['total_score'] != null &&
            training['total_score'] as int != totalScore) {
          print(
              'Coach: Total score mismatch! Expected: $totalScore, Got: ${training['total_score']}');
        }

        if (training['average'] != null) {
          final calculatedAverage =
              totalArrows > 0 ? totalScore / totalArrows : 0.0;
          if (((training['average'] as double) - calculatedAverage).abs() >
              0.01) {
            print(
                'Coach: Average mismatch! Expected: $calculatedAverage, Got: ${training['average']}');
          }
        }
        
        if (training['x_count'] != null &&
            training['x_count'] as int != totalXCount) {
          print(
              'Coach: X count mismatch! Expected: $totalXCount, Got: ${training['x_count']}');
        }
      } catch (e) {
        print('Coach: Error validating training data: $e');
      }
    }
  }

  // Helper: Remove duplicate sessions by type and delete extras
  List<TrainingSession> _deduplicateSessions(List<TrainingSession> sessions) {
    final seen = <String, TrainingSession>{};
    final duplicatesToDelete = <TrainingSession>[];
    for (final s in sessions) {
      String key;
      if (s.trainingType == 'technique') {
        key = '${s.date.toIso8601String()}_${s.totalArrows}';
      } else {
        key = '${s.date.toIso8601String()}_${s.totalScore}';
      }
      if (!seen.containsKey(key)) {
        seen[key] = s;
      } else {
        duplicatesToDelete.add(s);
      }
    }
    // Fazlalık olanları sil (hem local hem Supabase)
    for (final dup in duplicatesToDelete) {
      DatabaseService().softDeleteTrainingSession(dup.id);
      SupabaseConfig.client
        .from('training_sessions')
        .update({'is_deleted': true})
        .eq('id', dup.id);
    }
    return seen.values.toList();
  }
}

// Antrenman detay ekranı - sporcu verilerini görmek için geliştirildi
class TrainingDetailsScreen extends StatefulWidget {
  final TrainingSession session;

  const TrainingDetailsScreen({
    super.key,
    required this.session,
  });

  @override
  State<TrainingDetailsScreen> createState() => _TrainingDetailsScreenState();
}

class _TrainingDetailsScreenState extends State<TrainingDetailsScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    // Debug için ekrana basılan session verisi
    print('TrainingDetailsScreen - session: ${widget.session.toJson()}');
    
    // Animasyon kontrolcüsü
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final dateFormat = DateFormat('dd/MM/yyyy - HH:mm');
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    
    // Hesaplanacak değerler
    final bestArrow = _calculateBestArrow(session.decodedSeriesData);
    final bestSeries = _calculateBestSeries(session.decodedSeriesData);

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
              opacity: _fadeAnimation,
              child: CustomScrollView(
                slivers: [
                  // Özel App Bar
                  SliverAppBar(
                    expandedHeight: 180.0,
                    floating: false,
                    pinned: true,
                    stretch: true,
                    backgroundColor: session.isIndoor ? Colors.blue.shade700 : Colors.green.shade700,
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        l10n.trainingDetails,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              blurRadius: 4.0,
                              color: Colors.black.withOpacity(0.5),
                              offset: const Offset(1.0, 1.0),
                            ),
                          ],
                        ),
                      ),
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Arkaplan görseli/deseni
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                                colors: session.isIndoor
                                    ? [Colors.blue.shade900, Colors.blue.shade600]
                                    : [Colors.green.shade900, Colors.green.shade600],
                              ),
                            ),
                          ),
                          // Ok deseni
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: Opacity(
                              opacity: 0.2,
                              child: Icon(
                                session.isIndoor ? Icons.home : Icons.landscape,
                                size: 120,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          // Bilgi kartı
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 60,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  dateFormat.format(session.date),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${getLocalizedBowType(session.bowType, l10n)} | ${session.distance} ${l10n.meters}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // İçerik
                  SliverToBoxAdapter(
                    child: AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - _animationController.value)),
                          child: Opacity(
                            opacity: _animationController.value,
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // İstatistik kartları
                            if (session.trainingType != 'technique')
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark ? colorScheme.surface : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.statistics,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        _buildStatisticItem(
                                          icon: Icons.score,
                                          color: Colors.orange,
                                          value: session.totalScore.toString(),
                                          label: l10n.total,
                                          isDark: isDark,
                                        ),
                                        _buildStatisticItem(
                                          icon: Icons.trending_up,
                                          color: Colors.green,
                                          value: session.average.toStringAsFixed(2),
                                          label: l10n.average,
                                          isDark: isDark,
                                        ),
                                        _buildStatisticItem(
                                          icon: Icons.arrow_forward,
                                          color: Colors.blue,
                                          value: session.totalArrows.toString(),
                                          label: l10n.arrows,
                                          isDark: isDark,
                                        ),
                                      ],
                                    ),
                                    if (bestArrow != null || bestSeries != null) const SizedBox(height: 24),
                                    if (bestArrow != null || bestSeries != null)
                                      Row(
                                        children: [
                                          if (bestArrow != null)
                                            _buildStatisticItem(
                                              icon: Icons.grade,
                                              color: Colors.amber,
                                              value: bestArrow.toString(),
                                              label: l10n.bestArrow,
                                              isDark: isDark,
                                            ),
                                          if (bestSeries != null)
                                            _buildStatisticItem(
                                              icon: Icons.trending_up,
                                              color: Colors.purple,
                                              value: bestSeries.toString(),
                                              label: l10n.bestSeries,
                                              isDark: isDark,
                                            ),
                                          const Expanded(child: SizedBox()),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            
                            const SizedBox(height: 24),
                            
                            // Antrenman bilgileri kartı
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? colorScheme.surface : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.trainingDetails,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  // Detay öğeleri
                                  _buildDetailItem(
                                    isDark: isDark,
                                    icon: Icons.sports_handball,
                                    iconColor: Colors.blue,
                                    title: l10n.bowType,
                                    value: getLocalizedBowType(session.bowType, l10n),
                                  ),
                                  const Divider(),
                                  
                                  _buildDetailItem(
                                    isDark: isDark,
                                    icon: Icons.speed,
                                    iconColor: Colors.orange,
                                    title: l10n.distance,
                                    value: '${session.distance} ${l10n.meters}',
                                  ),
                                  const Divider(),
                                  
                                  _buildDetailItem(
                                    isDark: isDark,
                                    icon: session.isIndoor ? Icons.home : Icons.landscape,
                                    iconColor: session.isIndoor ? Colors.indigo : Colors.green,
                                    title: l10n.environment,
                                    value: session.isIndoor ? l10n.indoor : l10n.outdoor,
                                  ),
                                  
                                  if (session.trainingType == 'technique') ...[
                                    const Divider(),
                                    _buildDetailItem(
                                      isDark: isDark,
                                      icon: Icons.arrow_forward,
                                      iconColor: Colors.blue,
                                      title: l10n.arrows,
                                      value: session.totalArrows.toString(),
                                    ),
                                  ],
                                  
                                  if (session.notes != null && session.notes!.isNotEmpty) const Divider(),
                                  
                                  if (session.notes != null && session.notes!.isNotEmpty)
                                    _buildDetailItem(
                                      isDark: isDark,
                                      icon: Icons.notes,
                                      iconColor: Colors.teal,
                                      title: l10n.notes,
                                      value: session.notes ?? '-',
                                    ),
                                  
                                  if (session.training_session_name != null && session.training_session_name!.isNotEmpty) const Divider(),
                                  
                                  if (session.training_session_name != null && session.training_session_name!.isNotEmpty)
                                    _buildDetailItem(
                                      isDark: isDark,
                                      icon: Icons.fitness_center,
                                      iconColor: Colors.purple,
                                      title: l10n.trainingSessionName,
                                      value: session.training_session_name ?? '-',
                                    ),
                                ],
                              ),
                            ),
                            
                            // Seriler
                            if (session.trainingType != 'technique' && session.decodedSeriesData.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              _buildSeriesSection(session, isDark, l10n, theme),
                            ],
                            
                            // Alt boşluk
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildStatisticItem({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    required bool isDark,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.2 : 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailItem({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesSection(TrainingSession session, bool isDark, AppLocalizations l10n, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.series,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: colorScheme.primary,
                ),
              ),
              Text(
                '${session.decodedSeriesData.length} ${l10n.series.toLowerCase()}',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Seri öğeleri
          ...List.generate(session.decodedSeriesData.length, (index) {
            final seriesArrows = session.decodedSeriesData[index];
            final seriesScore = seriesArrows.fold(0, (sum, arrow) => sum + (arrow == 11 || arrow == -1 ? 10 : arrow));
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark 
                    ? colorScheme.surface.withOpacity(0.7) 
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark 
                      ? Colors.grey[800]! 
                      : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${l10n.series} ${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          seriesScore.toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: seriesArrows.map((arrow) {
                      // Renk ve değer ayarları
                      Color arrowColor;
                      String arrowValue;
                      if (arrow == 11 || arrow == -1) {
                        arrowColor = Colors.yellow; // X için sarı
                        arrowValue = 'X';
                      } else if (arrow == 10 || arrow == 9) {
                        arrowColor = Colors.yellow;
                        arrowValue = arrow.toString();
                      } else if (arrow == 8 || arrow == 7) {
                        arrowColor = Colors.red;
                        arrowValue = arrow.toString();
                      } else if (arrow == 6 || arrow == 5) {
                        arrowColor = Colors.blue;
                        arrowValue = arrow.toString();
                      } else if (arrow == 4 || arrow == 3) {
                        arrowColor = Colors.black;
                        arrowValue = arrow.toString();
                      } else if (arrow == 2 || arrow == 1) {
                        arrowColor = Colors.white;
                        arrowValue = arrow.toString();
                      } else if (arrow == 0) {
                        arrowColor = Colors.grey;
                        arrowValue = 'M'; // 0 için M harfi
                      } else {
                        arrowColor = Colors.grey;
                        arrowValue = arrow.toString();
                      }
                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: arrowColor.withOpacity(isDark ? 0.7 : 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: arrowColor.withOpacity(isDark ? 0.5 : 1.0),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            arrowValue,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: arrowColor == Colors.white 
                                  ? Colors.black 
                                  : (isDark ? Colors.white : arrowColor),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
  
  // En iyi ok skorunu hesapla
  int? _calculateBestArrow(List<List<int>> seriesData) {
    if (seriesData.isEmpty) return null;
    
    int bestArrow = 0;
    for (var series in seriesData) {
      for (var arrow in series) {
        if (arrow == 11 || arrow == -1) {
          return 10; // X ok en yüksek değerdir
        }
        if (arrow > bestArrow) {
          bestArrow = arrow;
        }
      }
    }
    
    return bestArrow > 0 ? bestArrow : null;
  }
  
  // En iyi seriyi hesapla
  int? _calculateBestSeries(List<List<int>> seriesData) {
    if (seriesData.isEmpty) return null;
    
    int bestSeriesScore = 0;
    for (var series in seriesData) {
      int seriesScore = 0;
      for (var arrow in series) {
        if (arrow == 11 || arrow == -1) {
          seriesScore += 10;
        } else if (arrow >= 0) {
          seriesScore += arrow;
        }
      }
      
      if (seriesScore > bestSeriesScore) {
        bestSeriesScore = seriesScore;
      }
    }
    
    return bestSeriesScore > 0 ? bestSeriesScore : null;
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
