import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/relay_api_client.dart';

class SettlementSummaryScreen extends StatefulWidget {
  const SettlementSummaryScreen({super.key, required this.dealId});

  final String dealId;

  @override
  State<SettlementSummaryScreen> createState() => _SettlementSummaryScreenState();
}

class _SettlementSummaryScreenState extends State<SettlementSummaryScreen> {
  SettlementPreview? _preview;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<RelayApiClient>();
      final preview = await api.fetchSettlement(widget.dealId);
      if (mounted) {
        setState(() {
          _preview = preview;
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

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Settlement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Chip(
                        label: Text(preview!.status.toUpperCase()),
                        avatar: Icon(
                          preview.status == 'executed' ? Icons.check_circle : Icons.preview,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (preview.endBtcEurRate != null)
                        _row('Spot rate', '€${preview.endBtcEurRate!.toStringAsFixed(0)}/BTC'),
                      _row('Ready', preview.readyForSettlement ? 'Yes' : 'No'),
                      if (preview.payoff != null) ...[
                        const Divider(height: 32),
                        Text('FloorEUR payoff', style: Theme.of(context).textTheme.titleMedium),
                        _row(
                          'Total liability',
                          '€${(preview.payoff!.liabilityEurCents / 100).toStringAsFixed(2)}',
                        ),
                        _row('Holder sats', '${preview.payoff!.totalHolderSats}'),
                        _row('Investor remainder', '${preview.payoff!.investorRemainderSats} sats'),
                        if (preview.payoff!.insolvent)
                          Text(
                            'Insolvent at this spot — capped by escrow',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                      ],
                      if (preview.holderAllocations.isNotEmpty) ...[
                        const Divider(height: 32),
                        Text('Holder allocations', style: Theme.of(context).textTheme.titleMedium),
                        ...preview.holderAllocations.map(
                          (a) => ListTile(
                            title: Text(a.user.name),
                            subtitle: Text('€${(a.shareCents / 100).toStringAsFixed(2)} share'),
                            trailing: Text('${a.btcSats} sats'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        preview.status == 'preview'
                            ? 'Preview only — Phase 1 uses relay FloorEUR math. Production settles on-device via mat-core.'
                            : 'Settlement executed on relay (PoC admin path).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))],
      ),
    );
  }
}
