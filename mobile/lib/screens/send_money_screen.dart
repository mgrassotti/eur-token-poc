import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/relay_api_client.dart';

class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  List<User> _users = [];
  User? _recipient;
  final _amount = TextEditingController();
  int _spendingEurCents = 0;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<RelayApiClient>();
      final dashboard = await api.fetchDashboard();
      final users = await api.fetchUsers();
      if (mounted) {
        setState(() {
          _spendingEurCents = dashboard.spendingEurCents;
          _users = users;
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

  Future<void> _send(RelayApiClient api) async {
    if (_recipient == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _submitting = true);
    try {
      final cents = (double.parse(_amount.text.replaceAll(',', '.')) * 100).round();
      await api.sendMoney(toUserId: _recipient!.id, amountEurCents: cents);
      if (!mounted) return;

      await context.read<DashboardState>().refresh();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sentTo((cents / 100).toStringAsFixed(2), _recipient!.name)),
        ),
      );
      context.pop();
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final api = context.read<RelayApiClient>();
    final spendingEur = _spendingEurCents / 100;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sendMoneyTitle)),
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
                        FilledButton(onPressed: _load, child: Text(l10n.retry)),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.availableEur(spendingEur.toStringAsFixed(2)),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/scan-pay'),
                        icon: const Icon(Icons.link),
                        label: Text(l10n.pastePaymentLink),
                      ),
                      const SizedBox(height: 16),
                      if (_spendingEurCents == 0)
                        Text(
                          l10n.noSpendingBalance,
                          style: TextStyle(color: Theme.of(context).colorScheme.outline),
                        )
                      else ...[
                        DropdownButtonFormField<User>(
                          value: _recipient,
                          decoration: InputDecoration(
                            labelText: l10n.recipient,
                            border: const OutlineInputBorder(),
                          ),
                          items: _users
                              .map((u) => DropdownMenuItem(value: u, child: Text(u.name)))
                              .toList(),
                          onChanged: (u) => setState(() => _recipient = u),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _amount,
                          decoration: InputDecoration(
                            labelText: l10n.amountEur,
                            border: const OutlineInputBorder(),
                            prefixText: '€ ',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _submitting || _recipient == null ? null : () => _send(api),
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(l10n.send),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
