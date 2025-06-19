# Archery OZS - Phase 4: Yarışma Yönetimi Uygulama Rehberi

## 1. Genel Bakış

Phase 4, Archery OZS uygulamasının yarışma yönetimi modülünü oluşturmayı hedeflemektedir. Bu aşamada, öncelikle yarışmalar oluşturulabilecek, katılımcılar kaydedilebilecek ve skorlar takip edilebilecektir. Eleme sistemi daha sonraki bir aşama için planlanacak olup, bu aşamada sadece sıralama yapılacaktır.

### 1.1 Okçuluk Yarışma Sistemi (Hibrit Model)

Bu hibrit sistem, hem sporcular hem de hakemler tarafından skor girişine olanak tanırken, farklı yaş grupları ve yay tipleri için farklı puanlama sistemlerini destekler.

### 1.2 Yaş Grupları ve Mesafeler

| Yaş Grubu | Yaş Aralığı | Recurve Mesafesi | Compound Mesafesi |
|-----------|-------------|------------------|-------------------|
| Büyükler (Senior) | 21 yaş ve üzeri | 70 metre | 50 metre |
| Gençler (Junior) | 18-20 yaş | 70 metre | 50 metre |
| Yıldızlar (Cadet) | 15-17 yaş | 60 metre | 50 metre |
| Minikler A | 13-14 yaş | 30 metre | 40 metre |
| Minikler B | 10-12 yaş | 20 metre | 30 metre |

### 1.3 Puanlama Sistemi

**Recurve Yay (Set Sistemi)**
- Maçlar 5 set üzerinden oynanır
- Her sette 3 ok atılır
- Seti kazanan sporcu 2 puan, beraberlik durumunda her iki sporcu 1 puan alır
- 6 puana ulaşan sporcu maçı kazanır

**Compound Yay (Toplam Skor Sistemi)**
- Sporcular toplam 15 ok (5 tur, her turda 3 ok) atar
- En yüksek toplam puanı alan sporcu kazanır

### 1.4 Takım ve Mix Takım Yarışmaları

- Bireysel Yarışma: Sporcular tek başına yarışır
- Takım Yarışması: 3 kişilik takımlar yarışır
- Mix Takım Yarışması: 1 erkek, 1 kadın sporcu olmak üzere 2 kişilik takımlar yarışır

## 2. Öncelikli Uygulama Adımları

Bu aşamada odaklanacağımız temel özellikler şunlardır:

- Yarışma oluşturma ve yapılandırma
- Katılımcı kayıt ve yönetimi
- Skor girişi ve doğrulama
- Sonuçların hesaplanması ve sıralama
- Raporlama ve sonuç paylaşımı

## 3. Veritabanı Yapısı

Projede kullanılan temel tablolar:

### 3.1 organized_competitions

- organized_competition_id (PK): Yarışma benzersiz ID'si
- name: Yarışma adı
- type: Yarışma türü (Bireysel, Takım, Mix Takım)
- distance: Yarışma mesafesi
- environment: Ortam türü (Indoor, Outdoor)
- start_date: Başlangıç tarihi
- end_date: Bitiş tarihi
- organizing_club_id: Düzenleyen kulüp
- created_by: Oluşturan kullanıcı

### 3.2 organized_competition_participants

- participant_id (PK): Katılımcı benzersiz ID'si
- organized_competition_id: Yarışma ID'si
- athlete_id: Sporcu ID'si
- age_group_id: Yaş grubu
- gender: Cinsiyet
- equipment: Yay tipi
- qualification_rank: Sıralama turu sonrası sıra
- qualification_score: Sıralama turu toplam puanı

### 3.3 organized_scores

- score_id (PK): Skor benzersiz ID'si
- organized_competition_id: Yarışma ID'si
- athlete_id: Sporcu ID'si
- round_number: Tur/set numarası
- score: Puan
- total_score: Toplam puan
- average_score: Ortalama puan
- target_photo: Hedef fotoğrafı
- is_verified: Hakem onayı

## 4. Uygulama Modelleri

- 4.1 Competition Model
- 4.2 CompetitionParticipant Model
- 4.3 Score Model
- 4.4 AgeGroup Model

## 5. Repository Sınıfları

- 5.1 CompetitionRepository
- 5.2 ParticipantRepository
- 5.3 ScoreRepository
- 5.4 AgeGroupRepository

## 6. Service Sınıfları

- 6.1 CompetitionService
- 6.2 ScoringService

## 7. Kullanıcı Arayüzü Ekranları

- 7.1 YarışmaListesiEkranı
- 7.2 YarışmaDetayEkranı
- 7.3 YarışmaSkorGirişiEkranı
- 7.4 SonuçlarEkranı

## 8. Uygulama Adımları Önceliklendirme

### 8.1 Hafta 1: Temel Yapı

**Veritabanı modellerinin oluşturulması**
- Competition, CompetitionParticipant, Score modelleri
- Repository sınıflarının implementasyonu

**Yarışma oluşturma ve listeleme**
- CompetitionService sınıfının geliştirilmesi
- Yarışma listeleme ekranı
- Yarışma oluşturma formu

### 8.2 Hafta 2: Katılımcı Yönetimi

**Katılımcı ekleme**
- Katılımcı yönetimi sınıfları
- Katılımcı ekleme formu
- Kategori yönetimi

**Kategori listeleme ve filtreleme**
- Kategori bazında katılımcı listeleme
- Kategori filtreleme ekranı

### 8.3 Hafta 3: Skor Giriş Sistemi

**Skor giriş ekranı**
- Recurve ve Compound için skor giriş formları
- Ok bazında puan girişi
- Hedef fotoğrafı yükleme

**Skor doğrulama**
- Hakem onayı ekranı
- Uyuşmazlık durumunda karar mekanizması

### 8.4 Hafta 4: Sonuç ve Raporlama

**Sıralama ve sonuç hesaplama**
- Puanlara göre sıralama algoritması
- Kategorilere göre sonuç listeleri

**Sonuç raporlama**
- PDF çıktı alma
- Sonuçları paylaşma
- Madalya sıralaması

## 9. Test Stratejisi

**Birim Testler**
- Repository sınıfları için CRUD testleri
- Service sınıfları için iş mantığı testleri
- Sıralama algoritmasının doğruluğu

**Widget Testleri**
- Form validasyonları
- Skor giriş ekranının davranışı
- Sonuç listeleme ekranı

**Integration Testleri**
- Yarışma oluşturma ve katılımcı ekleme akışı
- Skor girişi ve sıralama oluşturma akışı
- Sonuç raporlama ve paylaşım akışı

## 10. İleri Seviye Özellikler (Gelecek İçin)

**Eleme Sistemi**
- Eleme tablosu algoritması
- Eşleştirmeler ve maç yönetimi
- Turnuva ağacı görselleştirme

**Takım Yarışmaları**
- Takım oluşturma
- Mix takım oluşturma
- Takım puanlarının hesaplanması

**Beraberlik (Tie-Break) Yönetimi**
- Özel atış kaydı
- Merkeze yakınlık ölçümü

Bu rehber, Phase 4 yarışma yönetimi modülünün sıralama odaklı implementasyonu için adım adım bir kılavuz sağlamaktadır. Eleme sistemi bir sonraki aşamada uygulanacak olup, şu aşamada odak sıralama üzerinde olacaktır.
