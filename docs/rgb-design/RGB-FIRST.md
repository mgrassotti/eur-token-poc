# RGB-first — da mirror a source of truth

Mini-design per convergere il PoC Rails da **ledger DB + mirror RGB** a **RGB come contabilità canonica**, con PostgreSQL come indice/cache derivato.

Stato attuale (post-M3): `TokenAccount` comanda; `RgbAssignment` + sidecar replicano dopo il fatto.

---

## 1) Stato attuale vs obiettivo

```text
OGGI (dual write)
  Activate  → TokenAccount.create!  →  Rgb::IssueService (mirror)
  Transfer  → TokenAccount −/+       →  Rgb::TransferService (mirror)
  Settlement→ legge TokenAccount
  Dashboard → TokenAccount + card RGB opzionale

OBIETTIVO (RGB-first)
  Activate  → Rgb::IssueService       →  proietta TokenAccount / RgbAssignment
  Transfer  → Rgb::TransferService    →  proietta TokenAccount / RgbAssignment
  Settlement→ legge saldi RGB (o proiezione sincronizzata)
  Dashboard → saldi da sidecar; DB solo metadata deal
```

**Invariante:** per ogni `budget_id` + `user_id`,  
`rgb_settled(asset_id)` = `rgb_assignments.notional_share_cents` = `token_accounts.balance_cents`  
(fino a deprecazione di `TokenAccount`).

---

## 2) Cosa resta in DB (sempre)

| Dato | Motivo |
|------|--------|
| `Budget` (peg, maturity, escrow refs, `rgb_asset_id`) | Metadata deal + anchor L1 |
| `CollateralLock`, campi L1 su `Budget` | Escrow BTC on-chain |
| `Settlement`, `MarketRate`, `ChainState` | Oracle / maturity |
| `TokenTransfer` (log) | Audit UI, link a `rgb_transfer_txid` |
| `BtcAccount` (`rgb_wallet_id`, `rgb_mnemonic`) | Mapping utente ↔ wallet RGB |
| `RgbAssignment` | **Proiezione** aggiornata da eventi RGB (non scritta in parallelo) |

**Candidata a deprecazione:** `TokenAccount` come source of truth → diventa vista/materializzazione opzionale per query SQL legacy.

---

## 3) Fasi di migrazione

### Fase A — Transfer RGB-first (primo passo, impatto alto / rischio medio)

**Perché prima:** è il flusso che oggi fa doppia scrittura esplicita; settlement e dashboard dipendono dai saldi post-transfer.

| Componente | Oggi | Dopo Fase A |
|------------|------|-------------|
| `Tokens::TransferService` | DB txn, poi mirror RGB | RGB send, poi proietta DB |
| `Rgb::LibTransferService` | aggiorna `rgb_assignments` | resta; diventa autoritativo |
| `TokenAccount` | scritto per primo | aggiornato da `Rgb::ProjectionService` |
| Validazione saldo | `balance_cents` | `sidecar.list_assets` settled per `rgb_asset_id` |

**Flusso proposto:**

```ruby
# Tokens::TransferService (nuovo)
1. Config.ensure_sidecar!
2. balance = Rgb::BalanceService.settled(user:, budget:)
3. raise se balance < amount_cents
4. Rgb::TransferService.call(...)   # on-chain
5. Rgb::ProjectionService.apply_transfer!(budget:, from:, to:, amount:)
   # aggiorna rgb_assignments + token_accounts in una txn DB
```

**Nuovi servizi:**

- `Rgb::BalanceService` — `list_assets(wallet_id)[nia]` filtrato per `budget.rgb_asset_id`, campo `balance.settled`
- `Rgb::ProjectionService` — unico punto che scrive `rgb_assignments` e (transitorio) `token_accounts`

**Spec:** estendere `rgb_lib_transfer_spec`; `transfer_service_spec` unitari mockano sidecar; regression su `WalletTransferService`.

---

### Fase B — Activate / issue RGB-first

| Componente | Oggi | Dopo Fase B |
|------------|------|-------------|
| `Budgets::ActivateService` | crea `TokenAccount` in txn | niente `TokenAccount` diretto |
| `L1::ProvisionEscrowService` | escrow poi `Rgb::IssueService` | invariato ordine L1 → RGB |
| `Rgb::LibIssueService` | già autoritativo on-chain | + `ProjectionService.apply_issue!` |

**Proiezione issue:**

```ruby
ProjectionService.apply_issue!(budget:, borrower:)
  # rgb_assignments: borrower = amount_eur_cents
  # token_accounts: stesso (transitorio)
```

Rimuovere `TokenAccount.create!` da `ActivateService` (riga 59–63).

---

### Fase C — Read path (dashboard, spendable)

| Componente | Oggi | Dopo Fase C |
|------------|------|-------------|
| `Tokens::Spendable` | `SUM(token_accounts.balance_cents)` | aggrega `Rgb::BalanceService` per deal attivi |
| `DashboardController` | `@my_fund_accounts` da `token_accounts` | lista deal + saldo RGB per `asset_id` |
| `WalletTransferService#spendable_accounts` | coin selection su `TokenAccount` | coin selection su saldi RGB (stessa logica, fonte diversa) |

**Cache (opzionale):** tabella `rgb_balance_snapshots (user_id, budget_id, settled_cents, refreshed_at)` aggiornata dopo ogni transfer/issue e su `dashboard#show` se stale > N secondi — evita N chiamate sidecar per utenti con molti deal.

---

### Fase D — Settlement RGB-first

| Componente | Oggi | Dopo Fase D |
|------------|------|-------------|
| `Settlements::ExecuteService` | `token_accounts.where(balance_cents > 0)` | holder da `rgb_assignments` o refresh sidecar pre-settle |
| Payoff | `holder_shares_cents` da DB | stesso array, fonte RGB |

**Precondizione settlement:**

```ruby
Rgb::SyncService.refresh_holders!(budget)  # refresh wallet di tutti gli holder noti
holders = budget.rgb_assignments.where("notional_share_cents > 0")
holder_shares_cents = holders.pluck(:notional_share_cents)
# assert: sum == budget.amount_eur_cents (conservazione)
```

Settlement L1 (PSBT) **resta invariato** — legge solo le quote holder, non il ledger token.

---

### Fase E — Deprecare `TokenAccount`

1. Rimuovere scritture in `ProjectionService` verso `token_accounts`
2. Migrare helper (`application_helper` mint_at, ecc.) su `RgbAssignment` / `TokenTransfer`
3. Migration: drop `token_accounts` o tenere tabella read-only per storico
4. Aggiornare PAYOFF-SPEC §9 mapping: `notional_share` → RGB settled, non `TokenAccount`

---

## 4) Ordine consigliato e milestone

| Fase | Milestone | Dipendenze |
|------|-----------|------------|
| **A** Transfer RGB-first | M3.1 | sidecar obbligatorio (fatto) |
| **B** Issue RGB-first | M3.2 | A stabile |
| **C** Read path | M3.3 | A+B; opzionale cache |
| **D** Settlement | M4 | C; refresh holder affidabile |
| **E** Drop TokenAccount | M4+ | D + suite verde |

**Non parallelizzare A e D:** settlement deve vedere saldi già RGB-first sui transfer.

---

## 5) Gestione errori e consistenza

| Scenario | Politica |
|----------|----------|
| RGB transfer OK, proiezione DB fallisce | **Rollback critico** — log alert; non esporre successo UI; job di riconciliazione |
| RGB transfer fallisce | nessuna modifica DB (oggi il DB può aggiornarsi prima — da invertire) |
| Sidecar giù | operazioni token bloccate (`ensure_sidecar!`); dashboard mostra ultima cache |
| Drift DB vs RGB | `Rgb::ReconcileService` (admin): confronta `list_assets` vs `rgb_assignments` |

**Transazione ideale (Fase A):** non esiste 2PC tra sidecar e Postgres. Pattern **outbox**:

1. RGB send (idempotency key = `token_transfer.id`)
2. Se OK → txn DB proiezione
3. Se DB fallisce → stato `token_transfers.rgb_status: pending_reconcile`

---

## 6) Modello asset (invariato)

- **1 NIA RGB20 per deal** (`budget.rgb_asset_id`)
- **1 wallet RGB per utente** (`user_{id}`)
- Transfer parziali = stesso `asset_id`, frazionamento tra holder
- Nessun EURT globale cross-deal: `WalletTransferService` resta coin selection su **più asset NIA** (uno per deal)

---

## 7) Impatto test

| Suite | Cambiamento |
|-------|-------------|
| Unit (non `:rgb_lib`) | stub `Rgb::BalanceService` + `ProjectionService` o sidecar fake |
| `:rgb_lib` integration | source of truth reale; assert solo RGB + proiezione |
| Settlement specs | Fase D: richiedono sidecar o stub holder da `rgb_assignments` |
| `l1_unit_stubs` | `stub_rgb_mirror!` → `stub_rgb_projection!` allineato al nuovo ordine |

---

## 8) Checklist implementativa

### Fase A (M3.1) — fatto

- [x] `Rgb::BalanceService`
- [x] `Rgb::ProjectionService.apply_transfer!`
- [x] Invertire ordine in `Tokens::TransferService`
- [x] `WalletTransferService` usa `BalanceService` per planning
- [x] `Rgb::LibTransferService` solo on-chain

### Fase B (M3.2) — fatto

- [x] `Rgb::IssueResult` + `LibIssueService` solo on-chain
- [x] `ProjectionService.apply_issue!`
- [x] `Rgb::IssueService` orchestra lib → proiezione
- [x] Rimosso `TokenAccount.create!` da `ActivateService`

### Fase C (M3.3) — fatto

- [x] `Tokens::Spendable` legge saldi via `Rgb::BalanceService` (`Position` per deal)
- [x] Dashboard fondi (`@my_fund_accounts`) da `Spendable.fund_positions_for`
- [x] `WalletTransferService` coin selection su `Spendable.positions_for`

---

## 9) Riferimenti

- [`PAYOFF-SPEC.md`](PAYOFF-SPEC.md) §9 — mapping `notional_share`
- [`P2P-OPTIONS.md`](P2P-OPTIONS.md) §10 — gap DB → assignment RGB
- `app/services/tokens/transfer_service.rb` — punto di inversione principale
- `app/services/settlements/execute_service.rb` — consumer holder shares (Fase D)
