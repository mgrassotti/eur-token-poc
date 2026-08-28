import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/app_state.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Set<String> _knownAddresses = {};

  @override
  void initState() {
    super.initState();
    // Phase 2: Sync on-device wallet + fetch public BTC/EUR rate from Rails
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAll(context);
    });
  }

  Future<void> _refreshAll(BuildContext context) async {
    final dashboard = context.read<DashboardState>();
    final wallet = context.read<WalletState>();
    await Future.wait([
      dashboard.refreshMarketRate(),
      dashboard.refreshOpenDeals(),
      if (wallet.isInitialized) wallet.sync(),
    ]);
    if (wallet.isInitialized) {
      final known = await wallet.knownReceiveAddresses();
      if (mounted) setState(() => _knownAddresses = known);
    }
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
    final openToInvest = dashboard.openDeals
        .where(
          (d) =>
              d.isPending &&
              !wallet.ownsAddressSync(d.fundingAddress, _knownAddresses),
        )
        .toList();

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
                  _PendingTopUpSection(deals: myTopUps),
                  if (myInvestments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _DealSection(
                      title: l10n.interests,
                      deals: myInvestments,
                      empty: l10n.noInterestsYet,
                    ),
                  ],
                  const SizedBox(height: 12),
                  if ((data?.spendingEurCents ?? 0) <= 0 && myTopUps.isEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: () => context.push('/deals/new'),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(l10n.topUpSpending),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (wallet.balanceSats <= 0) ...[
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/reserve/add-funds'),
                      icon: const Icon(Icons.qr_code),
                      label: Text(l10n.depositFunds),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/send-money'),
                          icon: const Icon(Icons.send_outlined, size: 18),
                          label: Text(
                            l10n.sendMoney,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/receive-money'),
                          icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                          label: Text(
                            l10n.receiveMoney,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (myInvestments.isEmpty) ...[
                    const SizedBox(height: 16),
                    _FundPositionSection(
                      positions: data?.fundPositions ?? const [],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _DealSection(
                    title: l10n.openToInvest,
                    deals: openToInvest,
                    empty: l10n.noPendingOffers,
                    showAccept: true,
                  ),
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
