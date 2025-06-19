import 'dart:convert';

class TrainingSession {
  /// Yeni algoritma için: Serilerin string (JSON) olarak tutulduğu alan
  final String? seriesData;
  final String id;
  final String userId;
  final DateTime date;
  final int? distance;
  final String? bowType;
  final bool isIndoor;
  final String? notes;
  final String? training_session_name;
  final int arrowsPerSeries; // Added field to store arrows per series
  final bool is_deleted; // Soft delete için ek alan (zorunlu)
  final String trainingType; // 'score' or 'technique'

  TrainingSession({
    required this.id,
    required this.userId,
    required this.date,
    this.distance,
    this.bowType,
    required this.isIndoor,
    this.notes,
    this.training_session_name,
    this.arrowsPerSeries = 3, // Default to 3 arrows per series
    this.seriesData,
    this.is_deleted = false,
    this.trainingType = 'score',
  });

  Map<String, dynamic> toJson() {
    // is_deleted alanını int olarak (0/1) gönder
    return {
      'is_deleted': is_deleted ? 1 : 0,
      'id': id,
      'user_id': userId,
      'date': date.toIso8601String(),
      'distance': distance,
      'bow_type': bowType,
      'is_indoor': isIndoor ? 1 : 0,
      'notes': notes,
      'training_session_name': training_session_name,
      'training_type': trainingType,
      'arrows_per_series': arrowsPerSeries,
      'series_data': seriesData, // Yeni alanı ekle
    };
  }

  factory TrainingSession.fromJson(Map<String, dynamic> json) {
    return TrainingSession(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      date: DateTime.parse(json['date'] as String),
      distance: json['distance'] as int?,
      bowType: json['bow_type'] as String?,
      isIndoor: (json['is_indoor'] == 1 || json['is_indoor'] == true),
      notes: json['notes'] as String?,
      training_session_name: (json['training_session_name']) as String?,
      arrowsPerSeries: json['arrows_per_series'] as int? ?? 3,
      is_deleted: json['is_deleted'] == null
          ? false
          : (json['is_deleted'] is bool
              ? json['is_deleted']
              : json['is_deleted'] == 1),
      seriesData: json['series_data'] as String?, // Yeni alanı ekle
      trainingType: (json['training_type'] as String?) ?? 'score',
    );
  }

  // --- YENİ: Seriler sadece seriesData üzerinden yönetilecek ---
  // Serileri JSON'dan çözüp ok listelerine dönüştüren yardımcı fonksiyon
  List<List<int>> get decodedSeriesData {
    if (seriesData == null || seriesData!.isEmpty) return [];
    try {
      final decoded = jsonDecode(seriesData!);
      if (decoded is! List) return [];
      // Sıralama için geçici dizi: [(seriNo, oklar)]
      List<MapEntry<int, List<int>>> numbered = [];
      for (var item in decoded) {
        if (item is List && item.length >= 2 && item[1] is List) {
          final arrowsList = item[1];
          if (arrowsList is List) {
            final arrows = List<int>.from(
              arrowsList.map((arrow) => arrow is num ? arrow.toInt() : 0)
            );
            final seriesNo = item[0] is int ? item[0] : int.tryParse(item[0].toString()) ?? 0;
            numbered.add(MapEntry(seriesNo, arrows));
          }
        } else if (item is Map && item["arrows"] is List) {
          final arrowsList = item["arrows"];
          if (arrowsList is List) {
            final arrows = List<int>.from(
              arrowsList.map((arrow) => arrow is num ? arrow.toInt() : 0)
            );
            final seriesNo = item["seriesNumber"] is int ? item["seriesNumber"] : int.tryParse(item["seriesNumber"].toString()) ?? 0;
            numbered.add(MapEntry(seriesNo, arrows));
          }
        } else if (item is List && item.every((e) => e is num)) {
          // Sırasızsa ekle (en sona)
          numbered.add(MapEntry(9999, List<int>.from(item.map((arrow) => arrow is num ? arrow.toInt() : 0))));
        }
      }
      // Seri numarasına göre sırala
      numbered.sort((a, b) => a.key.compareTo(b.key));
      return numbered.map((e) => e.value).toList();
    } catch (e) {
      print('seriesData çözümleme hatası: $e');
      print('seriesData içeriği: $seriesData');
      return [];
    }
  }

  // Toplam ok sayısı (seriesData üzerinden hesaplanır)
  int get totalArrows {
    try {
      return decodedSeriesData.fold(0, (sum, arrows) => sum + arrows.length);
    } catch (e) {
      print('totalArrows hesaplama hatası: $e');
      return 0;
    }
  }

  // Toplam skor (seriesData üzerinden hesaplanır)
  int get totalScore {
    try {
      return decodedSeriesData.fold(0, (sum, arrows) {
        return sum + arrows.fold(0, (s, v) => s + ((v == -1 || v == 11) ? 10 : v));
      });
    } catch (e) {
      print('totalScore hesaplama hatası: $e');
      return 0;
    }
  }

  // Ortalama skor (seriesData üzerinden hesaplanır)
  double get average {
    try {
      return totalArrows > 0 ? totalScore / totalArrows : 0.0;
    } catch (e) {
      print('average hesaplama hatası: $e');
      return 0.0;
    }
  }

  // X sayısı (11 puan olan oklar)
  int get xCount {
    try {
      return decodedSeriesData.fold(0, (sum, arrows) => sum + arrows.where((v) => v == 11).length);
    } catch (e) {
      print('xCount hesaplama hatası: $e');
      return 0;
    }
  }

  // Yardımcı: JSON'dan alanı oku (int)
  int _getIntField(String key) {
    try {
      final json = toJson();
      final value = json[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      if (value is double) return value.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  // Yardımcı: JSON'dan alanı oku (double)
  double _getDoubleField(String key) {
    try {
      final json = toJson();
      final value = json[key];
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  // copyWith metodu
  TrainingSession copyWith({
    bool? is_deleted,
    String? id,
    String? userId,
    DateTime? date,
    int? distance,
    String? bowType,
    bool? isIndoor,
    String? notes,
    String? training_session_name,
    int? arrowsPerSeries,
    String? seriesData,
    String? trainingType,
  }) {
    return TrainingSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      distance: distance ?? this.distance,
      bowType: bowType ?? this.bowType,
      isIndoor: isIndoor ?? this.isIndoor,
      notes: notes ?? this.notes,
      training_session_name: training_session_name ?? this.training_session_name,
      trainingType: trainingType ?? this.trainingType,
      arrowsPerSeries: arrowsPerSeries ?? this.arrowsPerSeries,
      is_deleted: is_deleted ?? this.is_deleted,
      seriesData: seriesData ?? this.seriesData,
    );
  }
}
