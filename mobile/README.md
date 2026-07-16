# MAT Mobile (Phase 1)

Flutter shell for the MAT deal flow — dashboard, create/accept deal, transfers, settlement preview. Talks to the Rails **relay API** (`/api/v1`); no keys or signing yet.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.24+
- Rails PoC running: `bin/rails server` (port 3000)
- Demo users seeded: `bin/rails db:seed`

## Integration tests (iOS / Android / web)

Runs Flutter `integration_test` against the live Rails relay API on a **real mobile simulator** (preferred) or Chrome.

**Prerequisites:** `bin/dev` running (Rails + regtest).

```bash
# iOS simulator (default on Mac)
./bin/mobile-integration-test

# Android emulator (uses 10.0.2.2 for host Rails)
MOBILE_TARGET=android ./bin/mobile-integration-test

# Web / Chrome
MOBILE_TARGET=web ./bin/mobile-integration-test
```

The suite includes:

- **Alice add-funds E2E**: copy address → admin funds **0.01 BTC** on regtest → sync balance
- **Deal + transfer E2E**: Alice creates €1000 deal → Bob accepts (DLC/RGB on regtest) → Alice sends **€500 EURT** to Claude

Regtest starts automatically; deal tests reset demo data and fund Alice/Bob reserves via the integration bridge.

Override device id:

```bash
MOBILE_DEVICE="iPhone 16 Pro" ./bin/mobile-integration-test
flutter devices   # list ids
```

Manual (iOS simulator example):

```bash
cd mobile
flutter test integration_test/mobile_flow_test.dart -d "iPhone 16 Pro" \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

Android emulator manual:

```bash
flutter test integration_test/mobile_flow_test.dart -d emulator-5554 \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Tests live in `integration_test/mobile_flow_test.dart`. Add new flows there as mobile features grow.

After admin sends funds: pull to refresh or tap **Sync balance** on Add funds.

## Run

First-time setup (generates `android/` and `ios/` platform folders):

```bash
cd mobile
flutter create . --project-name mat_mobile --org com.mat
flutter pub get
flutter run
```

### API base URL

Default in `lib/config/api_config.dart`:

| Platform | URL |
|----------|-----|
| iOS simulator / macOS | `http://127.0.0.1:3000/api/v1` |
| Android emulator | `http://10.0.2.2:3000/api/v1` |
| Physical device | your machine LAN IP |

Override at build time:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000/api/v1
```

## Demo login

Use seeded demo users (`password`):

- `alice@example.com` — borrower
- `bob@example.com` — hodler
- `claude@example.com` / `david@example.com` — holders

## Screens

| Screen | Route | API |
|--------|-------|-----|
| Login | `/login` | `POST /auth/login` |
| Dashboard | `/` | `GET /dashboard` |
| Create deal | `/deals/new` | `POST /deals` |
| Deal detail | `/deals/:id` | `GET /deals/:id` |
| Accept deal | (on detail) | `POST /deals/:id/accept` |
| Transfers | `/deals/:id/transfers` | `GET/POST transfers` |
| Settlement | `/deals/:id/settlement` | `GET settlement` |

## mat_sdk stub

`packages/mat_sdk/` is a placeholder for Phase 2+ Rust FFI (`mat-ffi` / `flutter_rust_bridge`). Phase 1 uses HTTP only.

## API contract

[docs/relay-api-v1.md](../docs/relay-api-v1.md)

## Related

- [docs/mobile-production-plan.md](../docs/mobile-production-plan.md)
- [mat-core/README.md](../mat-core/README.md)
