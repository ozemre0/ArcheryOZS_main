# ArcheryOZS

**ArcheryOZS** is a modern and comprehensive mobile application developed for archery training and performance tracking. It digitizes the training process for coaches and athletes, providing advanced analysis and reporting capabilities.

---

## 🎯 Project Purpose

ArcheryOZS aims to make archery training more **efficient**, **systematic**, and **data-driven**. It helps athletes and coaches:
- Analyze performance,
- Access past training sessions,
- Monitor progress over time.

---

## 🔑 Key Features

- 👤 User management (athlete/coach roles)  
- 📝 Create & save training sessions  
- 📊 Training history and performance statistics  
- 🎯 Target and score tracking  
- 🌐 Multi-language support (fully localized with `l10n`)  
- 🎨 Modern and responsive UI (dark/light theme)  
- 🔐 Secure login & authentication  
- ☁️ Cloud-based data sync (Supabase)  

---

## 🛠️ Technical Details

- **Platform:** Flutter (cross-platform)  
- **Backend:** Supabase (or Firebase, optionally)  
- **Database:** PostgreSQL (via Supabase)  
- **State Management:** Riverpod / Provider  
- **Localization:** `l10n` (no hardcoded strings)  
- **Responsive Design:** Fully adaptive for all screen sizes  

---

## 🧱 Project Architecture

- lib/
├── l10n/                # Localization files
├── models/              # Data models
├── providers/           # State management
├── screens/             # All UI screens
├── services/            # API and data services
├── widgets/             # Reusable widgets
└── main.dart            # Entry point
- Clean Architecture principles  
- Layered structure (`presentation`, `domain`, `data`)  
- Service and data layers are clearly separated  
- All strings handled via `l10n` (no hardcoded UI text)  
- Application starts from `main.dart`
---

## 🚀 Installation & Run

Make sure you have **Flutter** and **Dart SDK** installed.

```bash
flutter pub get
flutter run
