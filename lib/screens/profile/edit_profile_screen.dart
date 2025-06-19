import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';
import '../../models/profile_model.dart';
import '../../services/profile_service.dart';
import '../../services/storage_service.dart';

class EditProfileScreen extends StatefulWidget {
  final Profile? profile;

  const EditProfileScreen({super.key, this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = ProfileService();
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneNumberController;
  String _selectedRole = 'viewer';
  DateTime? _selectedBirthDate;
  bool _isLoading = false;
  dynamic _selectedImage; // File veya XFile olabilir
  String? _currentPhotoUrl;
  PhoneNumber _phoneNumber = PhoneNumber(isoCode: 'TR');
  String? _selectedGender;

  final Map<String, Map<String, String>> _countryCodes = {
    // European Countries
    "AL": {"code": "+355", "flag": "🇦🇱", "name": "Albania"},
    "AD": {"code": "+376", "flag": "🇦🇩", "name": "Andorra"},
    "AT": {"code": "+43", "flag": "🇦🇹", "name": "Austria"},
    "BY": {"code": "+375", "flag": "🇧🇾", "name": "Belarus"},
    "BE": {"code": "+32", "flag": "🇧🇪", "name": "Belgium"},
    "BA": {"code": "+387", "flag": "🇧🇦", "name": "Bosnia and Herzegovina"},
    "BG": {"code": "+359", "flag": "🇧🇬", "name": "Bulgaria"},
    "HR": {"code": "+385", "flag": "🇭🇷", "name": "Croatia"},
    "CY": {"code": "+357", "flag": "🇨🇾", "name": "Cyprus"},
    "CZ": {"code": "+420", "flag": "🇨🇿", "name": "Czech Republic"},
    "DK": {"code": "+45", "flag": "🇩🇰", "name": "Denmark"},
    "EE": {"code": "+372", "flag": "🇪🇪", "name": "Estonia"},
    "FI": {"code": "+358", "flag": "🇫🇮", "name": "Finland"},
    "FR": {"code": "+33", "flag": "🇫🇷", "name": "France"},
    "DE": {"code": "+49", "flag": "🇩🇪", "name": "Germany"},
    "GR": {"code": "+30", "flag": "🇬🇷", "name": "Greece"},
    "HU": {"code": "+36", "flag": "🇭🇺", "name": "Hungary"},
    "IS": {"code": "+354", "flag": "🇮🇸", "name": "Iceland"},
    "IE": {"code": "+353", "flag": "🇮🇪", "name": "Ireland"},
    "IT": {"code": "+39", "flag": "🇮🇹", "name": "Italy"},
    "XK": {"code": "+383", "flag": "🇽🇰", "name": "Kosovo"},
    "LV": {"code": "+371", "flag": "🇱🇻", "name": "Latvia"},
    "LI": {"code": "+423", "flag": "🇱🇮", "name": "Liechtenstein"},
    "LT": {"code": "+370", "flag": "🇱🇹", "name": "Lithuania"},
    "LU": {"code": "+352", "flag": "🇱🇺", "name": "Luxembourg"},
    "MT": {"code": "+356", "flag": "🇲🇹", "name": "Malta"},
    "MD": {"code": "+373", "flag": "🇲🇩", "name": "Moldova"},
    "MC": {"code": "+377", "flag": "🇲🇨", "name": "Monaco"},
    "ME": {"code": "+382", "flag": "🇲🇪", "name": "Montenegro"},
    "NL": {"code": "+31", "flag": "🇳🇱", "name": "Netherlands"},
    "MK": {"code": "+389", "flag": "🇲🇰", "name": "North Macedonia"},
    "NO": {"code": "+47", "flag": "🇳🇴", "name": "Norway"},
    "PL": {"code": "+48", "flag": "🇵🇱", "name": "Poland"},
    "PT": {"code": "+351", "flag": "🇵🇹", "name": "Portugal"},
    "RO": {"code": "+40", "flag": "🇷🇴", "name": "Romania"},
    "RU": {"code": "+7", "flag": "🇷🇺", "name": "Russia"},
    "SM": {"code": "+378", "flag": "🇸🇲", "name": "San Marino"},
    "RS": {"code": "+381", "flag": "🇷🇸", "name": "Serbia"},
    "SK": {"code": "+421", "flag": "🇸🇰", "name": "Slovakia"},
    "SI": {"code": "+386", "flag": "🇸🇮", "name": "Slovenia"},
    "ES": {"code": "+34", "flag": "🇪🇸", "name": "Spain"},
    "SE": {"code": "+46", "flag": "🇸🇪", "name": "Sweden"},
    "CH": {"code": "+41", "flag": "🇨🇭", "name": "Switzerland"},
    "TR": {"code": "+90", "flag": "🇹🇷", "name": "Turkey"},
    "UA": {"code": "+380", "flag": "🇺🇦", "name": "Ukraine"},
    "UK": {"code": "+44", "flag": "🇬🇧", "name": "United Kingdom"},
    "VA": {"code": "+379", "flag": "🇻🇦", "name": "Vatican City"},

    // Other Important Countries
    "US": {"code": "+1", "flag": "🇺🇸", "name": "United States"},
    "CA": {"code": "+1", "flag": "🇨🇦", "name": "Canada"},
    "BR": {"code": "+55", "flag": "🇧🇷", "name": "Brazil"},
    "CN": {"code": "+86", "flag": "🇨🇳", "name": "China"},
    "IN": {"code": "+91", "flag": "🇮🇳", "name": "India"},
    "JP": {"code": "+81", "flag": "🇯🇵", "name": "Japan"},
    "KR": {"code": "+82", "flag": "🇰🇷", "name": "South Korea"},
    "AU": {"code": "+61", "flag": "🇦🇺", "name": "Australia"},
    "NZ": {"code": "+64", "flag": "🇳🇿", "name": "New Zealand"},
  };

  @override
  void initState() {
    super.initState();
    _firstNameController =
        TextEditingController(text: widget.profile?.firstName);
    _lastNameController = TextEditingController(text: widget.profile?.lastName);
    _addressController = TextEditingController(text: widget.profile?.address);
    _phoneNumberController = TextEditingController();
    _selectedRole = widget.profile?.role ?? 'viewer';
    _selectedBirthDate = widget.profile?.birthDate;
    _currentPhotoUrl = widget.profile?.photoUrl;
    _selectedGender = widget.profile?.gender ??
        _selectedGender; // Cinsiyet seçimini düzgün atama

    // Initialize phone number from existing profile
    if (widget.profile?.phoneNumber != null) {
      final phoneStr = widget.profile!.phoneNumber!;
      if (phoneStr.startsWith('+')) {
        final spaceIndex = phoneStr.indexOf(' ');
        if (spaceIndex > 0) {
          final dialCode =
              phoneStr.substring(0, spaceIndex); // Keep the '+' prefix
          final number = phoneStr.substring(spaceIndex + 1);
          _phoneNumberController.text = number;

          // Find the matching country code
          String? foundIsoCode;
          for (var entry in _countryCodes.entries) {
            if (entry.value["code"] == dialCode) {
              foundIsoCode = entry.key;
              break;
            }
          }

          _phoneNumber = PhoneNumber(
              phoneNumber: number,
              dialCode: dialCode.substring(1), // Remove '+' for dialCode
              isoCode: foundIsoCode ?? 'TR');
        }
      }
    } else {
      // Set default phone number settings
      _phoneNumber =
          PhoneNumber(phoneNumber: '', dialCode: "90", isoCode: 'TR');
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
        if (kIsWeb) {
          // Web platformunda doğrudan XFile kullanılabilir
          setState(() => _selectedImage = image);
        } else {
          // Mobil platformlarda File nesnesi kullanılır
          setState(() => _selectedImage = File(image.path));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).error(e.toString()))),
        );
      }
    }
  }

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

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBirthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).birthDateRequired)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? photoUrl = _currentPhotoUrl;

      if (_selectedImage != null) {
        photoUrl = await _storageService.uploadProfilePhoto(
          widget.profile!.id,
          _selectedImage!,
        );
      }

      // Handle phone number formatting
      String? phoneNumber;
      if (_phoneNumberController.text.isNotEmpty) {
        final cleanNumber = _phoneNumberController.text.trim();
        // Find the country code with + prefix
        String countryCode = _countryCodes.entries
            .firstWhere((entry) =>
                entry.value["code"]!.replaceAll("+", "") ==
                _phoneNumber.dialCode)
            .value["code"]!;

        // Ensure the phone number format is consistent
        phoneNumber = '$countryCode $cleanNumber';
      }

      final updatedProfile = widget.profile?.copyWith(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        role: _selectedRole,
        birthDate: _selectedBirthDate,
        photoUrl: photoUrl,
        address:
            _addressController.text.isEmpty ? null : _addressController.text,
        phoneNumber: phoneNumber,
        gender: _selectedGender,
        updatedAt: DateTime.now(),
      );

      if (updatedProfile != null) {
        await _profileService.updateProfile(updatedProfile);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context).profileUpdated)),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        // İnternet bağlantısı hatası olup olmadığını kontrol et
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('socket') ||
            errorStr.contains('connection') ||
            errorStr.contains('network') ||
            errorStr.contains('failed host lookup')) {
          // İnternet bağlantısı hatası
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).profileUpdateError),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          // Diğer hatalar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).error(e.toString())),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Country dropdown with improved overflow handling
  Widget _buildCountryDropdown(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? theme.colorScheme.surface : theme.cardColor;
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField<String>(
        value: _getSelectedCountryValue(),
        items: _getCountryItems(),
        onChanged: (value) {
          if (value != null) {
            final parts = value.split('_');
            final iso = parts[1];
            final selectedCountry = _countryCodes[iso]!;
            setState(() {
              _phoneNumber = PhoneNumber(
                phoneNumber: _phoneNumberController.text,
                dialCode: selectedCountry["code"]!.replaceAll("+", ""),
                isoCode: iso,
              );
            });
          }
        },
        style: TextStyle(color: textColor),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
        icon: Icon(
          Icons.arrow_drop_down, 
          size: 24,
          color: hintTextColor,
        ),
        isExpanded: true,
        dropdownColor: cardColor,
        isDense: true,
        itemHeight: 50,
      ),
    );
  }
  
  // Modified country items method to handle overflow better
  List<DropdownMenuItem<String>> _getCountryItems() {
    var entries = _countryCodes.entries.toList();
    entries.sort((a, b) => a.value["name"]!.compareTo(b.value["name"]!));
    return entries.map<DropdownMenuItem<String>>((entry) {
      final value = entry.value["code"]!.replaceAll("+", "") + "_" + entry.key;
      return DropdownMenuItem(
        value: value,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.value["flag"]!,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "${entry.value["name"]} (${entry.value["code"]})",
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  String? _getSelectedCountryValue() {
    if (_phoneNumber.dialCode == null || _phoneNumber.isoCode == null) return null;
    return _phoneNumber.dialCode!.replaceAll("+", "") + "_" + _phoneNumber.isoCode!;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    // Limit text scale factor to prevent overflow
    final adjustedTextScaleFactor = textScaleFactor > 1.2 ? 1.2 : textScaleFactor;
    
    // Define colors for better dark theme support
    final sectionTitleColor = isDark ? Colors.white : theme.primaryColor;
    final sectionIconColor = isDark ? theme.primaryColor.withOpacity(0.8) : theme.primaryColor;
    final cardBackgroundColor = isDark ? theme.colorScheme.surface : theme.cardColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.editProfile,
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 2,
        centerTitle: true,
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: l10n.save,
                onPressed: _saveProfile,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: theme.primaryColor,
              ),
            )
          : SafeArea(
              child: GestureDetector(
                onTap: () {
                  // Dismiss keyboard when tapping outside input fields
                  FocusScope.of(context).unfocus();
                },
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(size.width * 0.04),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Profile Image
                          Align(
                            alignment: Alignment.center,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: GestureDetector(
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
                                              ? kIsWeb
                                                  ? Image.network(
                                                      (_selectedImage as XFile).path,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : Image.file(
                                                      _selectedImage!,
                                                      fit: BoxFit.cover,
                                                    )
                                              : FadeInImage.memoryNetwork(
                                                  placeholder: kTransparentImage,
                                                  image: _currentPhotoUrl!,
                                                  fit: BoxFit.cover,
                                                  imageErrorBuilder: (context, error, stackTrace) {
                                                    return Icon(
                                                      Icons.error_outline,
                                                      size: size.width * 0.12,
                                                      color: theme.colorScheme.error,
                                                    );
                                                  },
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
                                            color: Colors.white, // Koyu temada daima beyaz
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Personal Information Section
                          Container(
                            margin: const EdgeInsets.only(top: 0, bottom: 20), // Üstte ve altta boşluk
                            decoration: BoxDecoration(
                              color: cardBackgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.dividerColor.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_outline,
                                        color: sectionIconColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          l10n.personalInfo,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: sectionTitleColor,
                                          ) ?? TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: sectionTitleColor,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(height: 1, color: theme.dividerColor),
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      // First & Last Name
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          if (constraints.maxWidth > 520) {
                                            return Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: _buildTextField(
                                                    controller: _firstNameController,
                                                    label: l10n.firstName,
                                                    icon: Icons.person_outline,
                                                    validator: (value) => value?.isEmpty ?? true
                                                        ? l10n.firstNameRequired
                                                        : null,
                                                    theme: theme,
                                                    isDark: isDark,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: _buildTextField(
                                                    controller: _lastNameController,
                                                    label: l10n.lastName,
                                                    icon: Icons.person_outline,
                                                    validator: (value) => value?.isEmpty ?? true
                                                        ? l10n.lastNameRequired
                                                        : null,
                                                    theme: theme,
                                                    isDark: isDark,
                                                  ),
                                                ),
                                              ],
                                            );
                                          } else {
                                            return Column(
                                              children: [
                                                _buildTextField(
                                                  controller: _firstNameController,
                                                  label: l10n.firstName,
                                                  icon: Icons.person_outline,
                                                  validator: (value) => value?.isEmpty ?? true
                                                      ? l10n.firstNameRequired
                                                      : null,
                                                  theme: theme,
                                                  isDark: isDark,
                                                ),
                                                const SizedBox(height: 12),
                                                _buildTextField(
                                                  controller: _lastNameController,
                                                  label: l10n.lastName,
                                                  icon: Icons.person_outline,
                                                  validator: (value) => value?.isEmpty ?? true
                                                      ? l10n.lastNameRequired
                                                      : null,
                                                  theme: theme,
                                                  isDark: isDark,
                                                ),
                                              ],
                                            );
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      
                                      // Birth Date Selection
                                      InkWell(
                                        onTap: () => _selectDate(context),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: theme.dividerColor,
                                              width: 1,
                                            ),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today_outlined,
                                                size: 20,
                                                color: hintTextColor,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      l10n.birthDate,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        color: hintTextColor,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      _selectedBirthDate != null
                                                          ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/${_selectedBirthDate!.year}'
                                                          : l10n.dateNotSelected,
                                                      style: theme.textTheme.titleSmall?.copyWith(
                                                        fontWeight: _selectedBirthDate != null
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                        color: textColor,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                Icons.arrow_drop_down,
                                                color: hintTextColor,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      
                                      const SizedBox(height: 16),
                                      
                                      // Gender & Role
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          if (constraints.maxWidth > 520) {
                                            return Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: _buildDropdownField(
                                                    value: _selectedGender,
                                                    label: l10n.gender,
                                                    icon: Icons.wc_outlined,
                                                    items: [
                                                      DropdownMenuItem(
                                                        value: 'male',
                                                        child: Text(
                                                          l10n.male,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      DropdownMenuItem(
                                                        value: 'female',
                                                        child: Text(
                                                          l10n.female,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                    onChanged: (value) {
                                                      setState(() => _selectedGender = value);
                                                    },
                                                    theme: theme,
                                                    isDark: isDark,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: _buildDropdownField(
                                                    value: _selectedRole,
                                                    label: l10n.role,
                                                    icon: Icons.assignment_ind_outlined,
                                                    items: [
                                                      DropdownMenuItem(
                                                        value: 'athlete',
                                                        child: Text(
                                                          l10n.athlete,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      DropdownMenuItem(
                                                        value: 'coach',
                                                        child: Text(
                                                          l10n.coach,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      DropdownMenuItem(
                                                        value: 'viewer',
                                                        child: Text(
                                                          l10n.viewer,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                    onChanged: (value) {
                                                      if (value != null) {
                                                        setState(() => _selectedRole = value);
                                                      }
                                                    },
                                                    theme: theme,
                                                    isDark: isDark,
                                                  ),
                                                ),
                                              ],
                                            );
                                          } else {
                                            return Column(
                                              children: [
                                                _buildDropdownField(
                                                  value: _selectedGender,
                                                  label: l10n.gender,
                                                  icon: Icons.wc_outlined,
                                                  items: [
                                                    DropdownMenuItem(
                                                      value: 'male',
                                                      child: Text(
                                                        l10n.male,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'female',
                                                      child: Text(
                                                        l10n.female,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                  onChanged: (value) {
                                                    setState(() => _selectedGender = value);
                                                  },
                                                  theme: theme,
                                                  isDark: isDark,
                                                ),
                                                const SizedBox(height: 16),
                                                _buildDropdownField(
                                                  value: _selectedRole,
                                                  label: l10n.role,
                                                  icon: Icons.assignment_ind_outlined,
                                                  items: [
                                                    DropdownMenuItem(
                                                      value: 'athlete',
                                                      child: Text(
                                                        l10n.athlete,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'coach',
                                                      child: Text(
                                                        l10n.coach,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'viewer',
                                                      child: Text(
                                                        l10n.viewer,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                  onChanged: (value) {
                                                    if (value != null) {
                                                      setState(() => _selectedRole = value);
                                                    }
                                                  },
                                                  theme: theme,
                                                  isDark: isDark,
                                                ),
                                              ],
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Contact Information Section
                          Container(
                            margin: const EdgeInsets.only(top: 0, bottom: 24), // Üstte ve altta boşluk
                            decoration: BoxDecoration(
                              color: cardBackgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.dividerColor.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.contact_phone,
                                        color: sectionIconColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          l10n.contactInfo,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: sectionTitleColor,
                                          ) ?? TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: sectionTitleColor,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(height: 1, color: theme.dividerColor),
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Address field
                                      _buildTextField(
                                        controller: _addressController,
                                        label: l10n.address,
                                        icon: Icons.location_on_outlined,
                                        maxLines: 3,
                                        theme: theme,
                                        isDark: isDark,
                                      ),
                                      const SizedBox(height: 16),
                                      
                                      // Phone Number with Country selector
                                      Text(
                                        l10n.phoneNumber,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: hintTextColor,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          // Adaptive layout for phone field
                                          return constraints.maxWidth > 520
                                              ? _buildPhoneRow(theme, constraints, isDark)
                                              : _buildPhoneColumn(theme, isDark);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Save Button
                          ElevatedButton(
                            onPressed: _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              l10n.save,
                              overflow: TextOverflow.ellipsis,
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

  // Build phone row layout (for wider screens)
  Widget _buildPhoneRow(ThemeData theme, BoxConstraints constraints, bool isDark) {
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: constraints.maxWidth * 0.4,
          child: _buildCountryDropdown(theme),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _phoneNumberController,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).phoneNumber,
              hintStyle: TextStyle(color: hintTextColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.dividerColor,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.dividerColor,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.primaryColor,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              prefixIcon: Icon(
                Icons.phone_outlined,
                color: hintTextColor,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _phoneNumber = PhoneNumber(
                  phoneNumber: value,
                  dialCode: _phoneNumber.dialCode,
                  isoCode: _phoneNumber.isoCode ?? 'TR',
                );
              });
            },
          ),
        ),
      ],
    );
  }

  // Build phone column layout (for narrower screens)
  Widget _buildPhoneColumn(ThemeData theme, bool isDark) {
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCountryDropdown(theme),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneNumberController,
          keyboardType: TextInputType.number,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).phoneNumber,
            hintStyle: TextStyle(color: hintTextColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.dividerColor,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.dividerColor,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.primaryColor,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            prefixIcon: Icon(
              Icons.phone_outlined,
              color: hintTextColor,
            ),
          ),
          onChanged: (value) {
            setState(() {
              _phoneNumber = PhoneNumber(
                phoneNumber: value,
                dialCode: _phoneNumber.dialCode,
                isoCode: _phoneNumber.isoCode ?? 'TR',
              );
            });
          },
        ),
      ],
    );
  }

  // Helper method to build text fields with overflow protection
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
    required ThemeData theme,
    required bool isDark,
  }) {
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hintTextColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.dividerColor,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.dividerColor,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.primaryColor,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.error,
            width: 2,
          ),
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: hintTextColor,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
    );
  }

  // Helper method for dropdown fields with overflow protection
  Widget _buildDropdownField<T>({
    required T? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    required ThemeData theme,
    required bool isDark,
  }) {
    final hintTextColor = isDark ? Colors.white70 : theme.hintColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? theme.colorScheme.surface : theme.cardColor;
    
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hintTextColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.dividerColor,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.dividerColor,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.primaryColor,
            width: 2,
          ),
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: hintTextColor,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
      isExpanded: true,
      icon: Icon(
        Icons.arrow_drop_down, 
        size: 24,
        color: hintTextColor,
      ),
      dropdownColor: cardColor,
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }
}
