import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/relay_api_client.dart';

/// Optional override for [SharePlus.instance.share] (tests / custom hosts).
typedef SharePaymentLinkFn = Future<ShareResult> Function(ShareParams params);

class ReceiveMoneyScreen extends StatefulWidget {
  const ReceiveMoneyScreen({super.key, this.sharePaymentLink});

  /// When set, used instead of the native share sheet (widget tests).
  final SharePaymentLinkFn? sharePaymentLink;

  @override
  State<ReceiveMoneyScreen> createState() => _ReceiveMoneyScreenState();
}

class _ReceiveMoneyScreenState extends State<ReceiveMoneyScreen> {
  final _amount = TextEditingController();
  final _shareButtonKey = GlobalKey();
  ReceiveRequestInfo? _request;
  bool _loading = false;
  String? _error;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  @override
  void dispose() {
    _amount.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(DateTime expiresAt) {
    _countdownTimer?.cancel();
    _updateRemaining(expiresAt);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining(expiresAt);
    });
  }

  void _updateRemaining(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (!mounted) return;
    setState(() {
      _remaining = remaining.isNegative ? Duration.zero : remaining;
    });
    if (_remaining == Duration.zero) {
      _countdownTimer?.cancel();
    }
  }

  bool get _isExpired => (_request?.expired ?? false) || _remaining == Duration.zero;

  String _formatCountdown(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatClockTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hours = local.hour.toString().padLeft(2, '0');
    final minutes = local.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
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
      _startCountdown(request.expiresAt);
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

  Future<void> _shareLink() async {
    final request = _request;
    if (request == null) return;
    final l10n = AppLocalizations.of(context);
    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    // iOS 26+ requires a non-zero sharePositionOrigin or the share sheet fails.
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    final params = ShareParams(
      text: l10n.sharePaymentLinkMessage(request.qrPayload),
      sharePositionOrigin: origin,
    );

    try {
      final share = widget.sharePaymentLink ?? SharePlus.instance.share;
      await share(params);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
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
            if (_isExpired)
              Text(
                l10n.requestExpiredMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else
              Text(
                l10n.requestExpiresCountdown(
                  _formatCountdown(_remaining),
                  _formatClockTime(request.expiresAt),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyLink,
                    icon: const Icon(Icons.copy),
                    label: Text(l10n.copyPaymentLink),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: _shareButtonKey,
                    onPressed: _shareLink,
                    icon: const Icon(Icons.share),
                    label: Text(l10n.sharePaymentLink),
                  ),
                ),
              ],
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
