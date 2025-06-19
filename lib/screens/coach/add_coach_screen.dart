import 'package:flutter/material.dart';
import '../../services/supabase_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:archeryozs/services/profile_service.dart';
import '../../models/profile_model.dart';

class AddCoachScreen extends StatefulWidget {
  const AddCoachScreen({super.key});

  @override
  State<AddCoachScreen> createState() => _AddCoachScreenState();
}

class _AddCoachScreenState extends State<AddCoachScreen> {
  final _formKey = GlobalKey<FormState>();
  final _coachIdController = TextEditingController();
  bool _isLoading = false;

  // ProfileService referansı
  final _profileService = ProfileService();

  Profile? _coachProfile;
  String? _profileError;

  Future<void> _fetchCoachProfile(String profileId) async {
    setState(() {
      _coachProfile = null;
      _profileError = null;
    });
    if (profileId.isEmpty) return;
    try {
      final profile = await _profileService.getProfileByProfileId(profileId);
      setState(() {
        _coachProfile = profile;
        _profileError = profile == null ? AppLocalizations.of(context).coachNotFound : null;
      });
    } catch (e) {
      setState(() {
        _profileError = e.toString();
      });
    }
  }

  Future<void> _linkCoach() async {
    if (!_formKey.currentState!.validate()) return;
    if (_coachProfile == null) return;
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
        if (profile['role'] != 'athlete') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.onlyAthletesCanAddCoaches)),
            );
            Navigator.pop(context);
            return;
          }
        }
        if (_coachProfile!.id == currentUser.id) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.cannotAddSelf)),
            );
            return;
          }
        }
        // İlişkiyi pending olarak ekle
        await SupabaseConfig.client.from('athlete_coach').insert({
          'athlete_id': currentUser.id,
          'coach_id': _coachProfile!.id,
          'status': 'pending',
          'requester_id': currentUser.id,
        });
        if (mounted) {
          // Sadece bilgi ver, listeye ekleme veya pop ile true döndürme
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Koç ekleme isteği gönderildi.')),
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
        title: Text(l10n.addCoach),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _coachIdController,
                decoration: InputDecoration(
                  labelText: l10n.coachProfileId, // |10n
                  helperText: l10n.coachProfileIdHelper, // |10n
                  prefixIcon: const Icon(Icons.sports_kabaddi),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? l10n.coachProfileIdRequired : null, // |10n
                onChanged: (val) => _fetchCoachProfile(val.trim()),
              ),
              if (_profileError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_profileError!, style: TextStyle(color: Colors.red)),
                ),
              if (_coachProfile != null)
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text('${_coachProfile!.firstName} ${_coachProfile!.lastName}'),
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading || _coachProfile == null ? null : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Koç eklemesini onayla'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Bu koçu eklemek istediğinizden emin misiniz?'),
                          if (_coachProfile != null)
                            ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person)),
                              title: Text('${_coachProfile!.firstName} ${_coachProfile!.lastName}'),
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
                          child: Text('Ekle'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _linkCoach();
                  }
                },
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(l10n.addCoach),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _coachIdController.dispose();
    super.dispose();
  }
}
