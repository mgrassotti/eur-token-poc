import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/api_config.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_state.dart';
import 'screens/add_funds_screen.dart';
import 'screens/create_deal_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/deal_detail_screen.dart';
// import 'screens/login_screen.dart'; // Saved for future: bank transfer deposits
import 'screens/local_wallet_debug_screen.dart';
import 'screens/name_form_screen.dart';
import 'screens/receive_money_screen.dart';
import 'screens/scan_pay_screen.dart';
import 'screens/send_money_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/settlement_summary_screen.dart';
import 'screens/transfer_list_screen.dart';
import 'services/relay_api_client.dart';

void bootstrap({RelayApiClient? api, String? apiBaseUrl}) {
  final client = api ?? RelayApiClient(baseUrl: apiBaseUrl ?? ApiConfig.baseUrl);
  runApp(MatApp(api: client));
}

void main() => bootstrap();

class MatApp extends StatelessWidget {
  const MatApp({super.key, required this.api});

  final RelayApiClient api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<RelayApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider(create: (_) => NameState()),
        ChangeNotifierProvider(create: (_) => AuthState(api)),
        ChangeNotifierProvider(create: (_) => DashboardState(api)),
        ChangeNotifierProxyProvider2<SettingsState, AuthState, WalletState>(
          create: (context) {
            final settings = context.read<SettingsState>();
            final api = context.read<RelayApiClient>();
            return WalletState(electrumUrl: settings.electrumUrl, api: api);
          },
          update: (context, settings, auth, previous) {
            final api = context.read<RelayApiClient>();
            return previous ?? WalletState(electrumUrl: settings.electrumUrl, api: api);
          },
        ),
      ],
      child: const MatAppRouter(),
    );
  }
}

class MatAppRouter extends StatelessWidget {
  const MatAppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final nameState = context.watch<NameState>();
    final settings = context.watch<SettingsState>();

    final router = GoRouter(
      initialLocation: nameState.hasName ? '/' : '/name',
      refreshListenable: nameState,
      redirect: (context, state) {
        final hasName = nameState.hasName;
        final onNameForm = state.matchedLocation == '/name';
        if (!hasName && !onNameForm) return '/name';
        if (hasName && onNameForm) return '/';
        return null;
      },
      routes: [
        // GoRoute(path: '/login', builder: (_, __) => const LoginScreen()), // Saved for future: bank transfer deposits
        GoRoute(path: '/name', builder: (_, __) => const NameFormScreen()),
        GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/reserve/add-funds', builder: (_, __) => const AddFundsScreen()),
        GoRoute(path: '/send-money', builder: (_, __) => const SendMoneyScreen()),
        GoRoute(path: '/receive-money', builder: (_, __) => const ReceiveMoneyScreen()),
        GoRoute(path: '/scan-pay', builder: (_, __) => const ScanPayScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(
          path: '/settings/local-wallet',
          builder: (_, __) => const LocalWalletDebugScreen(),
        ),
        GoRoute(path: '/deals/new', builder: (_, __) => const CreateDealScreen()),
        GoRoute(
          path: '/deals/:id',
          builder: (_, state) => DealDetailScreen(dealId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/deals/:id/transfers',
          builder: (_, state) => TransferListScreen(dealId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/deals/:id/settlement',
          builder: (_, state) => SettlementSummaryScreen(dealId: state.pathParameters['id']!),
        ),
      ],
    );

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: settings.locale,
      supportedLocales: SettingsState.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4332)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
