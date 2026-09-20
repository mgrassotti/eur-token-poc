# mat_sdk

Dart package mirroring [`mat-core`](../../../mat-core) FloorEUR economics so the
Flutter app can recompute settlement amounts **on device** without trusting the
relay.

## Status (Phase 0 / mobile independence)

| Layer | Role |
|-------|------|
| **This package** | Pure Dart `FloorEurCalculator` — used by settlement UI today |
| **`mat-ffi`** | C ABI (`mat_floor_eur_json` / `mat_string_free`) over Rust mat-core — scaffolded, not yet loaded from Dart |
| **Relay** | Still returns preview payoff + `calculation_inputs` for comparison |

Until native FFI is wired, keep Dart tests aligned with `mat-core/src/floor_eur.rs`.

## Usage

```dart
import 'package:mat_sdk/mat_sdk.dart';

final result = FloorEurCalculator(
  notionalEurCents: 100000,
  notionalTotalCents: 100000,
  holderSharesCents: [100000],
  spotEurPerBtc: 50000,
  rateBpsMonthly: 100,
  monthsElapsed: 1,
  escrowTotalSats: 3975000,
).call();
```

## Tests

```bash
cd mobile/packages/mat_sdk && dart test
```

## Next

- Load `libmat_ffi` via `dart:ffi` / `flutter_rust_bridge` and prefer Rust when available
- Drop the Dart mirror once FFI parity is proven in CI
