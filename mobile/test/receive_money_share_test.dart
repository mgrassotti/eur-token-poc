import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mat_mobile/l10n/app_localizations.dart';
import 'package:mat_mobile/models/models.dart';
import 'package:mat_mobile/screens/receive_money_screen.dart';
import 'package:mat_mobile/services/relay_api_client.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class _FakeRelayApiClient extends RelayApiClient {
  _FakeRelayApiClient(this.request) : super(baseUrl: 'http://test.invalid');

  final ReceiveRequestInfo request;

  @override
  Future<ReceiveRequestInfo> createReceiveRequest({int? amountEurCents}) async {
    return request;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const payload = 'mat:pay/1?u=2&rid=req-abc&a=5000';
  final request = ReceiveRequestInfo(
    id: 'req-abc',
    user: const User(id: 2, name: 'Alice', email: 'alice@example.com', admin: false),
    amountEurCents: 5000,
    qrPayload: payload,
    expiresAt: DateTime.now().add(const Duration(minutes: 14)),
    paid: false,
    expired: false,
  );

  testWidgets('tapping Share opens share options with the payment link', (tester) async {
    ShareParams? shared;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Provider<RelayApiClient>.value(
          value: _FakeRelayApiClient(request),
          child: ReceiveMoneyScreen(
            sharePaymentLink: (params) async {
              shared = params;
              return ShareResult.unavailable;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Generate request'));
    await tester.pumpAndSettle();

    expect(find.text('Share'), findsOneWidget);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(shared, isNotNull);
    expect(shared!.text, contains(payload));
    expect(shared!.text, 'Pay me via MAT: $payload');
    expect(shared!.sharePositionOrigin, isNotNull);
    expect(shared!.sharePositionOrigin!.width, greaterThan(0));
    expect(shared!.sharePositionOrigin!.height, greaterThan(0));
  });

  testWidgets('tapping Invia opens share options (Italian)', (tester) async {
    ShareParams? shared;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Provider<RelayApiClient>.value(
          value: _FakeRelayApiClient(request),
          child: ReceiveMoneyScreen(
            sharePaymentLink: (params) async {
              shared = params;
              return ShareResult.unavailable;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Genera richiesta'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();

    expect(shared, isNotNull);
    expect(shared!.text, 'Pagami con MAT: $payload');
    expect(shared!.sharePositionOrigin, isNotNull);
  });
}
