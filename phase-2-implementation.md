# Phase 2: User Profile System Implementation Guide

## Directory Structure Updates

Add the following directories and files to your current structure:

```
lib/
├── models/
│   ├── profile_model.dart
│   └── role_model.dart
├── screens/
│   ├── profile/
│   │   ├── profile_screen.dart
│   │   ├── edit_profile_screen.dart
│   │   ├── profile_setup_screen.dart
│   │   └── widgets/
│   │       ├── profile_avatar.dart
│   │       ├── profile_info_card.dart
│   │       └── role_selection_card.dart
├── services/
│   ├── profile_service.dart
│   ├── storage_service.dart
│   └── auth_service.dart
├── providers/
│   └── profile_provider.dart
└── utils/
    ├── validators.dart
    └── constants.dart
```

## Core Components Implementation

### 1. Models

**models/profile_model.dart**
```dart
class Profile {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String role;
  final String? clubId;
  final String? coachId;
  final String? photo;
  final DateTime dateOfBirth;
  final String gender;
  final String? nationality;
  final String? address;
  final String? city;
  final String? country;
  final String? phoneNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Constructor and fromJson/toJson methods
}
```

**models/role_model.dart**
```dart
enum UserRole {
  athlete,
  coach,
  viewer,
  admin
}

extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.athlete: return 'Sporcu';
      case UserRole.coach: return 'Antrenör';
      case UserRole.viewer: return 'İzleyici';
      case UserRole.admin: return 'Admin';
    }
  }
}
```

### 2. Services

**services/profile_service.dart**
```dart
class ProfileService {
  final SupabaseClient _supabase;

  Future<Profile> createProfile(Profile profile) async {
    // Implementation for creating profile in Supabase
  }

  Future<Profile> updateProfile(Profile profile) async {
    // Implementation for updating profile
  }

  Future<Profile?> getProfile(String userId) async {
    // Implementation for fetching profile
  }

  Future<String> uploadProfilePhoto(File photo, String userId) async {
    // Implementation for photo upload
  }
}
```

**services/storage_service.dart**
```dart
class StorageService {
  final SupabaseClient _supabase;

  Future<String> uploadFile(File file, String path) async {
    // Implementation for file upload to Supabase storage
  }

  Future<void> deleteFile(String path) async {
    // Implementation for file deletion
  }
}
```

### 3. Providers

**providers/profile_provider.dart**
```dart
final profileProvider = StateNotifierProvider<ProfileNotifier, AsyncValue<Profile>>((ref) {
  return ProfileNotifier(ref.watch(profileServiceProvider));
});

class ProfileNotifier extends StateNotifier<AsyncValue<Profile>> {
  final ProfileService _profileService;

  // Implementation of profile state management
}
```

### 4. Screens

**screens/profile/profile_setup_screen.dart**
```dart
class ProfileSetupScreen extends ConsumerStatefulWidget {
  // Multi-step profile setup implementation
  // 1. Basic Info
  // 2. Role Selection
  // 3. Additional Info based on role
  // 4. Photo Upload
}
```

**screens/profile/profile_screen.dart**
```dart
class ProfileScreen extends ConsumerWidget {
  // Profile view implementation
  // - Display user info
  // - Show stats and connections
  // - Edit profile button
}
```

**screens/profile/edit_profile_screen.dart**
```dart
class EditProfileScreen extends ConsumerStatefulWidget {
  // Profile editing implementation
  // - Form for all editable fields
  // - Photo update
  // - Save functionality
}
```

## Implementation Steps

1. **Database Setup**
   - Ensure all required columns exist in the profiles table
   - Set up proper indexes and constraints
   - Configure storage buckets for profile photos

2. **Models and Services**
   - Implement all models with proper serialization
   - Create services with error handling
   - Set up storage service for file handling

3. **State Management**
   - Configure providers for profile management
   - Implement state updates and caching
   - Handle loading and error states

4. **UI Implementation**
   - Create reusable widgets for profile components
   - Implement step-by-step profile setup flow
   - Add profile viewing and editing screens

5. **Validation and Error Handling**
   - Implement input validation
   - Add error messages and handling
   - Create loading states and indicators

## Testing Checklist

- [ ] Profile creation flow
- [ ] Profile update functionality
- [ ] Photo upload and update
- [ ] Role-based field validation
- [ ] Error handling scenarios
- [ ] Loading states
- [ ] Form validation
- [ ] Navigation flow

## Security Considerations

1. Implement proper access control for profile updates
2. Validate file uploads (size, type, etc.)
3. Sanitize user inputs
4. Secure storage of sensitive information

## Next Steps

After implementing these components:
1. Test the complete profile flow
2. Implement connection with Club system
3. Add role-specific features
4. Implement profile completion tracking
