# mat_dlc

Dart FFI bindings for the `mat_dlc` native library (`dlc-rs`).

Used by the on-device wallet to:

- derive a DLC 2-of-2 **fund key** from the BIP39 mnemonic (`SHA256("mat-dlc-fund-v1" || mnemonic)`, independent of BIP84 spend keys)
- adaptor-sign the CET set + refund (`sign_adaptor`)
- optionally complete a CET / refund from a watchtower close package (`complete_cet`, `complete_refund`) — no party secret required once both adaptor signatures are present

Build the dylib from `dlc-rs`:

```bash
cargo build --release --manifest-path dlc-rs/Cargo.toml
# libmat_dlc.{so,dylib} in dlc-rs/target/release
```

When the native library is not loaded (Flutter unit tests), `FakeWalletService` supplies placeholder signatures.
