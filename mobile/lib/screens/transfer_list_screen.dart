import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/relay_api_client.dart';

class TransferListScreen extends StatefulWidget {
  const TransferListScreen({super.key, required this.dealId});

  final String dealId;

  @override
  State<TransferListScreen> createState() => _TransferListScreenState();
}

class _TransferListScreenState extends State<TransferListScreen> {
  List<TransferRecord> _transfers = [];
  List<User> _users = [];
  User? _recipient;
  final _amount = TextEditingController();
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
    final api = context.read<RelayApiClient>();
    try {
      final transfers = await api.fetchTransfers(widget.dealId);
      final users = await api.fetchUsers();
      if (mounted) {
        setState(() {
          _transfers = transfers;
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
      await api.createTransfer(
        dealId: widget.dealId,
        toUserId: _recipient!.id,
        amountEurCents: cents,
      );
      _amount.clear();
      await _load();
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transfer sent')));
      }
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

    return Scaffold(
      appBar: AppBar(title: const Text('Transfers')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
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
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _submitting ? null : () => _send(api),
                        child: _submitting
                            ? const CircularProgressIndicator()
                            : const Text('Send EURT'),
                      ),
                    ],
                  ),
                ),
                if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                Expanded(
                  child: _transfers.isEmpty
                      ? const Center(child: Text('No transfers yet'))
                      : ListView.builder(
                          itemCount: _transfers.length,
                          itemBuilder: (_, i) {
                            final t = _transfers[i];
                            return ListTile(
                              title: Text('€${(t.amountCents / 100).toStringAsFixed(2)}'),
                              subtitle: Text('${t.fromUser.name} → ${t.toUser.name}'),
                              trailing: Text(t.createdAt.substring(0, 10)),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
