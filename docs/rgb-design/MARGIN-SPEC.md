# MARGIN-SPEC: margin intraday con top-up in escrow (`FloorEUR`)

Specifica del **margin mark-to-market** per contratti bilaterali P2P, complementare a [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md) e [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md).

**Meccanismo scelto:** **Opzione 1 — top-up in escrow** — l’investor deposita sats aggiuntivi in **UTXO annex** sullo **stesso script `2-of-3`** del deal; a settlement/liquidazione tutti gli UTXO del deal sono input della PSBT.

**Abilitazione:** il margin **non** fa parte del core **M0–M1** (settlement solo a `maturity_height`). Questa spec governa l’estensione **M2+** quando `margin_enabled = true` al genesis o per policy di prodotto.

**Nomi negli esempi:** *Alice* = `peg_party`, *Bob* = `investor`, *Bot* = facilitatore.

---

## 1) Obiettivo

Durante la vita del deal (`genesis_height` … `maturity_height`), monitorare se l’escrow copre la passività holder **mark-to-market** (liability € maturata convertita allo spot corrente). Se la **coverage** scende sotto soglia:

1. **Margin call** → l’investor deve fare **top-up** on-chain entro `grace_blocks`.
2. Se la call non è soddisfatta e la coverage scende sotto **liquidation** → **settlement anticipato** (stesso payoff FloorEUR, liability e spot al momento della liquidazione).

Il peg_party / holder **non** versa margin; il rischio di rifinanziamento è sull’**investor** (hedger).

---

## 2) Parametri (genesis o policy deal)

| Campo | Tipo | Default | Descrizione |
|-------|------|---------|-------------|
| `margin_enabled` | bool | `false` (M0–M1) | Abilita monitoraggio e call |
| `margin_call_bps` | u32 | **12_000** | Soglia call: coverage &lt; `margin_call_bps / 10_000` (120%) |
| `liquidation_bps` | u32 | **10_500** | Soglia liquidazione forzata: coverage &lt; `liquidation_bps / 10_000` (105%) |
| `grace_blocks` | u32 | **144** | Blocchi per rispondere a una margin call (~1 giorno) |
| `oracle_tick_blocks` | u32 | **1** | Minimo intervallo tra due valutazioni coverage (MVP: ogni blocco se oracle aggiorna) |
| `escrow_script` | bytes | — | Script `2-of-3` condiviso (stesso di [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md)) |
| `escrow_utxos` | outpoint[] | `[genesis]` | Elenco UTXO escrow del deal (genesis + annex top-up) |
| `peg_collateral_sats` | u64 | — | Collateral iniziale peg_party (UTXO genesis) |
| `hedge_collateral_sats` | u64 | — | Collateral iniziale investor (UTXO genesis) |
| `top_ups_sats` | u64 | `0` | Somma annex depositati dall’investor (stato aggiornato off-chain) |

### Vincoli

```text
margin_enabled = false  →  comportamento PAYOFF-SPEC puro (solo settlement a T)
liquidation_bps < margin_call_bps ≤ 10_000 × max_realistic_coverage   (es. 12_000 = 120%)
grace_blocks > 0
oracle_tick_blocks > 0

# Apertura (anche con margin_enabled): stesso stress di PAYOFF-SPEC §7
max_holder_sats_at_S_min + fees ≤ peg_collateral_sats + hedge_collateral_sats
```

Con `margin_enabled = true`, il check a `S_min` all’apertura resta **necessario ma non sufficiente** — il monitoraggio intraday copre movimenti spot e accrual successivi.

---

## 3) Liability e coverage (mark-to-market)

Alla height `h` con spot oracle `S_h` (€/BTC, come PAYOFF-SPEC):

```text
blocks_elapsed_h = h − genesis_height
months_h         = blocks_elapsed_h / blocks_per_month          # mesi interi (PAYOFF-SPEC §3)

liability_h = floor(
  notional_eur_cents × (10_000 + rate_bps_monthly × months_h) / 10_000
)

required_sats_h = floor(liability_h × 10^8 / (S_h × 100))

escrow_total_sats = peg_collateral_sats + hedge_collateral_sats + top_ups_sats
                  = sum(value(utxo) for utxo in escrow_utxos)   # al netto premium

coverage_bps_h = floor(escrow_total_sats × 10_000 / required_sats_h)   # 12_000 = 120%
```

| Grandezza | Interpretazione |
|-----------|-----------------|
| `liability_h` | Passività holder in € se il deal “finisse” a `h` |
| `required_sats_h` | Sats necessari oggi a spot `S_h` |
| `coverage_bps_h` | Quanto l’escrow copre il fabbisogno (in basis point) |

**Nota:** fino a maturity si usa la stessa regola di accrual a **mesi interi** di PAYOFF-SPEC §3. Estensione futura: accrual per blocco (cambia `liability_h` e la frequenza delle call).

---

## 4) Opzione 1 — Top-up in escrow (annex UTXO)

### 4.1 Modello UTXO

```text
Deal escrow (stesso script 2-of-3 per tutti gli UTXO):

```text
escrow_utxos[0]  genesis    unico UTXO (peg + hedge)
escrow_utxos[1]  annex_1    top-up investor (opz., margin)
```
```

| Regola | Dettaglio |
|--------|-----------|
| Script | Identico per genesis e annex: `2-of-3` `peg_party`, `investor`, `bot` (BIP67 sort) |
| Indirizzo | Stesso P2WSH / Taproot policy per ogni deposito |
| Funding top-up | **Solo firma investor** sull’input; output → indirizzo escrow condiviso |
| Spesa | Qualsiasi spend del deal include **tutti** gli `escrow_utxos` con balance &gt; 0 (o subset sufficiente se dust policy) |
| `top_ups_sats` | Incrementato a ogni annex confermato; tracciato in stato deal / RGB |

Il genesis è **un UTXO** (`escrow_utxo`); gli annex margin sono UTXO aggiuntivi sullo stesso script — [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) §3.4.

### 4.2 Transazione top-up (annex)

```text
Input:  UTXO wallet investor (firma investor)
Output: escrow_address(script_2of3), amount = top_up_amount
Fee:    a carico investor
```

Dopo conferma L1:

```text
escrow_utxos.append(new_outpoint)
top_ups_sats += top_up_amount
# Ricalcolo coverage; se ≥ margin_call_bps → margin call risolta
```

**Nessuna firma** di `peg_party` o `bot` richiesta per il deposito annex.

### 4.3 Importo richiesto dalla margin call

Alla height `h` di call:

```text
target_escrow_sats = ceil(required_sats_h × margin_call_bps / 10_000)

top_up_required_sats = max(0, target_escrow_sats − escrow_total_sats)
```

Arrotondamento: `ceil` sul target per non restare sotto soglia per pochi sats; politica dust minima **546 sats** (o parametro `min_top_up_sats`).

Il bot pubblica: `{ deal_id, h, S_h, coverage_bps_h, top_up_required_sats, grace_deadline_height }` firmato (attestation margin).

---

## 5) Macchina a stati margin

```text
                    ┌──────────────┐
                    │   HEALTHY    │  coverage_bps ≥ margin_call_bps
                    └──────┬───────┘
                           │ coverage < margin_call_bps
                           ▼
                    ┌──────────────┐
         ┌─────────│  MARGIN_CALL │  grace_deadline = h + grace_blocks
         │         └──────┬───────┘
         │ annex ok       │ grace scaduta ∧ coverage < liquidation_bps
         │                ▼
         │         ┌──────────────┐
         └────────►│   HEALTHY    │     ┌─────────────────┐
                   └──────────────┘     │  LIQUIDATING    │ → settlement anticipato
                                        └────────┬────────┘
                                                 ▼
                                        ┌─────────────────┐
                                        │     CLOSED      │
                                        └─────────────────┘
```

| Stato | Ingresso | Azione |
|-------|----------|--------|
| `HEALTHY` | coverage OK | Nessuna |
| `MARGIN_CALL` | `coverage_bps < margin_call_bps` | Notifica investor; avvia `grace_deadline` |
| `HEALTHY` | annex confermato prima di grace | Aggiorna `escrow_utxos`, `top_ups_sats` |
| `LIQUIDATING` | grace scaduta e `coverage_bps < liquidation_bps` | PSBT settlement anticipato |
| `CLOSED` | settlement (anticipato o a maturity) | Deal terminato |

Se durante la grace la coverage risale sopra `margin_call_bps` (spot ↑), la call si **chiude** senza top-up.

---

## 6) Liquidazione anticipata

Se `h_liq < maturity_height` e le condizioni di liquidazione sono soddisfatte:

### Payout (stessa formula FloorEUR, variabili a `h_liq`)

```text
liability_liq     = liability_h_liq
required_sats_liq = floor(liability_liq × 10^8 / (S_h_liq × 100))

total_holder_sats = min(
  required_sats_liq,
  escrow_total_sats − mining_fees
)

holder_sats_i = pro-rata su notional_share (PAYOFF-SPEC §4)
investor_remainder_sats = escrow_total_sats − total_holder_sats − mining_fees
```

### PSBT

```text
Inputs:  tutti escrow_utxos[] del deal
Outputs: holder addresses, investor_remainder, fees
Firmatari: 2-of-3 (tipicamente bot + peg_party o bot + investor)
Witness:   attestation oracle S_h_liq + attestation margin (stato LIQUIDATING)
```

Dopo broadcast: `margin_state = CLOSED`; RGB / record Rails invalida ulteriori transfer sul deal.

**Distinzione da MULTISIG-SPEC Path B (timelock refund):** il refund restituisce collateral **grezzo** se nessuno settlement; la liquidazione margin paga la **liability FloorEUR** agli holder.

---

## 7) Settlement a maturity (con margin abilitato)

Se il deal raggiunge `maturity_height` in stato `HEALTHY` o `MARGIN_CALL` risolta:

- Stesso flusso [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md) §4 e [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) §5.1.
- PSBT con **tutti** gli `escrow_utxos[]` come input.
- `escrow_total_sats` include i top-up annex.

---

## 8) Refund cooperativo e timelock (con annex)

### Cancel cooperativo (pre-maturity)

```text
peg_party  ← peg_collateral_sats
investor   ← hedge_collateral_sats + top_ups_sats
fees
```

Gli annex sono **100%** capitale aggiuntivo investor → restano all’investor in cancel/refund.

### Path B timelock (`maturity_height + refund_delay_blocks`)

Stessa ripartizione del cancel: investor recupera `hedge_collateral_sats + top_ups_sats`.

---

## 9) Ruolo del bot

| Funzione | Dettaglio |
|----------|-----------|
| **Monitor** | A ogni tick oracle (`oracle_tick_blocks`): calcola `coverage_bps_h` |
| **Margin attestation** | Firma payload call / stato `LIQUIDATING` |
| **PSBT annex template** | Indirizzo escrow + `top_up_required_sats` per wallet investor |
| **PSBT liquidazione** | Input multi-UTXO; output secondo §6 |
| **Notifiche** | Investor (call), peg_party (warning), holder via app |

Il bot **non** può spendere l’escrow da solo (sempre 2-of-3).

---

## 10) Esempio numerico (margin call + top-up)

Deal demo (PAYOFF-SPEC §5), **3 mesi** trascorsi, `margin_call_bps = 12_000`:

```text
notional_eur_cents = 500_000
rate_bps_monthly   = 100
months_h           = 3
liability_h        = floor(500_000 × 1.03) = 515_000   # 5_150 €

escrow_total_sats  = 3_000_000   # 1M peg + 2M hedge, nessun annex ancora
S_h                = 17_500 €/BTC

required_sats_h    = floor(515_000 × 10^8 / (17_500 × 100)) = 2_942_857
coverage_bps_h     = floor(3_000_000 × 10_000 / 2_942_857) = 10_194   # ~102% < 120%

target_escrow      = ceil(2_942_857 × 12_000 / 10_000) = 3_531_428
top_up_required    = 3_531_428 − 3_000_000 = 531_428 sats
```

1. Bot emette margin call; `grace_deadline = h + 144`.
2. Investor invia annex **531_428 sats** → stesso script 2-of-3.
3. `escrow_total_sats = 3_531_428`, `coverage_bps_h ≈ 12_000` → stato `HEALTHY`.

Se l’investor non deposita e `coverage_bps` resta &lt; `10_500` dopo la grace → liquidazione anticipata §6.

---

## 11) Mapping implementativo

### Simulatore Rails

| Concetto MARGIN | Modello target |
|-----------------|----------------|
| `margin_enabled` | `Deal#margin_enabled` |
| Soglie | `Deal#margin_call_bps`, `#liquidation_bps`, `#grace_blocks` |
| `escrow_utxos` | `Deal#escrow_utxos` (jsonb array) o `EscrowUtxo` has_many |
| `top_ups_sats` | `Deal#top_ups_sats` (denormalizzato) |
| Stato | `Deal#margin_state` enum (`healthy`, `margin_call`, `liquidating`, `closed`) |
| Call | `MarginCall` (deal_id, height, spot, coverage_bps, amount_required, deadline) |
| Tick | `Margins::EvaluateCoverageService` su `MarketRate` / `ChainState` update |

### Bitcoin L1 (M2 regtest)

1. Deal genesis 2-of-3 come M1.
2. Simulare calo spot → margin call.
3. Broadcast annex tx (solo investor).
4. Verificare PSBT maturity con 2 input (genesis + annex).
5. Test liquidazione: nessun annex → settlement anticipato a `h_liq`.

### RGB (M3+)

Estensione `FloorEURPosition` / global deal state:

```text
margin_enabled, margin_state, top_ups_sats, escrow_utxos[]
```

Validazione client: rifiuta transfer se `margin_state = liquidating`.

---

## 12) Decisioni chiuse (fase 0 #3)

| # | Decisione | Scelta |
|---|-----------|--------|
| 3 | Margin intraday | **Specificato**; **disabilitato** in M0–M1; abilitabile M2+ |
| — | Meccanismo top-up | **Opzione 1:** annex UTXO, stesso script `2-of-3` |
| — | `margin_call_bps` | **12_000** (120%) |
| — | `liquidation_bps` | **10_500** (105%) |
| — | `grace_blocks` | **144** |
| — | Obbligo rifinanziamento | Solo **investor**; holder non versa margin |

---

## 13) Checklist test

- [ ] `coverage_bps` calcolato come §3 per fixture PAYOFF-SPEC §5 a metà deal.
- [ ] Margin call: `top_up_required_sats` corretto (esempio §10).
- [ ] Annex: `escrow_utxos` e `top_ups_sats` aggiornati; coverage torna ≥ `margin_call_bps`.
- [ ] Liquidazione: payout = `min(required, escrow)`; `investor_remainder` ≥ 0.
- [ ] Maturity con annex: PSBT multi-input; stesso payout che con escrow aggregato.
- [ ] Cancel / timelock: investor riceve `hedge_collateral_sats + top_ups_sats`.
- [ ] `margin_enabled = false` → nessuna call (regressione M0–M1).

---

## 14) Riferimenti

- [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md) — liability, settlement, insolvenza §7
- [`MULTISIG-SPEC.md`](MULTISIG-SPEC.md) — genesis escrow `2-of-3`, refund Path B
- [`P2P-OPTIONS.md`](P2P-OPTIONS.md) §10 — mapping liquidazione LTV 90% PoC Rails

---

## Sintesi

Con `margin_enabled`, il bot monitora `coverage_bps = escrow_total / required_sats(spot, liability)`. Sotto **120%** → call all’investor con **top-up** in **annex UTXO** (stesso multisig). Sotto **105%** dopo `grace_blocks` → **liquidazione anticipata** FloorEUR. Gli annex aumentano `escrow_total_sats` e sono restituiti all’investor in cancel/refund; in settlement/liquidazione partecipano al payout holder come qualsiasi altro sat in escrow.
