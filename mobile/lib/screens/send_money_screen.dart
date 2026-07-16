import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
    setState(() => _submitting = true);
    try {
      final cents = (double.parse(_amount.text.replaceAll(',', '.')) * 100).round();
      await api.sendMoney(toUserId: _recipient!.id, amountEurCents: cents);
      if (!mounted) return;

      await context.read<DashboardState>().refresh();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent €${(cents / 100).toStringAsFixed(2)} to ${_recipient!.name}')),
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
    final api = context.read<RelayApiClient>();
    final spendingEur = _spendingEurCents / 100;

    return Scaffold(
      appBar: AppBar(title: const Text('Send money')),
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
                        FilledButton(onPressed: _load, child: const Text('Retry')),
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
                        'Available: €${spendingEur.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      if (_spendingEurCents == 0)
                        Text(
                          'No spending balance yet. Activate a deal or receive EURT first.',
                          style: TextStyle(color: Theme.of(context).colorScheme.outline),
                        )
                      else ...[
                        DropdownButtonFormField<User>(
                          value: _recipient,
                          decoration: const InputDecoration(
                            labelText: 'Recipient',
                            border: OutlineInputBorder(),
                          ),
                          items: _users
                              .map((u) => DropdownMenuItem(value: u, child: Text(u.name)))
                              .toList(),
                          onChanged: (u) => setState(() => _recipient = u),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _amount,
                          decoration: const InputDecoration(
                            labelText: 'Amount (EUR)',
                            border: OutlineInputBorder(),
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
                              : const Text('Send'),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
