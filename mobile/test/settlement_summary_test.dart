import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mat_mobile/l10n/app_localizations.dart';
import 'package:mat_mobile/models/models.dart';
import 'package:mat_mobile/screens/settlement_summary_screen.dart';
import 'package:mat_mobile/services/relay_api_client.dart';
import 'package:provider/provider.dart';

/// PAYOFF-SPEC §5 peg-spot fixture (matches mat_sdk / mat-core).
const _inputs = SettlementCalculationInputs(
  notionalEurCents: 500000,
  notionalTotalCents: 500000,
  holderSharesCents: [500000],
  spotEurPerBtc: 50000,
  rateBpsMonthly: 100,
  monthsElapsed: 6,
  escrowTotalSats: 50000000,
  miningFeeSats: 0,
);

const _matchingPayoff = PayoffSummary(
  liabilityEurCents: 530000,
  totalHolderSats: 10600000,
  investorRemainderSats: 39400000,
  insolvent: false,
);

const _mismatchedPayoff = PayoffSummary(
  liabilityEurCents: 530000,
  totalHolderSats: 9999999,
  investorRemainderSats: 39400000,
  insolvent: false,
);

const _bob = User(id: 2, name: 'Bob', email: 'bob@example.com', admin: false);

class _FakeRelayApiClient extends RelayApiClient {
  _FakeRelayApiClient(this.preview) : super(baseUrl: 'http://test.invalid');

  final SettlementPreview preview;

  @override
  Future<SettlementPreview> fetchSettlement(String dealId) async => preview;
}

Widget _harness(SettlementPreview preview) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Provider<RelayApiClient>.value(
      value: _FakeRelayApiClient(preview),
      child: const SettlementSummaryScreen(dealId: '42'),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recomputes FloorEUR on-device when calculation_inputs present', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SettlementPreview(
          status: 'preview',
          endBtcEurRate: 50000,
          readyForSettlement: false,
          payoff: _matchingPayoff,
          holderAllocations: [
            HolderAllocation(user: _bob, shareCents: 500000, btcSats: 10600000),
          ],
          calculationInputs: _inputs,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settlement'), findsOneWidget);
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(find.text('FloorEUR payoff'), findsOneWidget);
    expect(find.text('Recomputed on-device (mat_sdk)'), findsOneWidget);
    expect(find.text('€5300.00'), findsOneWidget);
    expect(find.text('10600000'), findsOneWidget);
    expect(find.text('39400000 sats'), findsOneWidget);
    expect(find.textContaining('On-device FloorEUR does not match'), findsNothing);
    expect(
      find.textContaining('amounts shown are recomputed on-device via mat_sdk'),
      findsOneWidget,
    );
  });

  testWidgets('shows mismatch warning when server payoff disagrees', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SettlementPreview(
          status: 'preview',
          endBtcEurRate: 50000,
          readyForSettlement: false,
          payoff: _mismatchedPayoff,
          calculationInputs: _inputs,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // On-device values still shown (not the wrong server holder sats).
    expect(find.text('10600000'), findsOneWidget);
    expect(find.text('9999999'), findsNothing);
    expect(
      find.textContaining('On-device FloorEUR does not match the relay preview'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to server payoff when calculation_inputs absent', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SettlementPreview(
          status: 'preview',
          endBtcEurRate: 50000,
          readyForSettlement: false,
          payoff: _matchingPayoff,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FloorEUR payoff'), findsOneWidget);
    expect(find.text('€5300.00'), findsOneWidget);
    expect(find.text('10600000'), findsOneWidget);
    expect(find.text('Recomputed on-device (mat_sdk)'), findsNothing);
  });
}
