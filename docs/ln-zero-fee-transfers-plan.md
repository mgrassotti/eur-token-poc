# Plan: Zero-fee user↔user EURT via Lightning

**Branch (planned):** `feature/ln-zero-fee-transfers`  
**Depends on:** `feature/mobile-relay-phase1` (relay API + mobile Send money)  
**Related but separate:** recipient selection (contacts / QR) — see `docs/send-money-recipient-ux-plan.md`

## Problem

Today **Send money** uses on-chain RGB (`/sendrgb`). Alice pays **Bitcoin L1 fees** per transfer. Product goal: **user↔user money exchange at 0 fees via Lightning**.

This is **not** the same as Phase 5 in `docs/mobile-production-plan.md` (LN for **holder settlement after CET**). This plan is **day-to-day EURT payments between users** while a deal is active.

## Current PoC path (status quo)

```
Mobile Send money
  → POST /api/v1/transfers
  → Tokens::WalletTransferService  (pick deal balances)
  → Tokens::TransferService
  → Rgb::LibTransferService
       Claude RLN: rgb_invoice (blinded)
       Alice RLN:  sendrgb (on-chain, fee_rate: 5)
  → NodeConfirm + ProjectionService (DB mirror)
```

Lightning APIs exist on `Rgb::LightningClient` (`open_channel`, `ln_invoice`, `send_payment`) but are **unused** by Send money.

## Target behaviour

| Property | Target |
|----------|--------|
| Fee for Alice→Claude EURT send | **0** (or dust-only LN routing fee if any; no L1 tx per send) |
| Asset | Same EURT / deal-scoped balance as today |
| UX | Unchanged Send money amount flow (recipient UX is a separate plan) |
| Fallback | Explicit: if no LN path, refuse or offer “slow L1 RGB” only behind advanced settings |

## Design options (spike order)

### Option A — Direct RGB-LN channel Alice↔Claude

Open (or reuse) an RGB-capable LN channel between the two users, then pay LN invoices with `asset_id` / `asset_amount`.

**Pros:** P2P; no hub trust.  
**Cons:** N² channels; peer discovery.

### Option B — Hub-mediated RGB-LN *(chosen for this branch)*

Alice and Claude each open an **RGB asset channel** to a **MAT liquidity hub** (PoC: Rails-orchestrated RLN, e.g. issuer node or dedicated `rln-hub`). Transfers are **multi-hop RGB-LN payments** through the hub — not DB-only bookkeeping and not “RGB updated off LN”.

**Pros:** Linear channel topology; Rails can open Alice→hub (and Claude→hub) for the PoC.  
**Cons:** Hub must stay online and hold BTC + EURT channel liquidity; hub is a trust/availability dependency for transfers.

### Option C — Accounting on relay + LN BTC only

Relay moves EURT balances in DB; LN only settles BTC. **Rejected** for production self-custody; acceptable only as temporary PoC mock with clear labelling.

### Option D — Production Breez / LDK (later)

Align with mobile-production Phase 4–5 once rgb-lib is on device. Out of scope for this PoC branch except as exit criteria.

**Decision for this branch:** implement **Option B** on regtest RLN (hub path).

## Moving Alice’s EURT from L1 RGB into LN

Yes — that is what an **RGB channel open** does in RLN.

Alice’s post-activation EURT sits as **on-chain RGB assignments** on her RLN (colorable UTXOs). Calling `/openchannel` with `asset_id` + `asset_amount`:

1. Spends/locks that much of her **off-channel (L1) RGB** into the channel funding commitment (still one **L1** funding tx).
2. Decreases her **spendable** off-channel asset balance by `asset_amount` (RLN tests assert this, e.g. 1000 → 400 after putting 600 into the channel).
3. Makes that amount available as **in-channel RGB-LN liquidity** toward the peer (the hub).

So: **L1 → LN for RGB is exactly “open (or push into) an RGB channel”**, not a separate custom migrate API. Subsequent Alice→Claude sends use `/lninvoice` + `/sendpayment` with the asset (multi-hop via hub) and should **not** call `/sendrgb`.

Closing the channel returns assets to off-channel / L1 RGB again (as in RLN’s `vanilla_payment_on_rgb_channel` test).

**PoC orchestration:** Rails can `connect_peer` + `open_channel` from Alice’s RLN to the hub (and likewise Claude→hub) when she first needs LN spend capacity — e.g. after deal activation or before first Send money. Who pays the open fee (Alice vs sponsored Exchange wallet) is a product choice; the open itself is unavoidable once per edge.

## Prerequisites before transfer (product rules)

1. Alice has **spendable EURT** on an active deal (off-channel RGB initially).
2. Both users have RLN wallets.
3. **New:** RGB-LN path via hub:
   - Alice↔hub channel with enough **outbound** EURT (and BTC for LN fees if required by stack),
   - Claude↔hub channel with enough **inbound** EURT capacity,
   - hub online and able to route.
4. If no path: Rails opens missing hub edges (PoC) or UI explains wait — **do not silently fall back to L1 `/sendrgb`** unless user opts in (advanced).

## Work packages

### WP0 — Spike (1–2 days)

- [x] Treat **issuer** as MAT liquidity node; fund BTC + ensure UTXOs (`HubSetupService`).
- [x] After Alice holds EURT: `connect_peer` + `open_channel(..., asset_id, asset_amount)` Alice→hub; assert off-channel balance drops and channel lists asset liquidity.
- [x] Same for hub→Claude (hub opens with seeded EURT).
- [x] Claude: `ln_invoice` with `asset_id` + `asset_amount`; Alice: `send_payment`; assert multi-hop via hub.
- [x] Confirm balances via `asset_balance` / `Rgb::BalanceService` without `/sendrgb` for the payment.
- [x] Record fees: channel open (L1, once per edge) vs payment (LN).
- [x] Write spike notes under `docs/spikes/rgb-ln-hub-transfer.md`.

**Exit:** one Alice→hub→Claude EURT payment on regtest with **no `/sendrgb`** for the payment (`spec/integration/rgb_ln_hub_transfer_spec.rb`).

### WP1 — Channel lifecycle service (hub-centric)

- [x] `Rgb::HubChannelService`: ensure Alice↔hub and recipient↔hub capacity for amount.
- [x] Rails-driven open for PoC (no mobile LN peer management yet).
- [x] Idempotent “ensure capacity for amount”.
- [ ] Persist channel metadata if needed (or rely on `list_channels`).
- [x] Request specs with stubs; one `:regtest` integration example.

### WP2 — Transfer path switch

- [x] `Rgb::LnTransferService` (hub route): prefer LN; feature flag `RGB_TRANSFER_VIA_LN=1`.
- [x] Keep L1 `/sendrgb` behind `RGB_TRANSFER_VIA_LN=0` or advanced fallback.
- [x] `Tokens::TransferService` / wallet transfer unchanged at API shape.
- [ ] Update relay + mobile docs: Send money is LN-via-hub when flag on.

### WP3 — Mobile / relay UX (minimal)

- [ ] Surface errors: hub offline, insufficient channel capacity, channel opening in progress.
- [ ] Optional: “Opening channel to MAT…” when Rails opens Alice→hub synchronously.
- [ ] No address-book/QR in this branch (`feature/send-money-recipient-ux` depends on this).

### WP4 — Fees product policy

- [ ] Document: **first LN setup** requires channel open(s) (L1 fee, once per hub edge); **subsequent sends** no L1.
- [ ] Decide who pays Alice→hub open (Alice vs sponsored Exchange on regtest).
- [ ] Integration test: second transfer does not call `/sendrgb`.

## Non-goals (this branch)

- Phone contacts / encrypted MSISDN directory
- QR receive invoice UX
- Breez SDK / production mobile LN
- Changing FloorEUR / DLC settlement

## Suggested git workflow

```bash
git checkout feature/mobile-relay-phase1
git checkout -b feature/ln-zero-fee-transfers
# WP0 spike commits, then WP1–WP4
```

Merge back to `feature/mobile-relay-phase1` or `main` independently of the recipient-UX branch.

## Test plan

1. Demo reset; fund Alice/Bob; activate deal; Alice has EURT off-channel.
2. Spike: open Alice→hub RGB channel (balance moves L1→LN); open Claude→hub; Alice→Claude via hub LN; no `sendrgb`.
3. Second transfer: no new L1 funding tx for the payment itself.
4. Flag off: existing L1 RGB path still works (regression).
5. Mobile Send money E2E with flag on (optional once WP2+WP3 land).

## Open questions

1. ~~Hub identity for PoC: reuse **issuer RLN (3005)** vs dedicated `rln-hub` container?~~ **Decided:** issuer as hub (`RLN_HUB_URL` overrideable).
2. Minimum BTC + EURT capacities on hub edges vs typical top-ups (€100–€1000).
3. Who initiates Claude→hub open if Claude has never sent/received (Rails auto-open on first inbound)?
4. One RGB channel per deal asset_id vs one hub channel that can carry the deal’s NIA (issue model today is per-deal)?
5. Exact LN fee policy: truly zero, or allow tiny BTC routing fees while forbidding L1?
6. Pre-fund hub treasury so first send does not require ~2× Alice off-channel liquidity?

## Success criteria

- Product can claim: **repeat user↔user EURT sends incur no L1 fee** when hub RGB-LN paths exist.
- PoC implements hub path on regtest RLN with a feature flag and clear fallback policy.
