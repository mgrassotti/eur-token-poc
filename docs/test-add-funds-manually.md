# Manual Testing Guide: Add Funds Screen

## Prerequisites

1. Start the regtest environment:
   ```bash
   ./bin/regtest up
   ```

2. Start Rails backend:
   ```bash
   bin/dev
   ```

3. Verify Electrum server is running:
   ```bash
   nc -zv 127.0.0.1 50001
   ```

## Test Scenario 1: First Time User (No Wallet)

### Steps:

1. Launch the app on macOS:
   ```bash
   cd mobile
   flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
   ```

2. Login with demo credentials:
   - Email: `alice@example.com`
   - Password: `password123`

3. Navigate to "Add funds" screen from the dashboard

4. **Expected Result:**
   - Screen should load **without hanging** ✅
   - Shows "No wallet found" message
   - Shows "Create a new Bitcoin wallet to receive funds" text
   - Shows "Create wallet" button

5. Tap "Create wallet" button

6. **Expected Result:**
   - Dialog appears with "Backup recovery phrase" title
   - Shows 12 words in monospace font
   - Shows warning about storing safely
   - Shows "I have backed it up" button
   - **Should NOT hang** ✅

7. Write down the 12 words (for testing only!)

8. Tap "I have backed it up"

9. **Expected Result:**
   - Dialog closes
   - Screen shows wallet interface:
     - Balance: "0 sats"
     - Bitcoin address (starts with `bcrt1q...`)
     - QR code
     - "Copy address" button
     - "Sync balance" button

## Test Scenario 2: Wallet Already Exists

### Steps:

1. Navigate away from "Add funds" screen (e.g., to Dashboard)

2. Navigate back to "Add funds" screen

3. **Expected Result:**
   - Screen loads quickly **without hanging** ✅
   - Shows existing wallet address
   - Shows current balance
   - No "Create wallet" dialog appears

## Test Scenario 3: Copy Address

### Steps:

1. On "Add funds" screen with wallet initialized

2. Tap "Copy address" button

3. **Expected Result:**
   - Snackbar appears: "Address copied"
   - Address is in clipboard (can paste in notes app to verify)

## Test Scenario 4: Sync Balance

### Steps:

1. Fund the wallet address from regtest:
   ```bash
   # Get the address from the app
   ADDRESS="bcrt1q..."
   
   # Send regtest BTC
   bitcoin-cli -regtest -datadir=./tmp/regtest sendtoaddress $ADDRESS 1.0
   
   # Mine a block to confirm
   bitcoin-cli -regtest -datadir=./tmp/regtest -generate 1
   ```

2. In the app, tap "Sync balance" button

3. **Expected Result:**
   - Syncing indicator appears briefly
   - Balance updates to show received sats (e.g., "100000000 sats" for 1 BTC)
   - Snackbar shows "Reserve updated: 100000000 sats"

## Test Scenario 5: Sync Error Handling

### Steps:

1. Stop the Electrum server:
   ```bash
   docker stop electrs
   ```

2. In the app, tap "Sync balance" button

3. **Expected Result:**
   - After timeout, shows red error snackbar with:
     - "Sync Failed" title
     - Error message
     - "Check your Electrum server configuration" hint
     - "Settings" button
   - App remains responsive **without hanging** ✅

4. Tap "Settings" button

5. **Expected Result:**
   - Navigates to Settings screen
   - Shows "Electrum Server" option under "Advanced Features"

6. Tap "Electrum Server"

7. **Expected Result:**
   - Dialog appears with current Electrum URL
   - Shows examples for different networks

## Test Scenario 6: Pull to Refresh

### Steps:

1. On "Add funds" screen, pull down from top

2. **Expected Result:**
   - Refresh indicator appears
   - Triggers sync operation
   - Updates balance if changed

## Success Criteria

All scenarios should complete **without the app hanging or freezing**. The key fix ensures that:

1. ✅ No `showDialog()` calls during `initState()`
2. ✅ Wallet initialization happens asynchronously without blocking UI
3. ✅ Sync errors are handled gracefully
4. ✅ App remains responsive even when Electrum server is down

## Common Issues

### Issue: "Sync Failed" immediately after wallet creation

**Cause:** Electrum server not running or unreachable

**Fix:**
```bash
# Check if Electrum is running
docker ps | grep electrs

# If not running, start regtest
./bin/regtest up
```

### Issue: Balance not updating after funding

**Cause:** Need to mine blocks for confirmation

**Fix:**
```bash
# Mine blocks
bitcoin-cli -regtest -datadir=./tmp/regtest -generate 1
```

### Issue: App still hangs

**Cause:** Old version of the code

**Fix:**
```bash
# Pull latest changes
git pull

# Clean and rebuild
cd mobile
flutter clean
flutter pub get
```

## Unit Test Verification

To verify the fix programmatically:

```bash
cd mobile
flutter test test/screens/add_funds_screen_test.dart
```

**Expected output:**
```
00:00 +3: All tests passed!
```

All 3 tests should pass:
1. ✅ renders without hanging when no wallet exists
2. ✅ shows create wallet UI when no wallet exists
3. ✅ create wallet button exists and is tappable
