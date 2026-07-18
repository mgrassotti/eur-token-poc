# Plan: Zero-fee user↔user EURT via Lightning

**Status (2026-07-18): shelved for day-to-day Send money.**  
Product default remains **L1 RGB** (`/sendrgb`) — unknown recipients make hub/LSP inbound liquidity the real cost, not “0 fee.”

**Working hub PoC (parked):** branch [`spike/rgb-ln-hub-poc`](https://github.com/mgrassotti/eur-token-poc/tree/spike/rgb-ln-hub-poc) — Alice→issuer-hub→Claude RGB-LN behind `RGB_TRANSFER_VIA_LN=1`; notes in `docs/spikes/rgb-ln-hub-transfer.md` on that branch.

**Still planned later (different problem):** Phase 5 holder **BTC** payouts via Breez/LSP (`docs/mobile-production-plan.md`) — not EURT user↔user.

**Depends on:** `feature/mobile-relay-phase1` (relay API + mobile Send money)  
**Related:** recipient UX — `docs/send-money-recipient-ux-plan.md` (can proceed on L1)

## Product decision

| Rail | Use |
|------|-----|
| **L1 RGB** | Default Send money (any recipient, immediate ability to transact) |
| **RGB-LN hub** | Parked spike only; revisit if MAT runs a funded EURT LSP |
| **BTC LN (Breez)** | Phase 5 settlement payouts, not day-to-day EURT |

**L1 UX follow-ups (preferred next):** pending vs settled, optional 0-conf *display* with re-spend blocked until confirm, fee clarity / sponsorship.

## Why LN was shelved for P2P EURT

- Recipients are not known in advance (Claude / David / Bob / …).
- Receiving on LN needs **inbound** capacity; with RGB, that is **asset** liquidity, not only BTC.
- A hub must size channels toward receivers (JIT/LSP capital) — “0 fee transfers” still cost someone channel open + locked EURT.
- Industry answer is LSPs / JIT / liquidity markets; we are not that LSP yet for EURT.

## Historical plan (spike archive)

Original goal: user↔user EURT at 0 L1 fee via Lightning. Options considered: direct RGB channels (A), hub-mediated (B), DB custody mock (C, rejected), Breez later (D).

Option B was implemented on `spike/rgb-ln-hub-poc` (regtest green). First-send economics required seeding hub liquidity from Alice (~3× payment on first setup with 2× provisioning) — confirmed the liquidity objection.

## Current PoC path (active)

```
Mobile Send money
  → POST /api/v1/transfers
  → Tokens::WalletTransferService
  → Tokens::TransferService
  → Rgb::LibTransferService
       recipient RLN: rgb_invoice
       sender RLN:    sendrgb (on-chain)
  → NodeConfirm + ProjectionService
```

## Non-goals on this branch now

- Shipping `RGB_TRANSFER_VIA_LN` as default
- Mobile channel-open UX for hub edges
- Replacing Phase 5 Breez work

## Success criteria (revised)

- Send money stays **L1 RGB** with clear fee/confirmation UX.
- LN hub PoC remains recoverable on `spike/rgb-ln-hub-poc` for a future LSP decision.
- Phase 5 BTC LN settlement remains independent.
