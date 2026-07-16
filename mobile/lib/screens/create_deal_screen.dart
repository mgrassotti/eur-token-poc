import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_state.dart';
import '../services/relay_api_client.dart';

class CreateDealScreen extends StatefulWidget {
  const CreateDealScreen({super.key});

  /// One symbolic month on regtest (~30.25 days), aligned with Budget::DAYS_PER_SYMBOLIC_MONTH.
  static const topUpDuration = Duration(milliseconds: 2613600000);

  @override
  State<CreateDealScreen> createState() => _CreateDealScreenState();
}

class _CreateDealScreenState extends State<CreateDealScreen> {
  final _amount = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  int _maxBorrowableEurCents = 0;

  late final DateTime _start;
  late final DateTime _expiration;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _expiration = now.add(CreateDealScreen.topUpDuration);
    _loadLimits();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadLimits() async {
    try {
      final api = context.read<RelayApiClient>();
      final dashboard = await api.fetchDashboard();
      if (!mounted) return;

      final maxCents = dashboard.maxBorrowableEurCents;
      setState(() {
        _maxBorrowableEurCents = maxCents;
        _amount.text = maxCents > 0 ? (maxCents / 100).toStringAsFixed(2) : '';
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

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int? _enteredCents() {
    final raw = _amount.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  Future<void> _submit(RelayApiClient api) async {
    final l10n = AppLocalizations.of(context);
    final cents = _enteredCents();
    if (cents == null) {
      setState(() => _error = l10n.enterValidAmount);
      return;
    }
    if (cents > _maxBorrowableEurCents) {
      setState(() {
        _error = l10n.amountExceedsReserve((_maxBorrowableEurCents / 100).toStringAsFixed(2));
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await api.createDeal(
        amountEurCents: cents,
        periodStart: _isoDate(_start),
        periodEnd: _isoDate(_expiration),
      );
      if (mounted) {
        await context.read<DashboardState>().refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.topUpSubmitted)),
        );
        context.go('/');
      }
    } on RelayApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final api = context.read<RelayApiClient>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final maxEur = _maxBorrowableEurCents / 100;
    final expirationLabel = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .add_jm()
        .format(_expiration);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.topUpTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_maxBorrowableEurCents == 0) ...[
                    Text(
                      l10n.noReserveToTopUp,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ] else ...[
                    TextField(
                      controller: _amount,
                      decoration: InputDecoration(
                        labelText: l10n.amountEur,
                        border: const OutlineInputBorder(),
                        prefixText: '€ ',
                        helperText: l10n.maxFromReserve(maxEur.toStringAsFixed(2)),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.estimatedExpiration,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      expirationLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.expirationNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const Spacer(),
                  FilledButton(
                    onPressed: _submitting || _maxBorrowableEurCents == 0 ? null : () => _submit(api),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.topUp),
                  ),
                ],
              ),
            ),
    );
  }
}
