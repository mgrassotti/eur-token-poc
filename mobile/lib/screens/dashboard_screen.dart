import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/btc_math.dart';
import '../services/relay_api_client.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Set<String> _knownAddresses = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAll(context);
    });
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _automate(context);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll(BuildContext context) async {
    final dashboard = context.read<DashboardState>();
    final wallet = context.read<WalletState>();
    await Future.wait([
      dashboard.refreshMarketRate(),
      if (wallet.isInitialized) wallet.sync(),
    ]);
    final known = wallet.isInitialized ? await wallet.knownReceiveAddresses() : <String>{};
    if (wallet.receiveAddress != null) known.add(wallet.receiveAddress!);
    if (mounted) setState(() => _knownAddresses = known);
    await dashboard.refreshFundingRequests(addresses: known.toList());
    await dashboard.refreshOpenDeals(addresses: known.toList());
    await _automate(context);
  }

  Future<void> _automate(BuildContext context) async {
    if (!mounted) return;
    final wallet = context.read<WalletState>();
    final dashboard = context.read<DashboardState>();
    final api = context.read<RelayApiClient>();
    if (!wallet.isInitialized || wallet.receiveAddress == null) return;

    final rate = dashboard.marketRateEur;
    for (final request in dashboard.fundingRequests.where((r) => r.awaitingDeposit)) {
      if (rate == null || rate <= 0) continue;
      final required = request.requiredSats ??
          BtcMath.borrowerRequiredSats(request.remainingEurCents ?? request.amountEurCents, rate);
      if (wallet.balanceSats < required) continue;
      try {
        final coins = await wallet.selectCoins(required);
        final change = await wallet.nextChangeAddress();
        await api.submitFundingUtxos(
          requestId: request.id,
          inputs: coins
              .map((u) => {'txid': u.txid, 'vout': u.vout, 'amount_sats': u.valueSats})
              .toList(),
          changeAddress: change,
          identityPubkey: BtcMath.placeholderIdentityPubkey(wallet.receiveAddress!),
        );
      } catch (_) {}
    }

    for (final deal in dashboard.openDeals.where((d) => d.awaitingFundingSignatures && d.fundingPsbt != null)) {
      final isBorrower = wallet.ownsAddressSync(deal.fundingAddress, _knownAddresses);
      final isInvestor = wallet.ownsAddressSync(deal.investorFundingAddress, _knownAddresses);
      if (!isBorrower && !isInvestor) continue;
      if (isBorrower && deal.borrowerFundingSigned) continue;
      if (isInvestor && deal.investorFundingSigned) continue;
      try {
        final signed = await wallet.signPsbt(deal.fundingPsbt!);
        final address = isBorrower ? deal.fundingAddress : deal.investorFundingAddress;
        await api.submitFundingSignature(
          dealId: deal.id,
          fundingAddress: address ?? wallet.receiveAddress!,
          signedPsbt: signed,
        );
      } catch (_) {}
    }

    await dashboard.refreshFundingRequests(addresses: _knownAddresses.toList());
    await dashboard.refreshOpenDeals(addresses: _knownAddresses.toList());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dashboard = context.watch<DashboardState>();
    final nameState = context.watch<NameState>();
    final wallet = context.watch<WalletState>();
    final data = dashboard.data;
    final myTopUps = dashboard.openDeals
        .where(
          (d) =>
              wallet.ownsAddressSync(d.fundingAddress, _knownAddresses) &&
              (d.isPending || d.awaitingFundingSignatures || d.isActive),
        )
        .toList();
    final myInvestments = dashboard.openDeals
        .where(
          (d) =>
              wallet.ownsAddressSync(d.investorFundingAddress, _knownAddresses) &&
              (d.awaitingFundingSignatures || d.isActive),
        )
        .toList();
    final saverRequests = dashboard.fundingRequests.where((r) => r.isSaver && !r.matched).toList();
    final investorRequests = dashboard.fundingRequests.where((r) => r.isInvestor && !r.matched).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.hiUser(nameState.name ?? '')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: () => _refreshAll(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settings,
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshAll(context),
        child: wallet.loading && !wallet.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (wallet.error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(wallet.error!),
                      ),
                    ),
                  _SummaryCard(
                    data: data,
                    walletSats: wallet.balanceSats,
                    marketRateEur: dashboard.marketRateEur ?? data?.marketRateEur,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.push('/requests/new/saver'),
                          icon: const Icon(Icons.savings_outlined),
                          label: Text(l10n.saveMoney),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/requests/new/investor'),
                          icon: const Icon(Icons.trending_up),
                          label: Text(l10n.invest),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _RequestSection(title: l10n.savingsRequests, requests: saverRequests, saver: true),
                  const SizedBox(height: 12),
                  _RequestSection(title: l10n.investmentRequests, requests: investorRequests, saver: false),
                  const SizedBox(height: 12),
                  _PendingTopUpSection(deals: myTopUps),
                  if (myInvestments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _DealSection(
                      title: l10n.interests,
                      deals: myInvestments,
                      empty: l10n.noInterestsYet,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({this.data, required this.walletSats, this.marketRateEur});

  final DashboardData? data;
  final int walletSats;
  final double? marketRateEur;

  static String _formatBtc(double btc) {
    if (btc == 0) return '0 BTC';
    var s = btc.toStringAsFixed(8);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return '$s BTC';
  }

  static String _formatShortMarketRate(double rate) {
    if (rate >= 1000) {
      final k = rate / 1000;
      final text = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '${text}k€/BTC';
    }
    return '€${rate.toStringAsFixed(0)}/BTC';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final rateEur = marketRateEur ?? data?.marketRateEur;
    final reserveEur = (rateEur != null && rateEur > 0) ? walletSats / 1e8 * rateEur : null;
    final pendingAmountEurCents = (data?.borrowedDeals ?? const <Deal>[])
        .where((deal) => deal.isPending)
        .fold<int>(0, (sum, deal) => sum + deal.amountEurCents);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.overview, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _row(l10n.spendingSavings, '€${((data?.spendingEurCents ?? 0) / 100).toStringAsFixed(2)}'),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(l10n.availableReserve)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        reserveEur != null
                            ? '€${reserveEur.toStringAsFixed(2)}'
                            : '—',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (pendingAmountEurCents > 0)
                        Text(
                          '€${(pendingAmountEurCents / 100.0).toStringAsFixed(2)} ${l10n.pending}',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatBtc(walletSats / 1e8),
                    style: TextStyle(fontSize: 12, color: muted),
                    textAlign: TextAlign.right,
                  ),
                  if (rateEur != null)
                    Text(
                      _formatShortMarketRate(rateEur),
                      style: TextStyle(fontSize: 12, color: muted),
                      textAlign: TextAlign.right,
                    ),
                ],
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
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))],
      ),
    );
  }
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({required this.title, required this.requests, required this.saver});

  final String title;
  final List<FundingRequest> requests;
  final bool saver;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (requests.isEmpty)
          Text(l10n.noPendingRequests, style: TextStyle(color: Theme.of(context).colorScheme.outline))
        else
          ...requests.map((request) {
            final status = request.awaitingDeposit
                ? (saver ? l10n.awaitingBankTransfer : l10n.awaitingBtcDeposit)
                : request.queued
                    ? l10n.awaitingMatch
                    : request.status;
            return Card(
              child: ListTile(
                title: Text('€${((request.remainingEurCents ?? request.amountEurCents) / 100).toStringAsFixed(2)}'),
                subtitle: Text('$status · ${request.payoutMode}'),
                trailing: request.budgetId != null
                    ? IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => context.push('/deals/${request.budgetId}'),
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }
}

class _PendingTopUpSection extends StatelessWidget {
  const _PendingTopUpSection({required this.deals});

  final List<Deal> deals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (deals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.pendingTopUps, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...deals.map(
          (deal) => Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: Icon(
                deal.awaitingFundingSignatures
                    ? Icons.draw_outlined
                    : Icons.hourglass_top_outlined,
              ),
              title: Text(l10n.pendingTopUpAmount(deal.amountEur.toStringAsFixed(2))),
              subtitle: Text(
                deal.awaitingFundingSignatures
                    ? (deal.borrowerFundingSigned
                        ? 'Awaiting investor funding signature'
                        : 'Sign funding to activate')
                    : l10n.awaitingInvestor,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/deals/${deal.id}'),
            ),
          ),
        ),
      ],
    );
  }
}

class _DealSection extends StatelessWidget {
  const _DealSection({
    required this.title,
    required this.deals,
    required this.empty,
    this.showAccept = false,
  });

  final String title;
  final List<Deal> deals;
  final String empty;
  final bool showAccept;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (deals.isEmpty)
          Text(empty, style: TextStyle(color: Theme.of(context).colorScheme.outline))
        else
          ...deals.map(
            (deal) => Card(
              child: ListTile(
                title: Text('€${deal.amountEur.toStringAsFixed(0)} · ${deal.status}'),
                subtitle: Text(
                  deal.awaitingFundingSignatures
                      ? 'Awaiting funding signatures'
                      : '${deal.period.start} → ${deal.period.end}'
                          '${deal.borrower != null ? ' · ${deal.borrower!.name}' : ''}',
                ),
                trailing: showAccept && deal.isPending
                    ? const Icon(Icons.handshake_outlined)
                    : deal.awaitingFundingSignatures
                        ? const Icon(Icons.draw_outlined)
                        : const Icon(Icons.chevron_right),
                onTap: () => context.push('/deals/${deal.id}'),
              ),
            ),
          ),
      ],
    );
  }
}

class _FundPositionSection extends StatelessWidget {
  const _FundPositionSection({required this.positions});

  final List<FundPosition> positions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.interests, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (positions.isEmpty)
          Text(l10n.noInterestsYet, style: TextStyle(color: Theme.of(context).colorScheme.outline))
        else
          ...positions.map(
            (position) => Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '€${position.interestEur.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      position.periodEnd.length >= 10
                          ? position.periodEnd.substring(0, 10)
                          : position.periodEnd,
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
