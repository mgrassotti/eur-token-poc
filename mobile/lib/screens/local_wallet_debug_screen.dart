import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/local_wallet_service.dart';

/// Settings → Phase 2 BDK spike: create/load mnemonic and show a receive address.
class LocalWalletDebugScreen extends StatefulWidget {
  const LocalWalletDebugScreen({super.key, this.wallet});

  /// Injected for tests; defaults to real [LocalWalletService] (native BDK).
  final LocalWalletApi? wallet;

  @override
  State<LocalWalletDebugScreen> createState() => _LocalWalletDebugScreenState();
}

class _LocalWalletDebugScreenState extends State<LocalWalletDebugScreen> {
  late final LocalWalletApi _wallet = widget.wallet ?? LocalWalletService();
  bool _loading = true;
  String? _address;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final loaded = await _wallet.tryLoad();
      String? address;
      if (loaded) {
        address = await _wallet.receiveAddress();
      }
      if (mounted) {
        setState(() {
          _address = address;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _wallet.create();
      final address = await _wallet.receiveAddress();
      if (mounted) {
        setState(() {
          _address = address;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.localWalletDebug)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.localWalletDebugSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(
                    l10n.localWalletError(_error!),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                if (_address != null) ...[
                  Text(
                    l10n.localWalletReceiveAddress,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_address!),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _address!));
                    },
                    icon: const Icon(Icons.copy),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.localWalletMnemonicSaved,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: _create,
                    child: Text(l10n.localWalletCreate),
                  ),
                ],
              ],
            ),
    );
  }
}
