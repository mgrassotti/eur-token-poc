import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mat_mobile/l10n/app_localizations.dart';
import 'package:mat_mobile/screens/local_wallet_debug_screen.dart';
import 'package:mat_mobile/services/local_wallet_service.dart';

/// Fake wallet — native BDK cannot run under plain `flutter test`.
class _FakeLocalWallet implements LocalWalletApi {
  _FakeLocalWallet({this.loadedAddress});

  String? loadedAddress;
  var createCalls = 0;

  @override
  Future<bool> tryLoad() async => loadedAddress != null;

  @override
  Future<String> create() async {
    createCalls += 1;
    loadedAddress = 'tb1qtestlocalwalletaddress00000000000000';
    return 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  }

  @override
  Future<String> receiveAddress() async {
    final address = loadedAddress;
    if (address == null) {
      throw StateError('Wallet not loaded');
    }
    return address;
  }
}

Widget _harness(LocalWalletApi wallet) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: LocalWalletDebugScreen(wallet: wallet),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty wallet shows create button', (tester) async {
    final wallet = _FakeLocalWallet();
    await tester.pumpWidget(_harness(wallet));
    await tester.pumpAndSettle();

    expect(find.text('Local wallet (BDK spike)'), findsOneWidget);
    expect(find.textContaining('Phase 2: create/load mnemonic'), findsOneWidget);
    expect(find.text('Create wallet'), findsOneWidget);
    expect(find.text('Receive address'), findsNothing);
  });

  testWidgets('create wallet shows receive address', (tester) async {
    final wallet = _FakeLocalWallet();
    await tester.pumpWidget(_harness(wallet));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create wallet'));
    await tester.pumpAndSettle();

    expect(wallet.createCalls, 1);
    expect(find.text('Receive address'), findsOneWidget);
    expect(find.text('tb1qtestlocalwalletaddress00000000000000'), findsOneWidget);
    expect(find.textContaining('Mnemonic stored on device'), findsOneWidget);
    expect(find.text('Create wallet'), findsNothing);
  });

  testWidgets('loaded wallet shows address without create', (tester) async {
    final wallet = _FakeLocalWallet(loadedAddress: 'tb1qalreadyloadedaddress0000000000000');
    await tester.pumpWidget(_harness(wallet));
    await tester.pumpAndSettle();

    expect(find.text('tb1qalreadyloadedaddress0000000000000'), findsOneWidget);
    expect(find.text('Create wallet'), findsNothing);
  });
}
