class ScoringRules {
  // İç temsil için sabit değer
  static const int xScoreInternal = -1;

  // Get available score values based on bow type and environment
  static List<int> getScoreValues(
      {required String bowType, required bool isIndoor}) {
    if (isIndoor) {
      // Indoor scoring is the same for all bow types - no X scoring indoors
      return [10, 9, 8, 7, 6, 0]; // 0 represents 'M' (miss)
    } else {
      // Outdoor scoring - includes X
      // All bow types should have full range for UI
      return [xScoreInternal, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0];
    }
  }

  // Yardımcı metodlar
  static int scoreFromLabel(String label) {
    if (label == 'M') return 0;
    if (label == 'X') return xScoreInternal;
    return int.parse(label);
  }

  static String labelFromScore(int score) {
    if (score == 0) return 'M';
    if (score == xScoreInternal) return 'X';
    return score.toString();
  }

  // Gösterilecek puan değerini döndür (display ve hesaplamalar için)
  static int getPointValue(int score) {
    if (score == xScoreInternal) {
      return 10; // X her zaman 10 puan olarak sayılır
    }
    return score;
  }

  // Bir skor X mi kontrol et
  static bool isX(int score) {
    return score == xScoreInternal;
  }
}
