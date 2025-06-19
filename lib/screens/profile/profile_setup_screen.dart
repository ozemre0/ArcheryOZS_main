import 'package:flutter/material.dart';
import '../../models/profile_model.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_config.dart';
import '../home_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../services/storage_service.dart';
import '../login_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _profileService = ProfileService();
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();
  String _selectedRole = 'viewer';
  String? _selectedGender;
  DateTime? _selectedBirthDate;
  bool _isLoading = false;
  dynamic _selectedImage; // File veya XFile olabilir
  String? _currentPhotoUrl;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedBirthDate = picked);
    }
  }

  Future<void> _selectImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        if (Platform.isAndroid || Platform.isIOS) {
          setState(() => _selectedImage = File(image.path));
        } else {
          setState(() => _selectedImage = image);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).error(e.toString()))),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBirthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).birthDateRequired)),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        String? photoUrl;
        if (_selectedImage != null) {
          photoUrl = await _storageService.uploadProfilePhoto(
            user.id,
            _selectedImage!,
          );
        }
        final profile = Profile(
          id: user.id,
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          role: _selectedRole,
          gender: _selectedGender,
          birthDate: _selectedBirthDate!,
          address: _addressController.text.isNotEmpty ? _addressController.text : null,
          phoneNumber: _phoneController.text.isNotEmpty ? _phoneController.text : null,
          photoUrl: photoUrl,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _profileService.createProfile(profile);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).profileUpdated)),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).error(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signOut() async {
    await SupabaseConfig.client.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final adjustedTextScaleFactor = textScaleFactor > 1.2 ? 1.2 : textScaleFactor;
    final cardBackgroundColor = isDark ? theme.colorScheme.surface : theme.cardColor;
    final sectionTitleColor = isDark ? Colors.white : theme.primaryColor;
    final sectionIconColor = isDark ? theme.primaryColor.withOpacity(0.8) : theme.primaryColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setupProfile),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: l10n.save,
            onPressed: _isLoading ? null : _submitForm,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.signOut,
            onPressed: _signOut,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(size.width * 0.04),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Hoş geldin başlığı ve açıklama
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Column(
                              children: [
                                // Profil fotoğrafı
                                GestureDetector(
                                  onTap: _selectImage,
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: size.width * 0.28,
                                        height: size.width * 0.28,
                                        constraints: const BoxConstraints(
                                          maxWidth: 130,
                                          maxHeight: 130,
                                          minWidth: 100,
                                          minHeight: 100,
                                        ),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: theme.scaffoldBackgroundColor,
                                          border: Border.all(
                                            color: theme.primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                        child: _selectedImage == null && _currentPhotoUrl == null
                                            ? Icon(
                                                Icons.person_outline_rounded,
                                                size: size.width * 0.12,
                                                color: theme.primaryColor,
                                              )
                                            : null,
                                      ),
                                      if (_selectedImage != null || _currentPhotoUrl != null)
                                        Positioned.fill(
                                          child: ClipOval(
                                            child: _selectedImage != null
                                                ? ( _selectedImage is XFile
                                                    ? Image.network(
                                                        (_selectedImage as XFile).path,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : Image.file(
                                                        _selectedImage!,
                                                        fit: BoxFit.cover,
                                                      )
                                                  )
                                                : Image.network(
                                                    _currentPhotoUrl!,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: theme.primaryColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: theme.scaffoldBackgroundColor,
                                              width: 2,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(6.0),
                                            child: Icon(
                                              Icons.camera_alt,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 0, bottom: 20),
                            decoration: BoxDecoration(
                              color: cardBackgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.dividerColor.withOpacity(0.3),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final isWide = constraints.maxWidth > 520;
                                  return isWide
                                      ? Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: _buildNameFields(theme, isDark, l10n)),
                                            const SizedBox(width: 16),
                                            Expanded(child: _buildOtherFields(theme, isDark, l10n)),
                                          ],
                                        )
                                      : Column(
                                          children: [
                                            _buildNameFields(theme, isDark, l10n),
                                            const SizedBox(height: 16),
                                            _buildOtherFields(theme, isDark, l10n),
                                          ],
                                        );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _submitForm,
                              icon: const Icon(Icons.save),
                              label: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(l10n.save),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildNameFields(ThemeData theme, bool isDark, AppLocalizations l10n) {
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;
    return Column(
      children: [
        TextFormField(
          controller: _firstNameController,
          decoration: InputDecoration(
            labelText: l10n.firstName,
            labelStyle: TextStyle(color: hintTextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) => value?.isEmpty ?? true ? l10n.firstNameRequired : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _lastNameController,
          decoration: InputDecoration(
            labelText: l10n.lastName,
            labelStyle: TextStyle(color: hintTextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) => value?.isEmpty ?? true ? l10n.lastNameRequired : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _addressController,
          decoration: InputDecoration(
            labelText: l10n.address,
            labelStyle: TextStyle(color: hintTextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phoneController,
          decoration: InputDecoration(
            labelText: l10n.phoneNumber,
            labelStyle: TextStyle(color: hintTextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          keyboardType: TextInputType.phone,
        ),
      ],
    );
  }

  Widget _buildOtherFields(ThemeData theme, bool isDark, AppLocalizations l10n) {
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _selectedRole,
          decoration: InputDecoration(
            labelText: l10n.role,
            labelStyle: TextStyle(color: hintTextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem(
              value: 'athlete',
              child: Text(l10n.athlete, style: TextStyle(color: textColor)),
            ),
            DropdownMenuItem(
              value: 'coach',
              child: Text(l10n.coach, style: TextStyle(color: textColor)),
            ),
            DropdownMenuItem(
              value: 'viewer',
              child: Text(l10n.viewer, style: TextStyle(color: textColor)),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedRole = value);
            }
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedGender,
          decoration: InputDecoration(
            labelText: l10n.gender,
            labelStyle: TextStyle(color: hintTextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem(
              value: 'male',
              child: Text(l10n.male, style: TextStyle(color: textColor)),
            ),
            DropdownMenuItem(
              value: 'female',
              child: Text(l10n.female, style: TextStyle(color: textColor)),
            ),
          ],
          onChanged: (value) {
            setState(() => _selectedGender = value);
          },
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () => _selectDate(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 20, color: hintTextColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.birthDate, style: theme.textTheme.bodyMedium?.copyWith(color: hintTextColor)),
                      const SizedBox(height: 4),
                      Text(
                        _selectedBirthDate != null
                            ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/${_selectedBirthDate!.year}'
                            : l10n.dateNotSelected,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: _selectedBirthDate != null ? FontWeight.bold : FontWeight.normal,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: hintTextColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
