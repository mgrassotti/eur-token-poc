# MULTISIG-SPEC: escrow 2-of-3 per deal (`FloorEUR`)

Specifica di custodia L1 per contratti bilaterali P2P descritti in [`P2P-OPTIONS.md`](P2P-OPTIONS.md), allineata al payoff in [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md).

**Decisione fase 0 #2:** ogni deal usa escrow **`2-of-3`** con chiavi `peg_party`, `investor` (hedger), `bot`.  
**Funding MVP (fase 0 #4):** peg_party e investor possono versare in **momenti separati**, ma il deal funded ha **un solo UTXO** multisig 2-of-3 — vedi §3.  
**Non** si adotta `2-of-2` + arbitro separato nel MVP.

**Nomi negli esempi:** *Alice* = `peg_party`, *Bob* = `investor`, *Bot* = facilitatore — personaggi fittizi del simulatore; nei parametri del contratto si usano solo i ruoli.

---

## 1) Scelta e alternative scartate

| Opzione | Pro | Contro | MVP |
|---------|-----|--------|-----|
| **`2-of-3` peg_party + investor + bot** | Recovery con **solo le due parti** se il bot è offline; bot facilita template PSBT e settlement; una chiave hot per deal, non su tutti i fondi | Terza chiave da gestire; bot compromesso = serve ancora 1 chiave utente | **Sì** |
| Due UTXO genesis (peg e hedge separati on-chain) | Funding tx indipendenti semplici | Due input a settlement; non è il modello scelto | No |
| `2-of-2` peg_party + investor | Minimo trust sul bot | Deadlock se una parte non coopera; serve **sempre** arbitro esterno o DLC | No |
| `2-of-2` + arbitro separato | Dispute path chiaro | Arbitro umano/servizio per ogni contestazione; latenza e costo; UX peggiore del bot-as-facilitator | No |

**Perché `2-of-3` per FloorEUR:** il bot è **facilitatore operativo** (match, PSBT, oracle), non custode unico. Le due controparti economiche (`peg_party`, `investor`) possono sempre cooperare (`peg_party + investor` = 2-of-3). Il bot accelera il path felice ma **non è necessario** per spendere l’escrow.

---

## 2) Parametri al genesis (estensione PAYOFF-SPEC §1)

| Campo | Tipo | Descrizione |
|-------|------|-------------|
| `multisig_policy` | enum | Fisso MVP: **`2-of-3`** |
| `peg_party_pubkey` | bytes | Chiave pubkey della parte peg (es. Alice) |
| `investor_pubkey` | bytes | Chiave pubkey dell’hedger (es. Bob) |
| `bot_pubkey` | bytes | Chiave pubkey del bot **per questo deal** (derivata HD: `m/.../deal_id`) |
| `escrow_utxo` | outpoint | **Unico** UTXO genesis del deal (peg + hedge aggregati) |
| `escrow_utxos` | outpoint[] | `[escrow_utxo]` + annex margin opzionali — [`MARGIN-SPEC.md`](MARGIN-SPEC.md) |
| `refund_delay_blocks` | u32 | `Δ` blocchi dopo `maturity_height` per Path B (default **1008** ≈ 7 giorni) |
| `estimated_settlement_fee_sats` | u64 | Stima conservativa fee settlement (default **5_000**) per sizing PAYOFF-SPEC §7 |

```text
multisig_policy     = 2-of-3
required_signatures = 2
signers             = { peg_party, investor, bot }
```

### Vincoli al genesis

```text
peg_party_pubkey, investor_pubkey, bot_pubkey distinte
escrow_total_sats = peg_collateral_sats + hedge_collateral_sats + top_ups_sats − premium_sats (se on-chain)
escrow_utxo.value = peg_collateral_sats + hedge_collateral_sats   (al funded; annex esclusi)
refund_delay_blocks > 0
deal funded ⇔ escrow_utxo confermato con importo pieno (peg + hedge)
```

---

## 3) Struttura UTXO e funding (MVP L1)

### 3.1 Obiettivo: un UTXO, depositi in momenti separati

| Cosa | Regola |
|------|--------|
| **Escrow funded** | **Un solo** UTXO `2-of-3` con `peg_collateral_sats + hedge_collateral_sats` |
| **Timing** | Peg_party e investor possono contribuire in **momenti diversi** |
| **Non** | Due UTXO genesis permanenti (peg e hedge separati on-chain) |

Il bot fornisce `escrow_script` / indirizzo multisig. Le mining fee di funding restano sui **wallet** dei depositanti (non sull’escrow finché non è funded).

### 3.2 Path preferito — PSBT asincrona (una tx, un UTXO)

Una **sola** transazione di funding; le parti aggiungono input e firme in sequenza **prima** del broadcast.

```text
1. Bot (o peg_party) crea PSBT:
     Output: escrow_script → peg_collateral + hedge_collateral  (es. 3_000_000 sats)

2. T₁ — peg_party aggiunge input (≥ peg_collateral + fee share) e firma i propri input

3. T₂ — investor aggiunge input (≥ hedge_collateral + fee share) e firma i propri input

4. Broadcast → un solo escrow_utxo (3M) sullo script 2-of-3
```

| Proprietà | Dettaglio |
|-----------|-----------|
| Firme | Ognuno firma **solo i propri input** (non è ancora spend multisig) |
| Fee | Ogni parte paga la quota legata ai **propri input** nella tx |
| Stato off-chain | `funding_psbt` in attesa fino a firma investor |
| Bot | Opzionale: coordina scambio PSBT; non deve firmare |

```text
  T₁ Alice firma ──┐
                   ├── PSBT (non broadcast) ──► broadcast ──► escrow_utxo unico (3M)
  T₂ Bob firma   ──┘
```

### 3.3 Path alternativo — deposito sequenziale + consolidamento

Se peg_party versa **prima** da sola (tx già on-chain):

```text
T₁ — peg_party (firma singola):
  wallet → escrow_script   peg_collateral_sats     (es. 1M)
  → escrow_utxo_partial    stato: peg_deposited

T₂ — consolidamento (2-of-3 sulla partial + input investor):
  Input:  escrow_utxo_partial + wallet investor
  Output: escrow_script → peg_collateral + hedge_collateral   (es. 3M)
  Firme:  2-of-3 sulla partial (tipicamente peg_party + investor) + investor sui propri input
  → escrow_utxo definitivo; partial spenta
```

| Proprietà | Dettaglio |
|-----------|-----------|
| Fee T₁ | Wallet peg_party |
| Fee T₂ | Principalmente wallet investor (consolidation) |
| Bot | Può fornire template PSBT consolidamento |
| Rischio intermedio | UTXO partial è escrow reale ma **sotto-collateralizzato** fino a T₂ |

**MVP M1:** preferire §3.2 (PSBT asincrona); §3.3 per recovery se peg_party ha già broadcast da sola.

### 3.4 Escrow a regime e annex

```text
                    ┌─────────────────────────────┐
                    │  escrow_utxo (2-of-3)       │
                    │  peg + hedge (unico UTXO)   │
                    │  es. 1M + 2M = 3M sats      │
                    └─────────────────────────────┘
                              │
         annex margin (opz.)  │  stesso script, UTXO aggiuntivi (MARGIN-SPEC)
```

| Proprietà | Regola |
|-----------|--------|
| Genesis | **1 UTXO** per deal funded |
| Annex margin | UTXO **aggiuntivi** sullo stesso script (M2+) |
| Spend settlement | Input: `escrow_utxo` (+ annex se presenti); **2-of-3** |

Implementazione M1 (regtest): P2WSH `OP_2 <pk1> <pk2> <pk3> OP_3 OP_CHECKMULTISIG` o equivalente Taproot script-path.

---

## 4) Matrice firme (chi firma cosa)

| Evento | Firmatari (2-of-3) | Bot obbligatorio? | Note |
|--------|-------------------|-------------------|------|
| **Funding PSBT** (§3.2) | Ognuno sui **propri input** | No | PSBT asincrona; broadcast quando completa |
| **Deposit peg solo** (§3.3 T₁) | `peg_party` sola | No | UTXO partial; fee wallet peg_party |
| **Consolidamento** (§3.3 T₂) | `peg_party` + `investor` (2-of-3 sulla partial) | No | Unico `escrow_utxo` definitivo |
| **Apertura deal (funded)** | — | No | `escrow_utxo` pieno on-chain; mint stato / RGB |
| **Cancel cooperativo** | `peg_party` + `investor` | No | Refund pro-rata collateral prima di maturity |
| **Settlement maturity** | tipicamente `bot` + `peg_party` **oppure** `bot` + `investor` | No* | *Path felice: bot costruisce PSBT payout + attestation oracle; serve 1 chiave utente |
| **Settlement senza bot** | `peg_party` + `investor` | No | Stesso payout FloorEUR; wallet locale verifica oracle e liability |
| **Refund timelock (Path B)** | `peg_party` o `investor` + half-sig pre-firmata | No | Dopo `maturity_height + refund_delay_blocks` |

**Regola:** per ogni spend dell’escrow servono **esattamente 2** firme tra `{ peg_party, investor, bot }`.

---

## 5) Path di spend (output attesi)

### 5.1 Settlement a maturity (path principale)

Alla height `≥ maturity_height`, con `spot` oracle valido (P2P-OPTIONS §6).

**Ordine fee (policy MVP):** si stima `mining_fees` sulla PSBT di settlement; si calcola il payout holder sul **netto escrow** — vedi [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md) §4 e §7.

```text
inputs:  tutti escrow_utxos[] del deal
outputs:
  Σ holder_sats_i  → indirizzi holder (peg_party + cessionari)
  investor_remainder_sats → investor
  (mining_fees implicite: sum(inputs) − sum(outputs))
```

Calcolo economico: [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md) §4–§7.  
Il bot **non** riceve payout dall’escrow (`protocol_fee_sats = 0` nel MVP).

**Coupling oracle:** l’attestation firmata dal bot (mediana feed) è allegata ai metadati PSBT / `witness`; i wallet **verificano localmente** `total_holder_sats` prima di firmare.

### 5.2 Cancel cooperativo (pre-maturity)

Spend con tutti gli `escrow_utxos[]`; fee settlement dedotta dall’escrow prima dello split (come §5.1):

```text
distributable_sats = escrow_total_sats − mining_fees
peg_party  ← peg_collateral_sats  (netto premium)
investor   ← distributable_sats − peg_collateral_sats   (= hedge + top_ups se distributable sufficiente)
```

### 5.3 Refund timelock (Path B — obbligatorio)

Se entro `maturity_height + refund_delay_blocks` non è stata confermata una spend di settlement valida:

```text
CLTV branch a height = maturity_height + refund_delay_blocks
distributable_sats = escrow_total_sats − mining_fees

peg_party  ← peg_collateral_sats
investor   ← distributable_sats − peg_collateral_sats
```

- PSBT refund **pre-firmata** (o half-signed) esportata all’apertura deal.
- Non riparte liability FloorEUR: è **recupero collateral**, non settlement.

### 5.4 Lightning force close (Path C — opzionale)

Se il transfer del diritto passa su LN: chiusura canale non tocca direttamente l’escrow multisig; consignment RGB + anchor L1 restano la fonte di verità del `notional_share`.

### 5.5 ERP / dispute key (Path D — fuori MVP)

Terza chiave umana di emergenza **non** sostituisce il bot nel design MVP; rimandata a fasi successive.

---

## 6) Recovery package (export obbligatorio all’apertura)

Ogni wallet (`peg_party`, `investor`) deve persistere localmente:

| Artefatto | Contenuto |
|-----------|-----------|
| `deal_params.json` | `deal_id`, strike, rate, heights, collateral, pubkeys, `escrow_utxo` |
| `psbt_funding` | PSBT asincrona §3.2 (o consolidamento §3.3) in corso |
| `psbt_maturity_template` | Output placeholder; firme parziali opzionali |
| `psbt_refund_timelock` | Half-signed CLTV refund Path B |
| `consignment_rgb` | Assignment `FloorEURPosition` (fase M3) |
| `oracle_policy` | Feed, soglia mediana, pubkey attestation |

**Checklist M0:** non implementato in Rails PoC (M1: export JSON / PSBT reali; target `Deal#recovery_package` o equivalente su `Budget`).

---

## 6bis) Mining fees (policy MVP)

### Due momenti

| Momento | Chi paga | Da dove |
|---------|----------|---------|
| **Funding** (PSBT §3.2 o consolidamento §3.3) | Chi firma i **propri input** | Wallet del depositante |
| **Spend escrow** (settlement, cancel, refund) | Dedotto dall’escrow | `escrow_total − outputs` |

### Settlement: fee prima del payout holder

```text
gross_holder_sats   = floor(liability_eur_cents × 10^8 / (S × 100))    # PAYOFF-SPEC §4
distributable_sats  = escrow_total_sats − mining_fees

total_holder_sats   = min(gross_holder_sats, distributable_sats)
holder_sats_i       = pro-rata su notional_share
investor_remainder  = distributable_sats − total_holder_sats
```

| Caso | Effetto |
|------|---------|
| Solvente | `gross_holder ≤ distributable` → holder riceve il gross; investor prende il residuo netto |
| Insolvente | `gross_holder > distributable` → holder cappato a `distributable`; investor remainder = 0 |
| Fee alta | Riduce `distributable` prima del calcolo holder — non si promettono sats oltre il netto |

**Sizing apertura** (PAYOFF-SPEC §7): `max_holder_sats + estimated_settlement_fee_sats ≤ escrow_total_sats`.  
La fee di **funding** non entra in `escrow_total` (pagata dai wallet).

### Fee protocollo

```text
protocol_fee_sats = 0    # MVP: nessun output verso il bot dall’escrow
```

`premium_sats` (opzionale peg_party → investor al genesis) resta campo separato; default **0**.

---

## 7) Sicurezza e threat model (MVP)

| Minaccia | Effetto | Mitigazione |
|----------|---------|-------------|
| Bot compromesso | Attaccante ha 1-of-3 | Non spende senza collusione con `peg_party` **o** `investor` |
| Investor non coopera a maturity | Settlement bloccato | `peg_party + bot` oppure timelock Path B |
| Bot offline | Nessun template automatico | `peg_party + investor` firmano payout manualmente |
| Oracle manipolato | Payout holder errato | Mediana 5 feed; verifica client-side; firma attestation |
| Peg party + investor colludono contro bot | Spend arbitraria | Bot non detiene fondi propri in escrow; rischio limitato al ruolo facilitatore |

**Boundary:** il bot **non** detiene saldi aggregati; ogni deal è isolato per UTXO e per `bot_pubkey`.

---

## 8) Mapping implementativo

### Simulatore Rails (`eur-token-poc`)

| Concetto MULTISIG | Modello Rails (PoC attuale) | Gap verso L1 |
|-------------------|-----------------------------|--------------|
| `multisig_policy` | Implicito `2-of-3` (non persistito) | Enum + pubkeys |
| Pubkeys | — | `Budget` / `Deal` con hex keys |
| `escrow_utxo` | `CollateralLock` (1 riga, `amount_sats`) | Outpoint reale |
| `escrow_utxos` | Stesso pool DB (+ top-up investitore, no annex) | Array outpoint |
| `estimated_settlement_fee_sats` | `Budget::ESTIMATED_SETTLEMENT_FEE_SATS` (5_000) | — |
| `refund_delay_blocks` | Solo in spec (default 1008), non in DB | CLTV Path B |
| Recovery package | — | JSON export wallet |
| Stato funding | `Budget` `pending` → `active` → `settled` | PSBT async / consolidate |

### Bitcoin L1 (M1 regtest)

1. Generare 3 chiavi (regtest).
2. Funding: PSBT asincrona (§3.2) o sequenziale + consolidamento (§3.3) → **un** UTXO 2-of-3.
3. A `maturity_height`, PSBT settlement multi-input con oracle mock.
4. Test: bot offline → `peg_party + investor` spendono comunque.
5. Test: no settlement → refund CLTV dopo `refund_delay_blocks`.

---

## 9) Decisioni chiuse (fase 0 #2)

| # | Decisione | Scelta |
|---|-----------|--------|
| 2 | Politica multisig | **`2-of-3`**: `peg_party`, `investor`, `bot` |
| — | Arbitro esterno | **Non** nel MVP |
| — | Recovery senza bot | **Obbligatoria**: `peg_party + investor` + timelock refund |
| — | `refund_delay_blocks` | Default **1008** (≈ 7 giorni post-maturity) |
| — | Funding escrow | **Momenti separati**, **un UTXO** (PSBT asincrona §3.2) |
| — | Granularità escrow | **1 UTXO** genesis (+ annex margin opz.) |
| 4 | Fee protocollo | **`protocol_fee_sats = 0`** |
| — | Mining fee settlement | **Prima del payout holder** (`distributable = escrow − fees`) |
| — | `estimated_settlement_fee_sats` | Default **5_000** (sizing) |

---

## 10) Checklist test (M0 — multisig)

Legenda: `[x]` fatto in Rails PoC · `[~]` parziale / simulato in DB · `[ ]` M1+ L1.

- [~] Parametri §2: subset su `Budget` (+ L1: pubkeys, `escrow_txid`/`vout`, `refund_delay_blocks`, `recovery_package` json).
- [x] Matrice firme §4 — `L1::SignatureMatrix` + spec regtest (2-of-3 pairs; bot-only incompleto).
- [x] Recovery package §6 serializzabile — `L1::RecoveryPackage` + `L1::RecordEscrowService`.
- [~] Path B: refund tx con `locktime` costruita in regtest; broadcast post-maturity da automatizzare.
- [x] Funding: un UTXO P2WSH via consolidamento §3.3 — `L1::RegtestHarness#fund_escrow!`.
- [x] Settlement: `total_holder = min(gross, escrow − fees)` — `Payoffs::FloorEurCalculator` + spend regtest.
- [x] Verifica L1: spend con **solo** bot → `complete: false` — spec regtest.

---

## 11) Riferimenti

- [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md) — payout holder e `investor_remainder_sats`
- [`P2P-OPTIONS.md`](P2P-OPTIONS.md) §4–§6 — architettura e ruolo bot
- [`MARGIN-SPEC.md`](MARGIN-SPEC.md) — annex top-up (estensione multi-UTXO)
- [BIP 67](https://github.com/bitcoin/bips/blob/master/bip-0067.mediawiki) — ordinamento pubkey multisig
- [BIP 141](https://github.com/bitcoin/bips/blob/master/bip-0141.mediawiki) — P2WSH

---

## Sintesi

Escrow **2-of-3** per deal: **un UTXO** con peg + hedge; versamenti in **momenti separati** (PSBT asincrona o consolidamento). Mining fee settlement **prima** del payout holder. Bot senza fee protocollo nel MVP.
