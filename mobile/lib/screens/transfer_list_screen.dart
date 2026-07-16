import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.transferSent)));
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
    final l10n = AppLocalizations.of(context);
    final api = context.read<RelayApiClient>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.transfers)),
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
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _submitting ? null : () => _send(api),
                        child: _submitting
                            ? const CircularProgressIndicator()
                            : Text(l10n.sendEurt),
                      ),
                    ],
                  ),
                ),
                if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                Expanded(
                  child: _transfers.isEmpty
                      ? Center(child: Text(l10n.noTransfersYet))
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
