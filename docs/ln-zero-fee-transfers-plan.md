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

### Option A — RGB over Lightning (RLN asset channel) *(preferred PoC direction)*

Use **RGB Lightning Nodes** already in Docker: open (or reuse) an **RGB-capable LN channel** between sender and recipient (or via a liquidity hub), then pay an **LN invoice with asset_id / asset_amount**.

**Pros:** Stays inside existing RLN fleet; matches “tokens move without L1”.  
**Cons:** Channel open still costs L1 once; capacity / asset liquidity management; peer discovery.

**Open once, transfer many:** channel open fee amortized; subsequent sends ≈ LN fees only (aim for zero with private/direct channel or sponsored routing).

### Option B — Hub-mediated LN (no direct Alice↔Claude channel)

Alice and Claude each have a channel to a **MAT liquidity node**; transfers are LN payments through the hub, with RGB state updated off RGB-LN or via hub custody of EURT (worse trust model).

**Pros:** No N² channels.  
**Cons:** Trust / custody; not pure P2P.

### Option C — Accounting on relay + LN BTC only

Relay moves EURT balances in DB; LN only settles BTC. **Rejected** for production self-custody; acceptable only as temporary PoC mock with clear labelling.

### Option D — Production Breez / LDK (later)

Align with mobile-production Phase 4–5 once rgb-lib is on device. Out of scope for this PoC branch except as exit criteria.

**Decision for this branch:** spike **Option A** on regtest RLN; document hub (B) as scale-out.

## Prerequisites before transfer (product rules)

1. Alice has **spendable EURT** on an active deal (unchanged).
2. Both users have RLN wallets (unchanged).
3. **New:** an LN path exists:
   - direct RGB channel Alice↔Claude, **or**
   - path via MAT hub with enough asset capacity.
4. If no path: UI explains “Open channel” / “Wait for peer online” — **do not silently fall back to L1** unless user opts in (advanced).

## Work packages

### WP0 — Spike (1–2 days)

- [ ] From Alice RLN: `connect_peer` + `open_channel` to Claude (BTC-only, then with `asset_id` if supported).
- [ ] Claude: `ln_invoice` with `asset_id` + `asset_amount`; Alice: `send_payment`.
- [ ] Confirm balances via `asset_balance` / `Rgb::BalanceService` without `/sendrgb`.
- [ ] Record fee: channel open (L1) vs payment (LN).
- [ ] Write spike notes under `docs/spikes/rgb-ln-transfer.md`.

**Exit:** one Alice→Claude EURT payment on regtest with **no `/sendrgb`**.

### WP1 — Channel lifecycle service

- [ ] `Rgb::ChannelService` (name TBD): ensure path between two users (open/reuse).
- [ ] Persist channel metadata if needed (or rely on `list_channels`).
- [ ] Idempotent “ensure capacity for amount”.
- [ ] Request specs with stubs; one `:regtest` integration example.

### WP2 — Transfer path switch

- [ ] `Rgb::LibTransferService` (or new `Rgb::LnTransferService`): prefer LN; feature flag `RGB_TRANSFER_VIA_LN=1`.
- [ ] Keep L1 `/sendrgb` behind `RGB_TRANSFER_VIA_LN=0` or advanced fallback.
- [ ] `Tokens::TransferService` / wallet transfer unchanged at API shape.
- [ ] Update relay + mobile docs: Send money is LN when flag on.

### WP3 — Mobile / relay UX (minimal)

- [ ] Surface errors: peer offline, insufficient channel capacity, channel opening in progress.
- [ ] Optional: show “Opening channel…” only if WP1 opens synchronously (prefer async + push later).
- [ ] No address-book/QR in this branch.

### WP4 — Fees product policy

- [ ] Document: **first interaction** may require channel open (L1 fee, once); **subsequent sends** zero L1.
- [ ] Decide who pays channel open (Alice, Claude, or sponsored by Exchange wallet on regtest).
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

1. Demo reset; fund Alice/Bob; activate deal; Alice has EURT.
2. Spike: LN transfer Alice→Claude; assert Claude settled balance; assert no `sendrgb` in logs.
3. Second transfer: no new L1 funding tx for the payment itself.
4. Flag off: existing L1 RGB path still works (regression).
5. Mobile Send money E2E with flag on (optional once WP2+WP3 land).

## Open questions

1. Does current RLN build support **asset channels** for this NIA EURT, or only BTC LN + separate RGB?
2. Minimum channel capacity vs typical top-up sizes (€100–€1000).
3. Who initiates channel open if Claude has never been online?
4. Should multi-deal wallet transfers open one channel per asset/deal or one shared EURT asset channel?

## Success criteria

- Product can claim: **repeat user↔user EURT sends incur no L1 fee** when an LN path exists.
- PoC implements it on regtest RLN with a feature flag and clear fallback policy.
