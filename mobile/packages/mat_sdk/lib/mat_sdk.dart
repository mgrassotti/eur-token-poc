/// On-device MAT economics (FloorEUR) and helpers.
///
/// This Dart package mirrors [`mat-core`](../../../mat-core) so the Flutter app
/// can recompute settlement amounts without trusting the relay. Keep tests
/// aligned with `mat-core/src/floor_eur.rs`.
library;

export 'src/constants.dart';
export 'src/floor_eur.dart';
export 'src/months.dart';
