# Phase 3: Training System Implementation Guide

## Overview
The training system allows archers to record and track practice sessions, including:
- Creating training sessions with configurable parameters
- Recording scores during practice
- Viewing and analyzing training history

## Data Models

### Training Session Model
```dart
class TrainingSession {
  final String id;
  final String userId;
  final DateTime date;
  final int distance;
  final String bowType; // "Recurve", "Compound", "Barebow"
  final bool isIndoor;
  final List<TrainingSeries> series;
  final String? notes;
  
  // Calculated properties
  int get totalArrows => series.fold(0, (sum, series) => sum + series.arrows.length);
  int get totalScore => series.fold(0, (sum, series) => sum + series.totalScore);
  double get average => totalArrows > 0 ? totalScore / totalArrows : 0;
  
  // Constructor and conversion methods omitted for brevity
}
```

### Training Series Model
```dart
class TrainingSeries {
  final String id;
  final String trainingId;
  final int seriesNumber;
  final List<int> arrows; // Scores for each arrow
  
  int get totalScore => arrows.fold(0, (sum, score) => sum + score);
  double get average => arrows.isNotEmpty ? totalScore / arrows.length : 0;
  
  // Constructor and conversion methods omitted for brevity
}
```

## Scoring Rules

```dart
class ScoringRules {
  // Get available score values based on bow type and environment
  static List<int> getScoreValues({required String bowType, required bool isIndoor}) {
    if (isIndoor) {
      // Indoor scoring is the same for all bow types
      return [10, 9, 8, 7, 6, 0]; // 0 represents 'M' (miss)
    } else {
      // Outdoor scoring
      if (bowType == 'Compound') {
        return [10, 9, 8, 7, 6, 5, 0];
      } else {
        // Recurve and Barebow
        return [10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0];
      }
    }
  }
  
  // Utility methods for score conversion
  static int scoreFromLabel(String label) {
    if (label == 'M') return 0;
    if (label == 'X') return 10;
    return int.parse(label);
  }
  
  static String labelFromScore(int score) {
    if (score == 0) return 'M';
    return score.toString();
  }
}
```

## Repository Pattern

```dart
class TrainingRepository {
  final SupabaseClient _supabase;
  
  TrainingRepository(this._supabase);
  
  // Key methods:
  // - createTrainingSession
  // - addSeries
  // - getUserTrainingSessions
  // - getTrainingSession
  // - updateTrainingSession
  // - updateSeries
  // - deleteTrainingSession
}
```

## Controllers

### Training Configuration
```dart
class TrainingConfigController extends StateNotifier<TrainingConfigState> {
  // Methods to set distance, arrows per series, series count, 
  // round count, bow type, indoor/outdoor setting
}

class TrainingConfigState {
  final int distance;
  final int arrowsPerSeries;
  final int seriesCount;
  final int roundCount;
  final String bowType;
  final bool isIndoor;
  
  // Default values: 18m distance, 3 arrows, 10 series, 1 round, Recurve, indoor
}
```

### Training Session
```dart
class TrainingSessionController extends StateNotifier<TrainingSessionState> {
  // Key methods:
  // - initSession: Initialize a new training session
  // - recordArrow: Record an arrow score
  // - completeCurrentSeries: Save current series and prepare next
  // - updateSeries: Modify a previously recorded series
  // - resetCurrentSeries: Clear current arrow entries
}
```

### Training History
```dart
class TrainingHistoryController extends StateNotifier<TrainingHistoryState> {
  // Methods for loading and filtering training history:
  // - loadUserTrainings
  // - filterByIndoor
  // - filterByDateRange
  // - clearFilters
}
```

## UI Components

### Training Configuration Screen
- Distance selector
- Arrows per series selector
- Series per round selector
- Round count selector
- Indoor/Outdoor toggle
- Bow type selector
- Start button

### Training Score Entry Screen
- Series navigation tabs
- Score buttons (1-10 and M)
- Arrow entry slots
- Reset button
- Complete Series button

### Training History Screen
- Indoor/Outdoor filter tabs
- Date filter
- Performance graph
- List of training sessions

## Database Schema

```sql
-- Training Sessions Table
CREATE TABLE training_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date TIMESTAMP WITH TIME ZONE NOT NULL,
  distance INTEGER NOT NULL,
  bow_type TEXT NOT NULL,
  is_indoor BOOLEAN NOT NULL,
  total_arrows INTEGER NOT NULL DEFAULT 0,
  total_score INTEGER NOT NULL DEFAULT 0,
  average NUMERIC(5,2) NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Training Series Table
CREATE TABLE training_series (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  training_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
  series_number INTEGER NOT NULL,
  arrows JSONB NOT NULL, -- Store as array
  total_score INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(training_id, series_number)
);
```

## Integration with Riverpod

```dart
// Providers
final trainingRepositoryProvider = Provider<TrainingRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return TrainingRepository(supabase);
});

final trainingConfigProvider = StateNotifierProvider<TrainingConfigController, TrainingConfigState>((ref) {
  return TrainingConfigController();
});

// Additional providers omitted for brevity
```

## Considerations

### Performance
- Pagination for training history
- Data caching for offline access
- Batch updates for multiple modifications
- Lazy loading for session details

### Security
- User authorization (access only own data)
- Input validation (client and server)
- Secure endpoints with Row Level Security
