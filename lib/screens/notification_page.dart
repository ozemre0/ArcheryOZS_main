import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/supabase_config.dart';
import '../services/coach_athlete_service.dart';

class NotificationPage extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final void Function(Map<String, dynamic>) onAccept;
  final void Function(Map<String, dynamic>) onReject;

  const NotificationPage({
    Key? key,
    required this.notifications,
    required this.onAccept,
    required this.onReject,
  }) : super(key: key);

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  Map<String, Map<String, dynamic>> _profileCache = {};

  @override
  void initState() {
    super.initState();
    _filterNotificationsForReceiver();
    _fetchProfiles();
  }

  List<Map<String, dynamic>> _filteredNotifications = [];

  void _filterNotificationsForReceiver() {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      _filteredNotifications = [];
      return;
    }
    setState(() {
      _filteredNotifications = widget.notifications.where((notif) {
        // Sadece istek alan kullanıcıya göster
        return notif['requester_id'] != user.id;
      }).toList();
    });
  }

  Future<void> _fetchProfiles() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    for (final notif in widget.notifications) {
      final otherId = notif['requester_id'] == user.id
        ? (notif['coach_id'] == user.id ? notif['athlete_id'] : notif['coach_id'])
        : notif['requester_id'];
      if (_profileCache.containsKey(otherId)) continue;
      final profileResp = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('id', otherId)
          .maybeSingle();
      if (profileResp != null) {
        setState(() {
          _profileCache[otherId] = profileResp;
        });
      }
    }
  }

  void _handleAccept(Map<String, dynamic> notif) async {
    widget.onAccept(notif);
    // Cache temizle
    final coachAthleteService = CoachAthleteService();
    coachAthleteService.clearCache();

    // Sync both coach and athlete so both lists update immediately
    final coachId = notif['coach_id'];
    final athleteId = notif['athlete_id'];
    await coachAthleteService.syncCoachAthleteData(coachId, 'coach');
    await coachAthleteService.syncCoachAthleteData(athleteId, 'athlete');

    if (mounted) Navigator.pop(context, true); // Return true to indicate a change
  }

  void _handleReject(Map<String, dynamic> notif) async {
    widget.onReject(notif);
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
      ),
      body: _filteredNotifications.isEmpty
          ? Center(child: Text(l10n.noNotifications))
          : ListView.builder(
              itemCount: _filteredNotifications.length,
              itemBuilder: (context, index) {
                final notif = _filteredNotifications[index];
                final user = SupabaseConfig.client.auth.currentUser;
                final otherId = notif['requester_id'] == user?.id
                  ? (notif['coach_id'] == user?.id ? notif['athlete_id'] : notif['coach_id'])
                  : notif['requester_id'];
                final profile = _profileCache[otherId];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: profile != null && profile['photo_url'] != null
                        ? CircleAvatar(backgroundImage: NetworkImage(profile['photo_url']))
                        : const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(
                      profile != null
                          ? '${profile['first_name']} ${profile['last_name']}'
                          : l10n.unknownUser,
                      maxLines: 1,
                    ),
                    subtitle: Text(profile != null && profile['role'] != null
                        ? l10n.role + ': ' + (profile['role'] == 'coach' ? l10n.coach : l10n.athlete)
                        : l10n.pendingRequestDetail),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          tooltip: l10n.accept,
                          onPressed: () => _handleAccept(notif),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          tooltip: l10n.reject,
                          onPressed: () => _handleReject(notif),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
