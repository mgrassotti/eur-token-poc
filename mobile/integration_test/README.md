# Integration Tests

Comprehensive end-to-end tests for the MAT mobile app.

## Prerequisites

Before running integration tests, ensure:

1. **Regtest environment running:**
   ```bash
   ./bin/regtest up
   ```

2. **Rails backend running:**
   ```bash
   bin/dev
   ```

3. **Electrum server available:**
   - Should be running on `localhost:50001`
   - Check with: `nc -zv 127.0.0.1 50001`

## Test Suites

### 1. Wallet Lifecycle Test

**File:** `wallet_lifecycle_test.dart`

Tests the complete wallet creation, persistence, and loading flow:
- ✅ Clean state (no wallet)
- ✅ Wallet creation with mnemonic backup
- ✅ Wallet persistence in SharedPreferences
- ✅ Wallet loading after app restart
- ✅ UI state updates
- ✅ Wallet operations (copy, sync)
- ✅ Wallet deletion

**Run:**
```bash
cd mobile
flutter test integration_test/wallet_lifecycle_test.dart \
  -d macos \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

**Expected output:**
```
========== TEST START: Wallet Lifecycle ==========
PHASE 1: Launching app with no wallet...
✓ App launched
✓ Logged in
✓ On Add Funds screen
✓ Correct UI for no wallet state

PHASE 2: Creating wallet...
✓ Mnemonic dialog shown
✓ Mnemonic has 12 words

...

========== TEST COMPLETE: All phases passed! ==========
```

### 2. BDK Wallet Test

**File:** `bdk_wallet_test.dart`

Low-level tests for BDK wallet operations:
- Wallet creation and restoration
- Electrum sync
- Balance tracking
- UTXO management
- PSBT signing

**Run:**
```bash
cd mobile
flutter test integration_test/bdk_wallet_test.dart \
  -d macos \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

### 3. Multi-User Flow Test

**File:** `multi_user_flow_test.dart`

End-to-end test simulating multiple users:
- Alice (mobile)
- Bob (macOS)
- Claude & David (API)

Tests:
- Wallet creation for all users
- Funding via regtest
- Recharge requests (Alice → Bob)
- P2P transfers (Alice → Claude)
- Expiry scenarios
- Final balance verification

**Run:**
```bash
cd mobile
flutter test integration_test/multi_user_flow_test.dart \
  -d macos \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

### 4. Mobile Flow Test

**File:** `mobile_flow_test.dart`

General app navigation and UI tests.

**Run:**
```bash
cd mobile
flutter test integration_test/mobile_flow_test.dart \
  -d macos \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

## Running All Tests

```bash
cd mobile
flutter test integration_test/ \
  -d macos \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

## Troubleshooting

### Test hangs or times out

**Issue:** Test waits indefinitely or times out.

**Solutions:**
1. Check that all prerequisites are running
2. Clear app state: `./bin/mobile-clear-wallet`
3. Restart the simulator/emulator
4. Check Electrum connection: `nc -zv 127.0.0.1 50001`

### "Wallet already exists" error

**Issue:** Test fails because wallet from previous run exists.

**Solution:**
```bash
./bin/mobile-clear-wallet
```

Or in the test itself, ensure `setUp()` clears SharedPreferences:
```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
});
```

### BDK ChecksumMismatchException

**Issue:** Wallet creation fails with checksum error.

**Cause:** Usually a corrupted database file.

**Solution:**
1. Delete database files manually:
   ```bash
   rm ~/Library/Containers/com.mat.matMobile/Data/Documents/*.db*
   ```
2. Or use the cleanup script:
   ```bash
   ./bin/mobile-clear-wallet
   ```

### Network timeout errors

**Issue:** Sync operations fail with timeout.

**Possible causes:**
1. Electrum server not running
2. Bitcoin regtest node not running
3. Network configuration issues

**Check:**
```bash
# Check Electrum
nc -zv 127.0.0.1 50001

# Check Bitcoin RPC
bitcoin-cli -regtest -datadir=./tmp/regtest getblockchaininfo

# Check Rails
curl http://127.0.0.1:3000/api/v1/health
```

## Test Development Guidelines

### Writing New Integration Tests

1. **Use descriptive test names:**
   ```dart
   testWidgets('Wallet creation shows mnemonic backup dialog', (tester) async {
     // ...
   });
   ```

2. **Add comprehensive logging:**
   ```dart
   print('PHASE 1: Testing wallet creation...');
   print('✓ Wallet created successfully');
   ```

3. **Use appropriate waits:**
   ```dart
   await tester.pumpAndSettle(const Duration(seconds: 3));
   ```

4. **Clean up in setUp/tearDown:**
   ```dart
   setUp(() async {
     // Clear state
   });
   
   tearDown(() async {
     // Cleanup resources
   });
   ```

5. **Verify both positive and negative cases:**
   ```dart
   expect(find.text('Success'), findsOneWidget);
   expect(find.text('Error'), findsNothing);
   ```

### Best Practices

- ✅ Test one feature per test
- ✅ Use Page Object pattern for complex screens
- ✅ Mock external dependencies when appropriate
- ✅ Use `Key` widgets for reliable element finding
- ✅ Add timeouts for async operations
- ✅ Verify error states, not just happy path
- ✅ Clean up after each test

## CI/CD Integration

To run tests in CI:

```yaml
# .github/workflows/integration-tests.yml
name: Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      
      - name: Start regtest
        run: ./bin/regtest up
      
      - name: Start Rails
        run: bin/dev &
      
      - name: Run integration tests
        run: |
          cd mobile
          flutter test integration_test/ \
            -d macos \
            --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

## Performance Benchmarks

Track test execution time to detect performance regressions:

| Test Suite | Expected Duration | Timeout |
|------------|-------------------|---------|
| wallet_lifecycle_test | 30-45s | 2 min |
| bdk_wallet_test | 45-60s | 3 min |
| multi_user_flow_test | 90-120s | 5 min |
| mobile_flow_test | 30-40s | 2 min |

If tests exceed these durations, investigate for:
- Network latency
- Database operations
- Sync bottlenecks
- UI rendering issues
