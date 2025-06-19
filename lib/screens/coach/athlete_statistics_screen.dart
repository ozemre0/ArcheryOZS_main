import 'package:flutter/material.dart';
import '../../services/athlete_statistics_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../../services/local_storage_service.dart';

class AthleteStatisticsScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;

  const AthleteStatisticsScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
  });

  @override
  State<AthleteStatisticsScreen> createState() =>
      _AthleteStatisticsScreenState();
}

enum EnvironmentFilter { all, indoor, outdoor }

enum DateRangeFilter { all, day, week, twoWeeks, custom }

class _AthleteStatisticsScreenState extends State<AthleteStatisticsScreen> {
  final _statisticsService = AthleteStatisticsService();
  bool _isLoading = true;
  Map<String, dynamic> _statistics = {};

  // Filtering variables
  EnvironmentFilter _environmentFilter = EnvironmentFilter.all;
  DateRangeFilter _dateRangeFilter = DateRangeFilter.all;
  DateTime? _startDate;
  DateTime? _endDate;

  static const String _envFilterKey = 'athlete_stats_env_filter';
  static const String _dateFilterKey = 'athlete_stats_date_filter';
  static const String _dateStartKey = 'athlete_stats_date_start';
  static const String _dateEndKey = 'athlete_stats_date_end';
  bool _filtersLoaded = false;

  // Add ScrollController for horizontal filter chips
  final ScrollController _dateFilterScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _dateFilterScrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _loadLastFilters();
    await _loadAthleteStatistics();
    setState(() {
      _filtersLoaded = true;
    });
  }

  Future<void> _loadLastFilters() async {
    // Environment
    final envValue = await LocalStorageService.getString(_envFilterKey);
    if (envValue == 'indoor') {
      _environmentFilter = EnvironmentFilter.indoor;
    } else if (envValue == 'outdoor') {
      _environmentFilter = EnvironmentFilter.outdoor;
    }
    // Date Range
    final dateValue = await LocalStorageService.getString(_dateFilterKey);
    if (dateValue != null) {
      _dateRangeFilter = DateRangeFilter.values.firstWhere(
        (e) => e.toString() == dateValue,
        orElse: () => DateRangeFilter.all,
      );
      if (_dateRangeFilter == DateRangeFilter.custom) {
        final startStr = await LocalStorageService.getString(_dateStartKey);
        final endStr = await LocalStorageService.getString(_dateEndKey);
        if (startStr != null && endStr != null) {
          _startDate = DateTime.tryParse(startStr);
          _endDate = DateTime.tryParse(endStr);
        }
      }
    }
  }

  Future<void> _saveEnvFilter(EnvironmentFilter filter) async {
    String value = filter == EnvironmentFilter.indoor
        ? 'indoor'
        : filter == EnvironmentFilter.outdoor
            ? 'outdoor'
            : 'all';
    await LocalStorageService.setString(_envFilterKey, value);
  }

  Future<void> _saveDateFilter(DateRangeFilter filter) async {
    await LocalStorageService.setString(_dateFilterKey, filter.toString());
    if (filter == DateRangeFilter.custom && _startDate != null && _endDate != null) {
      await LocalStorageService.setString(_dateStartKey, _startDate!.toIso8601String());
      await LocalStorageService.setString(_dateEndKey, _endDate!.toIso8601String());
    }
  }

  Future<void> _loadAthleteStatistics() async {
    setState(() => _isLoading = true);
    try {
      // Prepare date range based on selected filter
      _updateDateRange();

      // Get environment filter
      bool? isIndoor;
      if (_environmentFilter == EnvironmentFilter.indoor) {
        isIndoor = true;
      } else if (_environmentFilter == EnvironmentFilter.outdoor) {
        isIndoor = false;
      }

      final statistics = await _statisticsService.getAthleteStatistics(
        widget.athleteId,
        isIndoor: isIndoor,
        startDate: _startDate,
        endDate: _endDate,
      );

      setState(() {
        _statistics = statistics;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error(e.toString()))),
        );
      }
    }
  }

  // Update date range based on selected filter
  void _updateDateRange() {
    final now = DateTime.now();

    switch (_dateRangeFilter) {
      case DateRangeFilter.day:
        _startDate = DateTime(now.year, now.month, now.day - 1);
        _endDate = now;
        break;
      case DateRangeFilter.week:
        _startDate = DateTime(now.year, now.month, now.day - 7);
        _endDate = now;
        break;
      case DateRangeFilter.twoWeeks:
        _startDate = DateTime(now.year, now.month, now.day - 14);
        _endDate = now;
        break;
      case DateRangeFilter.custom:
        // Keep existing custom dates
        break;
      case DateRangeFilter.all:
      default:
        _startDate = null;
        _endDate = null;
        break;
    }
  }

  // Show date picker for custom date range
  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final initialDateRange = DateTimeRange(
      start: _startDate ?? DateTime(now.year, now.month, now.day - 7),
      end: _endDate ?? now,
    );

    final pickedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Theme.of(context).colorScheme.primary,
                ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDateRange != null) {
      setState(() {
        _dateRangeFilter = DateRangeFilter.custom;
        _startDate = pickedDateRange.start;
        _endDate = pickedDateRange.end;
      });
      await _saveDateFilter(DateRangeFilter.custom);
      await _loadAthleteStatistics();
    }
  }

  String getDateRangeText() {
    if (_startDate == null || _endDate == null) {
      return '';
    }

    final formatter = DateFormat('dd/MM/yyyy');
    return '${formatter.format(_startDate!)} - ${formatter.format(_endDate!)}';
  }

  String _getFilterStatusText(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    List<String> filters = [];

    // Environment filter
    if (_environmentFilter != EnvironmentFilter.all) {
      String envFilter = _environmentFilter == EnvironmentFilter.indoor
          ? l10n.indoor
          : l10n.outdoor;
      filters.add(envFilter);
    }

    // Date range filter
    if (_dateRangeFilter != DateRangeFilter.all) {
      if (_dateRangeFilter == DateRangeFilter.custom &&
          _startDate != null &&
          _endDate != null) {
        filters.add('${l10n.dateRange}: ${getDateRangeText()}');
      } else {
        // Replace l10n.dateRangeFilter with direct values
        String dateFilter;
        switch (_dateRangeFilter) {
          case DateRangeFilter.day:
            dateFilter = "Son 1 Gün";
            break;
          case DateRangeFilter.week:
            dateFilter = "Son 1 Hafta";
            break;
          case DateRangeFilter.twoWeeks:
            dateFilter = "Son 2 Hafta";
            break;
          default:
            dateFilter = "Özel Tarih";
        }
        filters.add(dateFilter);
      }
    }

    if (filters.isEmpty) {
      // Replace l10n.noActiveFilters with a direct value
      return "Aktif Filtre Yok";
    }

    // Replace l10n.activeFilters with a direct value
    return "Aktif Filtreler: ${filters.join(', ')}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final l10n = AppLocalizations.of(context);
    if (!_filtersLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.athleteName} - ${l10n.statistics}'),
        elevation: isDark ? 1 : 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: () {
              _statisticsService.clearCacheForAthlete(widget.athleteId);
              _loadAthleteStatistics();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              color: isDark ? theme.scaffoldBackgroundColor : Colors.grey[50],
              child: _statistics.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noStatisticsAvailable,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilterSection(theme, isDark, textColor),
                          const SizedBox(height: 16),
                          // Ortam seçimine göre sadece ilgili kartı göster
                          if (_environmentFilter == EnvironmentFilter.indoor)
                            _buildEnvironmentStatCard(
                                l10n.indoor,
                                _statistics['indoor'],
                                Colors.blue,
                                Icons.home_outlined,
                                theme,
                                isDark),
                          if (_environmentFilter == EnvironmentFilter.outdoor)
                            _buildEnvironmentStatCard(
                                l10n.outdoor,
                                _statistics['outdoor'],
                                Colors.green,
                                Icons.landscape_outlined,
                                theme,
                                isDark),
                        ],
                      ),
                    ),
            ),
    );
  }

  Widget _buildEnvironmentStatCard(
    String title,
    Map<String, dynamic> stats,
    Color color,
    IconData icon,
    ThemeData theme,
    bool isDark,
  ) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: isDark ? 2 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? theme.colorScheme.surface : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailLine(
                l10n.totalSessions, stats['totalSessions'].toString(), isDark),
            _buildDetailLine(
                l10n.totalArrows, stats['totalArrows'].toString(), isDark),
            _buildDetailLine(
                l10n.average, stats['averageScore'].toStringAsFixed(2), isDark),
            _buildDetailLine(l10n.highestScore,
                stats['bestScore'].toStringAsFixed(2), isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailLine(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 1,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(ThemeData theme, bool isDark, Color textColor) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Indoor/Outdoor Seçim Tabları - Daha yaratıcı UI
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: isDark ? theme.colorScheme.surface.withOpacity(0.7) : Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black12 : Colors.black.withOpacity(0.05),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _environmentFilter = EnvironmentFilter.indoor;
                      });
                      _saveEnvFilter(EnvironmentFilter.indoor);
                      _loadAthleteStatistics();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: _environmentFilter == EnvironmentFilter.indoor
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.home_outlined,
                            color: _environmentFilter == EnvironmentFilter.indoor
                                ? Colors.white
                                : isDark ? Colors.white70 : Colors.grey[800],
                            size: 26,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.indoor,
                            style: TextStyle(
                              color: _environmentFilter == EnvironmentFilter.indoor
                                  ? Colors.white
                                  : isDark ? Colors.white70 : Colors.grey[800],
                              fontWeight: _environmentFilter == EnvironmentFilter.indoor
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _environmentFilter = EnvironmentFilter.outdoor;
                      });
                      _saveEnvFilter(EnvironmentFilter.outdoor);
                      _loadAthleteStatistics();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: _environmentFilter == EnvironmentFilter.outdoor
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.landscape_outlined,
                            color: _environmentFilter == EnvironmentFilter.outdoor
                                ? Colors.white
                                : isDark ? Colors.white70 : Colors.grey[800],
                            size: 26,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.outdoor,
                            style: TextStyle(
                              color: _environmentFilter == EnvironmentFilter.outdoor
                                  ? Colors.white
                                  : isDark ? Colors.white70 : Colors.grey[800],
                              fontWeight: _environmentFilter == EnvironmentFilter.outdoor
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Tarihe Göre Filtreler - Card
        Card(
          elevation: isDark ? 2 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
          color: isDark ? theme.colorScheme.surface : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.date_range,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.dateRange,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const Spacer(),
                    if (_dateRangeFilter != DateRangeFilter.all)
                      TextButton.icon(
                        icon: const Icon(Icons.clear, size: 16),
                        label: Text(
                          l10n.clear,
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          setState(() {
                            _dateRangeFilter = DateRangeFilter.all;
                            _startDate = null;
                            _endDate = null;
                          });
                          _loadAthleteStatistics();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black12 : Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.grey.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      controller: _dateFilterScrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDateFilterChip(
                            DateRangeFilter.all,
                            l10n.allTime,
                            Icons.all_inclusive,
                            theme,
                            isDark,
                          ),
                          _buildDateFilterChip(
                            DateRangeFilter.day,
                            l10n.lastDay,
                            Icons.watch_later_outlined,
                            theme,
                            isDark,
                          ),
                          _buildDateFilterChip(
                            DateRangeFilter.week,
                            l10n.lastWeek,
                            Icons.calendar_view_week,
                            theme,
                            isDark,
                          ),
                          _buildDateFilterChip(
                            DateRangeFilter.twoWeeks,
                            l10n.lastTwoWeeks,
                            Icons.date_range_outlined,
                            theme,
                            isDark,
                          ),
                          _buildDateFilterChip(
                            DateRangeFilter.custom,
                            l10n.customDateRange,
                            Icons.edit_calendar,
                            theme,
                            isDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Custom date range display if applicable
                if (_dateRangeFilter == DateRangeFilter.custom &&
                    _startDate != null &&
                    _endDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            getDateRangeText(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16),
                            color: theme.colorScheme.primary,
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onPressed: _selectCustomDateRange,
                            tooltip: l10n.changeDateRange,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Tarih filtreleri için chip butonları
  Widget _buildDateFilterChip(
    DateRangeFilter filter,
    String label, 
    IconData icon,
    ThemeData theme,
    bool isDark,
  ) {
    final isSelected = _dateRangeFilter == filter;
    
    return GestureDetector(
      onTap: () async {
        setState(() {
          _dateRangeFilter = filter;
        });
        // Scroll to selected chip after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToSelectedDateFilter(filter);
        });
        if (filter == DateRangeFilter.custom) {
          await _selectCustomDateRange();
        } else {
          await _saveDateFilter(filter);
          await _loadAthleteStatistics();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.colorScheme.primary 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : isDark ? Colors.white70 : theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Colors.white
                    : isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Yeni: Seçili chip'i görünür yapmak için scroll fonksiyonu
  void _scrollToSelectedDateFilter(DateRangeFilter filter) {
    // Chip index'ini bul
    int index = 0;
    switch (filter) {
      case DateRangeFilter.all:
        index = 0;
        break;
      case DateRangeFilter.day:
        index = 1;
        break;
      case DateRangeFilter.week:
        index = 2;
        break;
      case DateRangeFilter.twoWeeks:
        index = 3;
        break;
      case DateRangeFilter.custom:
        index = 4;
        break;
    }
    // Her chip yaklaşık 110px genişlikte, margin/padding ile birlikte
    final double chipWidth = 110;
    final double offset = (index * chipWidth) - 16;
    _dateFilterScrollController.animateTo(
      offset < 0 ? 0 : offset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }
}
