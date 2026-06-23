# FloorEUR PoC (Rails)

Proof-of-concept Rails che simula **deal P2P bilaterali** (un `Budget` = un deal): token EUR nominale spendibili, collateral BTC in escrow simulato, settlement **FloorEUR** a scadenza. Nessuna blockchain reale — solo ledger in database.

Specifiche di design: [`docs/rgb-design/`](docs/rgb-design/) (`PAYOFF-SPEC`, `P2P-OPTIONS`, `MULTISIG-SPEC`, `MARGIN-SPEC`).

## Setup

```bash
cd ~/dev/eur-token-poc
bundle install
bin/rails db:setup
bin/dev
```

`bin/dev` avvia **bitcoind regtest** (`./bin/regtest up`) e **Rails** con `L1_ENABLED=1`.  
Senza L1: `bin/rails server` come prima.

Apri http://localhost:3000 e accedi con:

| Utente | Email | Password | Ruolo |
|--------|-------|----------|-------|
| Admin | admin@example.com | password | Cambio BTC/€, altezza blocco, settlement |
| Alice | alice@example.com | password | Richiedente (borrower) |
| Bob | bob@example.com | password | Investitore |
| Claude | claude@example.com | password | Destinatario token |
| David | david@example.com | password | — |

In development puoi usare il dropdown **Switch** nella navbar per cambiare utente rapidamente.

## Modello (per deal)

Ogni **ricarica** (`Budget`) è un deal autonomo:

| Concetto | Implementazione PoC |
|----------|---------------------|
| Escrow | `CollateralLock#amount_sats` (borrower + investitore, + top-up) |
| Strike | `Budget#peg_eur_per_btc` — fissato **all’attivazione** dal `MarketRate` corrente |
| Maturity | `Budget#maturity_block_height` (da `genesis_block_height` + durata in blocchi) |
| Token | `TokenAccount` — 1 cent = 0,01 € nominale sul deal |
| Settlement | `Payoffs::FloorEurCalculator` → `Settlements::ExecuteService` |
| Transfer | `Tokens::WalletTransferService` — spend da più deal se serve |
| Oracle / catena | `MarketRate` + `ChainState` (admin); auto-settle al maturity block |

**Collateral in apertura:** richiedente **1×** + investitore **1×** l’importo nominale → escrow **2×**, LTV iniziale **50%**.

**Monitoraggio LTV** (demo Rails, non annex on-chain): margin call investitore ≥ **70%**, liquidazione automatica ≥ **90%** (`Budgets::AutoLiquidationService`).

## Scenario demo

### Stato iniziale (`db:setup` / seed)

Il seed esegue `DemoData::ResetService` e crea una ricarica **pending** da Alice:

- **Alice:** 0,1 BTC (10_000_000 sats) sul conto di riserva — ~2M sats già bloccati come collateral richiedente (1000 € @ 50k)
- **Bob:** 0,2 BTC (20_000_000 sats)
- **Cambio demo:** **50_000 €/BTC** (`MarketRate`)
- **Altezza blocco:** stimata corrente (`ChainState`)

### 1. Admin — cambio e catena

1. Login come **Admin**
2. Dashboard → pannello admin
3. Verifica **Cambio BTC/€** (default 50_000) e **Altezza blocco**
4. Opzionale: **Reset demo DB** per ripartire da zero

L’admin **non** imposta un peg per singolo budget: il peg del deal è il cambio corrente al momento in cui l’investitore attiva.

### 2. Attivazione deal (Bob)

1. Switch **Bob**
2. Dashboard → **Ricariche in attesa di investitore** → **Dettagli**
3. **Accetta rischio e attiva budget**

Il sistema:

- Blocca ~2_000_000 sats da Bob (1000 € @ 50k)
- Fissa `peg_eur_per_btc = 50_000` sul budget
- Crea `CollateralLock` ≈ **4_000_000 sats** (2× nominale)
- Mint **1000 €** nominali ad Alice sul conto corrente

### 3. Spesa token (Alice → Claude → David)

1. Switch **Alice** → **Invia Denaro**
2. Invia 300 € a Claude (30000 cent)
3. Switch **Claude** → invia 100 € a David

Saldi attesi sul conto corrente: Alice 700 €, Claude 200 €, David 100 €.

I transfer usano `WalletTransferService` e possono attingere a più deal se l’utente ne ha più di uno attivo.

### 4. Settlement a scadenza

Quando `ChainState.block_height >= maturity_block_height`:

- **Automatico:** aggiornando l’altezza blocco (admin) scatta `Budgets::AutoSettleService`
- **Manuale:** Admin → budget attivo → **Settlement** → prezzo BTC a scadenza → **Esegui settlement**

Il settlement **FloorEUR**:

1. Calcola `liability_eur = notional × (1 + rate_bps_monthly × mesi)`
2. Converte in sats: `gross = liability_eur / spot`
3. Cap: `total_holder = min(gross, escrow − mining_fee)` (fee default 5_000 sats)
4. Riproparte pro-rata tra i detentori di token; **residuo all’investitore**
5. Brucia i token e accredita BTC sui conti di riserva

### Esempio numerico — 1000 €, peg 50k, 0 mesi interi, spot 50k

```
Escrow totale:           4_000_000 sats  (Alice 1× + Bob 1×)
Liability holder:        1_000,00 €
Gross holder @ 50k:      2_000_000 sats
Distributable:           3_995_000 sats  (escrow − 5_000 fee)
Payout holder (100%):    2_000_000 sats
Investitore (residuo):   1_995_000 sats
```

Se lo **spot crolla a 25k** (stessa liability, stesso escrow):

```
Gross holder:            4_000_000 sats  (1000 € / 25k)
Cap escrow:              3_995_000 sats  → insolvenza parziale
Investitore (residuo):   ~0 sats
```

Con **transfer parziale** (es. Alice 60%, Claude 40%) il payout holder segue le quote correnti — vedi `spec/scenarios/payoff_spec_section11_spec.rb`.

### 5. Margin call e top-up (opzionale)

1. Admin abbassa il cambio BTC/€ (es. 35_000) con deal attivo
2. Se LTV ≥ 70%, Bob vede **margin call** in dashboard
3. Bob → dettaglio ricarica → **Versa collateral aggiuntivo**
4. Se LTV ≥ 90%, liquidazione automatica al prossimo aggiornamento cambio

## Test

```bash
bundle exec rspec
```

Per suite pulite senza dati seed che alterano i conteggi:

```bash
bin/rails db:schema:load RAILS_ENV=test
bundle exec rspec
```

## Architettura

- **Ledger simulato** — saldi BTC e token in PostgreSQL/SQLite, nessun UTXO L1
- **Un budget = un deal** — niente epoch/pool globale
- **Servizi principali**
  - `Budgets::CreateService`, `Budgets::ActivateService`
  - `Budgets::InvestorCollateralTopUpService`, `Budgets::AutoLiquidationService`, `Budgets::AutoSettleService`
  - `Tokens::WalletTransferService`
  - `Payoffs::FloorEurCalculator`, `Settlements::ExecuteService`
- **Gap verso M1+:** multisig 2-of-3, PSBT, recovery package, RGB — vedi checklist in `docs/rgb-design/`

## M1 — multisig regtest (L1)

Modulo `lib/l1/` per escrow **2-of-3 P2WSH** su Bitcoin Core regtest (JSON-RPC, nessuna gem nativa).

```bash
bin/dev   # regtest + Rails L1
```

Ogni utente ha un **wallet regtest personale** (`user_<id>`). I depositi arrivano dal **Wallet esterno** (`l1_external_wallet`, 1 BTC demo).  
**«Deposita su conto riserva»** apre un form (default Alice 0,1 · Bob 0,2 BTC) e avanza la catena simulata di **6 blocchi**.

| Componente | Ruolo |
|------------|--------|
| `L1::UserWallet` | `createwallet` / `loadwallet` per utente |
| `L1::ExchangeWallet` | Wallet esterno regtest (`l1_external_wallet`, 1 BTC) → transfer utente |
| `L1::DepositReserveService` | transfer Wallet esterno + accredito DB + **+6 blocchi** catena simulata |
| `L1::SyncReserveBalanceService` | `getbalance` → `BtcAccount#balance_sats` |
| `POST /reserve_deposit` | bottone dashboard |
| `L1::ProvisionEscrowService` | chiamato da `ActivateService` se `L1_ENABLED=1` |
| `L1::RegtestHarness` | funding §3.3, settlement, refund timelock, bot-only probe |
| `L1::RecoveryPackage` | export JSON §6 (deal params, outpoint, locktime) |
| `L1::RecordEscrowService` | persiste pubkeys + `recovery_package` su `Budget` |
| `GET /budgets/:id/recovery_package` | download JSON (richiedente, investitore, admin) |

Campi DB su `Budget`: `peg_party_pubkey`, `investor_pubkey`, `bot_pubkey`, `escrow_txid`, `escrow_vout`, `refund_delay_blocks` (default 1008).

Senza `L1_ENABLED` il demo resta solo ledger Rails (comportamento predefinito).

## Console walkthrough

```ruby
admin = User.find_by!(email: "admin@example.com")
alice = User.find_by!(email: "alice@example.com")
bob = User.find_by!(email: "bob@example.com")
claude = User.find_by!(email: "claude@example.com")

MarketRate.current.update!(btc_eur_per_btc: 50_000, set_by: admin)

budget = Budget.pending.first
Budgets::ActivateService.call(budget: budget, investor: bob)

Tokens::WalletTransferService.call(from_user: alice, to_user: claude, amount_cents: 30_000)

result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)
result.payouts.each { |p| puts "#{p.user.name}: #{p.btc_sats} sats (liability #{p.liability_eur_cents} cent)" }
puts "Investitore: #{result.investor_btc_sats} sats"
puts "Insolvent: #{result.payoff.insolvent}"
```
