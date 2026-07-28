import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_state.dart';

/// Phase 2: Add funds screen using on-device BDK wallet.
///
/// Replaces relay-backed reserve with local Bitcoin wallet.
/// Shows BDK receive address and balance synced via Electrum.
class AddFundsScreen extends StatefulWidget {
  const AddFundsScreen({super.key});

  @override
  State<AddFundsScreen> createState() => _AddFundsScreenState();
}

class _AddFundsScreenState extends State<AddFundsScreen> {
  @override
  void initState() {
    super.initState();
    _ensureWalletInitialized();
  }

  Future<void> _ensureWalletInitialized() async {
    final wallet = context.read<WalletState>();
    if (!wallet.isInitialized && !wallet.loading) {
      // No wallet exists - prompt user to create one
      _showCreateWalletDialog();
    }
  }

  void _showCreateWalletDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Create wallet'),
        content: Text(l10n.localWalletDebugSubtitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _createWallet();
            },
            child: Text(l10n.localWalletCreate),
          ),
        ],
      ),
    );
  }

  Future<void> _createWallet() async {
    final wallet = context.read<WalletState>();
    final mnemonic = await wallet.createWallet();

    if (mnemonic != null && mounted) {
      _showMnemonicBackupDialog(mnemonic);
    }
  }

  void _showMnemonicBackupDialog(String mnemonic) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Backup recovery phrase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Write down these 12 words in order. You will need them to restore your wallet.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SelectableText(
              mnemonic,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Store it safely offline. Anyone with this phrase can access your funds.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I have backed it up'),
          ),
        ],
      ),
    );
  }

  void _copyAddress(String address) {
    final l10n = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.addressCopied)),
    );
  }

  Future<void> _sync() async {
    final wallet = context.read<WalletState>();
    await wallet.sync();

    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    
    if (wallet.lastSyncError != null) {
      // Show error as a persistent banner, not just a snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sync Failed',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(wallet.lastSyncError!),
              const SizedBox(height: 8),
              const Text(
                'Check your Electrum server configuration in Settings.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Settings',
            textColor: Colors.white,
            onPressed: () => context.push('/settings'),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.reserveUpdated(wallet.balanceSats))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wallet = context.watch<WalletState>();

    if (wallet.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.addFunds)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!wallet.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.addFunds)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet, size: 64),
                const SizedBox(height: 24),
                Text(
                  'No wallet found',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Create a new Bitcoin wallet to receive funds',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _createWallet,
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(l10n.localWalletCreate),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (wallet.error != null && wallet.receiveAddress == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.addFunds)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  wallet.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.read<WalletState>().sync(),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final receiveAddress = wallet.receiveAddress ?? 'Loading...';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addFunds)),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'On-device wallet (regtest)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.balanceSats(wallet.balanceSats),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: receiveAddress,
                  version: QrVersions.auto,
                  size: 220,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              receiveAddress,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _copyAddress(receiveAddress),
              icon: const Icon(Icons.copy),
              label: Text(l10n.copyAddress),
            ),
            const SizedBox(height: 24),
            Text(
              'Send regtest BTC to this address. Use `flutter test integration_test/bdk_wallet_test.dart` to test funding via Rails.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: wallet.syncing ? null : _sync,
              icon: wallet.syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(l10n.syncBalance),
            ),
            if (wallet.error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  wallet.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
