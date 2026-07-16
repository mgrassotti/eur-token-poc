import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Advanced features'),
            subtitle: const Text('Show open deals available to invest in'),
            value: settings.advancedFeatures,
            onChanged: settings.setAdvancedFeatures,
          ),
        ],
      ),
    );
  }
}
