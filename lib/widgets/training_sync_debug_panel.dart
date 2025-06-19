import 'package:flutter/material.dart';
import '../services/training_history_service.dart';
import '../services/supabase_config.dart';

/// Bu widget, geliştirme sırasında senkronizasyon durumunu görüntülemek
/// ve manuel senkronizasyon işlemlerini tetiklemek için kullanılabilir.
class TrainingSyncDebugPanel extends StatefulWidget {
  const TrainingSyncDebugPanel({super.key});

  @override
  State<TrainingSyncDebugPanel> createState() => _TrainingSyncDebugPanelState();
}

class _TrainingSyncDebugPanelState extends State<TrainingSyncDebugPanel> {
  final TrainingHistoryService _historyService = TrainingHistoryService();
  List<Map<String, dynamic>> _localSessions = [];
  bool _isLoading = false;
  String _statusMessage = '';
  String _syncResult = '';

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Yerel veritabanından veri alınıyor...';
    });

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _statusMessage = 'Kullanıcı oturumu bulunamadı';
          _isLoading = false;
        });
        return;
      }

      final sessions = await _historyService.showLocalTrainingSessions(userId);
      setState(() {
        _localSessions = sessions;
        _isLoading = false;
        _statusMessage = '${sessions.length} antrenman bulundu';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Hata: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _syncAllData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Tüm veriler senkronize ediliyor...';
      _syncResult = '';
    });

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _statusMessage = 'Kullanıcı oturumu bulunamadı';
          _isLoading = false;
        });
        return;
      }

      final result = await _historyService.manualSyncTrainingData(userId);

      setState(() {
        _syncResult = 'Senkronizasyon sonucu: $result';
        _isLoading = false;
      });

      // Verileri yeniden yükle
      await _loadLocalData();
    } catch (e) {
      setState(() {
        _statusMessage = 'Hata: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _syncSingleSession(String trainingId) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Antrenman senkronize ediliyor: $trainingId';
    });

    try {
      final success =
          await _historyService.syncSingleTrainingSession(trainingId);

      setState(() {
        _statusMessage = success
            ? 'Antrenman başarıyla senkronize edildi'
            : 'Senkronizasyon başarısız oldu';
        _isLoading = false;
      });

      // Verileri yeniden yükle
      await _loadLocalData();
    } catch (e) {
      setState(() {
        _statusMessage = 'Hata: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Senkronizasyon Hata Ayıklama'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _loadLocalData,
                  child: const Text('Yenile'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isLoading ? null : _syncAllData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Tümünü Senkronize Et'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(_statusMessage),
          ),
          if (_syncResult.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_syncResult,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          if (_isLoading)
            const CircularProgressIndicator()
          else
            Expanded(
              child: _localSessions.isEmpty
                  ? const Center(child: Text('Yerel antrenman bulunamadı'))
                  : ListView.builder(
                      itemCount: _localSessions.length,
                      itemBuilder: (context, index) {
                        final session = _localSessions[index];
                        final id = session['id'] as String;
                        final date = session['date'] as String;
                        final seriesCount = session['series_count'] as int;
                        final idType = session['id_type'] as String;
                        final syncStatus = session['sync_status'] as String;

                        // Renkler
                        final Color bgColor = idType == 'local'
                            ? Colors.amber.shade100 // Yerel ID
                            : Colors.green.shade100; // Uzak ID

                        final Color statusColor = syncStatus == 'pending'
                            ? Colors.red.shade300 // Bekleyen
                            : Colors.green.shade300; // Senkronize

                        return Card(
                          color: bgColor,
                          margin: const EdgeInsets.all(8),
                          child: ListTile(
                            title: Text(
                                '$date (${DateTime.parse(date).toLocal()})'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ID: $id'),
                                Text('Seri Sayısı: $seriesCount'),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      color: statusColor,
                                      child: Text('Durum: $syncStatus'),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      color: Colors.blue.shade100,
                                      child: Text('Tip: $idType'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.sync),
                              tooltip: 'Bu antrenmanı senkronize et',
                              onPressed: () => _syncSingleSession(id),
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
