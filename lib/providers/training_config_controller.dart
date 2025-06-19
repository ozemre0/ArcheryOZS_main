import 'package:flutter_riverpod/flutter_riverpod.dart';

// Antrenman yapılandırması için durum sınıfı
class TrainingConfigState {
  final bool isIndoor;
  final String bowType;
  final int distance;
  final int arrowsPerSeries;
  final int seriesCount;
  final int roundCount;
  final String trainingType; // eklendi
  final String? targetFace; // hedef kağıdı

  TrainingConfigState({
    required this.isIndoor,
    required this.bowType,
    required this.distance,
    required this.arrowsPerSeries,
    required this.seriesCount,
    required this.roundCount,
    this.trainingType = 'score', // varsayılan skor antrenmanı
    this.targetFace, // hedef kağıdı
  });

  TrainingConfigState copyWith({
    bool? isIndoor,
    String? bowType,
    int? distance,
    int? arrowsPerSeries,
    int? seriesCount,
    int? roundCount,
    String? trainingType, // eklendi
    String? targetFace, // hedef kağıdı
  }) {
    return TrainingConfigState(
      isIndoor: isIndoor ?? this.isIndoor,
      bowType: bowType ?? this.bowType,
      distance: distance ?? this.distance,
      arrowsPerSeries: arrowsPerSeries ?? this.arrowsPerSeries,
      seriesCount: seriesCount ?? this.seriesCount,
      roundCount: roundCount ?? this.roundCount,
      trainingType: trainingType ?? this.trainingType, // eklendi
      targetFace: targetFace ?? this.targetFace, // hedef kağıdı
    );
  }
}

class TrainingConfigController extends StateNotifier<TrainingConfigState> {
  // İç mekan (indoor) ve dış mekan (outdoor) için varsayılan değerler
  static final TrainingConfigState _defaultIndoorConfig = TrainingConfigState(
    isIndoor: true,
    bowType: 'Recurve',
    distance: 18,
    arrowsPerSeries: 3,
    seriesCount: 10,
    roundCount: 1,
    trainingType: 'score', // eklendi
  );

  static final TrainingConfigState _defaultOutdoorConfig = TrainingConfigState(
    isIndoor: false,
    bowType: 'Recurve',
    distance: 70,
    arrowsPerSeries: 6,
    seriesCount: 6,
    roundCount: 1,
    trainingType: 'score', // eklendi
  );

  TrainingConfigController() : super(_defaultIndoorConfig);

  // İç/dış mekan durumunu değiştir
  void setIndoor(bool isIndoor) {
    if (isIndoor) {
      state = _defaultIndoorConfig;
    } else {
      state = _defaultOutdoorConfig;
    }
  }

  // Yay tipini ayarla
  void setBowType(String bowType) {
    state = state.copyWith(bowType: bowType);
  }

  // Mesafeyi ayarla
  void setDistance(int distance) {
    state = state.copyWith(distance: distance);
  }

  // Ok sayısını ayarla
  void setArrowsPerSeries(int arrowsPerSeries) {
    state = state.copyWith(arrowsPerSeries: arrowsPerSeries);
  }

  // Seri sayısını ayarla
  void setSeriesCount(int seriesCount) {
    state = state.copyWith(seriesCount: seriesCount);
  }

  // Tur sayısını ayarla
  void setRoundCount(int roundCount) {
    state = state.copyWith(roundCount: roundCount);
  }

  // Antrenman türünü ayarla
  void setTrainingType(String trainingType) {
    state = state.copyWith(trainingType: trainingType);
  }

  // Hedef kağıdını ayarla
  void setTargetFace(String? targetFace) {
    state = state.copyWith(targetFace: targetFace);
  }
}

final trainingConfigProvider =
    StateNotifierProvider<TrainingConfigController, TrainingConfigState>((ref) {
  return TrainingConfigController();
});
