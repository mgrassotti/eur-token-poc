import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/relay_api_client.dart';

class ReceiveMoneyScreen extends StatefulWidget {
  const ReceiveMoneyScreen({super.key});

  @override
  State<ReceiveMoneyScreen> createState() => _ReceiveMoneyScreenState();
}

class _ReceiveMoneyScreenState extends State<ReceiveMoneyScreen> {
  final _amount = TextEditingController();
  ReceiveRequestInfo? _request;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<RelayApiClient>();
      int? cents;
      final raw = _amount.text.trim();
      if (raw.isNotEmpty) {
        cents = (double.parse(raw.replaceAll(',', '.')) * 100).round();
        if (cents <= 0) throw FormatException(l10n.enterValidAmount);
      }
      final request = await api.createReceiveRequest(amountEurCents: cents);
      if (!mounted) return;
      setState(() {
        _request = request;
        _loading = false;
      });
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
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

  void _copyLink() {
    final request = _request;
    if (request == null) return;
    final l10n = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: request.qrPayload));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.paymentLinkCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final request = _request;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.receiveMoneyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.optionalAmountEur,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _generate,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.generateRequest),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (request != null) ...[
            const SizedBox(height: 24),
            Text(l10n.showThisQr, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.requestExpires(
                TimeOfDay.fromDateTime(request.expiresAt.toLocal()).format(context),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: QrImageView(
                data: request.qrPayload,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.copy),
              label: Text(l10n.copyPaymentLink),
            ),
            const SizedBox(height: 8),
            SelectableText(
              request.qrPayload,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
