import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/profile_model.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_config.dart';
import '../coach/coach_athlete_list_screen.dart';
import 'profile_setup_screen.dart';
import 'edit_profile_screen.dart';
import '../home_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _profileService = ProfileService();
  Profile? _profile;
  final Key _avatarKey = UniqueKey();
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadCachedProfile();
  }

  // Sadece cache'den profil verilerini yükle
  Future<void> _loadCachedProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      final profile = await _profileService.getCachedProfile(user.id);
      if (mounted) {
        setState(() {
          _profile = profile;
          _isOffline = false;
        });

        // İnternet kontrolünü geciktirerek yapıyoruz
        Future.delayed(const Duration(milliseconds: 500), () {
          _checkOnlineProfile();
        });
      }
    }
  }

  // Arka planda online profil kontrolü yap
  Future<void> _checkOnlineProfile() async {
    if (!mounted) return;

    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      try {
        final profile = await _profileService.getProfile(user.id);
        if (mounted) {
          if (profile == null) {
            // Profil bulunamadıysa ProfileSetupScreen'e yönlendir
            _navigateToProfileSetup();
          } else {
            setState(() {
              _profile = profile;
              _isOffline = false;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isOffline = true;
          });
        }
      }
    }
  }

  // Profil kurulum ekranına yönlendir
  void _navigateToProfileSetup() {
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (context) => const ProfileSetupScreen()));
  }

  // Manuel yenileme için
  Future<void> _loadProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      try {
        final profile = await _profileService.getProfile(user.id);
        if (mounted) {
          if (profile == null) {
            // Profil bulunamadıysa ProfileSetupScreen'e yönlendir
            _navigateToProfileSetup();
          } else {
            setState(() {
              _profile = profile;
              _isOffline = false;
            });
          }
        }
      } catch (e) {
        setState(() {
          _isOffline = true;
        });
      }
    }
  }

  Widget _buildPhoneNumberTile(String phoneNumber) {
    return ListTile(
      leading: const Icon(Icons.phone),
      title: Text(phoneNumber),
      subtitle: Text(AppLocalizations.of(context).phoneNumber),
      trailing: IconButton(
        icon: const Icon(Icons.content_copy),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: phoneNumber));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).phoneNumberCopied),
            ),
          );
        },
      ),
    );
  }

  String _getGenderDisplay(String? gender) {
    final l10n = AppLocalizations.of(context);
    if (gender == null) return '';
    switch (gender.toLowerCase()) {
      case 'male':
        return l10n.male;
      case 'female':
        return l10n.female;
      default:
        return gender;
    }
  }

  // Show enlarged profile photo (WhatsApp/Instagram style)
  void _showEnlargedPhoto(BuildContext context, String imageUrl) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Profile Photo',
      barrierColor: Colors.black.withOpacity(0.7), // semi-transparent background
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Stack(
            children: [
              Center(
                child: Hero(
                  tag: 'profile_photo_${_profile?.id}',
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: MediaQuery.of(context).size.width * 0.7,
                      height: MediaQuery.of(context).size.width * 0.7,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: MediaQuery.of(context).size.width * 0.7,
                        height: MediaQuery.of(context).size.width * 0.7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey,
                        ),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: MediaQuery.of(context).size.width * 0.7,
                        height: MediaQuery.of(context).size.width * 0.7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey,
                        ),
                        child: const Icon(Icons.error_outline, color: Colors.white, size: 50),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 32,
                right: 32,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = SupabaseConfig.client.auth.currentUser;

    // Sadece cache'de veri yoksa loading göster
    if (_profile == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: Scrollbar(
          thumbVisibility: true,
          thickness: 6,
          radius: const Radius.circular(10),
          interactive: true,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // Profil Fotoğrafı - Tıklanabilir ve büyütülebilir
              Center(
                child: GestureDetector(
                  onTap: () {
                    if (_profile?.photoUrl != null && !_isOffline) {
                      _showEnlargedPhoto(context, _profile!.photoUrl!);
                    }
                  },
                  child: Hero(
                    tag: 'profile_photo_${_profile?.id}',
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: _profile?.photoUrl != null && !_isOffline
                            ? Border.all(
                                color: Theme.of(context).primaryColor.withOpacity(0.3),
                                width: 2,
                              )
                            : null,
                      ),
                      child: ClipOval(
                        child: _profile?.photoUrl != null && !_isOffline
                            ? CachedNetworkImage(
                                imageUrl: _profile!.photoUrl!,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: 100,
                                  height: 100,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey[300],
                                  ),
                                  child: const Icon(
                                    Icons.person, 
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : const CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.grey,
                                child: Icon(Icons.person, size: 50),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${_profile?.firstName} ${_profile?.lastName}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 24),

              // Role ve Cinsiyet Bilgisi
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.roleLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text(_getRoleDisplay(_profile!.role)),
                        ],
                      ),
                      if (_profile?.gender != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              l10n.genderLabel,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Text(_getGenderDisplay(_profile!.gender)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (_profile?.visibleId != null && _profile!.visibleId!.isNotEmpty) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]?.withOpacity(0.22)
                          : Colors.grey.withOpacity(0.22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _profile!.visibleId!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.profileIdCopied)),
                            );
                          },
                          child: Icon(Icons.content_copy, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Profile ID: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          _profile!.visibleId!,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Contact Information section
              if (_profile?.address != null ||
                  _profile?.phoneNumber != null ||
                  user?.email != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      l10n.contactInfo,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
                const Divider(),

                // Show email if available
                if (user?.email != null)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: const Icon(Icons.email),
                      title: Text(user!.email!),
                      subtitle: Text(l10n.emailLabel),
                    ),
                  ),

                // Show address if available
                if (_profile?.address != null)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(_profile!.address!),
                      subtitle: Text(l10n.address),
                    ),
                  ),

                // Show phone number if available
                if (_profile?.phoneNumber != null)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: _buildPhoneNumberTile(_profile!.phoneNumber!),
                  ),
              ],

              const SizedBox(height: 32),
              if (_profile?.role == 'athlete' ||
                  _profile?.role == 'coach') ...[
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CoachAthleteListScreen(
                          args: CoachAthleteListArgs(
                              userRole: _profile!.role),
                        ),
                      ),
                    );
                  },
                  icon: Icon(_profile?.role == 'athlete'
                      ? Icons.sports
                      : Icons.people),
                  label: Text(_profile?.role == 'athlete'
                      ? l10n.myCoaches
                      : l10n.myAthletes),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: _isOffline
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.profileUpdateError),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    : () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EditProfileScreen(profile: _profile!),
                          ),
                        );
                        if (result == true) {
                          _loadProfile();
                        }
                      },
                icon: const Icon(Icons.edit),
                label: Text(l10n.editProfile),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isOffline
                    ? null
                    : () {
                        _showSetPasswordDialog(context, l10n);
                      },
                icon: const Icon(Icons.lock_outline),
                label: Text(l10n.setPassword),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required String title, required String value}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(value),
          ],
        ),
      ),
    );
  }

  String _getRoleDisplay(String role) {
    final l10n = AppLocalizations.of(context);

    switch (role) {
      case 'athlete':
        return l10n.athlete;
      case 'coach':
        return l10n.coach;
      case 'viewer':
        return l10n.viewer;
      case 'admin':
        return 'Admin';
      default:
        return role;
    }
  }

  void _showSetPasswordDialog(BuildContext context, AppLocalizations l10n) {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.setPasswordTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.setPasswordNew,
                    prefixIcon: const Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.setPasswordConfirm,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPassword = newPasswordController.text.trim();
                final confirmPassword = confirmPasswordController.text.trim();
                if (newPassword != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.setPasswordMismatch)),
                  );
                  return;
                }
                // Show confirmation dialog (larger)
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => Dialog(
                    insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.8,
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.lock, size: 48, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 24),
                          Text(
                            l10n.confirmPasswordChangeTitle ?? 'Confirm Password Change',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.confirmPasswordChangeContent ?? 'Are you sure you want to change your password?',
                            style: const TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: Text(l10n.cancel, style: const TextStyle(fontSize: 16)),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: Text(l10n.setPasswordSave, style: const TextStyle(fontSize: 16)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                if (confirm != true) return;
                try {
                  // Supabase password update
                  final user = await SupabaseConfig.client.auth.updateUser(
                    UserAttributes(password: newPassword),
                  );
                  if (user.user != null) {
                    if (context.mounted) {
                      Navigator.of(context).pop(); // Close password dialog
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.setPasswordSuccess)),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.setPasswordError)),
                      );
                    }
                  }
                } catch (e) {
                  // Check if password was actually changed by trying to sign in with the new password
                  try {
                    final email = SupabaseConfig.client.auth.currentUser?.email;
                    if (email != null) {
                      final response = await SupabaseConfig.client.auth.signInWithPassword(
                        email: email,
                        password: newPassword,
                      );
                      if (response.user != null) {
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.setPasswordSuccess)),
                          );
                        }
                        return;
                      }
                    }
                  } catch (_) {}
                  if (context.mounted) {
                    String errorMsg = l10n.setPasswordError;
                    if (e is AuthException && e.message.isNotEmpty) {
                      errorMsg += ' (${e.message})';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(errorMsg)),
                    );
                  }
                }
              },
              child: Text(l10n.setPasswordSave),
            ),
          ],
        );
      },
    );
  }
}
