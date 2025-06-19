import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'create_competition_screen.dart';

class CoachCompetitionsScreen extends StatelessWidget {
  const CoachCompetitionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myCompetitionsTitle),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.myCompetitionsDesc,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateCompetitionScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.createCompetitionTitle),
            ),
          ],
        ),
      ),
    );
  }
}
