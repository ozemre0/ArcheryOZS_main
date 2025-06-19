import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_config.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:archeryozs/services/competition_local_db.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/foundation.dart'; // For listEquals
import 'dart:async';

class EditCompetitionScreen extends StatefulWidget {
  final Map<String, dynamic> competition;

  const EditCompetitionScreen({
    super.key,
    required this.competition,
  });

  @override
  State<EditCompetitionScreen> createState() => _EditCompetitionScreenState();
}

class _EditCompetitionScreenState extends State<EditCompetitionScreen> {
  final List<String> finalRankOptions = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '17',
    '33',
    'Diğer'
  ];
  String? _selectedFinalRankDropdown;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _totalScoreController;
  late final TextEditingController _finalRankController;
  late final TextEditingController _qualificationRankController;
  late String? _selectedEnvironment;
  late int? _selectedDistance;
  late String? _customDistance;
  late String? _selectedBowType;
  late int? _selectedMaxScore;
  late String? _customMaxScore;
  late DateTime _competitionDate;
  bool _isLoading = false;
  bool _hasChanges = false;
  final List<int> _predefinedDistances = [18, 30, 50, 60, 70];
  final List<int> _predefinedMaxScores = [180, 300, 360, 600, 720];

  List<Map<String, dynamic>> _ageGroups = [];
  int? _selectedAgeGroupId;
  bool _isLoadingAgeGroups = true; // New state variable
  Timer? _debounceTotalScore;

  // TEAM DEGREE/TYPE/RESULT STATE
  bool _hasTeamDegree = false;
  String? _selectedTeamType;
  List<Map<String, dynamic>> _teamTypes = [];
  bool _isLoadingTeamTypes = true;
  int? _selectedTeamResult;
  final List<int> _teamResultOptions = [1,2,3,4,5,6,7,8,9,17];

  @override
  void initState() {
    super.initState();
    _loadAgeGroups();
    _loadTeamTypes();

    // Var olan yarışma verilerini yükle
    final comp = widget.competition;

    _nameController =
        TextEditingController(text: comp['competition_name'] ?? '');
    _totalScoreController = TextEditingController(
        text: comp['qualification_score']?.toString() ?? '');
    _finalRankController =
        TextEditingController(text: comp['final_rank']?.toString() ?? '');
    _qualificationRankController = TextEditingController(
        text: comp['qualification_rank']?.toString() ?? '');

    // Şimdi controller'ın text'ine erişebilirsin:
    if (_finalRankController.text.isNotEmpty &&
        finalRankOptions.contains(_finalRankController.text)) {
      _selectedFinalRankDropdown = _finalRankController.text;
    } else if (_finalRankController.text.isNotEmpty) {
      _selectedFinalRankDropdown = 'Diğer';
    } else {
      _selectedFinalRankDropdown = null;
    }

    _selectedEnvironment = comp['environment'] ?? 'indoor';
    _selectedBowType = comp['bow_type'] ?? 'recurve';

    // Load age group
    // The age_group from Supabase/local DB should be an integer (ID)
    if (comp['age_group'] != null && comp['age_group'] is int) {
      _selectedAgeGroupId = comp['age_group'] as int?;
    } else if (comp['age_group'] != null && comp['age_group'] is String) {
      _selectedAgeGroupId = int.tryParse(comp['age_group'] as String);
    }

    final int distance = comp['distance'] ?? 0;
    if (_predefinedDistances.contains(distance)) {
      _selectedDistance = distance;
      _customDistance = null;
    } else {
      _selectedDistance = null;
      _customDistance = distance.toString();
    }

    final int maxScore = comp['max_score'] ?? 0;
    if (_predefinedMaxScores.contains(maxScore)) {
      _selectedMaxScore = maxScore;
      _customMaxScore = null;
    } else {
      _selectedMaxScore = null;
      _customMaxScore = maxScore.toString();
    }

    _competitionDate =
        DateTime.tryParse(comp['competition_date']) ?? DateTime.now();

    // Load team degree/type/result from competition
    if (comp['team_type'] != null || comp['team_result'] != null) {
      _hasTeamDegree = true;
      _selectedTeamType = comp['team_type']?.toString();
      _selectedTeamResult = comp['team_result'] is int
        ? comp['team_result']
        : int.tryParse(comp['team_result']?.toString() ?? '');
    } else {
      _hasTeamDegree = false;
      _selectedTeamType = null;
      _selectedTeamResult = null;
    }

    // Form değişikliklerini izle
    _nameController.addListener(_onFormChanged);
    _totalScoreController.addListener(_onFormChanged);
    _finalRankController.addListener(_onFormChanged);
    _qualificationRankController.addListener(_onFormChanged);
  }

  Future<void> _loadAgeGroups() async {
    if (!mounted) return;
    setState(() {
      _isLoadingAgeGroups = true;
    });

    // 1. Load and display local data immediately
    final initialLocalAgeGroups = await CompetitionLocalDb.instance.getAgeGroups();
    if (mounted && !listEquals(_ageGroups, initialLocalAgeGroups)) {
      setState(() {
        _ageGroups = initialLocalAgeGroups;
        _isLoadingAgeGroups = false;
        // Ensure existing selected ID is valid after loading
        if (_selectedAgeGroupId != null && !_ageGroups.any((ag) => ag['age_group_id'] == _selectedAgeGroupId)) {
           _selectedAgeGroupId = null; // Reset if not found
        }
      });
    } else if (mounted) {
      setState(() {
        _isLoadingAgeGroups = false;
      });
    }

    // 2. Sync with Supabase in the background
    CompetitionLocalDb.instance.syncAgeGroupsFromSupabase(forceRefresh: true).then((_) async {
      if (!mounted) return;
      // 3. Reload from local DB after sync and update UI if changed
      final latestLocalAgeGroups = await CompetitionLocalDb.instance.getAgeGroups();
      if (mounted && !listEquals(_ageGroups, latestLocalAgeGroups)) {
        setState(() {
          _ageGroups = latestLocalAgeGroups;
          // Re-validate selected ID if it became invalid
          if (_selectedAgeGroupId != null && !_ageGroups.any((ag) => ag['age_group_id'] == _selectedAgeGroupId)) {
            _selectedAgeGroupId = null; // Reset if selected group no longer exists
          }
        });
      }
    }).catchError((e) {
      if (mounted) {
        debugPrint("|10n:background_age_group_sync_failed_edit_screen: $e");
      }
    });
  }

  Future<void> _loadTeamTypes() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTeamTypes = true;
    });
    try {
      final initialLocalTeamTypes = await CompetitionLocalDb.instance.getTeamTypes();
      if (mounted && !listEquals(_teamTypes, initialLocalTeamTypes)) {
        setState(() {
          _teamTypes = initialLocalTeamTypes;
          _isLoadingTeamTypes = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoadingTeamTypes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTeamTypes = false;
        });
      }
    }
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) {
      try {
        await CompetitionLocalDb.instance.syncTeamTypesFromSupabase(forceRefresh: true);
        if (!mounted) return;
        final latestLocalTeamTypes = await CompetitionLocalDb.instance.getTeamTypes();
        if (mounted && !listEquals(_teamTypes, latestLocalTeamTypes)) {
          setState(() {
            _teamTypes = latestLocalTeamTypes;
            if (_selectedTeamType != null && !_teamTypes.any((tt) => tt['team_type_id'].toString() == _selectedTeamType)) {
              _selectedTeamType = null;
            }
          });
        }
      } catch (e) {}
    }
  }

  void _onFormChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalScoreController.dispose();
    _finalRankController.dispose();
    _qualificationRankController.dispose();
    _debounceTotalScore?.cancel();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _competitionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _competitionDate && mounted) {
      setState(() {
        _competitionDate = picked;
        _hasChanges = true;
      });
    }
  }

  void _showCustomDistanceDialog() {
    final controller = TextEditingController(text: _customDistance);
    final l10n = AppLocalizations.of(context)!; // Add l10n instance for dialog

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.customDistanceDialogTitle), // Localized
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: l10n.distanceInMetersHint), // Localized
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancelButtonLabel), // Localized
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty && int.tryParse(value) != null) {
                  setState(() {
                    _customDistance = value;
                    _hasChanges = true;
                  });
                }
                Navigator.of(context).pop();
              },
              child: Text(l10n.okButtonLabel), // Localized
            ),
          ],
        );
      },
    );
  }

  void _showCustomMaxScoreDialog() {
    final controller = TextEditingController(text: _customMaxScore);
    final l10n = AppLocalizations.of(context)!; // Add l10n instance for dialog

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.customMaxScoreDialogTitle), // Localized
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: l10n.maxScoreHint), // Localized
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancelButtonLabel), // Localized
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty && int.tryParse(value) != null) {
                  setState(() {
                    _customMaxScore = value;
                    _hasChanges = true;
                  });
                }
                Navigator.of(context).pop();
              },
              child: Text(l10n.okButtonLabel), // Localized
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateCompetition() async {
    final l10n = AppLocalizations.of(context)!; // Add l10n instance for method scope
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final int? totalScore = int.tryParse(_totalScoreController.text);
    final int maxScore =
        _selectedMaxScore ?? int.tryParse(_customMaxScore ?? '') ?? 0;
    if (totalScore != null && maxScore > 0 && totalScore > maxScore) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.totalScoreExceedsMaxValidation)), // Localized
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.userSessionNotFound)), // Localized
        );
        setState(() => _isLoading = false);
        return;
      }

      final int distance =
          _selectedDistance ?? int.tryParse(_customDistance ?? '') ?? 0;
      final int maxScore =
          _selectedMaxScore ?? int.tryParse(_customMaxScore ?? '') ?? 0;
      final int? totalScore = int.tryParse(_totalScoreController.text);
      
      // Allow null values by checking if empty
      String? finalRank = _finalRankController.text.trim().isEmpty 
          ? null 
          : _finalRankController.text.trim();
      String? qualificationRank = _qualificationRankController.text.trim().isEmpty 
          ? null 
          : _qualificationRankController.text.trim();

      // İnternet kontrolü
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        // Local güncelleme
        await CompetitionLocalDb.instance.insertCompetition({
          'competition_id': widget.competition['competition_id'],
          'athlete_id': widget.competition['athlete_id'],
          'competition_name': _nameController.text.isEmpty
              ? l10n.unnamedCompetitionPlaceholder // Localized
              : _nameController.text,
          'competition_date': _competitionDate.toIso8601String(),
          'environment': _selectedEnvironment,
          'distance': distance,
          'bow_type': _selectedBowType,
          'qualification_score': totalScore,
          'max_score': maxScore,
          'final_rank': finalRank,
          'qualification_rank': qualificationRank,
          'age_group': _selectedAgeGroupId,
          'created_at': widget.competition['created_at'],
          'updated_at': DateTime.now().toIso8601String(),
          // Takım Sonucu ve Türü
          'team_result': _selectedTeamResult,
          'team_type': _selectedTeamType != null ? int.tryParse(_selectedTeamType!) : null,
        }, pending: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(l10n.competitionUpdatedLocallyOffline)), // Localized
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context, true);
        return;
      }

      await SupabaseConfig.client.from('competition_records').update({
        'competition_name': _nameController.text.isEmpty
            ? l10n.unnamedCompetitionPlaceholder // Localized
            : _nameController.text,
        'competition_date': _competitionDate.toIso8601String(),
        'environment': _selectedEnvironment,
        'distance': distance,
        'bow_type': _selectedBowType,
        'qualification_score': totalScore,
        'max_score': maxScore,
        'final_rank': finalRank,
        'qualification_rank': qualificationRank,
        'age_group': _selectedAgeGroupId,
        'updated_at': DateTime.now().toIso8601String(),
        // Takım Sonucu ve Türü
        'team_result': _selectedTeamResult,
        'team_type': _selectedTeamType != null ? int.tryParse(_selectedTeamType!) : null,
      }).eq('competition_id', widget.competition['competition_id']);

      // Supabase güncellemesinden sonra local veritabanını da güncelle
      await CompetitionLocalDb.instance.insertCompetition({
        'competition_id': widget.competition['competition_id'],
        'athlete_id': widget.competition['athlete_id'],
        'competition_name': _nameController.text.isEmpty
            ? l10n.unnamedCompetitionPlaceholder // Localized
            : _nameController.text,
        'competition_date': _competitionDate.toIso8601String(),
        'environment': _selectedEnvironment,
        'distance': distance,
        'bow_type': _selectedBowType,
        'qualification_score': totalScore,
        'max_score': maxScore,
        'final_rank': finalRank,
        'qualification_rank': qualificationRank,
        'age_group': _selectedAgeGroupId,
        'created_at': widget.competition['created_at'],
        'updated_at': DateTime.now().toIso8601String(),
        // Takım Sonucu ve Türü
        'team_result': _selectedTeamResult,
        'team_type': _selectedTeamType != null ? int.tryParse(_selectedTeamType!) : null,
      }, pending: false);

      // Güncelleme başarılı oldu
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.competitionUpdateSuccess)), // Localized
      );
      Navigator.pop(context, true);
    } catch (e) {
      // Hata durumunu göster
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorPrefix}${e.toString()}')), // Localized
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _onWillPop() async {
    final l10n = AppLocalizations.of(context)!; // Add l10n instance for method scope
    if (!_hasChanges) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmExitTitle), // Localized
        content: Text(l10n.confirmExitMessage), // Localized
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButtonLabel), // Localized
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.exitButtonLabel), // Localized
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!; // Ensure l10n is available

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.editCompetitionTitle), // Localized
          actions: [
            TextButton(
              onPressed:
                  (_isLoading || !_hasChanges) ? null : _updateCompetition,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.saveChangesButtonLabel, style: TextStyle(color: Colors.white)), // Localized
            )
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: MediaQuery.of(context).viewPadding.bottom),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.competitionNameOptionalLabel, // Localized
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                // Age Group ChoiceChips Section
                Text(l10n.ageGroupLabel, style: TextStyle(fontSize: 16)), // Localized
                const SizedBox(height: 8),
                AgeGroupChips(
                  ageGroups: _ageGroups,
                  selectedAgeGroupId: _selectedAgeGroupId,
                  onSelected: (id) {
                    setState(() {
                      _selectedAgeGroupId = id;
                      _hasChanges = true;
                    });
                  },
                  locale: l10n.localeName,
                  notFoundLabel: l10n.ageGroupsNotFound,
                  isLoading: _isLoadingAgeGroups,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text(l10n.competitionDateLabel), // Localized
                  subtitle: Text(DateFormat.yMd().format(_competitionDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _selectDate(context),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.environmentLabel, style: TextStyle(fontSize: 16)), // Localized
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(l10n.indoorLabel), // Localized
                        value: 'indoor',
                        groupValue: _selectedEnvironment,
                        onChanged: (value) {
                          setState(() {
                            _selectedEnvironment = value;
                            _hasChanges = true;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(l10n.outdoorLabel), // Localized
                        value: 'outdoor',
                        groupValue: _selectedEnvironment,
                        onChanged: (value) {
                          setState(() {
                            _selectedEnvironment = value;
                            _hasChanges = true;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(l10n.distanceInMetersLabel, style: TextStyle(fontSize: 16)), // Localized
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: [
                    ..._predefinedDistances.map((distance) {
                      return ChoiceChip(
                        label: Text('$distance m'),
                        selected: _selectedDistance == distance,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedDistance = distance;
                              _customDistance = null;
                            } else {
                              _selectedDistance = null;
                            }
                            _hasChanges = true;
                          });
                        },
                      );
                    }).toList(),
                    ChoiceChip(
                      label: Text(l10n.otherLabel), // Localized
                      selected:
                          _selectedDistance == null && _customDistance != null,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedDistance = null;
                            _customDistance = _customDistance ?? '';
                            _showCustomDistanceDialog();
                          }
                          _hasChanges = true;
                        });
                      },
                    ),
                  ],
                ),
                if (_customDistance != null && _customDistance!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('${l10n.customDistancePrefix}${_customDistance} m', // Localized
                        style: const TextStyle(fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 16),
                Text(l10n.bowTypeLabel, style: TextStyle(fontSize: 16)), // Localized
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedBowType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  items: [
                    DropdownMenuItem(value: 'recurve', child: Text(l10n.bowTypeRecurve)), // Localized
                    DropdownMenuItem(
                        value: 'compound', child: Text(l10n.bowTypeCompound)), // Localized
                    DropdownMenuItem(value: 'barebow', child: Text(l10n.bowTypeBarebow)), // Localized
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedBowType = value;
                      _hasChanges = true;
                    });
                  },
                  validator: (value) =>
                      value == null ? l10n.selectBowTypeValidation : null, // Localized
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _totalScoreController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.totalScoreLabel, // Localized
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.enterTotalScoreValidation; // Localized
                    }
                    if (int.tryParse(value) == null) {
                      return l10n.enterValidNumberValidation; // Localized
                    }
                    return null;
                  },
                  onChanged: (_) {
                    // Debounced validation
                    if (_debounceTotalScore?.isActive ?? false) _debounceTotalScore!.cancel();
                    _debounceTotalScore = Timer(const Duration(milliseconds: 300), () {
                      if (_formKey.currentState != null) {
                        _formKey.currentState!.validate();
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text(l10n.maxScoreLabel, style: TextStyle(fontSize: 16)), // Localized
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: [
                    ..._predefinedMaxScores.map((score) {
                      return ChoiceChip(
                        label: Text('$score'),
                        selected: _selectedMaxScore == score,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedMaxScore = score;
                              _customMaxScore = null;
                            } else {
                              _selectedMaxScore = null;
                            }
                            _hasChanges = true;
                          });
                        },
                      );
                    }).toList(),
                    ChoiceChip(
                      label: Text(l10n.otherLabel), // Localized
                      selected:
                          _selectedMaxScore == null && _customMaxScore != null,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedMaxScore = null;
                            _customMaxScore = _customMaxScore ?? '';
                            _showCustomMaxScoreDialog();
                          }
                          _hasChanges = true;
                        });
                      },
                    ),
                  ],
                ),
                if (_customMaxScore != null && _customMaxScore!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('${l10n.customMaxScorePrefix}${_customMaxScore}', // Localized
                        style: const TextStyle(fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 16),
                // Qualification Rank Field
                TextFormField(
                  controller: _qualificationRankController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.qualificationRankLabel, // Localized
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    // Allow empty values (null)
                    if (value == null || value.isEmpty) {
                      return null; // Empty is valid
                    }
                    // Only validate if not empty
                    if (int.tryParse(value) == null) {
                      return l10n.enterValidNumberValidation; // Localized
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Eleme Sonucu (Final Rank) ChoiceChip group
                Text(l10n.finalRankLabel, // Localized
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: [
                    ...[1, 2, 3, 4, 5, 6, 7, 8, 17, 33].map((option) {
                      return ChoiceChip(
                        label: Text('$option'),
                        selected:
                            _selectedFinalRankDropdown == option.toString(),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedFinalRankDropdown = option.toString();
                              _finalRankController.text = option.toString();
                            } else {
                              _selectedFinalRankDropdown = null;
                              _finalRankController.text = '';
                            }
                          });
                        },
                      );
                    }).toList(),
                    ChoiceChip(
                      label: Text(l10n.otherLabel), // Localized
                      selected: _selectedFinalRankDropdown == 'Diğer',
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedFinalRankDropdown = 'Diğer';
                            _finalRankController.text = '';
                          } else {
                            _selectedFinalRankDropdown = null;
                            _finalRankController.text = '';
                          }
                        });
                      },
                    ),
                  ],
                ),
                if (_selectedFinalRankDropdown == 'Diğer')
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: TextFormField(
                      controller: _finalRankController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.otherCustomFinalRankLabel, // Localized
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return null;
                        }
                        if (int.tryParse(value) == null) {
                          return l10n.enterValidNumberValidation;
                        }
                        return null;
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                // TEAM DEGREE SECTION START
                Text(l10n.hasTeamDegreeLabel, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: Text(l10n.selectTeamDegreeYes),
                        value: true,
                        groupValue: _hasTeamDegree,
                        onChanged: (value) {
                          setState(() {
                            _hasTeamDegree = value ?? false;
                            if (!_hasTeamDegree) _selectedTeamType = null;
                            _hasChanges = true;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: Text(l10n.selectTeamDegreeNo),
                        value: false,
                        groupValue: _hasTeamDegree,
                        onChanged: (value) {
                          setState(() {
                            _hasTeamDegree = value ?? false;
                            if (!_hasTeamDegree) _selectedTeamType = null;
                            _hasChanges = true;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
                if (_hasTeamDegree) ...[
                  const SizedBox(height: 16),
                  Text(l10n.teamTypeLabel, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  _isLoadingTeamTypes
                      ? Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)))
                      : _teamTypes.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(l10n.teamTypesNotFound),
                            )
                          : Wrap(
                              spacing: 8.0,
                              runSpacing: 4.0,
                              children: _teamTypes.map((type) {
                                final id = type['team_type_id'].toString();
                                String displayName = (l10n.localeName == 'en')
                                    ? (type['team_type_en'] ?? type['team_type_tr'] ?? id)
                                    : (type['team_type_tr'] ?? type['team_type_en'] ?? id);
                                return ChoiceChip(
                                  label: Text(displayName),
                                  selected: _selectedTeamType == id,
                                  onSelected: (selected) {
                                    setState(() {
                                      _selectedTeamType = selected ? id : null;
                                      _hasChanges = true;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                  // Takım Sonucu Picker
                  const SizedBox(height: 16),
                  Text(l10n.teamResultLabel, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    children: _teamResultOptions.map((option) {
                      return ChoiceChip(
                        label: Text(option.toString()),
                        selected: _selectedTeamResult == option,
                        onSelected: (selected) {
                          setState(() {
                            _selectedTeamResult = selected ? option : null;
                            _hasChanges = true;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
                // TEAM DEGREE SECTION END
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed:
                      (_isLoading || !_hasChanges) ? null : _updateCompetition,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.saveChangesButtonLabel), // Localized
                ),
                SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AgeGroupChips extends StatelessWidget {
  final List<Map<String, dynamic>> ageGroups;
  final int? selectedAgeGroupId;
  final ValueChanged<int?> onSelected;
  final String locale;
  final String notFoundLabel;
  final bool isLoading;

  const AgeGroupChips({
    super.key,
    required this.ageGroups,
    required this.selectedAgeGroupId,
    required this.onSelected,
    required this.locale,
    required this.notFoundLabel,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (ageGroups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(notFoundLabel),
      );
    }
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: ageGroups.map((Map<String, dynamic> ageGroup) {
        final id = ageGroup['age_group_id'] as int?;
        if (id == null) return const SizedBox.shrink();
        String displayName;
        if (locale == 'en') {
          displayName = (ageGroup['age_group_en'] as String?) ?? (ageGroup['age_group_tr'] as String?) ?? id.toString();
        } else {
          displayName = (ageGroup['age_group_tr'] as String?) ?? (ageGroup['age_group_en'] as String?) ?? id.toString();
        }
        return ChoiceChip(
          label: Text(displayName),
          selected: selectedAgeGroupId == id,
          onSelected: (bool selected) {
            if (selected) {
              onSelected(id);
            }
          },
        );
      }).toList(),
    );
  }
}
