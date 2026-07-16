import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
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
  bool _accepting = false;

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
      final deal = await api.fetchDeal(widget.dealId);
      if (mounted) {
        setState(() {
          _deal = deal;
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

  Future<void> _accept(RelayApiClient api) async {
    setState(() => _accepting = true);
    try {
      final deal = await api.acceptDeal(widget.dealId);
      context.read<DashboardState>().refresh();
      if (mounted) {
        setState(() {
          _deal = deal;
          _accepting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deal activated')),
        );
      }
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() => _accepting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final deal = _deal;
    final canAccept = deal != null &&
        deal.isPending &&
        deal.borrower?.id != auth.user?.id;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Home',
          onPressed: () => context.go('/'),
        ),
        title: Text('Deal #${widget.dealId}'),
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
                      _info('Amount', '€${deal.amountEur.toStringAsFixed(2)}'),
                      _info('Rate', '${deal.rateBpsMonthly / 100}% / month'),
                      _info('Period', '${deal.period.start} → ${deal.period.end}'),
                      _info('Borrower', deal.borrower?.name ?? '—'),
                      _info('Investor', deal.investor?.name ?? '—'),
                      if (deal.pegEurPerBtc != null)
                        _info('Peg', '€${deal.pegEurPerBtc!.toStringAsFixed(0)}/BTC'),
                      if (deal.poolSats > 0) _info('Pool', '${deal.poolSats} sats'),
                      if (deal.liabilityEurCents != null)
                        _info(
                          'Liability at maturity',
                          '€${(deal.liabilityEurCents! / 100).toStringAsFixed(2)}',
                        ),
                      if (deal.tokenHolders.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('Token holders', style: Theme.of(context).textTheme.titleMedium),
                        ...deal.tokenHolders.map(
                          (h) => ListTile(
                            title: Text(h.user.name),
                            trailing: Text('€${(h.balanceCents / 100).toStringAsFixed(2)}'),
                            subtitle: h.interestCents != null
                                ? Text('+€${(h.interestCents! / 100).toStringAsFixed(2)} interest')
                                : null,
                          ),
                        ),
                      ],
                      if (canAccept) ...[
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _accepting
                              ? null
                              : () => _accept(context.read<RelayApiClient>()),
                          child: _accepting
                              ? const CircularProgressIndicator()
                              : const Text('Accept & activate'),
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
    Color color;
    switch (status) {
      case 'active':
        color = Colors.green;
      case 'settled':
        color = Colors.blue;
      default:
        color = Colors.orange;
    }
    return Chip(
      label: Text(status.toUpperCase()),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color),
    );
  }
}
