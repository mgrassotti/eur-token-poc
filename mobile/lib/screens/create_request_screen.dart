import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/relay_api_client.dart';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key, required this.role});

  final String role;

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _amount = TextEditingController();
  final _iban = TextEditingController();
  String _payoutMode = 'keep_btc';
  bool _submitting = false;
  String? _error;
  FundingRequest? _created;

  bool get _isSaver => widget.role == 'saver';

  @override
  void dispose() {
    _amount.dispose();
    _iban.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final wallet = context.read<WalletState>();
    final nameState = context.read<NameState>();
    final address = wallet.receiveAddress;
    final euros = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (address == null || euros == null || euros <= 0) {
      setState(() => _error = 'Wallet or amount not ready');
      return;
    }
    if (_isSaver && _payoutMode == 'eur' && _iban.text.trim().isEmpty) {
      setState(() => _error = l10n.yourIban);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = context.read<RelayApiClient>();
      final created = await api.createFundingRequest(
        role: widget.role,
        amountEurCents: (euros * 100).round(),
        receiveAddress: address,
        payoutMode: _isSaver ? _payoutMode : (_payoutMode == 'eur' ? 'keep_btc' : _payoutMode),
        payoutIban: _payoutMode == 'eur' ? _iban.text.trim() : null,
        displayName: nameState.name,
      );
      if (!mounted) return;
      setState(() {
        _created = created;
        _submitting = false;
      });
    } on RelayApiException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = '$e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final created = _created;
    return Scaffold(
      appBar: AppBar(title: Text(_isSaver ? l10n.saveMoney : l10n.invest)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.onePercentMonth, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (created != null) ...[
            if (_isSaver) ...[
              Text(l10n.matIban),
              const SizedBox(height: 8),
              SelectableText(created.collectionIban, style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: created.collectionIban));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.addressCopied)));
                },
                child: Text(l10n.copyAddress),
              ),
              const SizedBox(height: 16),
              Text(l10n.awaitingBankTransfer),
            ] else ...[
              Text(l10n.awaitingBtcDeposit),
              const SizedBox(height: 8),
              SelectableText(created.receiveAddress, style: const TextStyle(fontFamily: 'monospace')),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.go('/'), child: Text(l10n.home)),
          ] else ...[
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'EUR', prefixText: '€ '),
            ),
            const SizedBox(height: 16),
            Text(l10n.onePercentMonth),
            RadioListTile<String>(
              title: Text(l10n.payoutKeepBtc),
              value: 'keep_btc',
              groupValue: _payoutMode,
              onChanged: (v) => setState(() => _payoutMode = v!),
            ),
            RadioListTile<String>(
              title: Text(l10n.payoutReinvest),
              value: 'reinvest',
              groupValue: _payoutMode,
              onChanged: (v) => setState(() => _payoutMode = v!),
            ),
            if (_isSaver)
              RadioListTile<String>(
                title: Text(l10n.payoutEur),
                value: 'eur',
                groupValue: _payoutMode,
                onChanged: (v) => setState(() => _payoutMode = v!),
              ),
            if (_isSaver && _payoutMode == 'eur')
              TextField(
                controller: _iban,
                decoration: InputDecoration(labelText: l10n.yourIban),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting ? const CircularProgressIndicator() : Text(_isSaver ? l10n.saveMoney : l10n.invest),
            ),
          ],
        ],
      ),
    );
  }
}
