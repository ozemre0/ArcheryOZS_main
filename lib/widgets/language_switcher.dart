import 'package:flutter/material.dart';
import '../main.dart';

class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    // Get current locale to determine which language is selected
    final currentLocale = Localizations.localeOf(context).languageCode;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.language),
      onSelected: (String languageCode) {
        MyApp.of(context).changeLanguage(Locale(languageCode));
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'tr',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Text('🇹🇷 '),
                  SizedBox(width: 8),
                  Text('Türkçe'),
                ],
              ),
              // Show checkmark if Turkish is selected
              if (currentLocale == 'tr')
                Icon(
                  Icons.check,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'en',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Text('🇬🇧 '),
                  SizedBox(width: 8),
                  Text('English'),
                ],
              ),
              // Show checkmark if English is selected
              if (currentLocale == 'en')
                Icon(
                  Icons.check,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
