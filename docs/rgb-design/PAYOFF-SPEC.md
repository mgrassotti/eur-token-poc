# PAYOFF-SPEC: peg € + interesse sul notional (`FloorEUR`)

Specifica del payoff per contratti bilaterali P2P descritti in [`P2P-OPTIONS.md`](P2P-OPTIONS.md).

**Prodotto:** l’**holder** (parte peg e cessionari del diritto / EURT) mantiene il **valore in euro del notional**, più un **interesse deterministico** sulla durata del contratto. **Nessun premio aggiuntivo** se `spot > K`: non c’è partecipazione al rialzo del BTC in euro oltre peg + carry.

**Non è** una put classica sul BTC (che sopra K lascia l’upside al detentore del sottostante). È un **claim in € liquidato in sats** allo spot di maturity.

**Nomi attori negli esempi:** *Alice*, *Bob*, *Claude* (e simili) sono **personaggi fittizi** del simulatore Rails / demo; nei parametri del contratto si usano solo ruoli (`peg_party`, `investor`, `holder`, `bot`).

---

## 1) Parametri fissati al genesis del deal

| Campo | Tipo | Descrizione |
|-------|------|-------------|
| `deal_id` | uuid / hash | Identificativo univoco |
| `escrow_utxo` | outpoint | Unico UTXO escrow `2-of-3` (peg + hedge) — funding a momenti separati, vedi [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) §3 |
| `peg_collateral_sats` | u64 | Collateral della parte peg in escrow |
| `hedge_collateral_sats` | u64 | Collateral dell’hedger in escrow |
| `notional_sats` | u64 | Base nominale del contratto (MVP: tipicamente = `peg_collateral_sats`) |
| `strike_eur_per_btc` | u64 | `K` — €/BTC al genesis (fixed-point, es. 50_000 = 50 000,00 €/BTC) |
| `rate_bps_monthly` | u32 | Interesse sul notional, in basis point per “mese” (100 = 1,00%/mese) |
| `blocks_per_month` | u32 | Durata simbolica di un mese in blocchi (default **4356** = 144 × 30,25) |
| `genesis_height` | u32 | Altezza blocco all’apertura |
| `maturity_height` | u32 | Altezza blocco di settlement |
| `premium_sats` | u64 | Opzionale: premio `peg_party` → `investor` all’apertura (default 0); flat sats |
| `estimated_settlement_fee_sats` | u64 | Stima fee settlement per sizing (default **5_000**) |
| `oracle_policy` | struct | Mediana feed + pubkey attestation (vedi P2P-OPTIONS §6) |
| `multisig_policy` | enum | `2-of-3` peg_party, investor, bot — vedi [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) |

### Vincoli al genesis

```text
hedge_collateral_sats ≥ 2 × peg_collateral_sats
notional_sats ≤ peg_collateral_sats                    (MVP: tipicamente uguali)
genesis_height < maturity_height
rate_bps_monthly ≥ 0
blocks_per_month > 0
strike_eur_per_btc > 0
```

---

## 2) Unità e rappresentazione numerica

| Grandezza | Unità | Note |
|-----------|-------|------|
| BTC | sats (u64) | 1 BTC = 10⁸ sats |
| EUR | centesimi (u64) | 1 € = 100 cent; in formula `liability_eur_cents` |
| `strike_eur_per_btc` | € interi per 1 BTC | Come nel PoC Rails (`MarketRate`, `Budget#peg_eur_per_btc`) |
| `rate_bps_monthly` | basis point | 1 bp = 0,01%/mese |
| `blocks_per_month` | blocchi | **4356** = 144 blocchi/giorno × 30,25 giorni/mese |

**Notional in euro al genesis** (fissato da K):

```text
notional_eur_cents = floor(notional_sats × strike_eur_per_btc × 100 / 10^8)
```

Esempio: `notional_sats = 1_000_000`, `K = 50_000` → `notional_eur_cents = 500_000` (5 000,00 €).

---

## 3) Passività in € (liability)

L’interesse si applica al **notional in €**, non al collateral grezzo dell’investor.

### Durata

```text
blocks_elapsed   = maturity_height − genesis_height
months_elapsed   = blocks_elapsed / blocks_per_month        (divisione intera)
```

Con `blocks_per_month = 4356`, un mese simbolico ≈ 30,25 giorni di blocchi Bitcoin (144 blocchi/giorno).

Per il MVP la durata effettiva usa **solo mesi interi**; i blocchi residui non maturano interesse aggiuntivo. (Estensione futura: accrual proporzionale ai blocchi.)

### Liability totale del deal

```text
liability_eur_cents = floor(
  notional_eur_cents × (10_000 + rate_bps_monthly × months_elapsed) / 10_000
)
```

Equivalente: `notional_€ × (1 + rate × months)` con `rate = rate_bps_monthly / 10_000`.

**Interpretazione:** a maturity ogni holder ha diritto alla propria quota di **`liability_eur_cents` totali**, convertiti in sats allo spot oracle. Il valore in € è **indipendente da `spot`**; cambia solo il numero di sats necessari.

### Nessun premio se `spot > K`

Non esiste un termine aggiuntivo legato a `max(0, spot − K)`. Sopra lo strike il holder riceve **esattamente** la liability in € (quota pro-rata), non di più. Il rialzo del BTC in euro **non** aumenta la passività verso gli holder.

---

## 4) Settlement a maturity

Alla height `maturity_height`, l’oracle pubblica `spot_eur_per_btc` (`S`) — mediana dei feed, attestazione firmata (P2P-OPTIONS §6).

### Payout totale holder-side (sats)

```text
gross_holder_sats = floor(liability_eur_cents × 10^8 / (S × 100))

distributable_sats  = escrow_total_sats − mining_fees
total_holder_sats   = min(gross_holder_sats, distributable_sats)
```

**Policy mining fee:** si stima `mining_fees` sulla PSBT di settlement; il payout holder usa il **netto escrow** (`distributable_sats`) — vedi [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) §6bis.  
Verifica dimensionalità: `liability_eur_cents / 100` = EUR → `/ S` = BTC → `× 10^8` = sats.

### Pro-rata tra holder (TransferPosition / EURT)

Per ogni holder `i` con `notional_share_i` (somma delle quote = `notional_sats`):

```text
holder_sats_i = floor(total_holder_sats × notional_share_i / notional_sats)
```

**Ultimo holder:** riceve il residuo per conservazione sats  
`holder_sats_last = total_holder_sats − sum(holder_sats_{i≠last})`.

### Residuo escrow (lato investor)

```text
escrow_total_sats = peg_collateral_sats + hedge_collateral_sats + top_ups_sats   (al netto di premium già pagati)
distributable_sats = escrow_total_sats − mining_fees
investor_remainder_sats = distributable_sats − total_holder_sats
```

**Vincolo:** `investor_remainder_sats ≥ 0`. Se `gross_holder_sats > distributable_sats` → insolvenza; vedi §7.

L’**investor** **non** firma i transfer RGB; resta controparte hedge fino a maturity.

---

## 5) Esempi numerici (K = 50 000 €/BTC)

*Personaggi: solo illustrazione — Alice = peg_party/holder, Bob = investor, Claude = cessionario.*

Assunzioni comuni:

- `notional_sats = 1_000_000` (0,01 BTC) → `notional_eur_cents = 500_000` (5 000 €)
- `rate_bps_monthly = 100` (1%/mese)
- `months_elapsed = 6` → fattore `1,06`
- `liability_eur_cents = floor(500_000 × 1,06) = 530_000` (**5 300 €**)

| Spot S (€/BTC) | total_holder_sats | Valore € (≈) |
|----------------|-------------------|--------------|
| 25 000 | floor(530_000 × 10⁸ / (25_000 × 100)) = **2 120 000** | ~5 300 € |
| 50 000 | **1 060 000** | ~5 300 € |
| 100 000 | **530 000** | ~5 300 € |

Sopra K il holder **non** riceve più di 5 300 €; servono meno sats perché il BTC vale di più in euro.

### Esempio transfer parziale (holder → cessionario, 40%)

Scenario demo: Alice cede il 40% a Claude.  
`notional_sats = 1_000_000`, a maturity `total_holder_sats = 1_060_000` (S = 50k):

| Holder | notional_share | holder_sats |
|--------|----------------|-------------|
| Alice (holder residuo) | 600_000 | 636_000 |
| Claude (cessionario) | 400_000 | 424_000 |

---

## 6) Confronto con put europea pura (P2P-OPTIONS §3.2)

| | Put europea (doc originale) | **FloorEUR** (questa spec) |
|--|----------------------------|----------------------------|
| Sopra K | 0 dal contratto | **Peg € + interesse** (fisso in €) |
| Sotto K | Compensazione | Stesso peg € + interesse |
| Interesse | No | **Sì**, sul notional |
| Upside BTC in € | Possibile sul collateral | **Escluso** oltre liability |
| Allineamento EURT | Parziale | **Diretto** (token = quota su liability €) |

---

## 7) Collateral, insolvenza e worst case

### Worst case per l’investor (spot → 0⁺)

```text
gross_holder_sats → ∞ teorico; praticamente cappato da distributable_sats
```

**Regola MVP:** se `gross_holder_sats > distributable_sats` (con `distributable_sats = escrow_total_sats − mining_fees`):

```text
total_holder_sats       := distributable_sats
holder_sats_i           := pro-rata su notional_share del cappato
investor_remainder_sats := 0
```

### Verifica apertura deal (conservativa)

Stimare il massimo sats necessario con `S_min` policy (es. floor oracle o parametro di stress):

```text
max_holder_sats = floor(liability_eur_cents_max × 10^8 / (S_min × 100))
richiedi: max_holder_sats + estimated_settlement_fee_sats ≤ escrow_total_sats
```

Le fee di **funding** sono sui wallet dei depositanti (PSBT asincrona o consolidamento) — non riducono `escrow_utxo.value`.

Con `escrow_total ≥ 2 × notional` all’apertura (richiedente 1× + investitore 1×, LTV iniziale 50%) il monitoraggio intraday usa **LTV mark-to-market**:

| Soglia LTV | Azione (simulatore Rails / deal) |
|------------|----------------------------------|
| **≥ 70%** | **Margin call** — notifica investitore; può versare collateral aggiuntivo nel multisig |
| **≥ 90%** | **Liquidazione automatica** FloorEUR (stesso payoff, spot corrente) |

L’investitore può **sempre** aumentare `escrow_total` con top-up (annex UTXO in produzione; stesso `collateral_lock` nel PoC) per abbassare il LTV.

---

## 8) Accrual e transfer prima della maturity

L’interesse **non** è pagato periodicamente on-chain nel MVP: matura implicitamente fino a `maturity_height`.

Su **`TransferPosition`** (RGB o simulatore Rails):

- Si trasferisce solo `notional_share` (diritto economico).
- Alla maturity il payout usa la **liability intera** del deal (basata su `months_elapsed` genesis→maturity), ripartita sulle quote **correnti**.
- L’interesse maturato “appartiene” a chi detiene la quota al settlement, non a chi l’ha detenuta per più tempo (semplificazione MVP).  
  *Estensione futura:* accrual per periodo di detenzione (richiede stato aggiuntivo nello schema).

---

## 9) Mapping implementativo

### Simulatore Rails (`eur-token-poc`)

| Concetto PAYOFF | Modello Rails (PoC attuale) |
|-----------------|-----------------------------|
| `notional_share` | `TokenAccount#balance_cents` (per budget) |
| `strike_eur_per_btc` | `Budget#peg_eur_per_btc` (fissato all’activate) |
| `maturity_height` | `Budget#maturity_block_height` (per deal, non epoch globale) |
| `genesis_height` | `Budget#genesis_block_height` |
| `peg_collateral_sats` | `Budget#borrower_locked_sats` |
| `hedge_collateral_sats` | `Budget#investor_locked_sats` (+ top-up investitore) |
| `escrow_total_sats` | `CollateralLock#amount_sats` |
| `liability_eur_cents`, payout | `Payoffs::FloorEurCalculator` via `Settlements::ExecuteService` |
| `spot` a maturity | `MarketRate` / parametro `end_btc_eur_rate` |
| Transfer | `Tokens::WalletTransferService` (coin selection multi-budget) |

**Settlement holder (equivalente Rails):**

```ruby
liability_cents = (notional_eur_cents * (10_000 + rate_bps_monthly * months)) / 10_000
holder_sats = (liability_cents * holder_share / notional) * 10**8 / (spot * 100)
```

### RGB (fase M3)

Assignment `FloorEURPosition` (owned state):

```text
deal_id, holder_pubkey, notional_share,
strike_eur_per_btc, rate_bps_monthly, blocks_per_month,
genesis_height, maturity_height, escrow_outpoint
```

Validazione client-side (rgb-lib):

- `0 < Δ ≤ N` su transfer; conservazione `notional_share`.
- A maturity, wallet + oracle costruiscono PSBT con `total_holder_sats` da questa spec.

### Bitcoin L1

- Escrow multisig invariato (P2P-OPTIONS §4–5).
- Una PSBT di payout a `maturity_height` distribuisce `holder_sats_i` e residuo all’investor.

---

## 10) Decisioni chiuse (ex P2P-OPTIONS §13)

| # | Decisione | Scelta |
|---|-----------|--------|
| 1 | Forma payoff | **Peg € + interesse sul notional** (non put con upside) |
| 2 | Politica multisig | **`2-of-3`**: `peg_party`, `investor`, `bot` — vedi [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) |
| 3 | Margin intraday | **Specificato** in [`MARGIN-SPEC.md`](MARGIN-SPEC.md) (top-up annex); **off** in M0–M1 |
| 4 | Fee protocollo | **`protocol_fee_sats = 0`**; `premium_sats` flat opzionale (default 0) |
| 5 | Ordine stack on-chain | **RGB prima** (M3 transfer); **DLC dopo** (M4 opz.); settlement MVP = multisig L1 (M1) |
| 6 | `notional_sats` | Parametro esplicito; MVP: **= `peg_collateral_sats`** |
| 7 | Allineamento PoC | Settlement = **`liability_eur / spot`**, non formula put §3.2 |
| — | `blocks_per_month` | **4356** (144 × 30,25) |
| — | Nomi collateral | `peg_collateral_sats`, `hedge_collateral_sats` |
| — | `refund_delay_blocks` | **1008** (default timelock Path B) |
| — | Funding escrow | **Momenti separati**, **un UTXO** — [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) §3 |
| — | Mining fee settlement | **Prima del payout holder** (`distributable = escrow − fees`) |

Fase 0 design: **chiusa**. Checklist M0 §11 **completata in Rails** (46 spec verdi); resta aperto solo multisig L1 (M1) — vedi [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) §10.

---

## 11) Checklist test (M0 done quando)

- [x] Esempio §5 (6 mesi, 1%/mese, tre spot) riprodotto in spec/fixture.
- [x] Transfer 40% a cessionario: pro-rata §5.
- [x] `spot > K` → stessi € holder, meno sats.
- [x] Cappo escrow §7 con `S` molto basso.
- [x] Apertura: `escrow_total ≥ 2 × notional` (1× richiedente + 1× investitore); LTV iniziale 50%.
- [x] LTV ≥ 70% margin call; ≥ 90% liquidazione; top-up investitore nel PoC.
- [ ] Multisig 2-of-3 L1: matrice firme e recovery package — **M1 regtest** in `lib/l1/` (wiring activate opzionale).

---

## 12) Riferimenti

- [`P2P-OPTIONS.md`](P2P-OPTIONS.md) — architettura P2P, RGB, multisig, roadmap
- [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) — escrow 2-of-3, recovery, timelock refund
- [`MARGIN-SPEC.md`](MARGIN-SPEC.md) — margin intraday, top-up annex
- [`eur-token-poc` README](../../README.md) — simulatore Rails
- [rgb-lib](https://github.com/RGB-Tools/rgb-lib) — validazione client-side

---

## Sintesi

A maturity ogni holder riceve in sats l’equivalente di:

```text
notional_€ × (1 + rate_bps_monthly × months / 10_000)
```

valutato allo **spot oracle**, **senza** componenti aggiuntive se `spot > K`. L’interesse è sul **notional**; il diritto è frazionabile (`TransferPosition` / EURT). All’apertura: **escrow 2×** il notional (richiedente + investitore); **LTV ≥ 70%** margin call, **≥ 90%** liquidazione; l’investitore può versare collateral aggiuntivo.
