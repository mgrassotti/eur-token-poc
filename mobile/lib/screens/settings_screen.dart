import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: Text(l10n.depositFunds),
            onTap: () => context.push('/reserve/add-funds'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(l10n.topUpSpending),
            onTap: () => context.push('/deals/new'),
          ),
          ListTile(
            title: Text(l10n.language),
            subtitle: Text(
              settings.locale.languageCode == 'it' ? l10n.languageItalian : l10n.languageEnglish,
            ),
            trailing: DropdownButton<Locale>(
              value: settings.locale,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: const Locale('en'),
                  child: Text(l10n.languageEnglish),
                ),
                DropdownMenuItem(
                  value: const Locale('it'),
                  child: Text(l10n.languageItalian),
                ),
              ],
              onChanged: (locale) {
                if (locale != null) settings.setLocale(locale);
              },
            ),
          ),
          SwitchListTile(
            title: Text(l10n.advancedFeatures),
            subtitle: Text(l10n.advancedFeaturesSubtitle),
            value: settings.advancedFeatures,
            onChanged: settings.setAdvancedFeatures,
          ),
        ],
      ),
    );
  }
}
