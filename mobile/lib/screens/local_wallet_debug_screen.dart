import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/local_wallet_service.dart';
import '../services/wallet_api.dart';
import '../services/wallet_lifecycle_manager.dart';

/// Settings → Phase 2: BDK wallet (create/restore mnemonic, show receive address).
class LocalWalletDebugScreen extends StatefulWidget {
  const LocalWalletDebugScreen({super.key, WalletApi? wallet})
      : _injectedWallet = wallet;

  /// Injected for tests; defaults to real [BdkWalletService] (native BDK).
  final WalletApi? _injectedWallet;

  @override
  State<LocalWalletDebugScreen> createState() => _LocalWalletDebugScreenState();
}

class _LocalWalletDebugScreenState extends State<LocalWalletDebugScreen> {
  late final WalletApi _wallet;
  late final WalletLifecycleManager _lifecycle;

  bool _loading = true;
  String? _address;
  int? _balance;
  String? _mnemonic;
  String? _error;

  @override
  void initState() {
    super.initState();
    _wallet = widget._injectedWallet ?? BdkWalletService(network: Network.regtest);
    _lifecycle = WalletLifecycleManager(_wallet);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final loaded = await _lifecycle.tryLoadWallet();
      if (loaded) {
        await _refreshWalletState();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Load failed: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _createWallet() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Generate new 12-word mnemonic
      final mnemonic = await Mnemonic.create(WordCount.words12);
      final mnemonicPhrase = mnemonic.asString();

      final address = await _lifecycle.createWallet(mnemonicPhrase);

      if (mounted) {
        setState(() {
          _address = address;
          _mnemonic = mnemonicPhrase;
          _loading = false;
        });
      }

      await _refreshWalletState();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Create failed: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshWalletState() async {
    if (!_wallet.isInitialized) return;

    try {
      // Sync first (may take time)
      await _wallet.sync();

      final address = await _wallet.getReceiveAddress();
      final balance = await _wallet.getBalance();
      final storedMnemonic = await _lifecycle.getStoredMnemonic();

      if (mounted) {
        setState(() {
          _address = address;
          _balance = balance;
          _mnemonic = storedMnemonic;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Sync/refresh failed: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _deleteWallet() async {
    // Confirm deletion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete wallet?'),
        content: const Text(
          'This will delete the wallet and mnemonic from this device. '
          'Make sure you have backed up your recovery phrase!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _lifecycle.deleteWallet();

      if (mounted) {
        setState(() {
          _address = null;
          _balance = null;
          _mnemonic = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Delete failed: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.localWalletDebug),
        actions: [
          if (_wallet.isInitialized)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshWalletState,
              tooltip: 'Sync wallet',
            ),
        ],
      ),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (_wallet.isInitialized) ...[
                  _buildInfoCard(
                    context,
                    title: l10n.localWalletReceiveAddress,
                    content: _address ?? 'Loading...',
                    copyable: true,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    context,
                    title: 'Balance',
                    content: _balance != null
                        ? '${_balance! / 100000000} BTC (${_balance!} sats)'
                        : 'Loading...',
                  ),
                  const SizedBox(height: 12),
                  if (_mnemonic != null)
                    _buildInfoCard(
                      context,
                      title: 'Recovery phrase (backup!)',
                      content: _mnemonic!,
                      copyable: true,
                      sensitive: true,
                    ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _deleteWallet,
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text(
                      'Delete wallet',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: _createWallet,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(l10n.localWalletCreate),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Phase 2: On-device BDK wallet with regtest Electrum sync',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required String content,
    bool copyable = false,
    bool sensitive = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (copyable)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    tooltip: 'Copy',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: sensitive ? 'monospace' : null,
                    fontSize: sensitive ? 12 : null,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
