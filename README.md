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
## Uygulama Ekran Görüntüsü

<img src="https://github.com/user-attachments/assets/8eb704c7-cb10-4d82-9820-7da563fa5939" alt="600" width="300"/>
<img src="https://github.com/user-attachments/assets/b9d95904-e3c9-4179-9a32-30bc9138f78c" alt="Image" width="300"/>
<img src="https://github.com/user-attachments/assets/ef804743-6f31-44e5-9929-fa05b1c09a0e" alt="Image" width="300"/>
<img src="https://github.com/user-attachments/assets/a3fe590a-4207-4ea7-8513-a1d0e90fc25f" alt="Image" width="300"/>
<img src="https://github.com/user-attachments/assets/ab3eb46d-8cfc-41f7-9307-3db4d687bcb4" alt="Image" width="300"/>
<img src="https://github.com/user-attachments/assets/55016d57-957a-48fa-beb7-08c03cb91503" alt="Image" width="300"/>
<img src="https://github.com/user-attachments/assets/bbb18a14-a5d0-4685-8cfa-546a7abeed0c" alt="Image" width="300"/>
<img src="https://github.com/user-attachments/assets/ce3a8a47-13b3-4c39-8447-8550e85b56b5" alt="Image" width="300"/>

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
