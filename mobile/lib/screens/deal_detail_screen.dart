import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/btc_math.dart';
import '../services/relay_api_client.dart';

class DealDetailScreen extends StatefulWidget {
  const DealDetailScreen({super.key, required this.dealId});

  final String dealId;

  @override
  State<DealDetailScreen> createState() => _DealDetailScreenState();
}

class _DealDetailScreenState extends State<DealDetailScreen> {
  Deal? _deal;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  Set<String> _knownAddresses = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<RelayApiClient>();
      final wallet = context.read<WalletState>();
      final results = await Future.wait([
        api.fetchDeal(widget.dealId),
        wallet.isInitialized
            ? wallet.knownReceiveAddresses()
            : Future.value(<String>{}),
      ]);
      final deal = results[0] as Deal;
      final known = results[1] as Set<String>;
      if (mounted) {
        setState(() {
          _deal = deal;
          _knownAddresses = known;
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

  bool _isBorrower(Deal deal, WalletState wallet) {
    return wallet.ownsAddressSync(deal.fundingAddress, _knownAddresses);
  }

  bool _isInvestor(Deal deal, WalletState wallet) {
    return wallet.ownsAddressSync(deal.investorFundingAddress, _knownAddresses);
  }

  Future<void> _accept(RelayApiClient api) async {
    final l10n = AppLocalizations.of(context);
    final wallet = context.read<WalletState>();
    final dashboard = context.read<DashboardState>();
    final nameState = context.read<NameState>();
    final deal = _deal;
    final rate = dashboard.marketRateEur;
    final address = wallet.receiveAddress;

    if (deal == null || rate == null || address == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallet or market rate not ready')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await wallet.sync();
      final collateralSats = BtcMath.eurCentsToSats(deal.amountEurCents, rate);
      final required = collateralSats + BtcMath.fundingFeeBufferSats;
      final coins = await wallet.selectCoins(required);
      final change = await wallet.nextChangeAddress();
      final payout = await wallet.nextChangeAddress();

      final updated = await api.acceptDeal(
        widget.dealId,
        fundingAddress: address,
        investorName: nameState.name,
        investorInputs: coins
            .map((u) => {
                  'txid': u.txid,
                  'vout': u.vout,
                  'amount_sats': u.valueSats,
                })
            .toList(),
        investorChangeAddress: change,
        investorPayoutAddress: payout,
        investorIdentityPubkey: BtcMath.placeholderIdentityPubkey(address),
      );

      // Investor signs funding PSBT when returned.
      var finalDeal = updated;
      if (updated.fundingPsbt != null && updated.awaitingFundingSignatures) {
        final signed = await wallet.signPsbt(updated.fundingPsbt!);
        finalDeal = await api.submitFundingSignature(
          dealId: widget.dealId,
          fundingAddress: address,
          signedPsbt: signed,
        );
      }

      final dashboard = context.read<DashboardState>();
      await dashboard.refreshOpenDeals();
      if (!mounted) return;
      setState(() {
        _deal = finalDeal;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dealActivated)),
      );
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _signFunding(RelayApiClient api) async {
    final wallet = context.read<WalletState>();
    final deal = _deal;
    if (deal?.fundingPsbt == null) return;

    // Prefer the address recorded on the deal so party matching survives
    // receive-address advancement after create/accept.
    final address = _isBorrower(deal!, wallet)
        ? (deal.fundingAddress ?? wallet.receiveAddress)
        : (deal.investorFundingAddress ?? wallet.receiveAddress);
    if (address == null) return;

    setState(() => _busy = true);
    try {
      final signed = await wallet.signPsbt(deal.fundingPsbt!);
      final updated = await api.submitFundingSignature(
        dealId: widget.dealId,
        fundingAddress: address,
        signedPsbt: signed,
      );
      if (mounted) {
        setState(() {
          _deal = updated;
          _busy = false;
        });
      }
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wallet = context.watch<WalletState>();
    final deal = _deal;
    final isBorrower = deal != null && _isBorrower(deal, wallet);
    final isInvestor = deal != null && _isInvestor(deal, wallet);
    final canAccept = deal != null && deal.isPending && !isBorrower;
    final needsBorrowerSign = deal != null &&
        deal.awaitingFundingSignatures &&
        isBorrower &&
        !deal.borrowerFundingSigned &&
        deal.fundingPsbt != null;
    final needsInvestorSign = deal != null &&
        deal.awaitingFundingSignatures &&
        isInvestor &&
        !deal.investorFundingSigned &&
        deal.fundingPsbt != null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: l10n.home,
          onPressed: () => context.go('/'),
        ),
        title: Text(l10n.dealTitle(widget.dealId)),
        actions: [
          if (deal?.isActive == true)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => context.push('/deals/${widget.dealId}/transfers'),
            ),
          IconButton(
            icon: const Icon(Icons.payments_outlined),
            onPressed: () => context.push('/deals/${widget.dealId}/settlement'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _StatusChip(status: deal!.status),
                      const SizedBox(height: 16),
                      _info(l10n.amount, '€${deal.amountEur.toStringAsFixed(2)}'),
                      _info(l10n.rate, l10n.ratePerMonth((deal.rateBpsMonthly / 100).toString())),
                      _info(l10n.period, '${deal.period.start} → ${deal.period.end}'),
                      _info(l10n.borrower, deal.borrower?.name ?? '—'),
                      _info(l10n.investor, deal.investor?.name ?? '—'),
                      if (deal.pegEurPerBtc != null)
                        _info(l10n.peg, '€${deal.pegEurPerBtc!.toStringAsFixed(0)}/BTC'),
                      if (deal.poolSats > 0) _info(l10n.pool, l10n.poolSats(deal.poolSats)),
                      if (deal.awaitingFundingSignatures)
                        _info(
                          'Funding',
                          'Awaiting signatures '
                          '(borrower: ${deal.borrowerFundingSigned}, '
                          'investor: ${deal.investorFundingSigned})',
                        ),
                      if (deal.liabilityEurCents != null)
                        _info(
                          l10n.liabilityAtMaturity,
                          '€${(deal.liabilityEurCents! / 100).toStringAsFixed(2)}',
                        ),
                      if (deal.tokenHolders.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(l10n.tokenHolders, style: Theme.of(context).textTheme.titleMedium),
                        ...deal.tokenHolders.map(
                          (h) => ListTile(
                            title: Text(h.user.name),
                            trailing: Text('€${(h.balanceCents / 100).toStringAsFixed(2)}'),
                            subtitle: h.interestCents != null
                                ? Text(
                                    l10n.interestAmount(
                                      (h.interestCents! / 100).toStringAsFixed(2),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ],
                      if (canAccept) ...[
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _busy ? null : () => _accept(context.read<RelayApiClient>()),
                          child: _busy
                              ? const CircularProgressIndicator()
                              : Text(l10n.acceptAndActivate),
                        ),
                      ],
                      if (needsBorrowerSign || needsInvestorSign) ...[
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _busy ? null : () => _signFunding(context.read<RelayApiClient>()),
                          child: _busy
                              ? const CircularProgressIndicator()
                              : const Text('Sign funding PSBT'),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'pending' => Colors.orange,
      'active' => Colors.green,
      'settled' => Colors.blueGrey,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(status),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color),
    );
  }
}
