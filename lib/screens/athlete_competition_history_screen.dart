import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:archeryozs/services/competition_local_db.dart';
import '../services/competition_sync_service.dart';
import '../services/supabase_config.dart';

class AthleteCompetitionHistoryScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;
  const AthleteCompetitionHistoryScreen(
      {Key? key, required this.athleteId, required this.athleteName})
      : super(key: key);

  @override
  State<AthleteCompetitionHistoryScreen> createState() =>
      _AthleteCompetitionHistoryScreenState();
}

class _AthleteCompetitionHistoryScreenState
    extends State<AthleteCompetitionHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _competitions = [];
  String? _error;

  // Yaş grubu id -> isim map'i
  Map<int, String> _resolvedAgeGroupNames = {};

  // Takım türü id -> isim map'i
  Map<String, String> _teamTypeNames = {};

  @override
  void initState() {
    super.initState();
    _loadAndMapAgeGroupsFromLocal();
    _loadCompetitionsFromLocal();
    _syncAndUpdateCompetitions();
    _loadTeamTypeNames();
  }

  Future<void> _loadAndMapAgeGroupsFromLocal() async {
    final allAgeGroups = await CompetitionLocalDb.instance.getAgeGroups();
    if (!mounted) return;
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
          displayName = (ageGroup['age_group_en'] ?? ageGroup['age_group_tr'] ?? id.toString()) as String? ?? 'N/A';
        }
        tempMap[id] = displayName;
      }
    }
    if (mounted) {
      setState(() {
        _resolvedAgeGroupNames = tempMap;
      });
    }
  }

  Future<void> _loadCompetitionsFromLocal() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final localList = await CompetitionLocalDb.instance.getCompetitionsByAthlete(widget.athleteId);
      if (mounted) {
        setState(() {
          _competitions = localList;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _syncAndUpdateCompetitions() async {
    try {
      await CompetitionSyncService.syncCompetitions(widget.athleteId);
      final localList = await CompetitionLocalDb.instance.getCompetitionsByAthlete(widget.athleteId);
      if (mounted) {
        setState(() {
          _competitions = localList;
        });
      }
    } catch (e) {
      // Sync hatası ekrana yansıtılmaz
    }
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

  String _environmentFilter = 'all';

  // Add date filter state variables
  DateTime? _startDate;
  DateTime? _endDate;
  bool _dateFilterActive = false;

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
          final isDeleted = comp['is_deleted'] == true || comp['is_deleted'] == 1;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final double baseFontSize = (screenWidth * 0.045).clamp(14, 22);
    final double smallFontSize = (screenWidth * 0.034).clamp(11, 16);
    final double textScale = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.25);

    // Use the unified filtered competitions
    final filteredCompetitions = _filteredCompetitions;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.athleteCompetitionHistoryTitle(widget.athleteName),
          style: TextStyle(fontSize: baseFontSize + 2),
          textScaleFactor: textScale,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(l10n.errorLoadingCompetitions, style: TextStyle(fontSize: baseFontSize), textScaleFactor: textScale))
                : Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.04, vertical: 12),
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
                                    color: _environmentFilter == 'all'
                                        ? Colors.blue
                                        : const Color.fromARGB(255, 155, 155, 155),
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
                                backgroundColor: isDark
                                    ? theme.colorScheme.surface
                                    : Colors.grey[100],
                                selectedColor: isDark
                                    ? Colors.blueGrey[800]
                                    : Colors.blue[100],
                                checkmarkColor: Colors.blue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: _environmentFilter == 'all'
                                        ? Colors.blue
                                        : Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                padding: EdgeInsets.symmetric(
                                    horizontal: screenWidth * 0.01, vertical: 2),
                              ),
                              FilterChip(
                                key: const ValueKey('filter_indoor'),
                                label: Text(
                                  l10n.indoorLabel.replaceAll(' (Hall)', ''),
                                  style: TextStyle(
                                    color: _environmentFilter == 'indoor'
                                        ? Colors.blue
                                        : const Color.fromARGB(255, 155, 155, 155),
                                    fontWeight: FontWeight.w500,
                                    fontSize: smallFontSize,
                                  ),
                                ),
                                avatar: Icon(
                                  Icons.home_outlined,
                                  size: 18,
                                  color: _environmentFilter == 'indoor'
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                selected: _environmentFilter == 'indoor',
                                onSelected: (_) {
                                  setState(() {
                                    _environmentFilter = 'indoor';
                                  });
                                },
                                backgroundColor: isDark
                                    ? theme.colorScheme.surface
                                    : Colors.grey[100],
                                selectedColor: isDark
                                    ? Colors.blueGrey[800]
                                    : Colors.blue[100],
                                checkmarkColor: Colors.blue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: _environmentFilter == 'indoor'
                                        ? Colors.blue
                                        : Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                padding: EdgeInsets.symmetric(
                                    horizontal: screenWidth * 0.01, vertical: 2),
                              ),
                              FilterChip(
                                key: const ValueKey('filter_outdoor'),
                                label: Text(
                                  l10n.outdoorLabel.replaceAll(' (Open Air)', ''),
                                  style: TextStyle(
                                    color: _environmentFilter == 'outdoor'
                                        ? Colors.green
                                        : const Color.fromARGB(255, 155, 155, 155),
                                    fontWeight: FontWeight.w500,
                                    fontSize: smallFontSize,
                                  ),
                                ),
                                avatar: Icon(
                                  Icons.landscape_outlined,
                                  size: 18,
                                  color: _environmentFilter == 'outdoor'
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                selected: _environmentFilter == 'outdoor',
                                onSelected: (_) {
                                  setState(() {
                                    _environmentFilter = 'outdoor';
                                  });
                                },
                                backgroundColor: isDark
                                    ? theme.colorScheme.surface
                                    : Colors.grey[100],
                                selectedColor: isDark
                                    ? Colors.green[900]
                                    : Colors.green[100],
                                checkmarkColor: Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: _environmentFilter == 'outdoor'
                                        ? Colors.green
                                        : Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                padding: EdgeInsets.symmetric(
                                    horizontal: screenWidth * 0.01, vertical: 2),
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
                                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.01, vertical: 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_dateFilterActive && _startDate != null && _endDate != null)
                        Padding(
                          padding: EdgeInsets.only(left: 20, right: 20, bottom: 4),
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
                        child: filteredCompetitions.isEmpty
                            ? Center(child: Text(l10n.noCompetitionHistory, style: TextStyle(fontSize: baseFontSize), textScaleFactor: textScale))
                            : ListView.builder(
                                key: ValueKey(
                                  '${_environmentFilter}_${_dateFilterActive ? _getDateRangeText() : "all"}'
                                ),
                                padding: EdgeInsets.symmetric(
                                    horizontal: screenWidth * 0.025, vertical: 8),
                                itemCount: filteredCompetitions.length,
                                itemBuilder: (context, index) {
                                  final comp = filteredCompetitions[index];
                                  // DEBUG: Print age group info for diagnosis
                                  debugPrint('Competition ID: \\${comp['competition_id']} - age_group: \\${comp['age_group']}');
                                  debugPrint('_resolvedAgeGroupNames: \\$_resolvedAgeGroupNames');
                                  debugPrint('DEBUG |10n: comp[team_type]=${comp['team_type']}, comp[team_result]=${comp['team_result']}');
                                  final showTeamRow = (comp['team_type'] != null && comp['team_type'].toString().isNotEmpty) ||
                                                      (comp['team_result'] != null && comp['team_result'].toString().isNotEmpty);
                                  debugPrint('DEBUG |10n: showTeamRow=$showTeamRow for competition_id=${comp['competition_id']}');
                                  final competitionDate = DateTime.tryParse(
                                      comp['competition_date'] ?? '');
                                  final formattedDate = competitionDate != null
                                      ? DateFormat('d MMM', l10n.localeName)
                                          .format(competitionDate)
                                      : l10n.dateNotSelected;
                                  final isIndoor =
                                      comp['environment'] == 'indoor';
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: isIndoor
                                            ? Colors.blue.shade100
                                            : Colors.orange.shade100,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: screenWidth * 0.022, horizontal: screenWidth * 0.02),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isIndoor
                                                ? Icons.home_outlined
                                                : Icons.landscape_outlined,
                                            color: isIndoor
                                                ? Colors.blue
                                                : Colors.green,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child:
                                                          SingleChildScrollView(
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        child: Text(
                                                          comp['competition_name']
                                                                      ?.toString()
                                                                      .isNotEmpty ==
                                                                  true
                                                              ? comp[
                                                                  'competition_name']
                                                              : l10n
                                                                  .unnamedCompetition,
                                                          style: TextStyle(
                                                            fontSize: baseFontSize,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: isDark
                                                                ? const Color
                                                                    .fromARGB(255,
                                                                    219, 219, 219)
                                                                : const Color
                                                                    .fromARGB(255,
                                                                    54, 54, 54),
                                                          ),
                                                          textScaleFactor: textScale,
                                                          overflow: TextOverflow.ellipsis,
                                                          maxLines: 1,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Builder(
                                                      builder: (context) {
                                                        double? score = comp[
                                                                    'qualification_score']
                                                                is num
                                                            ? comp['qualification_score']
                                                                ?.toDouble()
                                                            : double.tryParse(
                                                                comp['qualification_score']
                                                                        ?.toString() ??
                                                                    '');
                                                        double? maxScore = comp[
                                                                    'max_score']
                                                                is num
                                                            ? comp['max_score']
                                                                ?.toDouble()
                                                            : double.tryParse(comp[
                                                                        'max_score']
                                                                    ?.toString() ??
                                                                '');
                                                        double? average;
                                                        if (score != null &&
                                                            maxScore != null &&
                                                            maxScore > 0) {
                                                          average =
                                                              (score / maxScore) *
                                                                  10;
                                                        }
                                                        Color avgColor =
                                                            Colors.grey;
                                                        if (average != null) {
                                                          if (average >= 0 &&
                                                              average < 5) {
                                                            avgColor =
                                                                Colors.grey;
                                                          } else if (average >=
                                                                  5 &&
                                                              average < 7) {
                                                            avgColor =
                                                                Colors.blue[800]!;
                                                          } else if (average >=
                                                                  7 &&
                                                              average < 9) {
                                                            avgColor =
                                                                Colors.red[700]!;
                                                          } else if (average >=
                                                                  9 &&
                                                              average <= 10) {
                                                            avgColor = Colors
                                                                .yellow[800]!;
                                                          }
                                                        }
                                                        return Text(
                                                          l10n.averageLabel +
                                                              ': ' +
                                                              (average != null
                                                                  ? average
                                                                      .toStringAsFixed(
                                                                          2)
                                                                  : '-'),
                                                          style: TextStyle(
                                                            fontSize: smallFontSize,
                                                            color: avgColor,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                          textScaleFactor: textScale,
                                                          overflow: TextOverflow.ellipsis,
                                                          maxLines: 1,
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Text(
                                                      '$formattedDate - ${comp['distance'] ?? '-'} ${l10n.meterLabel}',
                                                      style: TextStyle(
                                                        fontSize: smallFontSize,
                                                        color: isDark
                                                            ? Colors.grey[300]
                                                            : Colors.grey[600],
                                                      ),
                                                      textScaleFactor: textScale,
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      l10n.scoreLabel +
                                                          ': ${comp['qualification_score'] ?? '-'}/${comp['max_score'] ?? '-'}',
                                                      style: TextStyle(
                                                        fontSize: smallFontSize,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: isDark
                                                            ? Colors.white70
                                                            : const Color
                                                                .fromARGB(
                                                                255, 82, 82, 82),
                                                      ),
                                                      textScaleFactor: textScale,
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        l10n.rankingResult +
                                                            ': ' +
                                                            (comp['qualification_rank']
                                                                        ?.toString()
                                                                        .isNotEmpty ==
                                                                    true
                                                                ? comp['qualification_rank']
                                                                    .toString()
                                                                : '-'),
                                                        style: TextStyle(
                                                          fontSize: smallFontSize,
                                                          color: isDark
                                                              ? Colors.amber[300]
                                                              : Colors.amber[900],
                                                        ),
                                                        textScaleFactor: textScale,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        l10n.eliminationResult +
                                                            ': ' +
                                                            (comp['final_rank']
                                                                        ?.toString()
                                                                        .isNotEmpty ==
                                                                    true
                                                                ? comp['final_rank']
                                                                    .toString()
                                                                : '-'),
                                                        style: TextStyle(
                                                          fontSize: smallFontSize,
                                                          color: isDark
                                                              ? Colors.cyan[200]
                                                              : Colors.cyan[800],
                                                        ),
                                                        textScaleFactor: textScale,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                // YAŞ GRUBU GÖSTERİMİ (competition_list_screen.dart ile aynı mantık)
                                                if (comp['age_group'] != null && _resolvedAgeGroupNames.containsKey(comp['age_group']))
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2.0),
                                                    child: Text(
                                                      l10n.ageGroupLabel + ': ' + _resolvedAgeGroupNames[comp['age_group']]!,
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
                                                // Takım türü ve sonucu gösterimi
                                                if (showTeamRow)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2.0),
                                                    child: Row(
                                                      children: [
                                                        if (comp['team_type'] != null && comp['team_type'].toString().isNotEmpty)
                                                          Text(
                                                            l10n.teamTypeLabel + ': ' + (_teamTypeNames[comp['team_type'].toString()] ?? comp['team_type'].toString()),
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
                                                              l10n.teamResultLabel + ': ' + comp['team_result'].toString(),
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
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
