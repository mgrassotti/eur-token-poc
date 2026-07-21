import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/relay_api_client.dart';

/// Pay a receive request from a pasted `mat:pay/1?...` link.
///
/// Camera QR scanning is deferred: Google ML Kit (via mobile_scanner) does not
/// support arm64 on Apple Silicon iOS 26+ simulators.
class ScanPayScreen extends StatefulWidget {
  const ScanPayScreen({super.key});

  @override
  State<ScanPayScreen> createState() => _ScanPayScreenState();
}

class _ScanPayScreenState extends State<ScanPayScreen> {
  final _paste = TextEditingController();
  final _amount = TextEditingController();
  ReceiveRequestInfo? _request;
  bool _loading = false;
  bool _paying = false;
  String? _error;

  @override
  void dispose() {
    _paste.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _resolve(String raw) async {
    final l10n = AppLocalizations.of(context);
    final link = MatPayLink.tryParse(raw);
    if (link == null) {
      setState(() => _error = l10n.invalidPaymentLink);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<RelayApiClient>();
      final request = await api.fetchReceiveRequest(link.requestId);
      if (!mounted) return;
      if (request.amountEurCents != null) {
        _amount.text = (request.amountEurCents! / 100).toStringAsFixed(2);
      } else if (link.amountEurCents != null) {
        _amount.text = (link.amountEurCents! / 100).toStringAsFixed(2);
      }
      setState(() {
        _request = request;
        _loading = false;
      });
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _pay() async {
    final request = _request;
    if (request == null) return;
    final l10n = AppLocalizations.of(context);

    int? cents;
    if (request.amountEurCents != null) {
      cents = request.amountEurCents;
    } else {
      try {
        cents = (double.parse(_amount.text.replaceAll(',', '.')) * 100).round();
      } catch (_) {
        setState(() => _error = l10n.enterValidAmount);
        return;
      }
      if (cents <= 0) {
        setState(() => _error = l10n.enterValidAmount);
        return;
      }
    }

    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final api = context.read<RelayApiClient>();
      await api.payReceiveRequest(
        receiveRequestId: request.id,
        amountEurCents: request.amountEurCents == null ? cents : null,
      );
      if (!mounted) return;
      await context.read<DashboardState>().refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.sentTo((cents! / 100).toStringAsFixed(2), request.user.name),
          ),
        ),
      );
      context.pop();
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _paying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final request = _request;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pastePaymentLink)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (request == null) ...[
            TextField(
              controller: _paste,
              decoration: InputDecoration(
                labelText: l10n.pastePaymentLink,
                border: const OutlineInputBorder(),
                hintText: 'mat:pay/1?u=…&rid=…',
              ),
              minLines: 2,
              maxLines: 4,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : () => _resolve(_paste.text),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.payRequest),
            ),
          ] else ...[
            Text(
              l10n.payingTo(request.user.name),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              readOnly: request.amountEurCents != null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.amountEur,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _paying ? null : _pay,
              child: _paying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.pay),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
