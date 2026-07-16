/// Integration test configuration (override via --dart-define).
library;

import 'package:mat_mobile/config/api_config.dart';

class IntegrationConfig {
  static String get apiBaseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    return ApiConfig.baseUrl;
  }

  static const aliceEmail = String.fromEnvironment(
    'TEST_ALICE_EMAIL',
    defaultValue: 'alice@example.com',
  );

  static const bobEmail = String.fromEnvironment(
    'TEST_BOB_EMAIL',
    defaultValue: 'bob@example.com',
  );

  static const claudeEmail = String.fromEnvironment(
    'TEST_CLAUDE_EMAIL',
    defaultValue: 'claude@example.com',
  );

  static const password = String.fromEnvironment(
    'TEST_PASSWORD',
    defaultValue: 'password',
  );

  static const integrationSecret = String.fromEnvironment(
    'INTEGRATION_TEST_SECRET',
    defaultValue: 'dev-integration-secret',
  );

  /// 0.01 BTC on regtest
  static const fundAmountBtc = '0.01';
  static const fundAmountSats = 1000000;

  /// Demo deal flow (see spec/support/demo_flow_helpers.rb)
  static const aliceDepositBtc = '0.021';
  static const bobDepositBtc = '0.1';
  static const dealAmountEur = '1000';
  static const transferAmountEur = '500';
}
