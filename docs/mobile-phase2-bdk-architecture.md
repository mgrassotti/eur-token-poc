# Phase 2 - BDK Architecture & FFI Integration

**Obiettivo:** Definire l'architettura per integrare BDK (Bitcoin Dev Kit) nella mobile app tramite FFI (Foreign Function Interface), sostituendo le chiamate Rails per gestione wallet L1.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App (Dart)                │
│                                                     │
│  ┌─────────────┐         ┌──────────────────────┐ │
│  │ UI Screens  │────────▶│   WalletApi          │ │
│  │ (Dart)      │         │   (interface)        │ │
│  └─────────────┘         └──────────────────────┘ │
│                                  │                  │
│                                  ▼                  │
│                          ┌──────────────────────┐  │
│                          │ BdkWalletService     │  │
│                          │ (Dart implementation)│  │
│                          └──────────────────────┘  │
│                                  │                  │
└──────────────────────────────────┼──────────────────┘
                                   │ FFI calls
                                   ▼
┌──────────────────────────────────────────────────────┐
│           bdk_flutter Plugin (Rust→Dart FFI)         │
│  ┌──────────────────────────────────────────────┐   │
│  │  Rust BDK Core                               │   │
│  │  - Wallet management                         │   │
│  │  - Descriptor parsing                        │   │
│  │  - PSBT signing                              │   │
│  │  - Coin selection                            │   │
│  └──────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │   Electrum / Esplora     │
        │   (Bitcoin indexer)      │
        └──────────────────────────┘
                       │
                       ▼
              ┌────────────────┐
              │  Bitcoin L1    │
              └────────────────┘
```

---

## Component Breakdown

### 1. Flutter Layer (Dart)

#### 1.1 WalletApi Interface

```dart
/// Abstract interface for wallet operations.
/// Enables testing with mock implementations.
abstract class WalletApi {
  /// Creates or loads a wallet from a mnemonic phrase.
  /// Returns the first receive address.
  Future<String> createWallet(String mnemonic);

  /// Restores wallet from existing mnemonic.
  /// Performs full blockchain sync.
  Future<void> restoreWallet(String mnemonic);

  /// Returns the next unused receive address (BIP84).
  Future<String> getReceiveAddress();

  /// Returns confirmed + unconfirmed balance in sats.
  Future<int> getBalance();

  /// Syncs wallet state with blockchain via Electrum.
  Future<void> sync();

  /// Lists all unspent transaction outputs (UTXOs).
  Future<List<Utxo>> listUnspent();

  /// Signs a Partially Signed Bitcoin Transaction (PSBT).
  /// Used for DLC funding (Phase 3).
  Future<String> signPsbt(String psbtBase64);

  /// Closes wallet and cleans up resources.
  Future<void> close();
}

/// UTXO representation (for coin selection)
class Utxo {
  final String txid;
  final int vout;
  final int valueSats;
  final String address;

  Utxo({
    required this.txid,
    required this.vout,
    required this.valueSats,
    required this.address,
  });
}
```

---

#### 1.2 BdkWalletService Implementation

```dart
import 'package:bdk_flutter/bdk_flutter.dart';
import '../config/wallet_config.dart';

class BdkWalletService implements WalletApi {
  Wallet? _wallet;
  Blockchain? _blockchain;
  final Network network;

  BdkWalletService({this.network = Network.regtest});

  @override
  Future<String> createWallet(String mnemonic) async {
    final mnemonicObj = await Mnemonic.fromString(mnemonic);
    final descriptorSecretKey = await DescriptorSecretKey.create(
      network: network,
      mnemonic: mnemonicObj,
    );

    // BIP84 descriptor (native segwit)
    final external = await Descriptor.newBip84(
      secretKey: descriptorSecretKey,
      keychain: KeychainKind.externalChain,
      network: network,
    );
    final internal = await Descriptor.newBip84(
      secretKey: descriptorSecretKey,
      keychain: KeychainKind.internalChain,
      network: network,
    );

    _wallet = await Wallet.create(
      descriptor: external,
      changeDescriptor: internal,
      network: network,
      databaseConfig: DatabaseConfig.sqlite(
        config: SqliteDbConfiguration(path: _dbPath()),
      ),
    );

    // Initial sync
    _blockchain = await _blockchainClient();
    await _wallet!.sync(blockchain: _blockchain!);

    return await getReceiveAddress();
  }

  @override
  Future<String> getReceiveAddress() async {
    if (_wallet == null) throw StateError('Wallet not initialized');

    final addressInfo = await _wallet!.getAddress(
      addressIndex: const AddressIndex.lastUnused(),
    );
    return addressInfo.address.asString();
  }

  @override
  Future<int> getBalance() async {
    if (_wallet == null) throw StateError('Wallet not initialized');

    final balance = await _wallet!.getBalance();
    return balance.total.toInt();
  }

  @override
  Future<void> sync() async {
    if (_wallet == null || _blockchain == null) {
      throw StateError('Wallet not initialized');
    }
    await _wallet!.sync(blockchain: _blockchain!);
  }

  @override
  Future<List<Utxo>> listUnspent() async {
    if (_wallet == null) throw StateError('Wallet not initialized');

    final utxos = await _wallet!.listUnspent();
    return utxos.map((u) => Utxo(
      txid: u.outpoint.txid,
      vout: u.outpoint.vout,
      valueSats: u.txout.value.toInt(),
      address: '', // BDK doesn't expose address directly
    )).toList();
  }

  @override
  Future<String> signPsbt(String psbtBase64) async {
    if (_wallet == null) throw StateError('Wallet not initialized');

    // Parse PSBT
    final psbt = await PartiallySignedTransaction.fromString(psbtBase64);

    // Sign with wallet keys
    final signed = await _wallet!.sign(psbt: psbt);

    // Return signed PSBT (still partial for 2-of-2)
    return signed.asString();
  }

  Future<Blockchain> _blockchainClient() async {
    return await Blockchain.create(
      config: BlockchainConfig.electrum(
        config: ElectrumConfig(
          url: WalletConfig.regtestElectrumUrl,
          socks5: null,
          retry: 3,
          timeout: WalletConfig.regtestElectrumTimeoutSec,
          stopGap: 10,
        ),
      ),
    );
  }

  String _dbPath() {
    // Platform-specific path (iOS vs Android)
    return 'wallet_${network.name}.db';
  }

  @override
  Future<void> close() async {
    // BDK cleanup if needed
    _wallet = null;
    _blockchain = null;
  }

  // ... restoreWallet implementation similar to createWallet
}
```

---

#### 1.3 FakeWalletService (Testing)

```dart
/// Mock wallet for testing without BDK native dependencies.
class FakeWalletService implements WalletApi {
  String? _currentAddress;
  int _balance = 0;
  final Map<String, Utxo> _utxos = {};

  @override
  Future<String> createWallet(String mnemonic) async {
    await Future.delayed(Duration(milliseconds: 100)); // Simulate work
    _currentAddress = 'bcrt1qfake...';
    return _currentAddress!;
  }

  @override
  Future<String> getReceiveAddress() async {
    return _currentAddress ?? 'bcrt1qfake...';
  }

  @override
  Future<int> getBalance() async => _balance;

  @override
  Future<void> sync() async {
    // In tests, manually set _balance
  }

  @override
  Future<List<Utxo>> listUnspent() async {
    return _utxos.values.toList();
  }

  // Test helpers
  void setBalance(int sats) => _balance = sats;
  void addUtxo(Utxo utxo) => _utxos[utxo.txid] = utxo;

  // ... other mock implementations
}
```

---

### 2. BDK Flutter Plugin (FFI Layer)

**Provided by:** `bdk_flutter: ^0.31.3` package

**What it does:**
- Wraps Rust BDK library
- Exposes Dart API via FFI
- Handles platform-specific builds (iOS/Android/macOS)

**Key classes:**
- `Wallet` - Main wallet operations
- `Blockchain` - Blockchain client (Electrum/Esplora)
- `Mnemonic` - BIP39 mnemonic handling
- `Descriptor` - Output descriptor (BIP84, etc.)
- `PartiallySignedTransaction` - PSBT handling

**Build process:**
1. Rust code compiled to native libs:
   - iOS: `.framework` (arm64)
   - Android: `.so` (multiple ABIs)
   - macOS: `.dylib` (x86_64/arm64)
2. Dart FFI bindings call into native libs

**No custom FFI code needed** - `bdk_flutter` handles it.

---

### 3. Configuration Layer

#### 3.1 WalletConfig (Already Created)

```dart
import 'dart:io' show Platform;

class WalletConfig {
  /// Electrum URL for regtest
  static String get regtestElectrumUrl {
    const override = String.fromEnvironment('REGTEST_ELECTRUM_URL');
    if (override.isNotEmpty) return override;

    if (Platform.isAndroid) {
      return 'tcp://10.0.2.2:50001'; // Android emulator host
    }
    return 'tcp://127.0.0.1:50001'; // iOS simulator / macOS
  }

  static const int regtestElectrumTimeoutSec = 15;

  // Future: testnet/mainnet configs
  static String get testnetElectrumUrl => 'ssl://electrum.blockstream.info:60002';
  static String get mainnetElectrumUrl => 'ssl://electrum.blockstream.info:50002';
}
```

---

### 4. State Management Integration

#### 4.1 AppState Changes

```dart
// app_state.dart

class WalletState extends ChangeNotifier {
  WalletState(this._wallet);

  final WalletApi _wallet;
  String? receiveAddress;
  int balanceSats = 0;
  bool syncing = false;
  String? error;

  Future<void> initialize() async {
    try {
      // Check if wallet exists, else prompt creation
      receiveAddress = await _wallet.getReceiveAddress();
      await refreshBalance();
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> refreshBalance() async {
    syncing = true;
    error = null;
    notifyListeners();

    try {
      await _wallet.sync();
      balanceSats = await _wallet.getBalance();
    } catch (e) {
      error = e.toString();
    }

    syncing = false;
    notifyListeners();
  }

  Future<void> createNewWallet(String mnemonic) async {
    try {
      receiveAddress = await _wallet.createWallet(mnemonic);
      await refreshBalance();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }
}

// main.dart - Dependency Injection
void main() {
  final useLocalWallet = true; // From SharedPreferences

  final WalletApi wallet = useLocalWallet
      ? BdkWalletService(network: Network.regtest)
      : FakeWalletService(); // Or Rails-backed service

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState(...)),
        ChangeNotifierProvider(create: (_) => WalletState(wallet)),
        // ...
      ],
      child: MyApp(),
    ),
  );
}
```

---

## Data Flow Diagrams

### 4.1 Wallet Creation Flow

```
User
  │
  ├─► Tap "Create Wallet" (WalletSetupScreen)
  │
  ▼
Generate Mnemonic (BDK)
  │
  ├─► Show 12 words to user
  │   User writes down
  │
  ▼
User confirms words (WalletConfirmScreen)
  │
  ▼
BdkWalletService.createWallet(mnemonic)
  │
  ├─► Derive BIP84 descriptor
  ├─► Create SQLite wallet DB
  ├─► Sync with Electrum (initial)
  │
  ▼
Return first receive address
  │
  ▼
Navigate to Dashboard
```

---

### 4.2 Receive Flow

```
User
  │
  ├─► Tap "Add Funds"
  │
  ▼
BdkWalletService.getReceiveAddress()
  │
  ├─► wallet.getAddress(lastUnused)
  │
  ▼
Show QR code + address
  │
User shares address
  │
External wallet sends BTC
  │
  ▼
User taps "Sync balance"
  │
  ▼
BdkWalletService.sync()
  │
  ├─► blockchain.sync()
  ├─► Electrum returns new TXs
  │
  ▼
BdkWalletService.getBalance()
  │
  ▼
UI updates: "Balance: 1,000,000 sats"
```

---

### 4.3 PSBT Signing Flow (Phase 3 Prep)

```
Phase 3: DLC Activation
  │
User taps "Accept Deal"
  │
  ├─► P2P: Receive DLC offer from borrower
  │   (funding PSBT unsigned)
  │
  ▼
BdkWalletService.signPsbt(psbtBase64)
  │
  ├─► Parse PSBT
  ├─► wallet.sign(psbt)
  ├─► Return partially signed PSBT
  │
  ▼
P2P: Send signed PSBT back to borrower
  │
Borrower signs their part
  │
Both parties finalize + broadcast
```

---

## Platform-Specific Considerations

### iOS

**Build:**
- BDK compiled as `.framework`
- Xcode must support arm64 (iPhone/iPad) + x86_64 (Simulator)

**Storage:**
- SQLite DB: `Application Support` directory
- Keychain: Optional mnemonic storage (use `flutter_secure_storage`)

**Permissions:**
- Network access (no permission needed for Electrum)

---

### Android

**Build:**
- BDK compiled as `.so` for multiple ABIs:
  - `armeabi-v7a` (32-bit ARM)
  - `arm64-v8a` (64-bit ARM)
  - `x86` (emulator)
  - `x86_64` (emulator)

**Storage:**
- SQLite DB: `getApplicationDocumentsDirectory()`
- EncryptedSharedPreferences: Optional mnemonic

**Permissions:**
- `INTERNET` (already in manifest)

---

### macOS

**Build:**
- BDK compiled as `.dylib`
- Supports both Intel + Apple Silicon

**Storage:**
- Same as iOS (Application Support)

**Deployment Target:**
- Minimum: macOS 10.15 (set in Podfile ✅)

---

## Error Handling Strategy

### Network Errors

```dart
try {
  await _wallet.sync();
} on ElectrumClientException catch (e) {
  if (e.message.contains('timeout')) {
    throw WalletException('Connection timeout. Check your network.');
  } else if (e.message.contains('connection refused')) {
    throw WalletException('Electrum server unavailable. Try again later.');
  } else {
    throw WalletException('Sync failed: ${e.message}');
  }
} catch (e) {
  throw WalletException('Unexpected error: $e');
}
```

### Insufficient Balance

```dart
Future<void> createDeal(int requiredSats) async {
  final balance = await _wallet.getBalance();
  if (balance < requiredSats) {
    throw InsufficientFundsException(
      'Need $requiredSats sats, have $balance sats',
    );
  }
  // Proceed...
}
```

### Mnemonic Validation

```dart
Future<void> restoreWallet(String phrase) async {
  try {
    final mnemonic = await Mnemonic.fromString(phrase);
    await _wallet.restoreWallet(mnemonic.asString());
  } on BdkException catch (e) {
    if (e.message.contains('invalid mnemonic')) {
      throw WalletException('Invalid recovery phrase. Check your words.');
    }
    rethrow;
  }
}
```

---

## Testing Architecture

### Unit Tests (Dart)

```dart
// test/services/bdk_wallet_service_test.dart
void main() {
  group('BdkWalletService', () {
    late FakeWalletService wallet;

    setUp(() {
      wallet = FakeWalletService();
    });

    test('createWallet returns receive address', () async {
      final address = await wallet.createWallet('abandon abandon...');
      expect(address, startsWith('bcrt1'));
    });

    test('getBalance returns 0 for new wallet', () async {
      await wallet.createWallet('abandon abandon...');
      final balance = await wallet.getBalance();
      expect(balance, 0);
    });

    // ... more tests
  });
}
```

### Integration Tests (Regtest)

```dart
// integration_test/wallet_flow_test.dart
testWidgets('BDK wallet deposit flow', (tester) async {
  // 1. Create wallet
  final wallet = BdkWalletService(network: Network.regtest);
  final mnemonic = await Mnemonic.create(WordCount.words12);
  await wallet.createWallet(mnemonic.asString());

  // 2. Get address
  final address = await wallet.getReceiveAddress();
  expect(address, startsWith('bcrt1'));

  // 3. Fund via Rails bridge
  await rails.fundRegtestAddress(
    address: address,
    amountBtc: '0.01',
  );

  // 4. Sync and verify balance
  await wallet.sync();
  final balance = await wallet.getBalance();
  expect(balance, 1_000_000); // 0.01 BTC in sats
});
```

---

## Migration Path from Rails

### Phase 2.0 (Current - Spike)

```
┌─────────────┐       ┌───────────────┐
│ Mobile App  │──────▶│ Rails L1 API  │ (100% dependency)
└─────────────┘       └───────────────┘
```

### Phase 2.1 (Flag-based)

```
┌─────────────┐
│ Mobile App  │
│             │
│ if use_local_wallet:
│   └──────────────▶ BDK (Electrum)
│ else:
│   └──────────────▶ Rails L1 API
└─────────────┘
```

### Phase 2.2 (Complete - Default BDK)

```
┌─────────────┐
│ Mobile App  │──────▶ BDK (Electrum) ──────▶ Bitcoin L1
└─────────────┘
       │
       └───────────▶ Rails (optional metadata only)
```

**Rails L1 services retired:**
- ❌ `L1::UserWallet`
- ❌ `L1::DepositReserveService`
- ❌ `L1::SyncReserveBalanceService`

**Rails kept (Phase 3):**
- ✅ `Dlc::*` services (fino a Fase 3)
- ✅ `Rgb::*` services (fino a Fase 4)

---

## Security Considerations

### Mnemonic Storage

**Options:**
1. **No storage** (recommended for v1):
   - User writes down mnemonic
   - App never stores it
   - User enters for recovery

2. **Secure storage** (optional):
   - iOS: Keychain (`flutter_secure_storage`)
   - Android: EncryptedSharedPreferences
   - Risk: Device compromise = mnemonic leak

**Recommendation:** Start with option 1 (paper backup only).

---

### PSBT Validation

**Before signing PSBT (Phase 3):**
- ✅ Verify all inputs belong to wallet
- ✅ Verify output amounts match expected (no fee surprises)
- ✅ Verify change output returns to wallet
- ✅ Show transaction details to user before signing

**Anti-patterns:**
- ❌ Blind signing (never sign without showing user)
- ❌ Trusting server-generated PSBT without validation

---

## Performance Optimization

### Sync Strategy

**Problem:** Full sync can take 10-60 seconds on slow networks.

**Optimizations:**
1. **Background sync:**
   ```dart
   // Sync every 30 seconds in background
   Timer.periodic(Duration(seconds: 30), (_) {
     if (mounted) wallet.sync();
   });
   ```

2. **Progressive UI:**
   ```
   "Syncing... (0 blocks)"
   "Syncing... (120 blocks)"
   "Synced ✓"
   ```

3. **Cache last sync time:**
   - Skip sync if < 10 seconds since last sync
   - User can force with pull-to-refresh

---

### UTXO Caching

**Problem:** `listUnspent()` called frequently for balance checks.

**Solution:**
```dart
class BdkWalletService {
  List<Utxo>? _cachedUtxos;
  DateTime? _lastUtxoFetch;

  Future<List<Utxo>> listUnspent() async {
    if (_cachedUtxos != null &&
        _lastUtxoFetch != null &&
        DateTime.now().difference(_lastUtxoFetch!) < Duration(minutes: 1)) {
      return _cachedUtxos!;
    }

    _cachedUtxos = await _wallet!.listUnspent();
    _lastUtxoFetch = DateTime.now();
    return _cachedUtxos!;
  }
}
```

---

## Next Steps

1. ✅ **Merge existing BDK spike** from `feature/mobile-independence-phase0-2`
2. **Refactor `LocalWalletService`** → implement full `WalletApi`
3. **Add wallet creation UI flow** (WalletSetupScreen)
4. **Implement balance sync** with Electrum regtest
5. **Test PSBT signing** (prep for Phase 3)
6. **Add integration tests** using `rails.fundRegtestAddress()`
7. **Document migration** from Rails L1

**Target:** Zero `L1::*` service dependencies in mobile app.

---

**Related:**
- [mobile-phase2-bdk-roadmap.md](mobile-phase2-bdk-roadmap.md) - Task breakdown
- [mobile-production-plan.md](mobile-production-plan.md) - Overall phases
