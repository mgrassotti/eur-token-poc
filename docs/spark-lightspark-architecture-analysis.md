# Spark/Lightspark vs RGB: Architecture Analysis for MAT

**Date:** 2026-09-15  
**Context:** Evaluating whether Spark (Lightspark's Layer 2) could simplify the MAT implementation and improve mobile-friendliness compared to the current RGB+DLC+Lightning stack.

---

## Executive Summary

**Short answer:** Spark could significantly simplify the token/transfer layer and mobile experience, but **cannot replace the DLC collateral mechanism** that is core to MAT's economics. A hybrid approach is possible but introduces complexity.

**Key findings:**

1. ✅ **Spark excels at:** instant token transfers, mobile SDKs, zero-fee user-to-user payments
2. ❌ **Spark cannot do:** DLC-style oracle-enforced collateral contracts
3. 🤔 **The "token per couple" idea:** interesting but adds complexity without clear benefits
4. 💡 **Recommendation:** Stay with RGB+DLC for v1; consider Spark for Phase 5+ holder payouts only

---

## Current Architecture (RGB + DLC + Lightning)

### What You Have Today

```
┌─────────────────────────────────────────────────────────────┐
│ MAT Deal Flow (Current)                                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Collateral Lock                                         │
│     └─→ DLC 2-of-2 funding tx (Bitcoin L1)                │
│         └─→ Borrower + Hodler real BTC locked              │
│                                                             │
│  2. Token Issuance                                          │
│     └─→ RGB (RLN nodes)                                    │
│         └─→ EUR-denominated tokens to borrower             │
│                                                             │
│  3. Token Transfers (during deal lifecycle)                 │
│     └─→ RGB transfers (currently on-chain)                 │
│         └─→ Future: RGB over Lightning (zero-fee plan)     │
│                                                             │
│  4. Settlement at Maturity                                  │
│     └─→ Oracle attests BTC/EUR price                       │
│     └─→ DLC executes CET (Commitment Execution Tx)         │
│     └─→ FloorEUR payout curve determines distribution      │
│                                                             │
│  5. Holder Distribution                                     │
│     └─→ Current: L1 fan-out (expensive)                    │
│     └─→ Planned: Lightning w/ HODL invoices (Phase 5)      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Critical Components

| Component | Technology | Purpose | Replaceable? |
|-----------|-----------|---------|--------------|
| **Collateral lock** | DLC (rust-dlc) | 2-of-2 BTC escrow with oracle-enforced payout | ❌ No - core to MAT |
| **EUR tokens** | RGB (rgb-lib + RLN) | Transferable EUR-denominated IOUs | ✅ Maybe - Spark has tokens |
| **Token transfers** | RGB (on-chain or LN) | User-to-user EUR payments | ✅ Maybe - Spark excels here |
| **Oracle settlement** | Pythia + DLC | Price attestation → CET execution | ❌ No - DLC-specific |
| **Holder payouts** | Planned: Lightning | Principal + interest distribution | ✅ Yes - Spark or Lightning |

---

## What is Spark? (Lightspark's Layer 2)

### Architecture Overview

**Spark = Statechains + FROST Signatures + Token Standard**

```
┌─────────────────────────────────────────────────────────────┐
│ Spark Architecture                                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Bitcoin L1 (Root UTXO)                                     │
│      ↓                                                      │
│  Statechain Tree (off-chain)                                │
│      ├─→ Leaves (user balances)                            │
│      └─→ FROST threshold sigs (operators)                  │
│                                                             │
│  BTKN Token Standard                                        │
│      ├─→ TTXOs (Token Transaction Outputs)                 │
│      ├─→ Instant transfers (< 1 sec)                       │
│      ├─→ Zero fees (Spark-to-Spark)                        │
│      └─→ Unilateral exit to L1                             │
│                                                             │
│  Trust Model: 1-of-n operators                              │
│      └─→ Safe if ≥1 operator honest                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Key Characteristics

**What Spark Does Well:**

✅ **Instant transfers:** < 1 second finality (vs RGB on-chain = 10 min confirmations)  
✅ **Zero fees:** Spark-to-Spark transfers free (vs RGB on-chain = miner fees)  
✅ **Mobile SDKs:** TypeScript/React Native with excellent DX  
✅ **Token standard:** BTKN - mint, transfer, freeze, burn  
✅ **Lightning compatible:** Can send/receive over Lightning  
✅ **Unilateral exit:** Users can always exit to L1 without operator consent  
✅ **Offline receive:** Tokens can be received while offline  

**What Spark Cannot Do:**

❌ **DLCs:** No support for oracle-enforced contracts  
❌ **Conditional payouts:** Cannot encode "if price > X then pay Y"  
❌ **2-of-2 escrows:** Operators are always part of signing (1-of-n trust)  
❌ **FloorEUR logic:** Would need to be implemented off-Spark  

### Trust Model Comparison

| Model | MAT Current | Spark |
|-------|-------------|-------|
| **Collateral** | Trustless 2-of-2 DLC (Bitcoin L1) | 1-of-n operators (Spark entity) |
| **Token transfers** | Client-side RGB validation | Operator validation + watchtowers |
| **Settlement** | Oracle + DLC (trustless) | N/A (no settlement mechanism) |
| **Exit** | Broadcast CET (trustless) | Unilateral exit to L1 (1-of-n) |

---

## Spark vs RGB for MAT: Direct Comparison

### Scenario 1: Replace RGB with Spark for EUR Tokens

**What changes:**

```diff
- RGB (RLN nodes per user)
+ Spark BTKN token (one token type: MAT_EUR or per-deal token)

- RGB transfers (on-chain or future LN)
+ Spark transfers (instant, zero-fee)

- RGB client-side validation
+ Spark operator validation

- rgb-lib on mobile (Phase 4)
+ Spark SDK (simpler integration)
```

**Pros:**

✅ **Much simpler mobile integration** - Spark SDK is production-ready, React Native support  
✅ **Zero-fee transfers** - Alice → Claude sends are instant and free (no RGB on-chain fees)  
✅ **Better UX** - < 1 sec finality vs 10 min RGB confirmations  
✅ **Less infrastructure** - No per-user RLN Docker fleet needed  
✅ **Proven tokens** - BTKN standard is battle-tested (USDB, etc.)  

**Cons:**

❌ **DLC incompatibility** - Spark tokens don't interact with DLC payouts natively  
❌ **1-of-n trust** - Borrower/hodler trust Spark operators for token state  
❌ **Distribution complexity** - At settlement, how do you pay Spark TTXO holders from DLC CET?  
❌ **Bridge logic** - Need mechanism to convert DLC output → Spark token redemption  
❌ **Operator dependency** - If all Spark operators fail, recovery is harder than RGB  

### Scenario 2: Hybrid - Keep DLC, Use Spark for Transfers Only

**Architecture:**

```
1. Activation
   └─→ DLC funding (2-of-2, as today)
   └─→ Issue Spark BTKN token (instead of RGB)

2. Transfers
   └─→ Spark-to-Spark (instant, free)

3. Settlement
   └─→ DLC CET executes (as today)
   └─→ Holders redeem Spark tokens for BTC payouts
       └─→ HOW? 🤔
```

**The Hard Problem: Settlement Bridge**

At maturity:
- DLC pays CET outputs to Bitcoin L1 addresses
- Holders have Spark BTKN tokens (off-chain)
- Need to **atomically link**: token redemption ↔ BTC payout

**Option A:** Spark tokens as claims
- Holder presents Spark token → gets paid from `peg_pot`
- Requires trusted distributor (defeats DLC trustlessness)

**Option B:** Burn Spark tokens → Lightning invoice
- Holder burns tokens → receives Lightning payment
- Still need trusted bridge service
- Similar to current Phase 5 plan (HODL invoices)

**Option C:** Spark operators co-sign DLC
- Spark operators become party to DLC
- Violates Spark's 1-of-n model
- Likely not supported by Spark protocol

**Verdict:** Hybrid is possible but introduces a **trusted bridge** between DLC and Spark, which undermines the trustless DLC settlement.

---

## The "Token Per Couple" Idea

### Your Question Interpretation

> "Emitting a new token per each couple of investor and saver"

**Possible meanings:**

1. **One token type per deal** (not per couple)
   - E.g., DEAL_001_EUR, DEAL_002_EUR
   - Each Budget gets its own BTKN token

2. **One token type per (borrower, hodler) pair**
   - E.g., ALICE_BOB_EUR
   - If Alice deals with Bob twice → reuse token
   - If Alice deals with Claude → new token

3. **One deal = one isolated economy**
   - Tokens from Deal A cannot be sent to Deal B participants

### Analysis

**Option 1: Token per Deal**

```
Budget #1 (Alice borrows from Bob)
  └─→ BTKN token: DEAL001_EUR
      └─→ Alice gets 1000 DEAL001_EUR
      └─→ Alice sends 300 → Claude (he now has DEAL001_EUR)

Budget #2 (David borrows from Eve)
  └─→ BTKN token: DEAL002_EUR
      └─→ David gets 500 DEAL002_EUR
      └─→ David sends 100 → Claude (he now has DEAL002_EUR)

Claude's balances:
  - 300 DEAL001_EUR
  - 100 DEAL002_EUR
```

**Pros:**
✅ Clean accounting per deal  
✅ Natural scoping for settlement (each token type settles independently)  
✅ Prevents cross-deal token pollution  
✅ Clear maturity tracking (each token has its own maturity date)
✅ Simpler to reason about holder rights per deal

**Cons:**
❌ More token types to manage in wallet implementation
❌ Multi-token transfers (send 350 EUR = 300 DEAL001_EUR + 50 DEAL002_EUR)
❌ Each token needs separate BTKN/RGB deployment
❌ Recipient must understand they're receiving multiple token types

**UX Note:** Similar to Bitcoin UTXOs - can be aggregated in wallet display:
```
Total Balance: 400 EUR
  ├─ Deal #1 (matures 2026-12-01): 300 EUR
  └─ Deal #2 (matures 2027-01-15): 100 EUR
```  

**Option 2: Token per Pair**

Even worse fragmentation. **Not recommended.**

**Option 3: Single Shared EUR Token (Current RGB Approach)**

```
All deals use: MAT_EUR (single RGB asset)

Budget #1: Alice borrows 1000 MAT_EUR
Budget #2: David borrows 500 MAT_EUR

Claude receives 300 from Alice + 100 from David
  → Total: 400 MAT_EUR (fungible)

At settlement:
  - Snapshot MAT_EUR balances
  - Distribute pro-rata from each deal's peg_pot
```

**This is simpler and matches your current RGB design.**

### Recommendation: Reconsider Token-Per-Deal 🤔

**You're right:** Token-per-deal is like Bitcoin UTXOs - wallet can aggregate and show total.

#### Arguments FOR Token-Per-Deal

**1. Natural Settlement Scoping**

Each deal has its own maturity date and settlement:
```
Deal #1 (matures Dec 2026): 300 DEAL001_EUR outstanding
Deal #2 (matures Jan 2027): 100 DEAL002_EUR outstanding

On Deal #1 maturity:
  - Only DEAL001_EUR holders get paid
  - DEAL002_EUR unaffected
  - No cross-deal accounting needed
```

**2. Clearer Holder Rights**

"I hold 300 DEAL001_EUR" = precise claim on Deal #1's `peg_pot`
- No ambiguity about which deal you're entitled to
- Simpler legal/accounting (each token = specific contract)

**3. UTXO Pattern Works**

Bitcoin wallets already solve this:
- Aggregate UTXO balance: "You have 1.5 BTC"
- Coin control: Spend from specific UTXOs when needed
- Same for tokens: "You have 400 EUR" (aggregated from multiple deals)

**4. Better for Failures**

If Deal #1 fails (oracle failure, refund needed):
- Only DEAL001_EUR affected
- DEAL002_EUR holders protected
- No cross-contamination

**5. Simpler Settlement Logic**

Current (shared token) approach:
```ruby
# At Deal #1 maturity
holders = TokenAccount.where(asset_id: 'MAT_EUR').where.not(balance: 0)
# Problem: How do you know which holders are entitled to THIS deal?
# Need: deal_participation tracking table
```

Token-per-deal approach:
```ruby
# At Deal #1 maturity
holders = TokenAccount.where(asset_id: 'DEAL001_EUR').where.not(balance: 0)
# All DEAL001_EUR holders are entitled. Done.
```

#### Arguments AGAINST Token-Per-Deal

**1. Implementation Complexity**

Each transfer now potentially involves multiple tokens:
```
Alice wants to send 350 EUR to Bob
Alice has: 300 DEAL001_EUR + 100 DEAL002_EUR

Wallet must:
  - Send 300 DEAL001_EUR
  - Send 50 DEAL002_EUR  
  - Keep 50 DEAL002_EUR as change

Bob receives 2 token types in one "payment"
```

**2. Recipient Acceptance**

Bob's wallet must be prepared to receive arbitrary token types:
- First time: Receives DEAL001_EUR (unknown token)
- Auto-register? Manual accept?
- Trust model: Does Bob trust each deal's issuer?

**3. More Issuance Overhead**

Each deal activation:
- Deploy new RGB asset (or BTKN token)
- Register in wallet address books
- More on-chain footprint (if RGB genesis)

**4. Not Directly Interchangeable**

300 DEAL001_EUR ≠ 300 DEAL002_EUR (even though both are "EUR")
- Can't directly swap without conversion logic
- If you add DEX later, need separate liquidity pools per token

#### Hybrid Approach: Single Token + Deal Tracking

**Alternative:** Keep single MAT_EUR token, track entitlements in metadata:

```ruby
# TokenAccount model
user_id: 123  (Claude)
asset_id: 'MAT_EUR'
balance: 400

# TokenEntitlement model (new)
user_id: 123
budget_id: 1
entitled_amount: 300

user_id: 123  
budget_id: 2
entitled_amount: 100
```

**Pros:**
- Fungible EUR token (simpler transfers)
- Still track per-deal entitlements for settlement
- Wallet shows: "400 EUR from 2 deals"

**Cons:**
- Need separate entitlement tracking
- Settlement must query entitlements (not just token balances)
- Token transfers don't automatically update entitlements (need transfer hooks)

### Updated Recommendation: It Depends 🎯

| Use Case | Recommendation |
|----------|----------------|
| **Few deals per user** | ✅ Token-per-deal (cleaner) |
| **Many deals per user** | ✅ Single token + entitlement tracking |
| **Priority: Trustless settlement** | ✅ Token-per-deal (direct claim) |
| **Priority: Transfer UX** | ✅ Single token (simpler sends) |
| **Using Spark BTKN** | 🟡 Either works (BTKN supports multiple token types) |
| **Using RGB** | 🟡 Either works (RGB supports multiple assets) |

**For MAT v1:** I'd now lean toward **token-per-deal** if:
1. You expect users to participate in 1-5 deals typically (not 100s)
2. Wallet can aggregate like Bitcoin (show "Total: 400 EUR")
3. Settlement simplicity > transfer UX

---

## Lightspark vs Spark Clarification

### Lightspark (The Company)

**Products:**
1. **Lightspark Connect** - Enterprise Lightning infrastructure
   - Managed nodes, liquidity, routing
   - Used by Coinbase, Nubank, others
   - Not relevant to MAT (you need DLCs)

2. **UMA Protocol** - Lightning addresses for global payments
   - `$alice@wallet.com` format
   - Good for UX, but doesn't help with collateral/tokens
   - Could be nice for Phase 5 holder payouts

3. **Grid** - Global accounts, fiat on/off-ramps
   - Banking integration, compliance
   - Could help with EUR fiat ramps (future)
   - Not for core MAT mechanics

4. **Spark** - The Layer 2 (covered above)

### What's Relevant to MAT?

| Lightspark Product | Relevance | Use Case |
|--------------------|-----------|----------|
| **Spark L2** | 🟡 Maybe | Token layer replacement (trade-offs) |
| **Grid** | 🟢 Yes (later) | EUR fiat on-ramps for users |
| **UMA** | 🟢 Yes (Phase 5) | Lightning addresses for holder payouts |
| **Lightspark Connect** | ⚪ No | You need DLCs, not managed nodes |

---

## Mobile-Friendliness Comparison

### Current Plan (RGB + DLC + BDK)

**Phase 2-4 from `mobile-production-plan.md`:**

```
Mobile app (Flutter)
  └─→ BDK (Rust FFI) - L1 wallet
  └─→ mat-dlc (Rust FFI) - DLC signing
  └─→ rgb-lib (Rust FFI) - RGB tokens
  └─→ Breez SDK (Phase 5) - Lightning payouts
```

**Complexity:**
- 🔴 High: 3-4 Rust FFI integrations
- 🔴 Large binary size
- 🔴 Complex state management (LDK + RGB)
- 🟢 Full self-custody

**Timeline (from plan):**
- Phase 2: BDK (6-8 weeks)
- Phase 3: DLC (8-12 weeks)
- Phase 4: RGB (8-10 weeks)
- Phase 5: Breez (8-12 weeks)

**Total: ~32-42 weeks of mobile work**

### Spark Alternative (Hypothetical)

```
Mobile app (Flutter/React Native)
  └─→ BDK (Rust FFI) - L1 wallet (still needed for DLC)
  └─→ mat-dlc (Rust FFI) - DLC signing (still needed)
  └─→ Spark SDK (TypeScript/RN) - Tokens + Lightning
```

**Complexity:**
- 🟡 Medium: 2 Rust FFI + 1 TypeScript SDK
- 🟢 Smaller binary (no rgb-lib)
- 🟢 Simpler: Spark SDK handles tokens + Lightning together
- 🟡 1-of-n trust for tokens (vs RGB self-custody)

**Timeline (estimated):**
- Phase 2: BDK (6-8 weeks)
- Phase 3: DLC (8-12 weeks)
- Phase 4: Spark SDK (2-4 weeks) ← **Much faster**
- Phase 5: Built-in to Spark

**Total: ~16-24 weeks** ← **50% faster**

### Winner: Spark is Significantly More Mobile-Friendly

**If you could solve the DLC settlement bridge problem, Spark would be a major win for mobile.**

---

## Architecture Options: Summary

### Option A: Stay with RGB + DLC (Recommended for v1)

```
✅ Proven architecture (your PoC works)
✅ Trustless end-to-end (DLC + RGB client-validation)
✅ No dependency on Spark operators
✅ Clear Phase 5 path (Breez SDK + HODL invoices)

❌ Longer mobile development (rgb-lib integration)
❌ More complex infrastructure (RLN nodes)
❌ Slower transfers until Phase 5
```

**Best for:** Launching MAT with maximum trustlessness and security.

### Option B: Hybrid - DLC + Spark Tokens

```
✅ Faster mobile development
✅ Better token transfer UX (instant, free)
✅ Simpler infrastructure (no RLN)

❌ Introduces 1-of-n trust for tokens
❌ Requires trusted bridge for settlement
❌ Undermines DLC trustlessness at payout
❌ Unproven architecture (need to build bridge)
```

**Best for:** Prioritizing mobile speed-to-market over trustlessness.

### Option C: Spark Everywhere (Not Viable)

```
❌ Cannot do DLCs on Spark
❌ Would need to rewrite FloorEUR logic off-chain
❌ Loses oracle-enforced settlement
❌ Fundamentally different product
```

**Best for:** Nothing - this breaks MAT's core mechanism.

---

## Detailed Trade-off Analysis

### If You Choose Spark (Hybrid Option B)

**What you gain:**
1. Mobile SDK simplicity (React Native ready)
2. Zero-fee user-to-user transfers (better than RGB on-chain)
3. Lightning built-in (no separate Breez integration)
4. Instant token issuance (< 1 sec vs RGB confirmation times)
5. BTKN token features (freeze, burn, analytics)

**What you lose/risk:**
1. **Trust:** Introduce 1-of-n assumption (vs RGB client-validation)
2. **Bridge complexity:** Need new service to connect DLC → Spark
3. **Settlement atomicity:** Hard to guarantee token burn ↔ BTC payout
4. **Operator dependency:** If Spark operators fail, token recovery harder
5. **Unproven:** No one has built DLC + Spark hybrid before

### If You Stay with RGB

**What you gain:**
1. **Trustless:** Pure client-side validation
2. **Proven:** Your PoC already works
3. **Clear path:** Mobile plan in `mobile-production-plan.md` is solid
4. **No bridge:** DLC settlement directly to RGB holders
5. **Self-custody:** Full keys on device

**What you lose:**
1. Slower mobile development (rgb-lib FFI is complex)
2. Slower transfers until Phase 5 (on-chain RGB = 10 min)
3. Transfer fees until Phase 5 (on-chain RGB = miner fees)
4. More infrastructure (RLN nodes per user in PoC; P2P in prod)

---

## What About "Simplified" Spark-Only Approach?

### Could MAT Work Without DLCs?

**Hypothetical: Replace DLC with Spark Smart Logic**

```
1. Borrower + Hodler deposit to Spark
2. Issue Spark tokens to borrower
3. At maturity, use Spark operators to enforce payout

Problem: Spark operators must be trusted to:
  - Read oracle price
  - Calculate FloorEUR payouts
  - Distribute correctly
```

**This is centralized custody.** The Spark operators become a trusted party, defeating the purpose of DLCs.

**Verdict: No.** MAT's value proposition is **trustless collateral + oracle settlement**. Removing DLCs removes the core innovation.

---

## Recommendation

### For v1 Production: Stick with RGB + DLC + Breez

**Reasoning:**

1. **Core to MAT:** DLCs are non-negotiable for oracle-enforced settlement
2. **Proven:** Your PoC works; mobile plan is solid
3. **Trust model:** Trustless beats 1-of-n for collateral-backed products
4. **Clear path:** `mobile-production-plan.md` phases are well-defined
5. **Breez SDK:** Solves Phase 5 (LN payouts) without Spark

**Timeline:** 32-42 weeks (but trustless and proven)

### For v2 / Future: Consider Spark for Specific Use Cases

**Where Spark Could Shine:**

1. **Post-settlement transfers:** After deal matures, let users keep EUR as Spark tokens for spending
2. **Non-DLC deals:** If you add non-collateralized loans, Spark could work
3. **Liquidity pools:** If you add DEX/AMM features, Spark has instant swaps
4. **Microtransactions:** Daily spending of EUR tokens (coffee, etc.)

**Hybrid Architecture (v2):**

```
DLC + RGB: Core collateral deals (trustless)
  └─→ Settlement pays to RGB holders

Spark Bridge (optional):
  └─→ Convert settled EUR_RGB → EUR_SPARK
  └─→ Users opt-in to Spark for fast spending
  └─→ Bridge is one-way: RGB → Spark (not critical path)
```

### For Mobile Phase 5: Evaluate Spark vs Breez

**Your current plan:** Breez SDK for Lightning payouts

**Alternative:** Spark Lightning integration

**Comparison:**

| Feature | Breez SDK | Spark |
|---------|-----------|-------|
| Lightning send/receive | ✅ Yes | ✅ Yes |
| LSP integration | ✅ Yes | ✅ Yes (SSP) |
| Instant transfers | ✅ Yes | ✅ Yes (even faster) |
| Token support | ❌ No | ✅ Yes (BTKN) |
| Stablecoin payments | ❌ No | ✅ Yes |
| Trust model | Non-custodial LSP | 1-of-n operators |
| Maturity | ✅ Production | 🟡 Newer |

**Decision point:** If you're already integrating Spark for tokens (hybrid), then use Spark for Lightning too. Otherwise, Breez is more mature for pure LN.

---

## Answers to Your Specific Questions

### Q1: "Could the implementation be simplified using Spark?"

**A:** Yes and no.

- **Token layer:** Spark is simpler than RGB (better SDK, instant transfers)
- **But:** Cannot replace DLC, so you still need DLC logic
- **Overall:** Hybrid is not necessarily simpler (introduces bridge complexity)

**Simpler for mobile:** Yes (Spark SDK < rgb-lib integration)  
**Simpler overall:** No (introduces new trust assumptions and bridge service)

### Q2: "Fully mobile friendly?"

**A:** Spark is **more mobile-friendly than RGB** due to:

- React Native SDK (vs Rust FFI)
- Smaller binary size
- Less state management complexity
- Instant operations (no waiting for confirmations)

**But:** You still need DLC (mat-dlc FFI), so mobile is not fully simplified.

**Verdict:** Spark helps mobile, but doesn't eliminate mobile complexity entirely.

### Q3: "Emitting a new token per each couple of investor and saver?"

**A:** Token-per-deal is actually viable (like Bitcoin UTXOs).

**Token per deal:** ✅ Clean settlement scoping; wallet can aggregate balance  
**Token per pair:** ❌ Too much fragmentation  
**Shared token:** ✅ Simpler transfers, but need entitlement tracking  

**Key insight:** You can aggregate tokens in wallet display (like BTC UTXOs):
```
Total: 400 EUR
├─ Deal #1 (300 EUR)
└─ Deal #2 (100 EUR)
```

**Recommendation:** Token-per-deal if users typically have 1-5 deals; single token if expecting 100s of deals per user.

**If using Spark:** Either works - BTKN supports multiple token types natively.

---

## Technical Deep Dive: Token-Per-Deal Implementation

### How It Would Work (RGB Example)

**Deal Activation:**

```ruby
class Budgets::ActivateService
  def call
    # 1. DLC funding (as today)
    fund_dlc_contract
    
    # 2. Issue deal-specific RGB asset
    asset_id = Rgb::IssueService.call(
      ticker: "D#{budget.id}EUR",  # e.g., "D42EUR"
      name: "MAT Deal ##{budget.id} EUR",
      precision: 2,
      amount: budget.borrower_amount_cents
    )
    
    budget.update!(rgb_asset_id: asset_id)
    
    # 3. Assign to borrower
    Rgb::TransferService.call(
      asset_id: asset_id,
      recipient: budget.borrower,
      amount: budget.borrower_amount_cents
    )
  end
end
```

**User Balance Query:**

```ruby
class User < ApplicationRecord
  def eur_tokens
    # Returns array of {asset_id, amount, deal} hashes
    TokenAccount.where(user: self)
      .joins(:rgb_assignment)
      .joins(rgb_assignment: :budget)
      .map do |account|
        {
          asset_id: account.asset_id,
          amount: account.balance,
          deal_id: account.rgb_assignment.budget.id,
          maturity: account.rgb_assignment.budget.maturity_at,
          ticker: "D#{account.rgb_assignment.budget.id}EUR"
        }
      end
  end
  
  def total_eur_balance
    # Aggregate for display
    eur_tokens.sum { |t| t[:amount] }
  end
end
```

**Transfer (Multi-Token):**

```ruby
class Tokens::WalletTransferService
  def call(sender:, recipient:, amount_cents:)
    # Find sender's token holdings
    holdings = sender.eur_tokens.sort_by { |t| t[:maturity] }
    
    remaining = amount_cents
    transfers = []
    
    holdings.each do |holding|
      break if remaining.zero?
      
      transfer_amount = [holding[:amount], remaining].min
      
      transfers << {
        asset_id: holding[:asset_id],
        amount: transfer_amount
      }
      
      remaining -= transfer_amount
    end
    
    raise InsufficientBalance if remaining > 0
    
    # Execute multiple RGB transfers
    transfers.each do |transfer|
      Rgb::LibTransferService.call(
        asset_id: transfer[:asset_id],
        sender: sender,
        recipient: recipient,
        amount: transfer[:amount]
      )
    end
    
    transfers
  end
end
```

**Settlement (Simplified):**

```ruby
class Settlements::ExecuteService
  def call(budget)
    # 1. Get all holders of THIS deal's token
    asset_id = budget.rgb_asset_id
    holders = TokenAccount.where(asset_id: asset_id)
                          .where("balance > 0")
    
    # 2. Execute DLC CET
    cet_result = Dlc::SettlementService.call(budget)
    
    # 3. Distribute peg_pot to holders
    Dlc::Distribution.call(
      holders: holders,
      peg_pot_sats: cet_result.peg_sats
    )
    
    # 4. Burn this deal's tokens (redeemed)
    holders.each do |holder|
      Rgb::BurnService.call(
        asset_id: asset_id,
        holder: holder.user,
        amount: holder.balance
      )
    end
  end
end
```

### Wallet Display (Mobile)

**Aggregated View:**

```dart
// Flutter example
class WalletBalanceWidget extends StatelessWidget {
  final List<TokenHolding> holdings;
  
  @override
  Widget build(BuildContext context) {
    final totalEur = holdings.fold<int>(
      0, 
      (sum, h) => sum + h.amount
    );
    
    return Column(
      children: [
        // Primary balance (aggregated)
        Text(
          '€${(totalEur / 100).toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.headline2,
        ),
        
        // Expandable detail
        ExpansionTile(
          title: Text('${holdings.length} active deals'),
          children: holdings.map((h) => 
            ListTile(
              title: Text('Deal #${h.dealId}'),
              subtitle: Text('Matures ${h.maturityDate}'),
              trailing: Text('€${(h.amount / 100).toStringAsFixed(2)}'),
            )
          ).toList(),
        ),
      ],
    );
  }
}
```

**Send Flow:**

```dart
// User enters: "Send 350 EUR to Bob"
// Wallet automatically selects tokens (like coin selection)

class SendMoneyScreen extends StatefulWidget {
  void _send(String recipient, int amountCents) async {
    // Backend selects which tokens to send
    final result = await api.sendEur(
      recipient: recipient,
      amount: amountCents,
    );
    
    // Show success with breakdown
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Sent €${(amountCents / 100).toStringAsFixed(2)}'),
        content: Column(
          children: [
            Text('Tokens sent:'),
            ...result.transfers.map((t) => 
              Text('${t.ticker}: €${(t.amount / 100).toStringAsFixed(2)}')
            ),
          ],
        ),
      ),
    );
  }
}
```

### Comparison: Settlement Logic Complexity

**Single Token (Current):**

```ruby
# More complex: need to track which balances belong to which deal
class Settlements::ExecuteService
  def call(budget)
    # Get all holders of MAT_EUR
    all_holders = TokenAccount.where(asset_id: 'MAT_EUR')
    
    # Filter to holders who participated in THIS budget
    # Option A: participation tracking table
    eligible_holders = all_holders.joins(:budget_participations)
                                   .where(budget_participations: { budget: budget })
    
    # Option B: scan transfer history (expensive)
    eligible_holders = all_holders.select do |holder|
      has_received_from_this_budget?(holder, budget)
    end
    
    # Distribute...
  end
end
```

**Token-Per-Deal:**

```ruby
# Simpler: all holders of this asset are entitled
class Settlements::ExecuteService
  def call(budget)
    holders = TokenAccount.where(asset_id: budget.rgb_asset_id)
                          .where("balance > 0")
    
    # All holders are entitled. Done.
    Dlc::Distribution.call(holders: holders, peg_pot_sats: ...)
  end
end
```

### Migration Path

**Start with single token (v1):**
- Simpler to launch
- Learn user patterns

**Evaluate token-per-deal (v2) if:**
- Users report confusion about mixed deal entitlements
- Settlement accounting becomes complex
- Want clearer legal separation per deal

---

## Technical Deep Dive: Spark Settlement Bridge

### The Critical Unsolved Problem

**Scenario:** DLC matures, holders have Spark tokens, how do they get paid?

```
Alice (borrower): 0 EUR_SPARK
Claude (holder): 300 EUR_SPARK
David (holder): 700 EUR_SPARK

DLC CET executes:
  └─→ peg_pot = 100,000 sats (to distributor address)
  └─→ investor_pot = 50,000 sats (to hodler)

Challenge: Atomically link Spark token → sats payout
```

### Attempted Solutions

#### Solution 1: Trusted Distributor (Easiest, Least Trustless)

```
1. Snapshot Spark token balances at maturity
2. Holders submit "redeem" request with Spark token burn
3. Distributor service validates burn, pays sats
```

**Pros:** Simple to implement  
**Cons:** Distributor is trusted; can steal `peg_pot` or refuse payouts

#### Solution 2: HTLC Atomic Swap (Better, Complex)

```
1. Holder creates Lightning invoice (amount = FloorEUR calc)
2. Holder burns Spark tokens, includes invoice in burn tx
3. Distributor watches burns, pays invoice only if valid burn
4. Invoice preimage proves payment
```

**Pros:** More atomic  
**Cons:** Still requires distributor honesty; Spark burn + LN payment not truly atomic

#### Solution 3: Spark Operators as DLC Signers (Breaks Both Protocols)

```
Make Spark operators part of DLC 2-of-2
  → Doesn't work: DLC is 2-of-2, Spark is 1-of-n threshold
```

**Verdict:** Not compatible with either protocol's design.

#### Solution 4: Exit Spark Before Settlement

```
1. Holders withdraw Spark tokens to RGB before maturity
2. Settlement pays RGB holders (as current design)
```

**Pros:** No bridge needed!  
**Cons:** Defeats purpose of using Spark (need RGB anyway)

### Conclusion: No Trustless Bridge Exists

**All solutions introduce trusted intermediary or reduce atomicity.**

This is why **staying with RGB end-to-end** maintains trustlessness.

---

## Integration with Lightspark Ecosystem

### If You Later Want Fiat On-Ramps (Grid)

**Scenario:** Users want to buy EUR tokens with fiat

**With RGB:**
```
User → Grid (fiat) → BTC → Your app → DLC/RGB → EUR tokens
```

**With Spark:**
```
User → Grid (fiat) → Spark USDB → Swap to MAT_EUR
```

**Spark integration is smoother here** (Grid + Spark are same ecosystem)

### If You Want UMA Addresses (Phase 5)

**For holder payouts:**
```
Claude's UMA: $claude@mat.example.com
At settlement: Pay to $claude@mat.example.com via Lightning
```

**Works with both:**
- RGB + Breez + UMA ✅
- Spark + UMA ✅ (even more integrated)

---

## Migration Path (If You Later Choose Spark)

### Phase 1-4: RGB (Trustless MVP)

Build and launch with RGB as planned.

### Phase 5: Add Spark Bridge (Optional)

```
1. Deploy MAT_EUR BTKN token on Spark
2. Build bridge service:
   - RGB → Spark (one-way)
   - User locks RGB tokens → receives Spark tokens
3. Users can opt-in to Spark for fast spending
4. DLC settlements still pay RGB holders
```

**This de-risks:** Launch with proven tech, add Spark later if demand warrants.

---

## Final Recommendation

### Do This Now (v1):

1. ✅ **Continue with RGB + DLC** as per `mobile-production-plan.md`
2. ✅ **Use Breez SDK** for Phase 5 Lightning payouts
3. ✅ **Single MAT_EUR token** (not per-deal tokens)
4. ✅ **Focus on trustless architecture** (your competitive advantage)

### Consider Later (v2+):

1. 🤔 **Spark for post-settlement spending** (if users want to hold/spend EUR)
2. 🤔 **Grid integration** for fiat on-ramps
3. 🤔 **UMA addresses** for cleaner payout UX
4. 🤔 **Spark bridge** if user testing shows demand for instant transfers > trustlessness

### Don't Do:

1. ❌ **Don't replace DLC with Spark** (breaks core mechanism)
2. ❌ **Don't do token-per-deal** (UX fragmentation)
3. ❌ **Don't rush Spark integration** without solving settlement bridge

---

## Key Takeaways

1. **Spark is great at tokens/transfers, but cannot do DLCs**
2. **Mobile-friendliness:** Spark wins (React Native vs Rust FFI)
3. **Trust model:** RGB is trustless; Spark is 1-of-n
4. **Settlement bridge is the unsolved problem** preventing clean hybrid
5. **Recommendation:** Stay RGB for v1; revisit Spark for v2 after launch

---

## References

- [MAT mobile-production-plan.md](./mobile-production-plan.md) - Current RGB+DLC mobile roadmap
- [Spark Documentation](https://docs.spark.money/) - Technical architecture
- [Spark Layer 2 Deep Dive](https://www.spark.money/research/what-is-spark-bitcoin-layer-2)
- [BTKN Token Standard](https://docs.spark.money/learn/tokens/hello-btkn)
- [Lightspark UMA Protocol](https://www.lightspark.com/knowledge/understanding-uma-the-universal-money-address-protocol)
- [RGB Protocol](https://rgb.tech/)

---

## Appendix: Spark SDK Mobile Example

**What Spark integration would look like (TypeScript/React Native):**

```typescript
import { SparkWallet } from '@buildonspark/spark-sdk';

// Initialize wallet
const wallet = await SparkWallet.initialize({
  network: 'mainnet',
  signer: myPhoneSigner,
});

// Issue MAT_EUR token (issuer only)
const tokenId = await wallet.createToken({
  name: 'MAT Euro',
  ticker: 'MEUR',
  decimals: 2,
  totalSupply: 1000000, // 10k EUR
});

// Mint tokens to borrower
await wallet.mintTokens({
  tokenId,
  recipient: borrowerAddress,
  amount: 100000, // 1k EUR
});

// Transfer tokens (instant, zero-fee)
await wallet.transferTokens({
  tokenId,
  recipient: claudeAddress,
  amount: 30000, // 300 EUR
});

// Lightning receive (built-in)
const invoice = await wallet.createLightningInvoice({
  amount: 50000, // 50k sats
});

// At settlement: Burn tokens (redemption)
await wallet.burnTokens({
  tokenId,
  amount: 30000,
  memo: 'Settlement for Budget #42',
});
```

**Compare to rgb-lib FFI:** This is significantly simpler than Rust FFI bindings + manual state management.

**But:** You still need DLC FFI for collateral, so overall complexity remains.
