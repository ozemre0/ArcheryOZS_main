// ignore_for_file: unused_local_variable
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/training_config_controller.dart';
import '../providers/training_session_controller.dart';
import '../services/supabase_config.dart';
import 'training_session_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'technique_training_screen.dart';
import '../widgets/target_face_widgets.dart';

class TrainingConfigScreen extends ConsumerStatefulWidget {
  const TrainingConfigScreen({super.key});

  @override
  ConsumerState<TrainingConfigScreen> createState() =>
      _TrainingConfigScreenState();
}

class _TrainingConfigScreenState extends ConsumerState<TrainingConfigScreen> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final ScrollController _distanceScrollController = ScrollController();
  DateTime? _selectedDateTime;

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _distanceScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(trainingConfigProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final primaryColor = theme.colorScheme.primary;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
        centerTitle: true,
        title: Text(
          l10n.trainingConfiguration,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: Container(
        color: theme.scaffoldBackgroundColor, // HomeScreen ile aynı renk tonu
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 32, 16, 20),
          physics: BouncingScrollPhysics(),
          children: [
            // Antrenman ismi
            _buildConfigItem(
              icon: Icons.edit_note_rounded,
              title: l10n.trainingName,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNameInput(context, l10n),
                  const SizedBox(height: 12),
                  _buildDateTimePicker(context, l10n),
                ],
              ),
              isDark: isDark,
            ),
            // İç/Dış mekan seçimi
            _buildConfigItem(
              icon: Icons.location_on_outlined,
              title: l10n.trainingEnvironment,
              child: _buildIndoorOutdoorToggle(ref, config.isIndoor, l10n, primaryColor, isDark),
              isDark: isDark,
            ),
            // Antrenman türü seçici (teknik/skor)
            _buildConfigItem(
              icon: Icons.category_rounded,
              title: 'Training Type',
              child: _buildTrainingTypeSelector(ref, config.trainingType, primaryColor, isDark, l10n),
              isDark: isDark,
            ),
            // Hedef kağıdı seçici (sadece hedef kağıdı skor antrenmanı için)
            if (config.trainingType == 'target_score')
              _buildConfigItem(
                icon: Icons.center_focus_strong_rounded,
                title: l10n.targetFace,
                child: _buildTargetFaceSelector(ref, config.targetFace, primaryColor, isDark, l10n),
                isDark: isDark,
              ),
            if (config.trainingType == 'technique')
              _buildConfigItem(
                icon: Icons.notes,
                title: l10n.notes,
                child: _buildNotesInput(context, l10n),
                isDark: isDark,
              ),
            if (config.trainingType == 'technique')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.calculate, color: primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      l10n.totalArrows + ': ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '${config.seriesCount * config.arrowsPerSeries} ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      '(${config.seriesCount} ${l10n.series} × ${config.arrowsPerSeries} ${l10n.arrows})',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
            ),
            // Yay tipi seçimi
            _buildConfigItem(
              icon: Icons.sports_kabaddi_rounded,
              title: l10n.bowType,
              child: _buildBowTypeSelector(ref, config.bowType, primaryColor, isDark),
              isDark: isDark,
            ),
            // Mesafe seçimi (yaratıcı tasarım)
            _buildConfigItem(
              icon: Icons.straighten_rounded,
              title: l10n.distance,
              child: _buildArcheryRangeSelector(ref, config.distance, l10n, primaryColor, isDark),
              isDark: isDark,
            ),
            // Ok ve Seri sayısı seçimi alt alta (Column)
            Column(
              children: [
                _buildConfigItem(
                  icon: Icons.arrow_forward_rounded,
                  title: l10n.arrowsPerSeries,
                  child: _buildCupertinoPicker(
                    context,
                    value: config.arrowsPerSeries,
                    min: 1,
                    max: 20,
                    suffix: l10n.arrows,
                    onChanged: (value) => ref.read(trainingConfigProvider.notifier).setArrowsPerSeries(value),
                    isDark: isDark,
                    primaryColor: primaryColor,
                  ),
                  isDark: isDark,
                  padding: EdgeInsets.all(8),
                ),
                SizedBox(height: 10),
                _buildConfigItem(
                  icon: Icons.repeat_rounded,
                  title: "Series Count",
                  child: _buildCupertinoPicker(
                    context,
                    value: config.seriesCount,
                    min: 1,
                    max: 20,
                    suffix: l10n.series,
                    onChanged: (value) => ref.read(trainingConfigProvider.notifier).setSeriesCount(value),
                    isDark: isDark,
                    primaryColor: primaryColor,
                  ),
                  isDark: isDark,
                  padding: EdgeInsets.all(8),
                ),
              ],
            ),
            // Başlatma butonu
            Container(
              margin: EdgeInsets.only(top: 30, bottom: 15),
              height: 55,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _startTraining(context, ref),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 5,
                  shadowColor: primaryColor.withOpacity(0.5),
                  padding: EdgeInsets.symmetric(horizontal: 20),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_outline_rounded, size: 22),
                      SizedBox(width: 8),
                      Text(
                        l10n.startTraining,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
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
    );
  }
  
  // Ayar öğesi container
  Widget _buildConfigItem({
    required IconData icon,
    required String title,
    required Widget child,
    required bool isDark,
    EdgeInsetsGeometry padding = const EdgeInsets.all(15),
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3) 
                : Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                size: 20,
              ),
              SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
  
  // Antrenman ismi girişi
  Widget _buildNameInput(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          width: 1.5,
        ),
      ),
      child: TextField(
        controller: _nameController,
        style: TextStyle(
          fontSize: 15,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: l10n.trainingNameHint,
          hintStyle: TextStyle(
            color: isDark ? Colors.grey[500] : Colors.grey[400],
            fontSize: 14,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 15),
          border: InputBorder.none,
        ),
      ),
    );
  }
  
  // İç/Dış mekan toggle
  Widget _buildIndoorOutdoorToggle(
    WidgetRef ref,
    bool isIndoor,
    AppLocalizations l10n,
    Color primaryColor,
    bool isDark,
  ) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isIndoor) {
                  ref.read(trainingConfigProvider.notifier).setIndoor(true);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isIndoor 
                      ? primaryColor 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.home_outlined,
                        size: 20,
                        color: isIndoor 
                            ? Colors.white 
                            : isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      SizedBox(width: 8),
                      Text(
                        l10n.indoor,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isIndoor ? FontWeight.bold : FontWeight.normal,
                          color: isIndoor 
                              ? Colors.white 
                              : isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isIndoor) {
                  ref.read(trainingConfigProvider.notifier).setIndoor(false);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: !isIndoor 
                      ? primaryColor 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.landscape_outlined,
                        size: 20,
                        color: !isIndoor 
                            ? Colors.white 
                            : isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      SizedBox(width: 8),
                      Text(
                        l10n.outdoor,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: !isIndoor ? FontWeight.bold : FontWeight.normal,
                          color: !isIndoor 
                              ? Colors.white 
                              : isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
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
  
  // Yay tipi seçimi
  Widget _buildBowTypeSelector(
    WidgetRef ref,
    String bowType,
    Color primaryColor,
    bool isDark,
  ) {
    final l10n = AppLocalizations.of(context);
    final types = [
      {'value': 'Recurve', 'label': l10n.bowTypeRecurve},
      {'value': 'Compound', 'label': l10n.bowTypeCompound},
      {'value': 'Barebow', 'label': l10n.bowTypeBarebow},
    ];
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: types.map((type) {
          final isSelected = bowType == type['value'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isSelected) {
                  ref.read(trainingConfigProvider.notifier).setBowType(type['value']!);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected 
                      ? primaryColor 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    type['label']!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected 
                          ? Colors.white 
                          : isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
  
  // Mesafe için yaratıcı atış yolu seçici
  Widget _buildArcheryRangeSelector(
    WidgetRef ref,
    int distance,
    AppLocalizations l10n,
    Color primaryColor,
    bool isDark,
  ) {
    final List<int> baseDistances = [18, 20, 30, 50, 60, 70];
    // Seçili mesafe listede yoksa ekle, sonra sırala
    final Set<int> allDistancesSet = {...baseDistances, distance};
    final List<int> distances = allDistancesSet.toList()..sort();
    final selectedIndex = distances.indexOf(distance);

    // Scroll to selected distance after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_distanceScrollController.hasClients && selectedIndex != -1) {
        _distanceScrollController.animateTo(
          (selectedIndex * 70.0) - 16.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });

    return Container(
      height: 90,
      child: Column(
        children: [
          Container(
            height: 65,
            child: ListView.builder(
              controller: _distanceScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: distances.length + 1, // +1 for custom add button
              itemExtent: 70,
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemBuilder: (context, index) {
                // Custom add button her zaman en sonda
                if (index == distances.length) {
                  return Padding(
                    padding: EdgeInsets.only(left: 10.0, right: 16.0),
                    child: GestureDetector(
                      onTap: () async {
                        final custom = await showDialog<int>(
                          context: context,
                          builder: (context) {
                            int? customValue;
                            return AlertDialog(
                              title: Text('Özel Mesafe'),
                              content: TextField(
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(hintText: 'Metre'),
                                onChanged: (val) {
                                  customValue = int.tryParse(val);
                                },
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('İptal'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (customValue != null && customValue! > 0) {
                                      Navigator.pop(context, customValue);
                                    }
                                  },
                                  child: Text('Tamam'),
                                ),
                              ],
                            );
                          },
                        );
                        if (custom != null && custom > 0) {
                          ref.read(trainingConfigProvider.notifier).setDistance(custom);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? Colors.grey[700] : Colors.grey[300],
                              border: Border.all(
                                color: Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.add,
                                color: isDark ? Colors.white : Colors.black87,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  final d = distances[index];
                  final isSelected = distance == d;
                  double leftPadding = 10.0;
                  if (index == 0) leftPadding = 16.0;
                  return Padding(
                    padding: EdgeInsets.only(left: leftPadding),
                    child: GestureDetector(
                      onTap: () {
                        if (!isSelected) {
                          ref.read(trainingConfigProvider.notifier).setDistance(d);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            width: isSelected ? 46 : 38,
                            height: isSelected ? 46 : 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? primaryColor : isDark ? Colors.grey[700] : Colors.grey[300],
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: isSelected 
                                  ? [
                                      BoxShadow(
                                        color: primaryColor.withOpacity(0.5),
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Text(
                                '$d',
                                style: TextStyle(
                                  fontSize: isSelected ? 15 : 13,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person,
                  color: primaryColor,
                  size: 20.24, // %15 daha büyütüldü (17.6 * 1.15)
                ),
                SizedBox(width: 3),
                Container(
                  width: 16,
                  height: 1,
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
                Icon(
                  Icons.arrow_forward,
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                  size: 17.71, // %15 daha büyütüldü (15.4 * 1.15)
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Cupertino Picker (iOS stili tekerlek)
  Widget _buildCupertinoPicker(
    BuildContext context, {
    required int value,
    required int min,
    required int max,
    required String suffix,
    required Function(int) onChanged,
    required bool isDark,
    required Color primaryColor,
  }) {
    final items = List.generate(max - min + 1, (index) => min + index);
    final backgroundColor = isDark ? Colors.grey[800] : Colors.white;
    
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Picker
          SizedBox(
            height: 120,
            width: double.infinity, // Ensure the picker fills the available width
            child: CupertinoPicker(
              backgroundColor: backgroundColor,
              itemExtent: 40,
              diameterRatio: 1.5, // Improves readability
              useMagnifier: true, // Shows a slight magnification effect
              magnification: 1.1, // Magnification amount
              selectionOverlay: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: primaryColor.withOpacity(0.6), width: 1.5),
                    bottom: BorderSide(color: primaryColor.withOpacity(0.6), width: 1.5),
                  ),
                ),
              ),
              scrollController: FixedExtentScrollController(initialItem: value - min),
              onSelectedItemChanged: (index) {
                final selectedValue = min + index;
                onChanged(selectedValue);
              },
              children: items.map((item) {
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$item',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      SizedBox(width: 5),
                      Text(
                        suffix,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Antrenman türü seçici
  Widget _buildTrainingTypeSelector(
    WidgetRef ref,
    String trainingType,
    Color primaryColor,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final types = [
      {'key': 'score', 'label': l10n.scoreTraining},
      {'key': 'target_score', 'label': l10n.targetFaceScoreTraining},
      {'key': 'technique', 'label': l10n.techniqueTraining},
    ];
    return Column(
      children: [
        // İlk satır: Normal Skor ve Hedef Kağıdı Skor
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              // Normal Skor Antrenmanı
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (trainingType != 'score') {
                      ref.read(trainingConfigProvider.notifier).setTrainingType('score');
                    }
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: trainingType == 'score' 
                          ? primaryColor 
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      l10n.scoreTraining,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: trainingType == 'score' ? FontWeight.bold : FontWeight.normal,
                        color: trainingType == 'score' 
                            ? Colors.white 
                            : isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ),
              // Hedef Kağıdı Skor Antrenmanı
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (trainingType != 'target_score') {
                      ref.read(trainingConfigProvider.notifier).setTrainingType('target_score');
                    }
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: trainingType == 'target_score' 
                          ? primaryColor 
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      l10n.targetFaceScoreTraining,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: trainingType == 'target_score' ? FontWeight.bold : FontWeight.normal,
                        color: trainingType == 'target_score' 
                            ? Colors.white 
                            : isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // İkinci satır: Teknik Antrenman
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(15),
          ),
          child: GestureDetector(
            onTap: () {
              if (trainingType != 'technique') {
                ref.read(trainingConfigProvider.notifier).setTrainingType('technique');
              }
            },
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: trainingType == 'technique' 
                    ? primaryColor 
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                l10n.techniqueTraining,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: trainingType == 'technique' ? FontWeight.bold : FontWeight.normal,
                  color: trainingType == 'technique' 
                      ? Colors.white 
                      : isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Hedef kağıdı seçici
  Widget _buildTargetFaceSelector(
    WidgetRef ref,
    String? targetFace,
    Color primaryColor,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final targetFaces = [
      {'key': '80cm', 'label': l10n.targetFace80cm},
      {'key': '122cm', 'label': l10n.targetFace122cm},
    ];
    
    return Column(
      children: [
        // Görsel hedef kağıtları
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: targetFaces.map((face) {
            final isSelected = targetFace == face['key'];
            return GestureDetector(
              onTap: () {
                ref.read(trainingConfigProvider.notifier).setTargetFace(face['key']!);
              },
              child: Column(
                children: [
                  // Hedef kağıdı görseli
                  TargetFaceWidget(
                    targetType: face['key']!,
                    size: 70,
                    isSelected: isSelected,
                  ),
                  const SizedBox(height: 8),
                  // Hedef kağıdı etiketi
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? primaryColor 
                          : (isDark ? Colors.grey[800] : Colors.grey[200]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      face['label']!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected 
                            ? Colors.white 
                            : (isDark ? Colors.grey[300] : Colors.grey[700]),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Seçim durumu göstergesi
        if (targetFace != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primaryColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: primaryColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  targetFace == '80cm' ? l10n.targetFace80cm : l10n.targetFace122cm,
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildNotesInput(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          width: 1.5,
        ),
      ),
      child: TextField(
        controller: _notesController,
        maxLines: 3,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: l10n.notes,
          hintStyle: TextStyle(
            color: isDark ? Colors.grey[500] : Colors.grey[400],
            fontSize: 13,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          border: InputBorder.none,
        ),
      ),
    );
  }

  // Date + Time picker UI
  Widget _buildDateTimePicker(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final dateTime = _selectedDateTime ?? DateTime.now();
    final formatted = MaterialLocalizations.of(context).formatFullDate(dateTime) +
        '  ' +
        TimeOfDay.fromDateTime(dateTime).format(context);

    return InkWell(
      onTap: () async {
        // Pick date
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: _selectedDateTime ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          builder: (context, child) {
            return Theme(
              data: theme.copyWith(
                colorScheme: theme.colorScheme.copyWith(
                  primary: primaryColor,
                ),
              ),
              child: child!,
            );
          },
        );
        if (pickedDate != null) {
          // Pick time
          final pickedTime = await showTimePicker(
            context: context,
            initialTime: _selectedDateTime != null
                ? TimeOfDay.fromDateTime(_selectedDateTime!)
                : TimeOfDay.now(),
            builder: (context, child) {
              return Theme(
                data: theme.copyWith(
                  colorScheme: theme.colorScheme.copyWith(
                    primary: primaryColor,
                  ),
                ),
                child: child!,
              );
            },
          );
          if (pickedTime != null) {
            setState(() {
              _selectedDateTime = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                pickedTime.hour,
                pickedTime.minute,
              );
            });
          }
        }
      },
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: primaryColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.trainingDateTime,
                    style: TextStyle(
                      fontSize: 13,
                      color: hintColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _selectedDateTime != null ? formatted : l10n.trainingDateTimeHint,
                        style: TextStyle(
                          fontSize: 15,
                          color: _selectedDateTime != null ? textColor : hintColor,
                          fontWeight: _selectedDateTime != null ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down, color: hintColor),
          ],
        ),
      ),
    );
  }

  // Antrenmanı başlat
  void _startTraining(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final config = ref.read(trainingConfigProvider);
    final trainingSController = ref.read(trainingSessionProvider.notifier);
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.userNotFound),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final trainingName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : null;
    final notes = _notesController.text.trim().isNotEmpty
        ? _notesController.text.trim()
        : null;
    final trainingType = config.trainingType;
    final selectedDate = _selectedDateTime ?? DateTime.now();

    // Skor antrenmanı için hedef kağıdı kontrolü
    if (trainingType == 'score' && config.targetFace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.targetFaceRequired),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (trainingType == 'technique') {
      // Teknik antrenman için onay ekranı göster
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TechniqueTrainingConfirmScreen(
            distance: config.distance,
            bowType: config.bowType,
            arrowsPerSeries: config.arrowsPerSeries,
            seriesCount: config.seriesCount,
            notes: notes,
            onCancel: () {
              Navigator.of(context).pop();
            },
            onConfirm: () async {
              // Kaydet (sadece veri kaydı, navigation yok)
              await trainingSController.initSession(
                userId: currentUserId,
                date: selectedDate,
                distance: config.distance,
                bowType: config.bowType,
                isIndoor: config.isIndoor,
                notes: notes,
                training_session_name: trainingName,
                trainingType: trainingType,
                arrowsPerSeries: config.arrowsPerSeries,
                seriesCount: config.seriesCount,
              );
            },
          ),
        ),
      );
      return;
    }

    // Skor antrenmanı için mevcut akış
    await trainingSController.initSession(
      userId: currentUserId,
      date: selectedDate,
      distance: config.distance,
      bowType: config.bowType,
      isIndoor: config.isIndoor,
      notes: notes,
      training_session_name: trainingName,
      trainingType: trainingType,
      arrowsPerSeries: config.arrowsPerSeries,
    );

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TrainingSessionScreen(),
        ),
      );
    }
  }
}
