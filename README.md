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

`bin/dev` avvia **regtest + stack RGB** (`./bin/regtest up`: bitcoind, electrs, rgb-proxy, sidecar) e **Rails**. Il PoC **richiede** regtest e sidecar RGB per depositi, escrow, transfer token e settlement.

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
| Token | `TokenAccount` — proiezione DB; saldi spendibili da `Rgb::BalanceService` |
| Settlement | `Payoffs::FloorEurCalculator` → `Settlements::ExecuteService` → `L1::SettlementPsbtService` |
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
4. **Redemption RGB:** ogni holder restituisce il saldo EURT al wallet **issuer/treasury** (`Rgb::RedeemService`) — rgb-lib 0.3 non ha un burn nativo, quindi la redemption all'issuer ritira i token dalla circolazione. La proiezione DB (`TokenAccount`/`RgbAssignment`) viene azzerata come cache (`Rgb::ProjectionService.apply_redeem!`)
5. **PSBT maturity async:** `L1::SettlementPsbtService` costruisce la PSBT (`L1::SettlementTxBuilder`), persiste la versione **unsigned** nel recovery package, poi firma in sequenza bot + investitore e broadcast
6. Sync saldi riserva

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
bundle exec rspec          # unit + integration (RGB lib se sidecar attivo)
./bin/demo-spec            # flusso demo end-to-end su regtest
./bin/system-spec          # stesso flusso via browser (Capybara + sidecar reale)
```

Per suite pulite senza dati seed che alterano i conteggi:

```bash
bin/rails db:schema:load RAILS_ENV=test
bundle exec rspec
```

`bin/demo-spec` richiede regtest + sidecar RGB (`./bin/regtest up`). Eseguilo dopo modifiche a payoff, settlement L1, RGB o saldi dashboard.

`bin/system-spec` replica lo stesso flusso nell'UI (login, switch utente dev, depositi, attivazione deal, transfer, settlement admin). Utile per debuggare errori sidecar su **Accetta rischio e attiva** con screenshot in `tmp/capybara/` al fallimento. Esempio rapido: `./bin/system-spec --example "attiva un deal"`.

### RGB — RGB Lightning Node (RLN), un nodo per utente

`./bin/regtest up` avvia **bitcoind**, **electrs**, **rgb-proxy** e **N nodi RGB Lightning** (uno per utente demo + issuer), costruiti dal submodule `vendor/rgb-lightning-node` (build Rust al primo avvio). Il legacy **rgb-sidecar** resta nel compose finché le spec `:rgb_lib` non sono migrate su RLN.

| Nodo | Porta API host | Utente |
|------|----------------|--------|
| `rln-alice` | `3001` | alice@example.com |
| `rln-bob` | `3002` | bob@example.com |
| `rln-claude` | `3003` | claude@example.com |
| `rln-david` | `3004` | david@example.com |
| `rln-issuer` | `3005` | issuer/treasury (redemption) |

```bash
./bin/regtest up        # build immagine RLN + avvio stack, attende i nodi su 3001-3005
```

Variabili principali (`lib/rgb/config.rb`):

| Variabile | Default | Ruolo |
|-----------|---------|--------|
| `RLN_PASSWORD` | `regtestpassword` | password init/unlock nodi |
| `RLN_ISSUER_URL` | `http://127.0.0.1:3005` | nodo issuer/treasury |
| `RLN_TOKEN` | _(vuoto)_ | Biscuit bearer opzionale (nodi con `--disable-authentication`) |

Il mapping utente→nodo (`BtcAccount#rln_node_url`) è impostato da `DemoData::ResetService`. `Rgb::IssueService` / `Rgb::TransferService` / `Rgb::RedeemService` operano sul nodo dell'utente (`Rgb::Config.ensure_node!`); la dashboard mostra la card **RGB (RLN)** con i saldi NIA letti da `/assetbalance`.

Per un reset RGB pulito riavviare i container (`./bin/regtest reset`): i nodi RLN non espongono un "reset wallet", lo stato si azzera ricreando i container.

Legacy: `RGB_SIDECAR_URL` (`http://127.0.0.1:3030`) resta usato solo dalle spec `:rgb_lib` non ancora migrate.

**Nota Docker:** se `docker pull` / `docker compose build` restano bloccati senza output, il credential helper Desktop può essere in stallo. Workaround: `mkdir -p /tmp/docker-nocreds && echo '{"auths":{}}' > /tmp/docker-nocreds/config.json` poi `DOCKER_CONFIG=/tmp/docker-nocreds docker pull …`.

## Architettura

- **Ibrido:** token e stato deal in PostgreSQL/SQLite; **BTC riserva ed escrow on-chain** (regtest)
- **Un budget = un deal** — niente epoch/pool globale
- **Servizi principali**
  - `Budgets::CreateService`, `Budgets::ActivateService`, `Budgets::ReserveRequirement`
  - `Budgets::InvestorCollateralTopUpService`, `Budgets::AutoLiquidationService`, `Budgets::AutoSettleService`
  - `Tokens::WalletTransferService`
  - `Payoffs::FloorEurCalculator`, `Settlements::ExecuteService`
- **Gap verso M2+:** oracle firmato, Path B CLTV in produzione, margin annex on-chain — vedi [`docs/rgb-design/`](docs/rgb-design/)
- **RGB (M3):** rgb-lib via sidecar Docker (obbligatorio con `./bin/regtest up`)

## Stato roadmap (`main`)

| Fase | Stato |
|------|--------|
| **M0** | Fatto — payoff FloorEUR, LTV, spec §11 |
| **M1** | **Fatto** — regtest multisig 2-of-3, funding PSBT §3.2, settlement on-chain FloorEUR via `SettlementPsbtService`, recovery package con `psbt_maturity` unsigned, `bin/demo-spec`, 92 spec |
| **M6** | Fatto — budget-as-deal, settlement per budget, L1 wiring (merged in `main`) |
| **M3** | **In corso** — RGB20 NIA via rgb-lib sidecar (`./bin/regtest up`), issue su activate, transfer parziale, card dashboard |
| **M2+** | Bot facilitatore / oracle firmato, Path B CLTV in prodotto, margin annex on-chain |

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
| `L1::SettlementPsbtService` | Settlement maturity async: build PSBT → persist unsigned → firma bot+investor → broadcast |
| `L1::SettlementTxBuilder` | Costruzione tx/PSBT settlement (output holder + investor) |
| `L1::SettlementSpendService` | Wrapper compat sottile su `SettlementPsbtService`; sync saldi |
| `L1::SettlementPsbtTemplateService` | PSBT maturity unsigned + output nel recovery package (`psbt_maturity`) |
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
