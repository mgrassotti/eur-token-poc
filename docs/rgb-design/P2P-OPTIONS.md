# Design P2P: contratti BTC con strike, maturity e transfer RGB

Documento di design on-chain per il simulatore Rails **`eur-token-poc`** (`README.md`).
Stack: Bitcoin nativo, RGB, bot facilitatore; Lightning opzionale per transfer RGB istantanei.

---

## 1) Obiettivo prodotto

Offrire **esposizione sintetica** (tipo “€ stabile” o BTC con **floor** a prezzo iniziale) tramite
**contratti bilaterali** su BTC.

| Attore | Ruolo |
|--------|--------|
| **Alice** (receiver) | Deposita BTC in escrow; a maturity ha payoff definito vs strike `K` |
| **Bob** (hedger / provider) | Collaterale ≥ 2× Alice; lato opposto (short volatility / short put) |
| **Claude / David** | Acquisitori del **diritto contrattuale** (cedenza) |
| **Bot** (facilitatore) | Match, PSBT, publish oracle median; una chiave su multisig per deal |

Modello di riferimento: Hodl Hodl + DLC/oracle a maturity + assignment RGB transferibile.

---

## 2) Principi di design

1. **Bitcoin L1** per apertura deal, escrow e settlement a maturity; **Lightning opzionale** per `TransferPosition` istantaneo a fee marginali zero.
2. **RGB** per diritti transferibili e validazione client-side (app mobile).
3. **Bot** come facilitatore; recovery **senza bot** obbligatoria (Alice + Bob, timelock).
4. **Fiat** via exchange dell’utente o P2P off-chain; il protocollo regola solo la gamba BTC.
5. **Un deal = un escrow multisig**; collateral Bob **≥ 2×** collateral Alice.

---

## 3) Contratto tipo: `FloorBTC` (un solo template MVP)

### 3.1 Parametri fissati al genesis del deal

| Campo | Tipo | Esempio |
|-------|------|---------|
| `escrow_utxo` | outpoint | Unico UTXO multisig 2-of-3 (peg + hedge) — [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) §3 |
| `peg_collateral_sats` | u64 | 1_000_000 (0.01 BTC) — parte peg |
| `hedge_collateral_sats` | u64 | 2_000_000 (0.02 BTC) — hedger |
| `notional_sats` | u64 | Base payoff lato Alice (es. 1_000_000) |
| `strike_eur_per_btc` | u64 | 50_000 (€/BTC al deal, fixed-point) |
| `maturity_height` | u32 | blocco Bitcoin di settlement |
| `premium_sats` | u64 | 0 o premio pagato Alice→Bob all’apertura |
| `oracle_policy` | struct | mediana di N feed; pubkey firmatari attestation |
| `multisig_policy` | 2-of-3 | peg_party, investor, bot — vedi [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) |

**Vincolo apertura deal:**

```text
hedge_collateral_sats ≥ 2 × peg_collateral_sats
```

Esempio semplificato: Alice e Bob versano in momenti separati (PSBT asincrona) → **un** escrow 2-of-3 da **3 M sats** (1M + 2M).

### 3.2 Payoff a maturity (concettuale)

Alla height `maturity_height`, oracle pubblica `spot_eur_per_btc` (mediana feed).

**Interpretazione “protezione al ribasso” (Alice long floor):**

```text
valore_nominale_eur = notional_sats × strike / 1e8   (in unità € fixed-point)

Se spot < strike:
  holder-side ha diritto a compensation in sats da Bob
  (come se vendesse notional a strike invece che a spot)

Se spot ≥ strike:
  holder-side mantiene il collateral; eventuale premio già pagato a Bob
```

Formula sats (semplificata, da fissare in implementazione):

```text
payout_holders_sats = max(0, notional × (1/spot - 1/strike))   // EUR→sats
payout_bob_sats     = collateral totale - payout_holders - fee
```

Arrotondamenti e cap al collateral **devono** essere deterministici nello schema RGB / DLC.

Variante **“rivendita a K”**: a maturity il holder può **forzare** scambio a strike (put europea);
Bob consegna la differenza in sats rispetto al valore di mercato.

---

## 4) Custodia: multisig per deal

Specifica completa: [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md).

```text
                    ┌─────────────────────────┐
                    │  UTXO escrow (2-of-3)   │
                    │  Alice + Bob + Bot      │
                    │  1M + 2M = 3M sats      │
                    └─────────────────────────┘
                              │
         maturity + oracle    │    cooperative close anytime
         → PSBT payout        │    (Alice + Bob sufficienti)
```

| Evento | Chi firma |
|--------|-----------|
| Apertura deal | Alice + Bob (+ Bot per template) |
| TransferPosition via LN (opz.) | Mittente ↔ destinatario sul canale; consignment RGB |
| Settlement maturity | 2-of-3 con attestation oracle valida |
| Bot offline | **Alice + Bob** cooperano |
| Bob non coopera | Timelock refund / force close path (pre-firmato) |

Il bot da solo non può spendere l’escrow (serve 2-of-3).

---

## 5) Recovery senza bot (obbligatorio)

Prevedere **almeno due** path indipendenti dal bot:

### Path A — Cooperative (2-of-3)

Alice e Bob firmano release secondo regole pre-accettate (o mutual cancel).

### Path B — Timelock refund

Script `OP_CHECKLOCKTIMEVERIFY` a `maturity_height + DELTA`:

- Se non settlement entro Δ blocchi → refund **pro-rata** su collateral Alice e Bob
- Transazioni **pre-firmate** o half-signed conservate localmente dai wallet

### Path C — Lightning force close (transfer RGB)

Se il transfer usa un canale LN: chiusura unilaterale del canale; consignment RGB e diritti restano validabili da history locale + anchor L1.

### Path D — ERP / dispute key (opzionale)

Terza chiave **nota** (non il bot prod) solo per deadlock prolungato — usare con parsimonia.

**Checklist wallet:** all’apertura deal, wallet **deve** esportare:

- consignment RGB
- PSBT refund timelocked
- parametri deal (K, T, outpoint)

---

## 6) Ruolo del bot facilitatore

| Funzione | Dettaglio |
|----------|-----------|
| **Matching** | Alice cerca hedger; Bob cerca flow |
| **Template PSBT** | Costruisce apertura escrow + maturity spend |
| **Oracle publish** | Mediana 5 feed; firma attestation |
| **Notifiche** | Maturity imminente, margin call (se previsto) |
| **Exchange assist** | Opzionale: API **con chiavi utente** per fiat leg |

| Boundary | Dettaglio |
|----------|-----------|
| Chiavi | Una chiave per deal nel multisig, mai unica firma su tutti i fondi |
| Custodia | Non detiene saldi aggregati; ogni deal ha il proprio UTXO |
| Token | Non emette pass-through EUR; regola solo diritti sul contratto BTC |

---

## 7) Transfer Alice → Claude (RGB)

**Con RGB — assignment `FloorBTCPosition`:**

Owned state per assignment:

```text
deal_id, holder_pubkey, notional_share, strike, maturity_height,
escrow_outpoint
```

### 7.1 Transfer parziale (frazionamento)

Il transfer muove il **diritto economico** (`notional_share`), **non** sposta BTC dall’escrow.
L’UTXO resta unico fino a maturity o refund.

```text
Escrow Bitcoin (multisig)          Assignment RGB
─────────────────────────          ─────────────────
[ 3M sats: Alice 1M + Bob 2M ]     Alice: notional_share = 1_000_000 (100%)
   ↑ invariato al transfer              │
                                        │ TransferPosition Δ = 400_000
                                        ▼
                                   Alice:  600_000 (60%)
                                   Claude: 400_000 (40%)
```

Transizione **`TransferPosition`**:

```text
Input:  assignment Alice  (notional = N)
Output: assignment Alice  (notional = N − Δ)
        assignment Claude (notional = Δ)
```

Regole di validazione:

- `0 < Δ ≤ N`
- stesso `deal_id`, `strike`, `maturity_height`, `escrow_outpoint`
- `sum(notional_share di tutti gli holder) ≤ notional_sats` del deal
- conservazione: `N = (N − Δ) + Δ`
- Bob **non** firma (controparte hedge invariata)

Transfer multipli ammessi (Alice → Claude, Alice → David, ecc.).

### 7.2 Settlement a maturity (pro-rata)

Se il payoff totale lato holder è `P` sats:

```text
payout_holder_i = P × notional_share_i / notional_sats
```

Esempio (deal `notional_sats = 1_000_000`, `P = 100_000`):

| Holder | Quota | Payout |
|--------|-------|--------|
| Alice | 600_000 | 60_000 sats |
| Claude | 400_000 | 40_000 sats |

Bob riceve il residuo del collateral escrow secondo le regole del deal.

### 7.3 Refund timelock (pro-rata)

In caso di refund senza settlement, ripartizione su **collateral** (non su notional):

```text
refund_alice = alice_collateral_sats × quota_ownership   // se applicabile
refund_bob   = bob_collateral_sats   × quota_ownership   // per path cooperativo
```

Gli holder secondari (Claude) partecipano al **payout holder-side** a maturity e al refund
del **diritto** secondo `notional_share` corrente, validato dallo schema RGB.

### 7.4 Firme

| Party | Transfer parziale |
|-------|-------------------|
| Alice (cedente) | Sì |
| Claude (cessionario) | Accetta consignment; wallet valida client-side |
| Bob | No |
| Bot | No |

App mobile: rgb-lib valida consignment + schema prima di accettare cessione.

**Transport layer (opzionale):** lo stesso `TransferPosition` può essere consegnato **on-chain** (§8.1)
o via **Lightning** (§8.2) per settlement istantaneo tra peer.

---

## 8) Lightning (opzionale): transfer RGB istante

Lightning **non** modifica escrow del deal né il payoff a maturity su L1.
Serve come **rail P2P opzionale** per consegnare `TransferPosition` (e altri asset RGB compatibili)
tra wallet con canale aperto.

### 8.1 Due modalità di `TransferPosition`

| | **L1 (default)** | **Lightning (opzionale)** |
|---|------------------|---------------------------|
| Settlement | Conferme on-chain | Istantaneo tra peer nel canale |
| Fee marginali | Mining fee per anchor tx | ~zero per hop diretto |
| Latenza | Minuti / blocchi | Sub-secondo |
| Escrow deal | Invariato | Invariato |
| Validazione | Client-side RGB + anchor | Client-side RGB + consignment su LN |

```text
Deal escrow (L1, fino a maturity)
  Alice 1M + Bob 2M  ─────────────────────────►  payoff a T

TransferPosition Alice → Claude (diritto, non BTC escrow)
  │
  ├─ L1:  STF RGB + tx anchor Bitcoin  (fee miner, wait blocks)
  │
  └─ LN:  consignment RGB over Lightning  (instant, ~zero fee)
          stesso schema, stesso notional_share splittato
```

### 8.2 Flusso LN (Alice → Claude)

1. Alice e Claude hanno un **canale LN** (o route verso Claude via LSP).
2. Alice esegue `TransferPosition` in locale: split assignment, valida schema.
3. Propaga **consignment RGB** a Claude over LN (invoice / offer asset-aware).
4. Claude valida client-side; accetta → **settlement immediato** del diritto.
5. L’**UTXO escrow** del deal resta untouched; Bob resta controparte hedge.

Requisiti implementativi (fase M5): wallet con rgb-lib + LN (LDK/LND/CLN), supporto
consegna consignment off-chain, recovery da backup consignment se canale chiuso.

### 8.3 Quando conviene LN

- Transfer frequenti o piccoli (es. Claude riceve 400k notional su 1M).
- UX mobile: conferma immediata senza attendere block.
- Riduzione costi rispetto a ripetuti anchor L1.

Apertura deal, maturity e refund timelock restano su **L1**.

---

## 9) Exchange esterni (fiat)

```text
[Exchange utente]  ←── EUR ──→  Alice (off-chain)
       │
       └── BTC ──→  wallet Alice ──→  escrow multisig (on-chain)
```

- Bot può orchestrare ordini **solo** con OAuth/API dell’utente.
- KYC e compliance restano responsabilità utente / exchange.

---

## 10) Mapping `eur-token-poc` → modello P2P

Il demo Rails **`eur-token-poc`** simula la stessa economia in DB centralizzato.
On-chain ogni riga “epoch / pool globale” diventa **N deal** con escrow dedicato.

| `eur-token-poc` (Rails) | Servizio / modello | `FloorBTC` P2P | Gap principale |
|-------------------------|-------------------|----------------|----------------|
| Apertura posizione Alice | `Budgets::CreateService` + `ActivateService` | Genesis deal: Alice collateral + mint `notional` | Budget pending → **escrow multisig** per deal |
| Strike al mint | `Budget#peg_eur_per_btc` | `strike_eur_per_btc` | Stesso concetto |
| Collateral 2× | `Budget::INVESTOR_COLLATERAL_MULTIPLIER` (2×) | `hedge_collateral ≥ 2 × peg_collateral` | Pool investitori **aggregata** → hedger dedicato per deal |
| Investor hedger | `InvestorDeposits::CreateService` | `hedge_collateral_sats` in escrow | N investitori pro-rata → **un** controparte per deal |
| Token € fungibile | `TokenAccount#balance_cents` post-activate | `notional_share` RGB (cent = unità nominale) | DB account → assignment |
| Transfer | `Tokens::TransferService` | `TransferPosition` (anche parziale); L1 o LN | Validazione server → client-side RGB |
| Maturity | `Epoch#end_block` (210_000 blocchi) | `maturity_height` per deal | Maturity **globale epoch** → **per deal** |
| Settlement | `Settlements::ExecuteService` | Payoff a T con oracle (`spot` vs `K`) | Settlement **tutti gli holder epoch** → singolo escrow |
| Ritiro anticipato | `Tokens::RedeemService` (cambio corrente) | Opzionale: uscita cooperativa pre-T | Non nel MVP P2P core |
| Catena / oracle | `ChainState` + `MarketRate` (admin) | `maturity_height` + attestation mediana | Admin DB → oracle firmato |
| Liquidazione LTV 90% | `Epochs::AutoLiquidationService` | Liquidazione anticipata margin — vedi [`MARGIN-SPEC.md`](MARGIN-SPEC.md) §6 | Extra demo PoC; per-deal in M2+ |
| Yield investitori | `Epochs::InvestorYieldService` (LTV &lt; 30%) | `premium_sats` upfront a Bob | Meccanismo diverso |
| Bot facilitatore | Dashboard admin + auto-activate | Match + PSBT + oracle; chiave 1-of-3 | Admin DB → facilitatore non custode |

### 10.1 Attori demo → P2P

| Utente demo | Ruolo Rails tipico | Ruolo P2P |
|-------------|-------------------|-----------|
| Alice | Borrower (`Budget`) | Receiver / holder `FloorBTCPosition` |
| Bob | Investitore pool (`InvestorDeposit`) | Hedger (collateral 2×) |
| Claude / David | Destinatario `TokenTransfer` | Cessionario `TransferPosition` |
| Admin | `ChainState`, `MarketRate`, settlement epoch | Opzionale: oracle publish; non custode fondi |

### 10.2 Evoluzione consigliata del demo Rails

Per avvicinare `eur-token-poc` al target P2P **prima** del codice RGB:

1. **Budget = deal** con collateral investitori **allocato** (non solo capienza pool epoch).
2. **Settlement per budget** a scadenza locale, oltre o invece del settlement epoch globale.
3. Transfer token invariato come proxy di `TransferPosition` (già parziale).
4. Test numerici: Alice 1M sats equivalenti, Bob 2M, `peg` = strike, `end_block` budget = maturity.

---

## 11) Roadmap implementazione

```text
M0  Spec payoff + multisig 2-of-3 + timelock refund + vincolo 2× collateral
M1  Prototipo L1: regtest, 1 deal (Alice 1M / Bob 2M), settlement oracle mock
M2  Bot: match + PSBT template + recovery package export
M3  RGB FloorEURPosition + TransferPosition (split) + rgb-lib mobile
M4  DLC/adaptor (opz.) — settlement L1 più ricco del multisig cooperativo
M5  TransferPosition over Lightning (instant, ~zero fee marginale)
M6  (opz.) Refactor eur-token-poc: budget-as-deal + settlement per budget
```

**Ordine fase 0 #5:** dopo M1/M2 si implementa **RGB prima** (diritti transferibili); **DLC** resta enhancement opzionale dello settlement, non prerequisito.

---

## 12) Rischi residui

| Rischio | Mitigazione |
|---------|-------------|
| Bob default a maturity | Collateral Bob ≥ 2× Alice |
| Oracle manipolazione | Mediana 5 feed; outlier drop; attestazione firmata |
| Bot compromesso | Bot solo 1-of-3 |
| Bob rifiuta coop | Timelock refund pro-rata |
| Transfer senza RGB | Novazione con firma Bob |
| BIP110 / policy relay | Script conservativi; testnet; monitoraggio |
| Fiat leg | Gamba off-chain utente |

---

## 13) Domande aperte (prima del codice)

1. ~~Payoff esatto: put europea pura vs floor con cap?~~ → [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md): **FloorEUR** (peg € + interesse sul notional)
2. ~~`2-of-3` vs `2-of-2` + arbiter separato?~~ → [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md): **`2-of-3`** peg_party + investor + bot
3. ~~Margin intraday obbligatorio o solo settlement a T?~~ → [`MARGIN-SPEC.md`](MARGIN-SPEC.md): **specificato** (top-up annex); **disabilitato** M0–M1, opzionale M2+
4. ~~Fee protocollo: premio % a Bob o flat sats?~~ → **zero fee protocollo** MVP; `premium_sats` flat default 0; mining fee — [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) §6bis
5. ~~RGB prima o DLC L1 prima nel MVP?~~ → **RGB prima** (M3); DLC opzionale dopo (M4); settlement FloorEUR MVP su multisig L1 (M1)
6. ~~`notional_sats` = sempre `peg_collateral_sats` o parametro separato?~~ → [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md): MVP **= `peg_collateral_sats`**
7. ~~Allineare payoff settlement epoch vs formula put §3.2?~~ → [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md): **`liability_eur / spot`**

---

## 14) Riferimenti utili

- [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md) — peg € + interesse sul notional (FloorEUR), formula settlement
- [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) — escrow 2-of-3, matrice firme, recovery, timelock
- [`MARGIN-SPEC.md`](MARGIN-SPEC.md) — margin intraday, top-up annex, liquidazione anticipata
- [`eur-token-poc` README](../../README.md) — simulatore Rails (epoch, budget, pool 2×, settlement)
- [Hodl Hodl](https://hodlhodl.com/) — multisig per contratto
- [rgb-lib](https://github.com/RGB-Tools/rgb-lib) — wallet mobile + validazione

---

## Sintesi

**Contratti bilaterali** su BTC in escrow multisig (Alice 1M + Bob 2M, vincolo 2×),
payoff a maturity via **oracle mediano**, **cedenza frazionabile** del diritto via **RGB**
(L1 o **Lightning** opzionale per transfer istante a fee marginali zero),
bot facilitatore con recovery **Alice+Bob** e **timelock**.

Il demo **`eur-token-poc`** fornisce i casi numerici e il vocabolario (budget, peg, epoch, transfer, settlement);
l’implementazione on-chain sostituisce pool/epoch globali con **deal indipendenti**.
