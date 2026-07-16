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
import 'screens/login_screen.dart';
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
        ChangeNotifierProvider(create: (_) => AuthState(api)),
        ChangeNotifierProvider(create: (_) => DashboardState(api)),
        ChangeNotifierProvider(create: (_) => SettingsState()),
      ],
      child: const MatAppRouter(),
    );
  }
}

class MatAppRouter extends StatelessWidget {
  const MatAppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final settings = context.watch<SettingsState>();

    final router = GoRouter(
      initialLocation: auth.isLoggedIn ? '/' : '/login',
      refreshListenable: auth,
      redirect: (context, state) {
        final loggedIn = auth.isLoggedIn;
        final loggingIn = state.matchedLocation == '/login';
        if (!loggedIn && !loggingIn) return '/login';
        if (loggedIn && loggingIn) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/reserve/add-funds', builder: (_, __) => const AddFundsScreen()),
        GoRoute(path: '/send-money', builder: (_, __) => const SendMoneyScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
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
