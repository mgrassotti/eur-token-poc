# MAT PoC (Rails + DLC + RGB on regtest)

Rails proof-of-concept for bilateral P2P deals (`Budget`), with:

- real BTC collateral on regtest
- EUR-denominated tokens transferable between users
- maturity settlement via DLC (oracle-attested CET)

## Current implementation status

- **Single settlement path:** DLC (Discreet Log Contract)
- **Reserve-funded DLC:** funding inputs come from users' real L1 reserve UTXOs
- **Single lock model:** the 2-of-2 DLC funding transaction is the collateral lock
- **RGB stack:** real RGB Lightning Nodes on regtest (one per user + issuer)
- **Demo / E2E tests:** integration and system specs aligned with the real flow

## Functional architecture

Each `Budget` is an autonomous deal:

- the borrower opens a request (EUR notional amount)
- the hodler activates the deal
- EUR nominal tokens are issued to the borrower
- tokens can be transferred to other users
- at maturity the DLC executes the CET, then the `peg_pot` is distributed pro-rata to holders

### Collateral and payout

- borrower + hodler collateral is locked in the **2-of-2 DLC funding output**
- the investor-side CET output returns to the hodler's L1 reserve
- the peg-side CET output is distributed to holders via `Dlc::Distribution`

### Important: DLC vs holder distribution

The DLC contract is signed once at activation. It only fixes:

- how much of the pool goes to the **peg side** vs the **hodler side** for each oracle price outcome

It does **not** enumerate individual holders. At settlement:

1. the CET pays the total `peg_pot` to a sidecar-controlled peg address
2. Rails snapshots RGB/token balances at maturity
3. `Dlc::Distribution` asks the sidecar to fan out that output pro-rata to holder reserve addresses

RGB therefore influences L1 payouts **indirectly** through the Rails orchestrator reading token ownership — not through a trustless on-chain link between RGB state and the DLC spend path. Transfers do not require re-signing the DLC.

## Technical architecture

### Main components

- **Rails app:** orchestration, domain state, dashboard, demo flow
- **bitcoind regtest:** chain and on-chain wallets
- **Pythia oracle:** numeric DLC event announce / attest
- **`dlc-rs` sidecar (Rust):**
  - builds the DLC tx set (funding / CET / refund)
  - accepts real reserve inputs from Ruby
  - returns the unsigned funding tx
  - executes the CET at maturity
  - distributes the `peg_pot` from real CET outputs
- **RGB Lightning Nodes:** one per user + issuer

### Activation flow (current)

`Budgets::ActivateService` → `L1::ProvisionEscrowService`:

1. announce the oracle event
2. select borrower / hodler reserve UTXOs
3. call `Dlc::NodeClient#create_contract` with:
   - `peg_inputs` / `investor_inputs`
   - change addresses
   - investor payout address
4. sign the funding tx with reserve wallets in Ruby
5. broadcast the funding tx
6. persist the DLC funding outpoint on `Budget` (`escrow_txid` / `escrow_vout`)
7. issue RGB

### Settlement flow

`Settlements::ExecuteService`:

1. validate maturity + funded contract
2. RGB token redemption
3. `Dlc::SettlementService` executes the CET with the oracle attestation
4. `Dlc::Distribution` distributes the `peg_pot` to holders
5. sync on-chain reserves

## Data model (essential)

- `Budget`: deal lifecycle + collateral lock outpoint (DLC funding)
- `DlcContract`: DLC contract metadata and funding outpoint
- `DlcSettlement`: CET result (`cet_txid`, outcome, peg / investor sats)
- `TokenAccount` / `TokenTransfer` / `RgbAssignment`: token state and ownership
- `CollateralLock`: domain-level collateral lock accounting
- `BtcAccount`: user spendable reserve balance

Note: some legacy DB columns may still exist for backward compatibility, but runtime follows the DLC-only model above.

## Quick setup

```bash
cd ~/dev/eur-token-poc
bundle install
bin/rails db:setup
bin/dev
```

`bin/dev` starts Rails and the required regtest stack.

Demo login:

- `admin@example.com` / `password`
- `alice@example.com` / `password`
- `bob@example.com` / `password`
- `claude@example.com` / `password`
- `david@example.com` / `password`

## Regtest / RGB / DLC stack

```bash
./bin/regtest up
```

Main services:

- bitcoind: `127.0.0.1:18443`
- RLN Alice / Bob / Claude / David: `3001..3004`
- RLN issuer: `3005`
- DLC node (`dlc-rs`): from `DLC_NODE_URL`
- Pythia oracle: from `DLC_ORACLE_URL`

Reset demo environment:

```bash
./bin/regtest reset
```

## Demo flow

1. Admin sets the BTC/EUR rate
2. Alice and Bob deposit into their reserves
3. Alice creates a budget
4. Bob activates the budget (DLC funded from real reserves)
5. Alice transfers part of her tokens to Claude / David
6. At the maturity block, DLC settlement runs
7. Holders receive the distributed `peg_pot`; the hodler receives the investor CET output

## Tests

```bash
bundle exec rspec
./bin/demo-spec
./bin/system-spec
```

- `bundle exec rspec`: full suite (unit + integration + system)
- `bin/demo-spec`: non-browser end-to-end scenario
- `bin/system-spec`: end-to-end scenario via UI

## Key files / services

- `app/services/dlc/contract_setup_service.rb`
- `app/services/dlc/settlement_service.rb`
- `app/services/dlc/distribution.rb`
- `app/services/settlements/execute_service.rb`
- `app/services/l1/provision_escrow_service.rb`
- `lib/dlc/node_client.rb`
- `dlc-rs/src/main.rs`
- `spec/integration/demo_end_to_end_flow_spec.rb`
- `spec/system/demo_end_to_end_flow_spec.rb`

## Known limitations

- Regtest / demo oriented environment, not production hardening.
- Depends on local Docker stack and oracle / DLC services.
- Some legacy DB artifacts remain only for historical compatibility.
- Holder distribution is orchestrated by Rails + sidecar, not atomically bound to RGB on-chain.

## Required future developments

To reach an economically sustainable and scalable architecture, the PoC must evolve beyond predominantly on-chain settlement and distribution.

### 1. Reduce Layer 1 usage

The current state uses Bitcoin L1 for:

- DLC funding / collateral lock
- hodler collateral return via CET
- `peg_pot` distribution to holders

This is correct for a verifiable PoC, but at real volume it introduces:

- miner fees for activation / settlement / distribution
- confirmation latency
- poor efficiency for fractional payouts to many holders

The natural direction is to keep on L1 only what is strictly necessary (`funding` / `refund` / final anchoring) and move operational payouts to Lightning.

### 2. Holder distribution via Lightning instead of L1 payout

Today `Dlc::Distribution` spends the peg-side CET output to holder L1 reserve addresses. For scalability and cost, the next step is:

- replace on-chain fan-out with Lightning payments
- use per-holder invoices instead of per-holder UTXOs
- avoid one L1 transaction with N outputs on every settlement

This reduces fees and payout size, especially when the `peg_pot` must be split across many recipients.

### 3. Pending / HODL invoices for atomicity

The important step is not just "use LN", but **pending invoices** (or HODL invoices) to atomically bind:

- RGB token redemption / burn / withdrawal
- BTC payout receipt on Lightning

Target flow:

1. the holder presents a pending Lightning invoice
2. DLC settlement determines the amount owed
3. the system prepares payment but does not finalize immediately
4. completion happens only when the atomic condition is satisfied (e.g. valid redemption / oracle secret / coherent application state)

This avoids:

- tokens redeemed but payout not received
- payout sent but token state not updated

### 4. Practical feasibility

To move to this model, some infrastructure work is still required:

- reliable pending / HODL invoice support on the Lightning node used
- invoice lifecycle management (`open` / `held` / `settled` / `cancelled`)
- clear mapping between DLC payout, holder position, and LN invoice
- recovery / retry on partial failures
- application accounting that distinguishes:
  - L1 collateral
  - CET payout
  - pending / settled LN payouts

### 5. Reasonable target architecture

A realistic direction for a more mature version:

- **Bitcoin L1:** DLC collateral lock, refund, exceptional / recovery cases
- **DLC:** main deal settlement and payout determination
- **Lightning:** holder payout distribution
- **RGB:** EUR nominal ownership / transferability

In this layout:

- L1 remains the security and finality layer
- LN becomes the operational layer for frequent payouts
- marginal costs for multi-holder settlement drop significantly

### 6. Project status vs this roadmap

The repository currently covers:

- working reserve-funded DLC on regtest
- real hodler return to reserve
- real holder distribution, but still **on-chain**

So the next major architectural step is not the DLC itself, but **migrating distribution to LN with pending invoices**, keeping L1 only where it is truly needed.

## Documentation

- English: `README.md` (this file)
- Italian: `README-ita.md`
