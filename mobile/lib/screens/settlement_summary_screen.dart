import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settlement)),
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
                        _row(l10n.spotRate, '€${preview.endBtcEurRate!.toStringAsFixed(0)}/BTC'),
                      _row(l10n.ready, preview.readyForSettlement ? l10n.yes : l10n.no),
                      if (preview.payoff != null) ...[
                        const Divider(height: 32),
                        Text(l10n.floorEurPayoff, style: Theme.of(context).textTheme.titleMedium),
                        _row(
                          l10n.totalLiability,
                          '€${(preview.payoff!.liabilityEurCents / 100).toStringAsFixed(2)}',
                        ),
                        _row(l10n.holderSats, '${preview.payoff!.totalHolderSats}'),
                        _row(
                          l10n.investorRemainder,
                          '${preview.payoff!.investorRemainderSats} sats',
                        ),
                        if (preview.payoff!.insolvent)
                          Text(
                            l10n.insolventNote,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                      ],
                      if (preview.holderAllocations.isNotEmpty) ...[
                        const Divider(height: 32),
                        Text(l10n.holderAllocations, style: Theme.of(context).textTheme.titleMedium),
                        ...preview.holderAllocations.map(
                          (a) => ListTile(
                            title: Text(a.user.name),
                            subtitle: Text(
                              l10n.shareAmount((a.shareCents / 100).toStringAsFixed(2)),
                            ),
                            trailing: Text('${a.btcSats} sats'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        preview.status == 'preview'
                            ? l10n.settlementPreviewNote
                            : l10n.settlementExecutedNote,
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
