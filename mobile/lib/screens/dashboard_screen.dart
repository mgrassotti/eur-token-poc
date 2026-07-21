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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardState>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dashboard = context.watch<DashboardState>();
    final auth = context.watch<AuthState>();
    final settings = context.watch<SettingsState>();
    final data = dashboard.data;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.hiUser(auth.user?.name ?? '')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settings,
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              auth.logout();
              context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<DashboardState>().refresh(),
        child: dashboard.loading && data == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (dashboard.error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(dashboard.error!),
                      ),
                    ),
                  _SummaryCard(data: data),
                  const SizedBox(height: 12),
                  _PendingTopUpSection(deals: data?.borrowedDeals ?? const []),
                  const SizedBox(height: 12),
                  if ((data?.spendingEurCents ?? 0) <= 0) ...[
                    OutlinedButton.icon(
                      onPressed: () => context.push('/deals/new'),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(l10n.topUpSpending),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if ((data?.savingsSats ?? 0) <= 0) ...[
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
                  const SizedBox(height: 16),
                  _FundPositionSection(
                    positions: data?.fundPositions ?? const [],
                  ),
                  if (settings.advancedFeatures) ...[
                    const SizedBox(height: 16),
                    _DealSection(
                      title: l10n.openToInvest,
                      deals: data?.investableDeals ?? const [],
                      empty: l10n.noPendingOffers,
                      showAccept: true,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({this.data});

  final DashboardData? data;

  static String _formatBtc(double btc) {
    var formatted = btc.toStringAsFixed(8);
    formatted = formatted.replaceFirst(RegExp(r'0+$'), '');
    formatted = formatted.replaceFirst(RegExp(r'\.$'), '');
    return formatted;
  }

  static String _formatShortMarketRate(double rateEur) {
    if (rateEur >= 1000) {
      final thousands = rateEur / 1000;
      if (thousands == thousands.roundToDouble()) {
        return '${thousands.toInt()}k€/BTC';
      }
      final oneDecimal = thousands.toStringAsFixed(1);
      final trimmed = oneDecimal.endsWith('.0') ? oneDecimal.substring(0, oneDecimal.length - 2) : oneDecimal;
      return '${trimmed}k€/BTC';
    }
    return '${rateEur.toStringAsFixed(0)}€/BTC';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.overview, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _row(l10n.spendingSavings, '€${((data?.spendingEurCents ?? 0) / 100).toStringAsFixed(2)}'),
            _reserveRow(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _reserveRow(BuildContext context, AppLocalizations l10n) {
    final sats = data?.savingsSats ?? 0;
    final rateEur = data?.marketRateEur;
    final pendingAmountEurCents = (data?.borrowedDeals ?? const <Deal>[])
        .where((deal) => deal.isPending)
        .fold<int>(0, (sum, deal) => sum + deal.amountEurCents);

    if (rateEur == null || rateEur <= 0) {
      return _row(l10n.availableReserve, '—');
    }

    final btc = sats / 100000000.0;
    final eur = btc * rateEur;
    final availableEur = (eur - (pendingAmountEurCents / 100.0)).clamp(0, double.infinity);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(l10n.availableReserve),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '€${availableEur.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.right,
                ),
                Text(
                  '${_formatBtc(btc)} BTC',
                  style: TextStyle(fontSize: 12, color: muted),
                  textAlign: TextAlign.right,
                ),
                if (pendingAmountEurCents > 0)
                  Text(
                    '€${(pendingAmountEurCents / 100.0).toStringAsFixed(2)} ${l10n.pending}',
                    style: TextStyle(fontSize: 12, color: muted),
                    textAlign: TextAlign.right,
                  )
                else
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
    final pendingDeals = deals.where((deal) => deal.isPending).toList();
    if (pendingDeals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.pendingTopUps, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...pendingDeals.map(
          (deal) => Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.hourglass_top_outlined),
              title: Text(l10n.pendingTopUpAmount(deal.amountEur.toStringAsFixed(2))),
              subtitle: Text(l10n.awaitingInvestor),
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
                  '${deal.period.start} → ${deal.period.end}'
                  '${deal.borrower != null ? ' · ${deal.borrower!.name}' : ''}',
                ),
                trailing: showAccept && deal.isPending
                    ? const Icon(Icons.handshake_outlined)
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
                      position.periodEnd.substring(0, 10),
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
