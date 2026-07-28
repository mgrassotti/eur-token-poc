# Add Funds Screen Specification

## Overview

The Add Funds screen allows users to receive Bitcoin (on regtest) to their on-device BDK wallet. It displays a receive address with QR code and shows the current wallet balance.

## User Flow

### Scenario 1: No Wallet Exists

1. User navigates to "Add funds" screen
2. Screen shows:
   - Wallet icon
   - "No wallet found" message
   - "Create a new Bitcoin wallet to receive funds" explanation
   - "Create wallet" button
3. User taps "Create wallet"
4. App generates a new 12-word mnemonic and creates wallet
5. Dialog appears with:
   - Title: "Backup recovery phrase"
   - The 12 words displayed in monospace font
   - Warning about storing safely
   - "I have backed it up" button
6. User acknowledges backup
7. Screen transitions to show wallet receive address

### Scenario 2: Wallet Exists

1. User navigates to "Add funds" screen
2. Screen shows:
   - "On-device wallet (regtest)" header
   - Current balance in sats
   - Bitcoin address (bcrt1q...) in large monospace font
   - QR code of the address
   - "Copy address" button
   - "Sync balance" button (pull-to-refresh also available)

## UI States

### Loading State

- Shows circular progress indicator
- Displayed during wallet initialization

### No Wallet State

- Centered layout with:
  - Wallet icon (64px)
  - "No wallet found" title
  - Explanation text
  - "Create wallet" button

### Wallet Initialized State

- Scrollable list with:
  - Balance display
  - Receive address section:
    - Address in monospace font
    - QR code (200x200)
    - Copy button
    - Sync button

### Error State

- Displayed when wallet initialization fails
- Shows error message in red
- "Retry" button to attempt re-initialization

### Sync Error State

- Persistent SnackBar at bottom with:
  - "Sync Failed" title
  - Error message
  - "Check your Electrum server configuration" hint
  - "Settings" action button (navigates to /settings)
- Duration: 8 seconds
- Background: red

## Technical Implementation

### Wallet Initialization

- `WalletState` is provided via Provider
- Initialization happens automatically in `WalletState._initialize()`
- Uses `WalletLifecycleManager` to:
  - Check for existing wallet in SharedPreferences
  - Load wallet if found
  - Refresh address and balance

### Wallet Creation

1. Generate mnemonic using `Mnemonic.create(WordCount.words12)`
2. Call `WalletLifecycleManager.createWallet(mnemonic)`
3. Store mnemonic in SharedPreferences
4. Initialize BDK wallet
5. Perform initial sync with timeout (non-blocking)
6. Update UI with receive address

### Sync Operation

- Triggered by:
  - "Sync balance" button
  - Pull-to-refresh gesture
- Calls `WalletState.sync()`
- Shows syncing indicator
- Updates balance after successful sync
- Shows error SnackBar if sync fails

### Error Handling

1. **Wallet Initialization Failure**
   - Displays error message
   - Provides retry button
   
2. **Sync Failure**
   - Wallet remains functional
   - Shows persistent error banner
   - Links to Electrum settings
   - User can retry sync

3. **Network Timeout**
   - Initial wallet sync has 30s timeout
   - Wallet creation succeeds even if sync fails
   - User can manually sync later

## Key Fix: Removing Dialog in initState()

### The Problem

The original implementation called `showDialog()` during `initState()`:

```dart
@override
void initState() {
  super.initState();
  _ensureWalletInitialized(); // This called showDialog() immediately
}
```

This caused the app to hang because:
- `showDialog()` requires a fully-built widget tree
- Calling it during `initState()` violates Flutter's build lifecycle
- The UI would freeze waiting for the frame to complete

### The Solution

Removed the automatic dialog prompt entirely:

```dart
class _AddFundsScreenState extends State<AddFundsScreen> {
  // Note: Wallet initialization is handled by WalletState provider.
  // The build method shows appropriate UI based on wallet state.
```

The `build()` method already handles the "no wallet" state properly by showing a non-intrusive screen with a "Create wallet" button. This is better UX than an automatic popup dialog.

## Test Coverage

Unit tests verify:

1. **No Hang**: Screen renders without hanging when no wallet exists
2. **UI Rendering**: Shows correct UI elements for "no wallet" state
3. **Button Availability**: Create wallet button exists and is tappable

Integration tests (in `bdk_wallet_test.dart`) verify:
- End-to-end wallet creation
- Sync with Electrum server
- Balance updates after funding
- UTXO listing

## Dependencies

- `WalletState` (Provider)
- `WalletLifecycleManager`
- `BdkWalletService`
- `SharedPreferences` for mnemonic storage
- `go_router` for navigation
- `qr_flutter` for QR code display
- `flutter/services` for clipboard

## Future Improvements

1. **HD Wallet Support**
   - Show multiple addresses
   - Address derivation paths
   
2. **Enhanced Backup Flow**
   - Verification step (user inputs mnemonic)
   - Biometric protection option
   
3. **Address History**
   - List of previous receive addresses
   - Transaction history per address
   
4. **Network Selection**
   - Switch between regtest/testnet/mainnet
   - Dynamic Electrum server per network
   
5. **Lightning Invoice Generation**
   - For Phase 5 (LN Settlement)
   - QR code for Lightning invoices
