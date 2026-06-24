# FloorEUR PoC (Rails)

Proof-of-concept Rails per **deal P2P bilaterali** (un `Budget` = un deal): token EUR nominale spendibili, collateral BTC in escrow **multisig on-chain (regtest)**, settlement **FloorEUR** a scadenza.

Specifiche di design: [`docs/rgb-design/`](docs/rgb-design/) (`PAYOFF-SPEC`, `P2P-OPTIONS`, `MULTISIG-SPEC`, `MARGIN-SPEC`).

## Setup

```bash
cd ~/dev/eur-token-poc
bundle install
bin/rails db:setup
bin/dev
```

`bin/dev` avvia **bitcoind regtest** (`./bin/regtest up`) e **Rails**. Il PoC **richiede** regtest per depositi, funding escrow e settlement.

Apri http://localhost:3000 e accedi con:

| Utente | Email | Password | Ruolo |
|--------|-------|----------|-------|
| Admin | admin@example.com | password | Cambio BTC/€, altezza blocco, settlement |
| Alice | alice@example.com | password | Richiedente (borrower) |
| Bob | bob@example.com | password | Investitore |
| Claude | claude@example.com | password | Destinatario token |
| David | david@example.com | password | — |

In development puoi usare il dropdown **Switch** nella navbar per cambiare utente rapidamente.

Dopo `db:setup` i **conti di riserva sono a zero**: deposita BTC dal Wallet esterno prima di creare ricariche.

## Modello (per deal)

Ogni **ricarica** (`Budget`) è un deal autonomo:

| Concetto | Implementazione PoC |
|----------|---------------------|
| Escrow | UTXO **2-of-3 P2WSH** on-chain (`escrow_txid`/`vout`) + `CollateralLock` (tracking importi) |
| Strike | `Budget#peg_eur_per_btc` — fissato **all’attivazione** dal `MarketRate` corrente |
| Maturity | `Budget#maturity_block_height` (da `genesis_block_height` + durata in blocchi) |
| Token | `TokenAccount` — 1 cent = 0,01 € nominale sul deal (ledger DB) |
| Settlement | `Payoffs::FloorEurCalculator` → `Settlements::ExecuteService` → `L1::SettlementSpendService` |
| Transfer | `Tokens::WalletTransferService` — spend da più deal se serve |
| Riserva BTC | Wallet regtest per utente; saldo **spendibile on-chain** (`L1::UserWallet`) |
| Oracle / catena | `MarketRate` + `ChainState` (admin); auto-settle al maturity block |

**Collateral in apertura:** richiedente **1×** + investitore **1×** l’importo nominale → escrow **2×**, LTV iniziale **50%**.

**Monitoraggio LTV** (ledger PoC, annex margin on-chain M2+): margin call investitore ≥ **70%**, liquidazione automatica ≥ **90%** (`Budgets::AutoLiquidationService`).

## Scenario demo

Flusso allineato a `bin/demo-spec` (integrazione regtest).

### Stato iniziale (`db:setup` / reset demo)

- Utenti demo creati; **saldi riserva a zero**
- **Nessuna** ricarica pending pre-caricata
- Cambio default: **50_000 €/BTC**; altezza blocco stimata (`ChainState`)

### 1. Admin — cambio, catena, wallet

1. Login come **Admin**
2. Dashboard → pannello admin
3. Verifica **Cambio BTC/€** e **Altezza blocco**
4. Tabella **Wallet on-chain**: saldi regtest + equivalente €
5. Opzionale: **Reset demo** (azzera DB e bitcoind via `./bin/regtest reset`)

### 2. Depositi on-chain (Alice e Bob)

1. Switch **Alice** → **Deposita su conto riserva** (default 0,1 BTC)
2. Switch **Bob** → deposito (default 0,2 BTC nel form; nel demo-spec 0,1 BTC)

Ogni deposito trasferisce dal **Wallet esterno** (`l1_external_wallet`) e avanza la catena simulata di **6 blocchi**.

### 3. Apertura deal

1. Switch **Alice** → **Ricarica conto spesa** (es. 1_000 €)
2. Switch **Bob** → **Ricariche in attesa** → **Accetta rischio e attiva**

Il sistema:

- Verifica saldo spendibile on-chain (peg + investor + fee funding)
- Provisiona escrow **2-of-3** (`L1::ProvisionEscrowService`)
- Fissa `peg_eur_per_btc` e mint **1_000 €** nominali ad Alice sul **conto spesa / risparmio**

### 4. Spesa token (Alice → Claude → David)

1. Switch **Alice** → **Invia Denaro**
2. Invia token a Claude / David come nel demo

I transfer usano `WalletTransferService` e possono attingere a più deal se l’utente ne ha più di uno attivo.

### 5. Settlement a scadenza

Quando `ChainState.block_height >= maturity_block_height`:

- **Automatico:** aggiornando l’altezza blocco (admin) scatta `Budgets::AutoSettleService`
- **Manuale:** Admin → budget attivo → **Settlement**

Il settlement **FloorEUR**:

1. Calcola liability € (notional + interessi)
2. Converte in sats al **spot** di chiusura
3. Cap: `total_holder = min(gross, escrow − mining_fee)` (fee default 5_000 sats)
4. **Spend on-chain** dall’escrow verso wallet holder e investitore (`L1::SettlementSpendService`)
5. Sync saldi riserva; brucia i token

### Esempio numerico — 1000 €, peg 50k, 1 mese @ 1%, spot 50k

```
Escrow totale:           4_000_000 sats  (Alice 1× + Bob 1×)
Liability holder:        1_010,00 €      (interesse 1%)
Gross holder @ 50k:      2_020_000 sats
Distributable:           3_995_000 sats  (escrow − 5_000 fee)
```

Con **transfer parziale** il payout holder segue le quote correnti — vedi `spec/scenarios/payoff_spec_section11_spec.rb` e `spec/integration/demo_end_to_end_flow_spec.rb`.

### 6. Margin call e top-up (opzionale)

1. Admin abbassa il cambio BTC/€ con deal attivo
2. Se LTV ≥ 70%, Bob vede **margin call** in dashboard
3. Bob → dettaglio ricarica → **Versa collateral aggiuntivo**
4. Se LTV ≥ 90%, liquidazione automatica al prossimo aggiornamento cambio

## Test

```bash
bundle exec rspec          # 83 esempi (unit + integration)
./bin/demo-spec            # flusso demo end-to-end su regtest
```

Per suite pulite senza dati seed che alterano i conteggi:

```bash
bin/rails db:schema:load RAILS_ENV=test
bundle exec rspec
```

`bin/demo-spec` richiede bitcoind (`./bin/regtest up`). Eseguilo dopo modifiche a payoff, settlement L1 o saldi dashboard.

## Architettura

- **Ibrido:** token e stato deal in PostgreSQL/SQLite; **BTC riserva ed escrow on-chain** (regtest)
- **Un budget = un deal** — niente epoch/pool globale
- **Servizi principali**
  - `Budgets::CreateService`, `Budgets::ActivateService`, `Budgets::ReserveRequirement`
  - `Budgets::InvestorCollateralTopUpService`, `Budgets::AutoLiquidationService`, `Budgets::AutoSettleService`
  - `Tokens::WalletTransferService`
  - `Payoffs::FloorEurCalculator`, `Settlements::ExecuteService`
- **Gap verso M2+:** settlement maturity come PSBT async lato wallet, Path B CLTV in produzione, RGB — vedi [`docs/rgb-design/`](docs/rgb-design/)

## Stato roadmap (branch `deal-per-budget`)

| Fase | Stato |
|------|--------|
| **M0** | Fatto — payoff FloorEUR, LTV, spec §11 |
| **M1** | ~95% — regtest multisig, funding §3.2, settlement on-chain, recovery package, `bin/demo-spec` |
| **M6** | Fatto — budget-as-deal, settlement per budget, L1 wiring |
| **M2+** | Bot facilitatore, margin annex on-chain, RGB (M3) |

## L1 — multisig regtest

Modulo `lib/l1/` per escrow **2-of-3 P2WSH** su Bitcoin Core regtest (JSON-RPC).

| Componente | Ruolo |
|------------|--------|
| `L1::UserWallet` | `createwallet` / `loadwallet` per utente; `spendable_sats` |
| `L1::ExchangeWallet` | Wallet esterno: mining regtest + transfer verso wallet utente |
| `L1::DepositReserveService` | Transfer Wallet esterno + sync + **+6 blocchi** catena simulata |
| `L1::SyncReserveBalanceService` | Allinea `BtcAccount#balance_sats` al saldo spendibile on-chain |
| `L1::WalletInventoryService` | Riepilogo admin wallet caricati + equivalente € |
| `L1::RegtestResetService` | Ricrea bitcoind al reset demo (`./bin/regtest reset`) |
| `L1::FundingPsbtService` | §3.2 PSBT: peg + investor → escrow 2-of-3 |
| `L1::ProvisionEscrowService` | Chiamato da `ActivateService` dopo l’attivazione |
| `L1::SettlementSpendService` | Spend cooperativo escrow → holder/investor; sync saldi |
| `L1::SettlementPsbtTemplateService` | Template maturity nel recovery package |
| `L1::RecoveryPackage` + `RecordEscrowService` | Export JSON §6 |
| `GET /budgets/:id/recovery_package` | Download JSON (richiedente, investitore, admin) |

Campi DB su `Budget`: `peg_party_pubkey`, `investor_pubkey`, `bot_pubkey`, `escrow_txid`, `escrow_vout`, `refund_delay_blocks` (default 1008), `recovery_package`.

## Console walkthrough

Richiede `./bin/regtest up` e depositi on-chain:

```ruby
admin = User.find_by!(email: "admin@example.com")
alice = User.find_by!(email: "alice@example.com")
bob = User.find_by!(email: "bob@example.com")
claude = User.find_by!(email: "claude@example.com")

L1::DepositReserveService.call(user: alice, amount_sats: 10_000_000)
L1::DepositReserveService.call(user: bob, amount_sats: 10_000_000)
MarketRate.current.update!(btc_eur_per_btc: 50_000, set_by: admin)

budget = Budgets::CreateService.call(
  borrower: alice,
  amount_eur_cents: 100_000,
  period_start: Date.current,
  period_end: Date.current + 1.month
)
Budgets::ActivateService.call(budget: budget, investor: bob)

Tokens::WalletTransferService.call(from_user: alice, to_user: claude, amount_cents: 30_000)
ChainState.update_block_height!(budget.maturity_block_height, auto_settle: false)

result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)
result.payouts.each { |p| puts "#{p.user.name}: #{p.btc_sats} sats" }
puts "Investitore: #{result.investor_btc_sats} sats"
```
