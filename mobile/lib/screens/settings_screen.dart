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
          if (settings.advancedFeatures) ...[
            ListTile(
              leading: const Icon(Icons.cloud_sync),
              title: const Text('Electrum Server'),
              subtitle: Text(settings.electrumUrl ?? 'Default (tcp://127.0.0.1:50001)'),
              onTap: () => _showElectrumDialog(context, settings),
            ),
            ListTile(
              leading: const Icon(Icons.developer_mode),
              title: Text(l10n.localWalletDebug),
              subtitle: Text(l10n.localWalletDebugSubtitle),
              onTap: () => context.push('/settings/local-wallet'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showElectrumDialog(BuildContext context, SettingsState settings) async {
    final controller = TextEditingController(text: settings.electrumUrl ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Electrum Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configure your Electrum server URL.\n'
              'Leave empty to use default local regtest.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'tcp://127.0.0.1:50001',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Examples:\n'
              '• tcp://127.0.0.1:50001 (regtest)\n'
              '• tcp://10.0.2.2:50001 (Android emulator)\n'
              '• ssl://electrum.blockstream.info:60002 (testnet)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await settings.setElectrumUrl(result.isEmpty ? null : result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Electrum server updated. Restart wallet to apply.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
