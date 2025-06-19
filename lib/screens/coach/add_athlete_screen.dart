import 'package:archeryozs/services/profile_service.dart';
import 'package:flutter/material.dart';
import '../../services/supabase_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/profile_model.dart';

class AddAthleteScreen extends StatefulWidget {
  const AddAthleteScreen({super.key});

  @override
  State<AddAthleteScreen> createState() => _AddAthleteScreenState();
}

class _AddAthleteScreenState extends State<AddAthleteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _athleteIdController = TextEditingController();
  bool _isLoading = false;

  // ProfileService referansı
  final _profileService = ProfileService();

  Profile? _athleteProfile;
  String? _profileError;

  Future<void> _fetchAthleteProfile(String profileId) async {
    setState(() {
      _athleteProfile = null;
      _profileError = null;
    });
    if (profileId.isEmpty) return;
    try {
      final profile = await _profileService.getProfileByProfileId(profileId);
      setState(() {
        _athleteProfile = profile;
        _profileError = profile == null ? AppLocalizations.of(context).athleteNotFound : null;
      });
    } catch (e) {
      setState(() {
        _profileError = e.toString();
      });
    }
  }

  Future<void> _linkAthlete() async {
    if (!_formKey.currentState!.validate()) return;
    if (_athleteProfile == null) return;
    setState(() => _isLoading = true);
    try {
      final currentUser = SupabaseConfig.client.auth.currentUser;
      if (currentUser != null) {
        final l10n = AppLocalizations.of(context);
        final profile = await SupabaseConfig.client
            .from('profiles')
            .select('role')
            .eq('id', currentUser.id)
            .single();
        if (profile['role'] != 'coach') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.onlyCoachesCanAddAthletes)),
            );
            Navigator.pop(context);
            return;
          }
        }
        if (_athleteProfile!.id == currentUser.id) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.cannotAddSelf)),
            );
            return;
          }
        }
        // İlişkiyi pending olarak ekle
        await SupabaseConfig.client.from('athlete_coach').insert({
          'athlete_id': _athleteProfile!.id,
          'coach_id': currentUser.id,
          'status': 'pending',
          'requester_id': currentUser.id,
        });
        if (mounted) {
          // Sadece bilgi ver, listeye ekleme veya pop ile true döndürme
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.athleteRequestSent)),
          );
          Navigator.pop(context); // true yerine sadece pop
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addAthlete),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _athleteIdController,
                decoration: InputDecoration(
                  labelText: l10n.athleteProfileId, // |10n
                  helperText: l10n.athleteProfileIdHelper, // |10n
                  prefixIcon: const Icon(Icons.sports),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? l10n.athleteProfileIdRequired : null, // |10n
                onChanged: (val) => _fetchAthleteProfile(val.trim()),
              ),
              if (_profileError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_profileError!, style: TextStyle(color: Colors.red)),
                ),
              if (_athleteProfile != null)
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text('${_athleteProfile!.firstName} ${_athleteProfile!.lastName}'),
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading || _athleteProfile == null ? null : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.confirmAddAthleteTitle),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.confirmAddAthleteMessage),
                          if (_athleteProfile != null)
                            ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person)),
                              title: Text('${_athleteProfile!.firstName} ${_athleteProfile!.lastName}'),
                            ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.cancel),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l10n.add),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _linkAthlete();
                  }
                },
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(l10n.addAthlete),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _athleteIdController.dispose();
    super.dispose();
  }
}
