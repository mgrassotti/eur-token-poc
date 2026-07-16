import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/relay_api_client.dart';

class AddFundsScreen extends StatefulWidget {
  const AddFundsScreen({super.key});

  @override
  State<AddFundsScreen> createState() => _AddFundsScreenState();
}

class _AddFundsScreenState extends State<AddFundsScreen> {
  ReserveInfo? _reserve;
  bool _loading = true;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool syncFirst = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<RelayApiClient>();
      if (syncFirst) {
        await api.syncReserve();
        if (mounted) context.read<DashboardState>().refresh();
      }
      final reserve = await api.fetchReserve();
      if (mounted) {
        setState(() {
          _reserve = reserve;
          _loading = false;
        });
      }
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await _load(syncFirst: true);
    if (!mounted) return;

    setState(() => _syncing = false);
    if (_error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error!)));
      return;
    }

    final balance = _reserve?.balanceSats ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reserve updated: $balance sats')),
    );
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Address copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reserve = _reserve;

    return Scaffold(
      appBar: AppBar(title: const Text('Add funds')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(syncFirst: true),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'Regtest reserve (${reserve!.network})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Balance: ${reserve.balanceSats} sats',
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
                            data: reserve.receiveAddress,
                            version: QrVersions.auto,
                            size: 220,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        reserve.receiveAddress,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _copyAddress(reserve.receiveAddress),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy address'),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        reserve.instructions ??
                            'Ask admin to send BTC from Exchange wallet to this address, then tap Sync.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _syncing ? null : _sync,
                        icon: _syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Sync balance'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
