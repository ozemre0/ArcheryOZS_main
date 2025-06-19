import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/training_sync_service.dart';
import 'training_session_controller.dart'; // trainingRepositoryProvider'ı buradan içe aktarıyoruz

// Provider for the TrainingSyncService
final trainingSyncServiceProvider = Provider<TrainingSyncService>((ref) {
  final repository = ref.watch(trainingRepositoryProvider);
  return TrainingSyncService(repository: repository);
});
