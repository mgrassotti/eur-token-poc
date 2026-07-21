# Trust boundaries (Phase 0)

This document defines what infrastructure may see or store versus what each phone must verify locally. It complements [mobile-production-plan.md](../docs/mobile-production-plan.md).

## Principle

**Anything that can sign or spend must live on the device.** Cloud services coordinate and attest; they do not custody keys or decide payout amounts.

## Relay (optional coordination API)

| May store | Must NOT store |
|-----------|----------------|
| Deal metadata (`DealOffer`, `DealAccept`) — amounts, dates, pubkeys | Private keys, mnemonics, PSBT partial signatures |
| Encrypted P2P blobs (consignment, funding package) | Cleartext unsigned PSBTs unless end-to-end encrypted |
| Notification tokens, deal status (`pending` / `active` / `settled`) | Oracle private keys |
| Market rate snapshots (informational) | Authoritative settlement amounts |

The relay is a **directory and mailbox**, not a settlement authority. Holder sats must be recomputed on device with `mat-core` before any payment is sent.

## Oracle

| Provides | Device must verify |
|----------|-------------------|
| Numeric announcement at activate | Announcement matches deal peg, maturity, `num_digits` |
| Attestation at settle | Signature validates against announcement; outcome matches fetched spot policy |
| Price outcome (EUR/BTC integer) | Outcome is within representable range; CET built from local payout curve |

The oracle attests **price**, not **who gets paid**. FloorEUR allocation is deterministic from price + token shares.

## Device (borrower, hodler, holder)

Each party verifies locally:

1. **Economics** — `FloorEurCalculator` / `PayoutCurve` match offer terms (`amount_eur_cents`, `rate_bps_monthly`, `period`).
2. **Funding PSBT** — inputs/outputs, multisig policy, collateral sats, fee buffer (`FUNDING_FEE_BUFFER_SATS` in PoC).
3. **CET** — peg_pot + investor_sats = distributable pool; holder targets sum to FloorEUR total at attested spot.
4. **RGB** — consignment authenticity, assignment matches deal id and share.
5. **LN invoices (Phase 5)** — amount in sats equals `mat-core` holder allocation, not a server-provided figure.

## Wire format trust

JSON packages (`schemas/*.schema.json`) carry `schema_version: 1`. Reject unknown versions. After deserialize, run `validate()` on each type before acting.

## Recovery package

Exported `SettlementPackage` + funding outpoint + oracle material must be sufficient to **audit** a deal offline. It does not replace key backup (seed / descriptor export).

## PoC gap (intentional)

The Rails PoC still runs settlement server-side. Phase 0 extracts the **math and schemas** so mobile can enforce the same rules without trusting Rails.

**Mobile progress:** the Flutter settlement screen recomputes FloorEUR via `mat_sdk` (Dart mirror of mat-core) using relay `calculation_inputs`, and surfaces a mismatch warning if server figures disagree. Authoritative on-device Rust (`mat-ffi`) remains a follow-up.
