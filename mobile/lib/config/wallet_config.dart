import 'dart:io' show Platform;

/// Phase 2 local BDK wallet — regtest indexer endpoints.
class WalletConfig {
  /// Electrum URL for the regtest electrs instance (`./bin/regtest up`, port 50001).
  ///
  /// Override at build time, e.g. `--dart-define=REGTEST_ELECTRUM_URL=tcp://192.168.1.10:50001`.
  static String get regtestElectrumUrl {
    const override = String.fromEnvironment('REGTEST_ELECTRUM_URL');
    if (override.isNotEmpty) return override;

    if (Platform.isAndroid) {
      return 'tcp://10.0.2.2:50001';
    }
    return 'tcp://127.0.0.1:50001';
  }

  /// Electrum client timeout (seconds) for regtest sync.
  static const int regtestElectrumTimeoutSec = 15;
}
