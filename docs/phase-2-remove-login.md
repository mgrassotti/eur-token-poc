# Phase 2: Remove Login, Add Local Name Form

## Overview

This update removes the login functionality from the mobile app and replaces it with a simple local name form. The login screen code is preserved for future use (bank transfer deposits feature).

## Changes Made

### 1. Backend: Dashboard Controller

**File:** `app/controllers/api/v1/dashboard_controller.rb`

- **Fixed:** Removed reference to `L1::ReserveBalance` which was deleted during Phase 2 wallet migration
- **Changed:** `savings_payload` method now returns `{ sats: 0, eur: 0 }` since mobile clients show their BDK wallet balance directly
- **Impact:** Dashboard endpoint no longer queries server-side reserve balance

### 2. Mobile: Name State Provider

**File:** `mobile/lib/providers/app_state.dart`

- **Added:** `NameState` class for managing locally stored user name
- **Features:**
  - Stores name in `SharedPreferences` with key `user_name`
  - `hasName` getter to check if name is set
  - `setName()` and `clearName()` methods for managing name
  - Auto-loads name on initialization

### 3. Mobile: Name Form Screen

**File:** `mobile/lib/screens/name_form_screen.dart` (NEW)

- **Created:** Simple name input form shown on first launch
- **Features:**
  - Single text field asking "What should we call you?"
  - Form validation (name required)
  - Saves name to local storage only (no server API)
  - Navigates to dashboard after submission

### 4. Mobile: Updated Routing

**File:** `mobile/lib/main.dart`

- **Changed:** Routing logic to use `NameState` instead of `AuthState`
- **Removed:** Login screen from routes (code commented out for future use)
- **Added:** Name form route at `/name`
- **New Flow:** App checks for name → shows name form if missing → shows dashboard if present
- **Provider:** Added `NameState` to provider list

### 5. Mobile: Updated Dashboard

**File:** `mobile/lib/screens/dashboard_screen.dart`

- **Changed:** Greeting uses `nameState.name` instead of `auth.user?.name`
- **Removed:** Logout button from app bar
- **Changed:** Pull-to-refresh now syncs local BDK wallet instead of fetching server dashboard
- **Changed:** Summary card displays local BDK wallet balance (`wallet.balanceSats`)
- **Changed:** "Deposit funds" button visibility based on local wallet balance
- **Changed:** Loading state based on wallet initialization, not server data

### 6. Tests: Updated Unit Test

**File:** `mobile/test/widget_test.dart`

- **Changed:** Test now expects "Welcome!" screen instead of "Log in"
- **Updated:** Assertions to check for name form fields

### 7. Tests: Updated Integration Helpers

**File:** `mobile/integration_test/support/mobile_test_helpers.dart`

- **Updated:** `loginAs()` helper to enter name from email (e.g., "alice@example.com" → "Alice")
- **Updated:** `logout()` helper to clear name from SharedPreferences
- **Note:** Helpers maintain backward compatibility with existing integration tests

### 8. Tests: Updated Wallet Lifecycle Test

**File:** `mobile/integration_test/wallet_lifecycle_test.dart`

- **Changed:** Login flow replaced with name entry
- **Updated:** Test now enters "Alice" as name instead of email/password

## User Flow

### Before (Login Flow)
1. App opens to login screen
2. User enters email/password
3. Server authenticates
4. Dashboard loads with server data

### After (Name Form Flow)
1. App checks for local name
2. If no name: show name form
3. User enters name (saved locally)
4. Dashboard loads with local BDK wallet balance
5. Greeting shows: "Hi, \<name\>"

## Technical Details

### Local Storage Keys
- `user_name`: User's display name (String)

### No Server Authentication
- Mobile app no longer requires login
- Dashboard endpoint still requires authentication (for future web/admin use)
- Mobile clients bypass dashboard endpoint, use local wallet balance

### Future: Login Restoration
When bank transfer deposits feature is needed:
1. Uncomment login screen in `main.dart`
2. Add login route back to router
3. Update UI to show login option
4. Keep name form for non-authenticated users

## Migration Notes

### For Existing Users
- No migration needed (fresh install assumed)
- If restoring login later, may need to migrate from name-only to user accounts

### For Developers
- Integration tests still use `loginAs()` helper, but now it enters name
- Server dashboard endpoint preserved but unused by mobile app
- `AuthState` provider still exists but not used in routing

## Benefits

1. **Simplified Onboarding:** No account creation required
2. **Local-First:** Name stored client-side only
3. **Privacy:** No PII sent to server
4. **Flexible:** Easy to re-add login when needed
5. **Phase 2 Aligned:** Works with BDK wallet balance (no server reserve tracking)

## Testing

Run integration tests to verify:
```bash
cd mobile
flutter test integration_test/wallet_lifecycle_test.dart -d macos
flutter test integration_test/mobile_flow_test.dart -d macos
```

Unit tests:
```bash
cd mobile
flutter test
```
