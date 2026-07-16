import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
    final dashboard = context.watch<DashboardState>();
    final auth = context.watch<AuthState>();
    final settings = context.watch<SettingsState>();
    final data = dashboard.data;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${auth.user?.name ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
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
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/reserve/add-funds'),
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Deposit funds'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/send-money'),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Send money'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/deals/new'),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Top up spending'),
                  ),
                  const SizedBox(height: 16),
                  _FundPositionSection(
                    positions: data?.fundPositions ?? const [],
                  ),
                  if (settings.advancedFeatures) ...[
                    const SizedBox(height: 16),
                    _DealSection(
                      title: 'Open to invest',
                      deals: data?.investableDeals ?? const [],
                      empty: 'No pending offers from other borrowers.',
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Overview', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _row('Spending / Savings', '€${((data?.spendingEurCents ?? 0) / 100).toStringAsFixed(2)}'),
            _reserveRow(context),
          ],
        ),
      ),
    );
  }

  Widget _reserveRow(BuildContext context) {
    final sats = data?.savingsSats ?? 0;
    final rateEur = data?.marketRateEur;

    if (rateEur == null || rateEur <= 0) {
      return _row('Reserve', '—');
    }

    final btc = sats / 100000000.0;
    final eur = btc * rateEur;
    final subtitle = '(${_formatBtc(btc)} BTC - ${_formatShortMarketRate(rateEur)})';
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Reserve'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${eur.toStringAsFixed(2)}€',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Interests', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (positions.isEmpty)
          Text('No interests yet.', style: TextStyle(color: Theme.of(context).colorScheme.outline))
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
