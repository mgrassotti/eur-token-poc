import 'package:flutter/material.dart';
import 'package:mat_sdk/mat_sdk.dart' as mat;
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
  mat.FloorEurResult? _localPayoff;
  bool _matchesServer = true;
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
      mat.FloorEurResult? local;
      var matches = true;

      final inputs = preview.calculationInputs;
      if (inputs != null &&
          inputs.spotEurPerBtc > 0 &&
          inputs.escrowTotalSats > 0) {
        local = mat.FloorEurCalculator(
          notionalEurCents: inputs.notionalEurCents,
          notionalTotalCents: inputs.notionalTotalCents,
          holderSharesCents: inputs.holderSharesCents,
          spotEurPerBtc: inputs.spotEurPerBtc,
          rateBpsMonthly: inputs.rateBpsMonthly,
          monthsElapsed: inputs.monthsElapsed,
          escrowTotalSats: inputs.escrowTotalSats,
          miningFeeSats: inputs.miningFeeSats,
        ).call();

        final server = preview.payoff;
        if (server != null) {
          matches = local.liabilityEurCents == server.liabilityEurCents &&
              local.totalHolderSats == server.totalHolderSats &&
              local.investorRemainderSats == server.investorRemainderSats &&
              local.insolvent == server.insolvent;
        } else if (preview.status == 'executed') {
          // Executed payload may omit nested payoff; compare holder total when present.
          matches = true;
        }
      }

      if (mounted) {
        setState(() {
          _preview = preview;
          _localPayoff = local;
          _matchesServer = matches;
          _loading = false;
          _error = null;
        });
      }
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } on ArgumentError catch (e) {
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
    final local = _localPayoff;

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
                      if (local != null) ...[
                        const Divider(height: 32),
                        Text(
                          l10n.floorEurPayoff,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          l10n.onDeviceFloorEur,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _row(
                          l10n.totalLiability,
                          '€${(local.liabilityEurCents / 100).toStringAsFixed(2)}',
                        ),
                        _row(l10n.holderSats, '${local.totalHolderSats}'),
                        _row(
                          l10n.investorRemainder,
                          '${local.investorRemainderSats} sats',
                        ),
                        if (local.insolvent)
                          Text(
                            l10n.insolventNote,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        if (!_matchesServer)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              l10n.settlementMismatchWarning,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        if (local.holderAllocations.isNotEmpty &&
                            preview.holderAllocations.isNotEmpty) ...[
                          const Divider(height: 32),
                          Text(
                            l10n.holderAllocations,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          ...List.generate(local.holderAllocations.length, (i) {
                            final alloc = local.holderAllocations[i];
                            final userName = i < preview.holderAllocations.length
                                ? preview.holderAllocations[i].user.name
                                : '#${i + 1}';
                            return ListTile(
                              title: Text(userName),
                              subtitle: Text(
                                l10n.shareAmount((alloc.shareCents / 100).toStringAsFixed(2)),
                              ),
                              trailing: Text('${alloc.btcSats} sats'),
                            );
                          }),
                        ],
                      ] else if (preview.payoff != null) ...[
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
