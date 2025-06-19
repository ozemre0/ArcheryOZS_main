import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';                   
import '../models/scoring_rules.dart';
import '../providers/training_session_controller.dart';
import '../providers/training_config_controller.dart';
import '../widgets/target_face_widgets.dart';
import 'training_history_screen.dart';
import 'package:archeryozs/utils/score_utils.dart';
import 'dart:math' as math;

class TrainingSessionScreen extends ConsumerWidget {
  const TrainingSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sessionState = ref.watch(trainingSessionProvider);
    final configState = ref.watch(trainingConfigProvider);

    // Hata durumunu kontrol et
    if (sessionState.error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sessionState.error!),
            backgroundColor: Colors.red,
          ),
        );
        ref.read(trainingSessionProvider.notifier).clearError();
      });
    }

    // Oturum yoksa yükleniyor veya hata ekranı göster
    if (sessionState.session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.training)),
        body: Center(
          child: sessionState.isLoading
              ? const CircularProgressIndicator()
              : const Text('Antrenman oturumu başlatılamadı'),
        ),
      );
    }

    final session = sessionState.session!;
    final currentArrows = sessionState.currentArrows;
    final currentSeries = sessionState.currentSeriesNumber;
    final isLoading = sessionState.isLoading;
    final combinedSeries = ref.read(trainingSessionProvider.notifier).combinedSeries;
    final isDirty = sessionState.isDirty;

    // Yapılandırmadan her seri için ok sayısını al
    final arrowsPerSeries =
        sessionState.session?.arrowsPerSeries ?? configState.arrowsPerSeries;
    // Yapılandırmadan toplam seri sayısını al
    final totalConfiguredSeries = configState.seriesCount;
    // Mevcut ok sayısı seri başına belirlenen ok sayısına ulaştı mı kontrol et
    final isSeriesComplete = currentArrows.length >= arrowsPerSeries;
    // Mevcut serinin son ayarlanan seri olup olmadığını kontrol et
    final isLastConfiguredSeries = currentSeries == totalConfiguredSeries;

    // Düzenleme modunda toplam skor ve seri sayısı doğru hesaplansın
    final filteredSeries = sessionState.isEditing
        ? combinedSeries.where((s) => s['seriesNumber'] != sessionState.currentSeriesNumber).toList()
        : combinedSeries;

    final totalScore = filteredSeries.fold<int>(0, (sum, seriesObj) {
      final arrows = (seriesObj['arrows'] as List<dynamic>?)?.cast<int>() ?? [];
      return sum + calculateSeriesTotal(arrows);
    }) + (currentArrows.isNotEmpty ? calculateSeriesTotal(currentArrows) : 0);

    // Calculate current series total
    final currentSeriesTotal = currentArrows.fold<int>(
        0, (sum, arrow) => sum + ScoringRules.getPointValue(arrow));

    // Get available scores based on bow type and environment
    final availableScores = ScoringRules.getScoreValues(
      bowType: session.bowType ?? '', // Provide default empty string
      isIndoor: session.isIndoor,
    );

    String environment = session.isIndoor ? l10n.indoor : l10n.outdoor;

    return WillPopScope(
      onWillPop: () async {
        // Eğer hiç seri yoksa ve mevcut seride de ok yoksa, direkt çıkış yap
        if (combinedSeries.isEmpty && currentArrows.isEmpty) {
          await ref.read(trainingSessionProvider.notifier).endSession();
          return true;
        }

        // Eğer kullanıcı hiçbir değişiklik yapmadıysa, alert dialog göstermeden çık
        if (!isDirty) {
          await ref.read(trainingSessionProvider.notifier).endSession();
          return true;
        }

        // Eğer mevcut seride ok varsa veya kaydedilmiş seriler varsa uyarı göster
        if (currentArrows.isNotEmpty || combinedSeries.isNotEmpty) {
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.warning),
              content: Text(l10n.trainingNotSavedMessage),
              actions: [
                TextButton(
                  onPressed: () async {
                    // Kaydetmeden çıkış yaparken hiçbir şey kaydetme
                    await ref
                        .read(trainingSessionProvider.notifier)
                        .endSession(forceDelete: false, saveChanges: false);
                    if (context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: Text(l10n.exitWithoutSaving),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancelButton),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Complete current series if needed
                    if (currentArrows.isNotEmpty &&
                        currentArrows.length == arrowsPerSeries) {
                      await ref
                          .read(trainingSessionProvider.notifier)
                          .completeCurrentSeries(
                              arrowsPerSeries: arrowsPerSeries);
                    }

                    // Save all changes to database
                    if (isDirty) {
                      await ref
                          .read(trainingSessionProvider.notifier)
                          .saveTrainingToDatabase();
                    }

                    if (context.mounted) {
                      Navigator.of(context).pop(false); // Close dialog
                      // Navigate to history with fade transition
                      Navigator.of(context).pushAndRemoveUntil(
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  const TrainingHistoryScreen(),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                                opacity: animation, child: child);
                          },
                          transitionDuration: const Duration(milliseconds: 200),
                        ),
                        (route) => route.isFirst,
                      );
                    }
                  },
                  child: Text(l10n.saveButton),
                ),
              ],
            ),
          );
          return result ?? false;
        }

        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.trainingEnvironmentTitle(environment)),
          actions: [
            if (isDirty)
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Kaydedilmemiş değişiklikler var',
                onPressed: () async {
                  // Complete current series if needed
                  if (currentArrows.isNotEmpty &&
                      currentArrows.length == arrowsPerSeries) {
                    await ref
                        .read(trainingSessionProvider.notifier)
                        .completeCurrentSeries(
                            arrowsPerSeries: arrowsPerSeries);
                  }

                  // Save all changes to database
                  await ref
                      .read(trainingSessionProvider.notifier)
                      .saveTrainingToDatabase();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.trainingSavedMessage),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
          ],
        ),
        body: Column(
          children: [
            // Üst bilgi alanı
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.distanceLabel(
                              '${session.distance}${l10n.meters}'),
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.bowTypeInfo(getLocalizedBowType(session.bowType, l10n)),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l10n.seriesCount(currentSeries, totalConfiguredSeries),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.totalScore(totalScore),
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Mevcut oklar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.currentSeries(
                            currentArrows.length, arrowsPerSeries),
                        style: const TextStyle(
                          fontSize: 16.2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.totalSeriesScore(currentSeriesTotal),
                        style: const TextStyle(
                          fontSize: 16.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildArrowScores(currentArrows),

                  // Seri tamamlandığında uyarı göster
                  if (isSeriesComplete)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.seriesCompleteMessage(arrowsPerSeries),
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Hedef kağıdı skor antrenmanı için özel görünüm
            if (session.trainingType == 'target_score' && configState.targetFace != null)
              Expanded(
                child: _buildTargetFaceSeriesView(context, ref, sessionState, combinedSeries, arrowsPerSeries, configState, l10n),
              )
            // Normal antrenmanlar için seri kartları
            else if (!(sessionState.isEditing && currentArrows.isEmpty) && combinedSeries.isNotEmpty)
              Expanded(
                child: Stack(
                  children: [
                    ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: combinedSeries.length,
                      itemBuilder: (context, index) {
                        final series = combinedSeries[index];
                        // Düzenleme modunda ve düzenlenen seri ise kartı gizle (ok sayısına bakmadan)
                        if (sessionState.isEditing && sessionState.currentSeriesNumber == (series['seriesNumber'] ?? (index + 1))) {
                          return const SizedBox.shrink();
                        }
                        return _buildSeriesItem(
                          context,
                          series,
                          series['seriesNumber'] ?? (index + 1),
                          (series['id'] ?? '').toString().startsWith('local_'),
                          l10n,
                        );
                      },
                    ),
                    if (isLoading)
                      Container(
                        color: Colors.black.withOpacity(0.1),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                  ],
                ),
              )
            else if (session.trainingType != 'target_score' || configState.targetFace == null)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 48),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        l10n.trainingSessionInfo,
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.blue[900],
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

            const Divider(height: 1),

            // Normal skor antrenmanı için puan butonları ve kontroller
            if (session.trainingType == 'score')
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Column(
                  children: [
                    // Puan butonları - sadece normal skor antrenmanı için (hedef kağıdı yoksa)
                    if (!isSeriesComplete)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: availableScores.map((score) {
                          return _buildScoreButton(
                            context,
                            score,
                            () {
                              ref
                                  .read(trainingSessionProvider.notifier)
                                  .recordArrow(score);
                            },
                            ref,
                            arrowsPerSeries,
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 16),

                    // İşlem butonları - HER ZAMAN sabit göster, sadece aktiflik değişsin
                    Row(
                      children: [
                        // Geri al butonu
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: currentArrows.isNotEmpty
                                ? () {
                                    ref
                                        .read(trainingSessionProvider.notifier)
                                        .undoLastArrow();
                                  }
                                : null, // Ok yoksa devre dışı
                            icon: const Icon(Icons.undo),
                            label: Text(l10n.undoButton),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              backgroundColor: Colors.grey[300],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Sıfırla butonu
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: currentArrows.isNotEmpty
                                ? () {
                                    ref
                                        .read(trainingSessionProvider.notifier)
                                        .resetCurrentSeries();
                                  }
                                : null, // Ok yoksa devre dışı
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.resetButton),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              backgroundColor: Colors.amber[200],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Seriyi Tamamla butonu
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (currentArrows.isNotEmpty && currentArrows.length == arrowsPerSeries)
                                ? () {
                                    // Son yapılandırılmış seriyse onay iste
                                    if (isLastConfiguredSeries && !sessionState.isEditing) {
                                      _showTrainingFinishConfirmation(
                                          context,
                                          ref,
                                          totalScore,
                                          combinedSeries.fold<int>(0, (sum, sObj) {
                                            final s = sObj as Map<String, dynamic>?;
                                            final arrows = s != null ? s['arrows'] as List<dynamic>? : null;
                                            final arrowsLength = arrows?.length ?? 0;
                                            return sum + arrowsLength;
                                          }) +
                                              currentArrows.length,
                                          isLastConfiguredSeries,
                                          arrowsPerSeries,
                                          l10n);
                                    } else {
                                      ref
                                          .read(trainingSessionProvider.notifier)
                                          .completeCurrentSeries(arrowsPerSeries: arrowsPerSeries);
                                    }
                                  }
                                : null, // Ok yoksa veya eksikse devre dışı
                            icon: const Icon(Icons.check),
                            label: Text(sessionState.isEditing ? 'Güncelle' : l10n.completeSeriesButton),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: (currentArrows.isNotEmpty && currentArrows.length == arrowsPerSeries)
                                  ? (sessionState.isEditing ? Colors.orange : Colors.green)
                                  : Colors.grey, // Devre dışıyken gri renk
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Teknik antrenman için basit bilgi gösterimi
            if (session.trainingType == 'technique')
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 64,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.techniqueTraining,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Teknik çalışmanız için zamanlayıcıyı kullanabilirsiniz.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Antrenman bitimi onay penceresini göster
  void _showTrainingFinishConfirmation(
      BuildContext context,
      WidgetRef ref,
      int totalScore,
      int totalArrows,
      bool isLastSeries,
      int arrowsPerSeries,
      AppLocalizations l10n) {
    // Ok başına ortalama puanı hesapla
    final double averagePerArrow =
        totalArrows > 0 ? totalScore / totalArrows : 0;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing while processing
      builder: (BuildContext context) {
        final dialogTheme = Theme.of(context);
        final isDarkDialog = dialogTheme.brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor:
              isDarkDialog ? dialogTheme.colorScheme.surface : Colors.white,
          title: Text(
            'Antrenmanı Bitir',
            style: TextStyle(
              color: isDarkDialog ? Colors.white : Colors.black,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryItem(
                  Icons.score, 'Toplam Puan', '$totalScore', isDarkDialog),
              _buildSummaryItem(Icons.arrow_forward, 'Toplam Ok',
                  '$totalArrows', isDarkDialog),
              _buildSummaryItem(Icons.calculate, 'Ok Başı Ortalama',
                  averagePerArrow.toStringAsFixed(2), isDarkDialog),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Antrenmana Devam Et'),
              onPressed: () async {
                // Eğer mevcut oklar tamamlanmışsa yeni seriyi başlat
                if (ref.read(trainingSessionProvider).currentArrows.length == arrowsPerSeries) {
                  await ref.read(trainingSessionProvider.notifier).completeCurrentSeries(arrowsPerSeries: arrowsPerSeries);
                }
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                // Show a loading indicator while saving
                // Web platformunda daha belirgin bir yükleme göstergesi
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return Dialog(
                      child: Container(
                        padding: const EdgeInsets.all(20.0),
                        width: kIsWeb ? 300 : 250, // Web'de daha geniş
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (kIsWeb)
                              // Web'de daha büyük yükleme göstergesi
                              SizedBox(
                                width: 60,
                                height: 60,
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.blue),
                                ),
                              )
                            else
                              CircularProgressIndicator(),
                            SizedBox(height: 20),
                            Text(
                              kIsWeb
                                  ? "Antrenman kaydediliyor...\nLütfen bekleyin"
                                  : "Antrenman kaydediliyor...",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: kIsWeb ? 16 : 14,
                                fontWeight: kIsWeb
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );

                try {
                  // First complete current series if needed
                  if (ref.read(trainingSessionProvider).currentArrows.length ==
                      arrowsPerSeries) {
                    print('Completing final series before saving training');
                    await ref
                        .read(trainingSessionProvider.notifier)
                        .completeCurrentSeries(
                            arrowsPerSeries: arrowsPerSeries);
                  }

                  // First make sure all local series are saved to local database
                  print('Saving all changes to local database');
                  await ref
                      .read(trainingSessionProvider.notifier)
                      .saveTrainingToDatabase();

                  // Now explicitly tell the controller to end and save training with scores
                  print('Ending training with saveChanges=true');
                  final success = await ref
                      .read(trainingSessionProvider.notifier)
                      .endTraining(saveChanges: true);

                  if (!success) {
                    throw Exception('Failed to save training session');
                  }

                  print('Training successfully saved and ended');

                  if (context.mounted) {
                    // Close loading dialog
                    Navigator.of(context).pop();
                    // Close confirmation dialog
                    Navigator.of(context).pop();

                    // Navigate to history screen with smooth transition - optimized for web
                    if (kIsWeb) {
                      // Web platformunda daha hızlı bir geçiş için
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const TrainingHistoryScreen(),
                        ),
                        (route) => route.isFirst,
                      );
                    } else {
                      // Mobil cihazlar için animasyonlu geçiş
                      Navigator.pushAndRemoveUntil(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  const TrainingHistoryScreen(),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                                opacity: animation, child: child);
                          },
                          transitionDuration: const Duration(milliseconds: 200),
                        ),
                        (route) => route.isFirst,
                      );
                    }
                  }
                } catch (e) {
                  print('Error saving training: $e');
                  if (context.mounted) {
                    // Close loading indicator
                    Navigator.of(context).pop();
                    // Show error
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Antrenman kaydedilemedi: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Kaydet ve Bitir'),
            ),
          ],
        );
      },
    );
  }

  // Özet öğesi için yardımcı widget - isDarkDialog parametresi ekledim
  Widget _buildSummaryItem(
      IconData icon, String label, String value, bool isDarkDialog) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                // Adapt text color based on theme
                color: isDarkDialog ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              // Adapt text color based on theme
              color: isDarkDialog ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  // Ok skorlarını gösteren widget
  Widget _buildArrowScores(List<int> arrows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < arrows.length; i++)
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _getColorForScore(arrows[i]),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26),
              ),
              alignment: Alignment.center,
              child: Text(
                ScoringRules.labelFromScore(arrows[i]),
                style: TextStyle(
                  color: _getTextColorForScore(arrows[i]),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Seri öğesi
  Widget _buildSeriesItem(BuildContext context, Map<String, dynamic> series,
      int seriesNumber, bool isLocal, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Toplam puanı ok dizisinden anlık hesapla
    final arrows = (series['arrows'] as List<dynamic>?)?.cast<int>() ?? [];
    final totalScore = calculateSeriesTotal(arrows);

    return Consumer(
      builder: (context, ref, _) => Card(
        // Adapt card color to current theme
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        elevation: 3, // Daha belirgin gölge
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            // Adapt border color to current theme
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                final dialogTheme = Theme.of(context);
                final isDarkDialog = dialogTheme.brightness == Brightness.dark;

                return AlertDialog(
                  // Adapt dialog background to current theme
                  backgroundColor:
                      isDarkDialog ? const Color(0xFF2D2D2D) : Colors.white,
                  title: Text(
                    'Seri $seriesNumber\'i Düzenle',
                    style: TextStyle(
                      // Adapt text color to current theme
                      color: isDarkDialog ? Colors.white : Colors.black,
                    ),
                  ),
                  content: Text(
                    'Bu seriyi düzenlemek istiyor musunuz?',
                    style: TextStyle(
                      // Adapt text color to current theme
                      color: isDarkDialog ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  actions: [
                    TextButton(
                      child: Text(l10n.cancelButton),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                      ),
                      child: Text(
                        'Düzenle',
                        // Adapt button text color based on primary color contrast
                        style: TextStyle(
                          color: isDarkDialog ? Colors.white : Colors.white,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        ref
                            .read(trainingSessionProvider.notifier)
                            .loadSeriesForEditing(
                              (series['id'] ?? 'local_$seriesNumber').toString(), // Null id fallback
                              (series['arrows'] as List).map((e) => e as int).toList(),
                              seriesNumber,
                            );
                      },
                    ),
                  ],
                );
              },
            );
          },
          child: Container(
            decoration: BoxDecoration(
              border: ref.watch(trainingSessionProvider).isEditing &&
                      ref.watch(trainingSessionProvider).currentSeriesNumber ==
                          seriesNumber
                  ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(8),
              // Adapt gradient based on theme
              gradient: isLocal
                  ? LinearGradient(
                      colors: isDark
                          ? [
                              Colors.grey.shade900,
                              Colors.grey.shade800,
                            ]
                          : [
                              Colors.grey.shade200,
                              Colors.grey.shade100,
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Seri numarası ve toplam skor (alt alta)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.seriesNumber(seriesNumber),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          '$totalScore/${arrows.length * 10}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isDark ? Colors.white60 : Colors.black54,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 36,
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          // Adapt divider color based on theme
                          isDark
                              ? Colors.grey.shade800.withOpacity(0.1)
                              : Colors.grey.shade300.withOpacity(0.1),
                          isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                          isDark
                              ? Colors.grey.shade800.withOpacity(0.1)
                              : Colors.grey.shade300.withOpacity(0.1),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  // Ok skorları
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: series['arrows'] != null
                        ? (series['arrows'] as List<dynamic>).map((score) => Container(
                              width: 32,
                              height: 32,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: _getColorForScore(score),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                ScoringRules.labelFromScore(score),
                                style: TextStyle(
                                  color: _getTextColorForScore(score),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ))
                        .toList()
                        : [],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Puan butonları
  Widget _buildScoreButton(BuildContext context, int score,
      VoidCallback onPressed, WidgetRef ref, int arrowsPerSeries) {
    final sessionState = ref.watch(trainingSessionProvider);
    final isMaxArrowsReached =
        sessionState.currentArrows.length >= arrowsPerSeries;

    return Material(
      color: Colors.transparent,
      elevation: 2,
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        borderRadius: BorderRadius.circular(25),
        onTap: isMaxArrowsReached
            ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Bu seri için maksimum ok sayısına ($arrowsPerSeries) ulaşıldı. Seriyi tamamlayın veya son oku geri alın.'),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            : onPressed,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _getColorForScore(score),
            border: Border.all(color: Colors.black26),
          ),
          alignment: Alignment.center,
          child: Text(
            ScoringRules.labelFromScore(score),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _getTextColorForScore(score),
            ),
          ),
        ),
      ),
    );
  }

  // Puana göre renk belirleme
  Color _getColorForScore(int score) {
    if (ScoringRules.isX(score)) return Colors.yellow;
    if (score == 10) return Colors.yellow;
    if (score == 9) return Colors.yellow;
    if (score == 8) return Colors.red;
    if (score == 7) return Colors.red;
    if (score == 6) return Colors.blue;
    if (score == 5) return Colors.blue;
    if (score == 4) return Colors.black;
    if (score == 3) return Colors.black;
    if (score == 2) return Colors.white;
    if (score == 1) return Colors.white;
    return Colors.white; // 0 için (M)
  }

  // Puana göre metin rengi belirleme
  Color _getTextColorForScore(int score) {
    if (ScoringRules.isX(score)) return Colors.black;
    if (score >= 9) return Colors.black;
    if (score >= 4 || score == 3) {
      return Colors.white; // 3 puanı için beyaz renk ekledim
    }
    return Colors.black;
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

  // Seri tamamlama ekranını göster
  void _showSeriesCompletionScreen(BuildContext context, WidgetRef ref, int arrowsPerSeries, AppLocalizations l10n) {
    final sessionState = ref.read(trainingSessionProvider);
    final currentArrows = sessionState.currentArrows;
    final seriesTotal = currentArrows.fold<int>(0, (sum, score) => sum + score);
    final averageScore = currentArrows.isNotEmpty ? seriesTotal / currentArrows.length : 0.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        l10n.seriesComplete,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Series summary
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                                                 'Seri ${sessionState.currentSeriesNumber}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildStatItem('Toplam', '$seriesTotal', Icons.score),
                                  _buildStatItem('Ortalama', averageScore.toStringAsFixed(1), Icons.calculate),
                                  _buildStatItem('Ok Sayısı', '${currentArrows.length}', Icons.arrow_forward),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Arrow scores display
                        Text(
                          'Ok Skorları',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: currentArrows.map((score) {
                            return Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: _getColorForScore(score),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                ScoringRules.labelFromScore(score),
                                style: TextStyle(
                                  color: _getTextColorForScore(score),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        
                        const Spacer(),
                        
                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  ref
                                      .read(trainingSessionProvider.notifier)
                                      .completeCurrentSeries(arrowsPerSeries: arrowsPerSeries);
                                },
                                icon: const Icon(Icons.arrow_forward),
                                label: Text(l10n.nextSeries),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                                                     _showTrainingFinishConfirmation(
                                     context,
                                     ref,
                                     sessionState.localSeries.fold<int>(0, (sum, series) => sum + (series['totalScore'] as int? ?? 0)) + seriesTotal,
                                     sessionState.localSeries.fold<int>(0, (sum, series) => sum + (series['arrows'] as List).length) + currentArrows.length,
                                     true,
                                     arrowsPerSeries,
                                     l10n,
                                   );
                                },
                                icon: const Icon(Icons.stop),
                                label: Text(l10n.finishTraining),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  // Basit seri kartı (hedef kağıdı antrenmanı için)
  Widget _buildSeriesCard(List<int> arrows, int seriesNumber, AppLocalizations l10n, BuildContext context, {bool showUndoButton = false, VoidCallback? onUndo}) {
    final totalScore = arrows.fold<int>(0, (sum, score) => sum + score);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      Colors.grey.shade900,
                      Colors.grey.shade800,
                    ]
                  : [
                      Colors.grey.shade200,
                      Colors.grey.shade100,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              // Ana seri kartı içeriği
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Seri numarası ve toplam skor (alt alta)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              l10n.seriesNumber(seriesNumber),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                                height: 1.2,
                              ),
                            ),
                            Text(
                              '$totalScore/${arrows.length * 10}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: isDark ? Colors.white60 : Colors.black54,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 36,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              isDark
                                  ? Colors.grey.shade800.withOpacity(0.1)
                                  : Colors.grey.shade300.withOpacity(0.1),
                              isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                              isDark
                                  ? Colors.grey.shade800.withOpacity(0.1)
                                  : Colors.grey.shade300.withOpacity(0.1),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      // Ok skorları
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: arrows.map((score) => Container(
                              width: 32,
                              height: 32,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: _getColorForScore(score),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                ScoringRules.labelFromScore(score),
                                style: TextStyle(
                                  color: _getTextColorForScore(score),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ))
                        .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Geri alma butonu (geçmiş seriler için)
              if (showUndoButton && arrows.isNotEmpty)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      onTap: onUndo,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.undo,
                              size: 16,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Son oku geri al',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black54,
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
        ),
      ),
         );
   }

   // Geçmiş serilerden ok geri alma (çoklu geri alma destekli)
   void _undoArrowFromSeries(WidgetRef ref, int seriesNumber, AppLocalizations l10n, BuildContext context) {
     // Basit geri alma - sadece son oku geri al
     ref.read(trainingSessionProvider.notifier).undoArrowFromSeries(seriesNumber);
   }

   // Geçmiş seriye ok ekleme
   void _addArrowToSeries(WidgetRef ref, int seriesNumber, int score, AppLocalizations l10n, BuildContext context) {
     ref.read(trainingSessionProvider.notifier).addArrowToSeries(seriesNumber, score);
     
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text('${l10n.arrowHole}: ${ScoringRules.labelFromScore(score)}'),
         duration: const Duration(seconds: 1),
       ),
     );
   }
 
   // Hedef kağıdı skor antrenmanı için özel seri görünümü
  Widget _buildTargetFaceSeriesView(
    BuildContext context,
    WidgetRef ref,
    TrainingSessionState sessionState,
    List<dynamic> combinedSeries,
    int arrowsPerSeries,
    TrainingConfigState configState,
    AppLocalizations l10n,
  ) {
    // Mevcut seri numarası (1'den başlar)
    final currentSeriesNumber = sessionState.currentSeriesNumber;
    final totalSeries = combinedSeries.length + 1; // Tamamlanan + mevcut seri
    final currentArrows = sessionState.currentArrows;
    final isCurrentSeriesActive = currentArrows.isNotEmpty || combinedSeries.isEmpty;
    
    // Görüntülenecek seri verisi
    Map<String, dynamic>? displaySeries;
    List<int> displayArrows = [];
    bool isViewingCurrentSeries = true;
    
    // Hangi seriyi görüntülüyoruz?
    if (currentSeriesNumber <= combinedSeries.length) {
      // Geçmiş seri görüntüleniyor
      displaySeries = combinedSeries[currentSeriesNumber - 1] as Map<String, dynamic>;
      displayArrows = List<int>.from(displaySeries['arrows'] ?? []);
      isViewingCurrentSeries = false;
    } else {
      // Mevcut seri görüntüleniyor
      displayArrows = currentArrows;
      isViewingCurrentSeries = true;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Skor kartları (geçmiş seriler için)
          if (!isViewingCurrentSeries && displayArrows.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: displayArrows.asMap().entries.map((entry) {
                    final index = entry.key;
                    final score = entry.value;
                    return Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: _getColorForScore(score),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        ScoringRules.labelFromScore(score),
                        style: TextStyle(
                          color: _getTextColorForScore(score),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          
          // Hedef kağıdı veya skor gösterimi
          Expanded(
            child: isViewingCurrentSeries && displayArrows.length < arrowsPerSeries
                ? Column(
                    children: [
                      Text(
                        l10n.tapTargetToScore,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).primaryColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // Aktif hedef kağıdı
                      Expanded(
                        child: Center(
                          child: InteractiveTargetFaceWidget(
                            targetType: configState.targetFace!,
                            size: math.min(
                              MediaQuery.of(context).size.width * 0.85,
                              MediaQuery.of(context).size.height * 0.5,
                            ),
                            arrowsPerSeries: arrowsPerSeries,
                            onScoreTap: (score) {
                              ref
                                  .read(trainingSessionProvider.notifier)
                                  .recordArrow(score);
                              
                              // Seri tamamlandı mı kontrol et
                              final updatedArrows = ref.read(trainingSessionProvider).currentArrows;
                              if (updatedArrows.length == arrowsPerSeries) {
                                // Seri tamamlandı, completion screen göster
                                _showSeriesCompletionScreen(context, ref, arrowsPerSeries, l10n);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  )
                                 : Center(
                     child: InteractiveTargetFaceWidget(
                       targetType: configState.targetFace!,
                       size: math.min(
                         MediaQuery.of(context).size.width * 0.7,
                         MediaQuery.of(context).size.height * 0.4,
                       ),
                       arrowsPerSeries: arrowsPerSeries,
                       existingArrows: displayArrows, // Geçmiş okları göster
                       isInteractive: true, // Geçmiş serilerde de interactive
                       onScoreTap: (score) {
                         if (!isViewingCurrentSeries) {
                           // Geçmiş seriye ok ekle
                           _addArrowToSeries(ref, currentSeriesNumber, score, l10n, context);
                         }
                       },
                     ),
                   ),
          ),
          
          const SizedBox(height: 16),
          
          // Alt navigasyon butonları
          Row(
            children: [
              // Geri butonu
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: currentSeriesNumber > 1
                      ? () {
                          ref
                              .read(trainingSessionProvider.notifier)
                              .goToPreviousSeries();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Geri'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Geri al butonu (hem mevcut hem geçmiş seriler için)
              if (displayArrows.isNotEmpty)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (isViewingCurrentSeries) {
                        ref
                            .read(trainingSessionProvider.notifier)
                            .undoLastArrow();
                      } else {
                        // Geçmiş seriden ok geri al
                        _undoArrowFromSeries(ref, currentSeriesNumber, l10n, context);
                      }
                    },
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.undoButton),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      backgroundColor: Colors.amber[200],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              if (displayArrows.isNotEmpty)
                const SizedBox(width: 12),
              // İleri butonu
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: currentSeriesNumber < totalSeries
                      ? () {
                          ref
                              .read(trainingSessionProvider.notifier)
                              .goToNextSeries();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('İleri'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
