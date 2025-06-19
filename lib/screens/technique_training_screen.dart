import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'training_history_screen.dart';

class TechniqueTrainingConfirmScreen extends StatelessWidget {
  final int distance;
  final String bowType;
  final int arrowsPerSeries;
  final int seriesCount;
  final String? notes;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  const TechniqueTrainingConfirmScreen({
    super.key,
    required this.distance,
    required this.bowType,
    required this.arrowsPerSeries,
    required this.seriesCount,
    this.notes,
    this.onCancel,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalArrows = arrowsPerSeries * seriesCount;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.technique),
        centerTitle: true,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth < 500 ? double.infinity : 400,
            ),
            child: Card(
              elevation: isDark ? 2 : 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: isDark ? theme.colorScheme.surface : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        l10n.trainingConfiguration,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildSummaryRow(l10n.distance, '$distance ${l10n.meters}', theme),
                    const SizedBox(height: 10),
                    _buildSummaryRow(l10n.bowType, getLocalizedBowType(bowType, l10n), theme),
                    const SizedBox(height: 10),
                    _buildSummaryRow(l10n.totalArrows, totalArrows.toString(), theme),
                    const SizedBox(height: 10),
                    if (notes != null && notes!.isNotEmpty)
                      _buildSummaryRow(l10n.notes, notes!, theme),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onCancel ?? () => Navigator.of(context).pop(),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (onConfirm != null) onConfirm!();
                              // After saving, go directly to TrainingHistoryScreen and clear stack
                              if (context.mounted) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (context) => const TrainingHistoryScreen(),
                                  ),
                                  (route) => false,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(l10n.save),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label + ':',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.normal,
              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
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
