import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../services/supabase_config.dart';
import 'package:archeryozs/services/competition_local_db.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/foundation.dart'; // For listEquals
import 'dart:async';

class AddCompetitionScreen extends StatefulWidget {
  const AddCompetitionScreen({super.key});

  @override
  State<AddCompetitionScreen> createState() => _AddCompetitionScreenState();
}

class _AddCompetitionScreenState extends State<AddCompetitionScreen> {
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
  final _nameController = TextEditingController();
  final _totalScoreController = TextEditingController();
  final _finalRankController = TextEditingController();
  final _qualificationRankController = TextEditingController();
  String? _selectedEnvironment = 'indoor';
  int? _selectedDistance;
  String? _customDistance;
  String? _selectedBowType = 'recurve';
  int? _selectedMaxScore;
  String? _customMaxScore;
  DateTime _competitionDate = DateTime.now();
  bool _isLoading = false;
  final List<int> _predefinedDistances = [18, 30, 50, 60, 70];
  final List<int> _predefinedMaxScores = [180, 300, 360, 600, 720];

  List<Map<String, dynamic>> _ageGroups = [];
  int? _selectedAgeGroupId;
  bool _isLoadingAgeGroups = true; // New state variable

  // FocusNode tanımlamaları
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _totalScoreFocus = FocusNode();
  final FocusNode _rankFocus = FocusNode();

  Timer? _debounceTotalScore;

  bool? _hasTeamDegree = false;
  String? _selectedTeamType;
  List<Map<String, dynamic>> _teamTypes = [];
  bool _isLoadingTeamTypes = true;

  // Team result picker için değişken
  int? _selectedTeamResult;
  final List<int> _teamResultOptions = [1,2,3,4,5,6,7,8,9,17];

  @override
  void initState() {
    super.initState();
    _loadAgeGroups(); // Load age groups
    _loadTeamTypes(); // Load team types

    if (_finalRankController.text.isNotEmpty &&
        finalRankOptions.contains(_finalRankController.text)) {
      _selectedFinalRankDropdown = _finalRankController.text;
    } else if (_finalRankController.text.isNotEmpty) {
      _selectedFinalRankDropdown = 'Diğer';
    } else {
      _selectedFinalRankDropdown = null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalScoreController.dispose();
    _finalRankController.dispose();
    _qualificationRankController.dispose();
    _nameFocus.dispose();
    _totalScoreFocus.dispose();
    _rankFocus.dispose();
    _debounceTotalScore?.cancel();
    super.dispose();
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
      });
    } else if (mounted) {
      setState(() {
        _isLoadingAgeGroups = false;
      });
    }

    // 2. Sync with Supabase in the background ONLY IF INTERNET
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) {
      CompetitionLocalDb.instance.syncAgeGroupsFromSupabase(forceRefresh: true).then((_) async {
        if (!mounted) return;
        final latestLocalAgeGroups = await CompetitionLocalDb.instance.getAgeGroups();
        if (mounted && !listEquals(_ageGroups, latestLocalAgeGroups)) {
          setState(() {
            _ageGroups = latestLocalAgeGroups;
            if (_selectedAgeGroupId != null && !_ageGroups.any((ag) => ag['age_group_id'] == _selectedAgeGroupId)) {
              _selectedAgeGroupId = null;
            }
          });
        }
      }).catchError((e) {
        if (mounted) {
          debugPrint("|10n:background_age_group_sync_failed_add_screen: $e");
        }
      });
    }
  }

  Future<void> _loadTeamTypes() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTeamTypes = true;
    });

    try {
      debugPrint("DEBUG |10n: _loadTeamTypes() started");
      final initialLocalTeamTypes = await CompetitionLocalDb.instance.getTeamTypes();
      debugPrint("DEBUG |10n: LOCAL TEAM TYPES: $initialLocalTeamTypes");
      if (mounted && !listEquals(_teamTypes, initialLocalTeamTypes)) {
        setState(() {
          _teamTypes = initialLocalTeamTypes;
          _isLoadingTeamTypes = false;
        });
        debugPrint("DEBUG |10n: setState with local team types, loading false");
      } else if (mounted) {
        setState(() {
          _isLoadingTeamTypes = false;
        });
        debugPrint("DEBUG |10n: setState loading false (no change)");
      }
    } catch (e) {
      debugPrint("ERROR |10n: getTeamTypes: $e");
      if (mounted) {
        setState(() {
          _isLoadingTeamTypes = false;
        });
      }
    }

    // 2. Sync with Supabase in the background ONLY IF INTERNET
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) {
      try {
        debugPrint("DEBUG |10n: syncTeamTypesFromSupabase() started");
        await CompetitionLocalDb.instance.syncTeamTypesFromSupabase(forceRefresh: true);
        if (!mounted) return;
        final latestLocalTeamTypes = await CompetitionLocalDb.instance.getTeamTypes();
        debugPrint("DEBUG |10n: AFTER SYNC TEAM TYPES: $latestLocalTeamTypes");
        if (mounted && !listEquals(_teamTypes, latestLocalTeamTypes)) {
          setState(() {
            _teamTypes = latestLocalTeamTypes;
            if (_selectedTeamType != null && !_teamTypes.any((tt) => tt['team_type_id'].toString() == _selectedTeamType)) {
              _selectedTeamType = null;
            }
          });
          debugPrint("DEBUG |10n: setState with synced team types");
        }
      } catch (e) {
        debugPrint("ERROR |10n: syncTeamTypesFromSupabase: $e");
      }
    }
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
      });
    }
  }

  void _showCustomDistanceDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Özel Mesafe Girin'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Mesafe (metre)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty && int.tryParse(value) != null) {
                  setState(() {
                    _customDistance = value;
                  });
                }
                Navigator.of(context).pop();
              },
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  void _showCustomMaxScoreDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Özel Maksimum Puan Girin'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Maksimum puan'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty && int.tryParse(value) != null) {
                  setState(() {
                    _customMaxScore = value;
                  });
                }
                Navigator.of(context).pop();
              },
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  bool _validateFormWithAgeGroup() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (_selectedAgeGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.ageGroupLabel + ' zorunlu!')),
      );
      return false;
    }
    return isValid;
  }

  Future<void> _saveCompetition() async {
    final int? totalScore = int.tryParse(_totalScoreController.text);
    final int maxScore =
        _selectedMaxScore ?? int.tryParse(_customMaxScore ?? '') ?? 0;
    bool hasScoreError = false;
    if (totalScore != null && maxScore > 0 && totalScore > maxScore) {
      hasScoreError = true;
    }
    if (!_validateFormWithAgeGroup() || hasScoreError) {
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 600));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı oturumu bulunamadı.')),
        );
        return;
      }
      final uuid = const Uuid();
      final competitionId = uuid.v4();
      final int qualificationScore = totalScore ?? 0;
      
      String? finalRank = _finalRankController.text.trim().isEmpty 
          ? null 
          : _finalRankController.text.trim();
      String? qualificationRank = _qualificationRankController.text.trim().isEmpty 
          ? null 
          : _qualificationRankController.text.trim();
          
      final competition = {
        'competition_id': competitionId,
        'athlete_id': user.id,
        'competition_name': _nameController.text.trim(),
        'max_score': maxScore,
        'distance': _selectedDistance ?? int.tryParse(_customDistance ?? '') ?? 0,
        'environment': _selectedEnvironment,
        'bow_type': _selectedBowType,
        'competition_date': _competitionDate.toIso8601String(),
        'final_rank': finalRank,
        'qualification_rank': qualificationRank,
        'qualification_score': qualificationScore,
        'age_group': _selectedAgeGroupId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        // Takım Sonucu ekle
        'team_result': _selectedTeamResult,
        // Takım Türü ekle (int olarak)
        'team_type': _selectedTeamType != null ? int.tryParse(_selectedTeamType!) : null,
      };
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        // Sadece local kaydet
        await CompetitionLocalDb.instance
            .insertCompetition(competition, pending: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Yarışma internet yokken yerel olarak kaydedildi.')),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        // Önce Supabase, sonra local
        await SupabaseConfig.client
            .from('competition_records')
            .insert(competition);
        await CompetitionLocalDb.instance
            .insertCompetition(competition, pending: false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yarışma başarıyla kaydedildi.')),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      // Hata durumunu göster
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _hasAnyInput {
    return _nameController.text.isNotEmpty ||
        _totalScoreController.text.isNotEmpty ||
        _finalRankController.text.isNotEmpty ||
        _qualificationRankController.text.isNotEmpty ||
        _selectedDistance != null ||
        (_customDistance != null && _customDistance!.isNotEmpty) ||
        _selectedBowType != null ||
        _selectedMaxScore != null ||
        (_customMaxScore != null && _customMaxScore!.isNotEmpty) ||
        _selectedAgeGroupId != null;
  }

  Future<bool> _onWillPop() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_hasAnyInput) {
      return true;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmExitTitle),
        content: Text(l10n.confirmExitMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.exitButtonLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context); // Get l10n instance

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.addCompetitionTitle)), // Localized AppBar Title
        body: SingleChildScrollView(
          padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: MediaQuery.of(context).viewPadding.bottom),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.competitionNameOptionalLabel, // Localized Label
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.competitionNameRequired;
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
                const SizedBox(height: 16),
                // Age Group ChoiceChips
                Text(l10n.ageGroupLabel, style: const TextStyle(fontSize: 16)), // Localized Label
                const SizedBox(height: 8),
                AgeGroupChips(
                  ageGroups: _ageGroups,
                  selectedAgeGroupId: _selectedAgeGroupId,
                  onSelected: (id) {
                    setState(() {
                      _selectedAgeGroupId = id;
                    });
                  },
                  locale: l10n.localeName,
                  notFoundLabel: l10n.ageGroupsNotFound,
                  isLoading: _isLoadingAgeGroups,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text(l10n.competitionDateLabel), // Localized Label
                  subtitle: Text(DateFormat.yMd().format(_competitionDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _selectDate(context),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.environmentLabel, style: TextStyle(fontSize: 16)), // Localized Label
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(
                          l10n.indoorLabel, // Localized Label
                          style: TextStyle(fontSize: 15),
                        ),
                        value: 'indoor',
                        groupValue: _selectedEnvironment,
                        onChanged: (value) {
                          setState(() => _selectedEnvironment = value);
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(l10n.outdoorLabel, // Localized Label
                            style: TextStyle(fontSize: 15)),
                        value: 'outdoor',
                        groupValue: _selectedEnvironment,
                        onChanged: (value) {
                          setState(() => _selectedEnvironment = value);
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(l10n.distanceInMetersLabel, style: TextStyle(fontSize: 16)), // Localized Label
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
                          });
                        },
                      );
                    }).toList(),
                    ChoiceChip(
                      label: Text(l10n.otherLabel), // Localized Label
                      selected:
                          _selectedDistance == null && _customDistance != null,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedDistance = null;
                            _customDistance = '';
                            _showCustomDistanceDialog();
                          }
                        });
                      },
                    ),
                  ],
                ),
                if (_customDistance != null && _customDistance!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('${l10n.customDistancePrefix}${_customDistance} m', // Localized Prefix
                        style: const TextStyle(fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 16),
                Text(l10n.bowTypeLabel, style: TextStyle(fontSize: 16)), // Localized Label
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedBowType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  items: [
                    DropdownMenuItem(value: 'recurve', child: Text(l10n.bowTypeRecurve)), // Localized Item
                    DropdownMenuItem(value: 'compound', child: Text(l10n.bowTypeCompound)), // Localized Item
                    DropdownMenuItem(value: 'barebow', child: Text(l10n.bowTypeBarebow)), // Localized Item
                  ],
                  onChanged: (value) {
                    setState(() => _selectedBowType = value);
                  },
                  validator: (value) => value == null ? l10n.selectBowTypeValidation : null, // Localized Validation
                ),
                // Toplam Skor Alanı (Maksimum puandan önce)
                const SizedBox(height: 16),
                TextFormField(
                  controller: _totalScoreController,
                  focusNode: _totalScoreFocus,
                  autofocus: false,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.totalScoreLabel, // Localized Label
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.enterTotalScoreValidation; // Localized Validation
                    }
                    final total = int.tryParse(value);
                    final max = _selectedMaxScore ??
                        int.tryParse(_customMaxScore ?? '') ??
                        0;
                    if (total == null) {
                      return l10n.enterValidNumberValidation; // Localized Validation
                    }
                    if (max > 0 && total > max) {
                      return l10n.totalScoreExceedsMaxValidation; // Localized Validation
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
                // Maksimum Puan Seçimi
                Text(l10n.maxScoreLabel, style: TextStyle(fontSize: 16)), // Localized Label
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
                            // Maksimum skor değiştiğinde toplam skor alanını tekrar doğrula
                            if (_formKey.currentState != null) {
                              _formKey.currentState!.validate();
                            }
                          });
                        },
                      );
                    }).toList(),
                    ChoiceChip(
                      label: Text(l10n.otherLabel), // Localized Label (reused)
                      selected:
                          _selectedMaxScore == null && _customMaxScore != null,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedMaxScore = null;
                            _customMaxScore = '';
                            _showCustomMaxScoreDialog();
                          }
                          // Maksimum skor değiştiğinde toplam skor alanını tekrar doğrula
                          if (_formKey.currentState != null) {
                            _formKey.currentState!.validate();
                          }
                        });
                      },
                    ),
                  ],
                ),
                if (_customMaxScore != null && _customMaxScore!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('${l10n.customMaxScorePrefix}${_customMaxScore}', // Localized Prefix
                        style: const TextStyle(fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 16),
                // Sıralama (Derece) Alanı (Maksimum puandan sonra)
                // Qualification Rank Field
                TextFormField(
                  controller: _qualificationRankController,
                  focusNode: _rankFocus,
                  autofocus: false,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.qualificationRankLabel, // Localized Label
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    // Allow empty values (null)
                    if (value == null || value.isEmpty) {
                      return null; // Empty is valid
                    }
                    // Only validate if not empty
                    if (int.tryParse(value) == null) {
                      return l10n.enterValidNumberValidation; // Localized Validation (reused)
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Eleme Sonucu (Final Rank) ChoiceChip group
                Text(l10n.finalRankLabel, // Localized Label
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: [
                    ...[1, 2, 3, 4, 5, 6, 7, 8, 9, 17, 33].map((option) {
                      return ChoiceChip(
                        label: Text('$option'),
                        selected: _selectedFinalRankDropdown == option.toString(),
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
                      label: Text(l10n.otherLabel), // Localized Label (reused)
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
                        labelText: l10n.otherCustomFinalRankLabel, // Localized Label
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        // Allow empty values (null)
                        if (value == null || value.isEmpty) {
                          return null; // Empty is valid
                        }
                        // Only validate if not empty
                        if (int.tryParse(value) == null) {
                          return l10n.enterValidNumberValidation; // Localized Validation (reused)
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
                            _hasTeamDegree = value;
                            if (_hasTeamDegree != true) _selectedTeamType = null;
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
                            _hasTeamDegree = value;
                            if (_hasTeamDegree != true) _selectedTeamType = null;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
                if (_hasTeamDegree == true) ...[
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
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
                // TEAM DEGREE SECTION END
                const SizedBox(height: 32),
                Center(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveCompetition,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l10n.saveCompetitionButton), // Localized Button Text
                  ),
                ),
                const SizedBox(height: 24.0),
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
