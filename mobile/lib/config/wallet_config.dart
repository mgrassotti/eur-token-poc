import 'dart:io' show Platform;

/// Phase 2 BDK wallet configuration.
///
/// Provides Electrum server URLs for different Bitcoin networks.
class WalletConfig {
  /// Electrum URL for regtest (local development).
  ///
  /// Expects `./bin/regtest up` running with electrs on port 50001.
  /// Override at build time: `--dart-define=REGTEST_ELECTRUM_URL=tcp://192.168.1.10:50001`
  static String get regtestElectrumUrl {
    const override = String.fromEnvironment('REGTEST_ELECTRUM_URL');
    if (override.isNotEmpty) return override;

    if (Platform.isAndroid) {
      return 'tcp://10.0.2.2:50001'; // Android emulator host
    }
    return 'tcp://127.0.0.1:50001'; // iOS simulator / macOS
  }

  /// Electrum URL for testnet (public testing).
  ///
  /// Uses Blockstream's public testnet Electrum server.
  static String get testnetElectrumUrl {
    const override = String.fromEnvironment('TESTNET_ELECTRUM_URL');
    if (override.isNotEmpty) return override;

    return 'ssl://electrum.blockstream.info:60002';
  }

  /// Electrum URL for mainnet (production).
  ///
  /// Uses Blockstream's public mainnet Electrum server.
  /// WARNING: For production, consider running your own Electrum server.
  static String get mainnetElectrumUrl {
    const override = String.fromEnvironment('MAINNET_ELECTRUM_URL');
    if (override.isNotEmpty) return override;

    return 'ssl://electrum.blockstream.info:50002';
  }

  /// Electrum client timeout (seconds).
  ///
  /// Increase if network is slow or initial sync takes too long.
  static const int electrumTimeoutSec = 30;
}
