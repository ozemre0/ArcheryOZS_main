# Simple Archery App Implementation Guide

## Genel Bakış
Bu dokuman, Simple Archery uygulamasının geliştirilme sürecini aşama aşama detaylandırır. Her aşama, bağımsız olarak geliştirilebilir ve test edilebilir modüller halinde düzenlenmiştir.

## Faz 1: Temel Altyapı (2 Hafta)

### 1.1 Proje Kurulumu
- Flutter projesinin oluşturulması
- Supabase bağlantısının kurulması
- Gerekli paketlerin eklenmesi:
  ```yaml
  dependencies:
    supabase_flutter: ^latest
    flutter_riverpod: ^latest
    go_router: ^latest
    cached_network_image: ^latest
    flutter_secure_storage: ^latest
    intl: ^latest
  ```

### 1.2 Proje Yapısı
```
lib/
├── core/
│   ├── constants/
│   ├── theme/
│   └── utils/
├── features/
│   ├── auth/
│   ├── profile/
│   ├── training/
│   └── competition/
├── shared/
│   ├── widgets/
│   └── models/
└── main.dart
```

### 1.3 Temel Authentication
- Google/Apple Sign-in entegrasyonu
- Email/Password authentication
- Role-based yetkilendirme sistemi
- Token yönetimi

## Faz 2: Kullanıcı Profil Sistemi (2 Hafta)

### 2.1 Profil Veri Modeli
```dart
class Profile {
  final String id;
  final String firstName;
  final String lastName;
  final String role;  // athlete, coach, viewer, admin
  final String? clubId;
  final DateTime createdAt;
  // ... diğer alanlar
}
```

### 2.2 Kayıt Akışı
1. Temel bilgi formu
2. Rol seçimi
3. Kulüp/antrenör bağlantısı (opsiyonel)
4. Profil fotoğrafı yükleme

### 2.3 Profil Yönetimi
- Profil görüntüleme/düzenleme
- ID yönetimi
- Bağlantı istekleri

## Faz 3: Antrenman Sistemi (3 Hafta)

### 3.1 Antrenman Kayıt
```dart
class Training {
  final String id;
  final String athleteId;
  final DateTime date;
  final int distance;
  final int arrowsShot;
  final int score;
  final String? notes;
}
```

### 3.2 Özellikler
- Antrenman oluşturma formu
- Skor takibi
- Fotoğraf yükleme(antrenman esnasında isteğe bağlı fotoğraf yükleyebilirz)
- Not ekleme

### 3.3 Görüntüleme ve Analiz
- Takvim görünümü
- Liste görünümü
- Performans grafikleri
- İstatistikler
- Antrenör sporcularının istatistiklerini görmeli

## Faz 4: Yarışma Sistemi (4 Hafta)

### 4.1 Yarışma Oluşturma
```dart
class Competition {
  final String id;
  final String name;
  final String organizingClubId;
  final DateTime startDate;
  final DateTime endDate;
  final String type;
  final int distance;
}
```

### 4.2 Eleme Sistemi Algoritması
```dart
class EliminationSystem {
  // Katılımcı sayısına göre tur hesaplama
  int calculateRounds(int participantCount) {
    return (log(participantCount) / log(2)).ceil();
  }
  
  // Bay geçme hesaplama
  int calculateByes(int participantCount) {
    int nextPowerOfTwo = pow(2, calculateRounds(participantCount)).toInt();
    return nextPowerOfTwo - participantCount;
  }
  
  // Eşleştirme oluşturma
  List<Match> createMatches(List<Participant> participants) {
    // 1vs32, 2vs31, etc. mantığıyla eşleştirme
  }
}
```

### 4.3 Yarışma Yönetimi
- Katılımcı yönetimi
- Skor girişi
- Eleme tablosu görüntüleme
- Sonuç raporlama

## Faz 5: Kulüp ve Mesajlaşma (3 Hafta)

### 5.1 Kulüp Yönetimi
- Üyelik sistemi
- Antrenör-sporcu eşleştirme
- Ödeme takibi

### 5.2 Mesajlaşma
- Bireysel chat
- Grup mesajlaşma
- Duyuru sistemi

## Test Stratejisi

### Birim Testler
```dart
void main() {
  group('EliminationSystem Tests', () {
    test('should calculate correct number of rounds', () {
      final system = EliminationSystem();
      expect(system.calculateRounds(7), 3); // 8 için 3 tur
      expect(system.calculateRounds(9), 4); // 16 için 4 tur
    });
  });
}
```

### Widget Testleri
- Temel UI bileşenleri
- Form validasyonları
- Navigasyon

### Integration Testleri
- Authentication akışı
- Yarışma oluşturma
- Skor girişi

## Güvenlik Kontrol Listesi
- [ ] Tüm API endpointleri için yetkilendirme
- [ ] Input validasyonu
- [ ] Güvenli dosya yükleme
- [ ] Token yönetimi
- [ ] Rol tabanlı erişim kontrolü

## Performans Optimizasyonu
- Lazy loading implementasyonu
- Image caching
- Pagination
- Offline destek

## Dağıtım Planı
1. Alpha sürümü (Temel özellikler)
2. Beta sürümü (Tüm özellikler)
3. Production sürümü

Her faz için detaylı teknik dokümantasyon ve API referansları ayrıca sağlanacaktır.
