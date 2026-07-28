# Phase 2 - BDK Wallet on Device: Roadmap Dettagliata

**Obiettivo:** Portare la gestione reserve L1 da Rails (bitcoind RPC) a mobile (BDK + Esplora).

**Exit Criteria:**
- Utente può generare mnemonic e backup su device
- Utente può ricevere BTC su address generato da BDK
- App sincronizza balance via Esplora (no bitcoind RPC)
- App può firmare PSBT per DLC funding (preparazione Fase 3)
- Nessun flusso deposit/reserve dipende più da Rails L1 services

---

## Task Breakdown

### 1. BDK FFI Integration

#### 1.1 Setup FFI Bridge
**Prerequisiti:**
- `bdk_flutter: ^0.31.3` (già in `feature/mobile-independence-phase0-2`)
- Rust toolchain (per rebuild native libs se necessario)

**Tasks:**
- [ ] Verificare compatibilità BDK version con target iOS/Android
- [ ] Test build nativo iOS (Xcode)
- [ ] Test build nativo Android (Gradle)
- [ ] Setup CI per rebuild BDK se aggiornato
- [ ] Documentare platform-specific quirks

**Rischi:**
- BDK native build può fallire su M1 Mac (workaround esistenti)
- Android NDK version mismatch

**Stima complessità:** BASSA (già integrato come spike)

---

#### 1.2 Wallet Service Refactor
**Attuale:** `LocalWalletService` è uno stub/debug.

**Da fare:**
- [ ] Estrarre interface `WalletApi`:
  ```dart
  abstract class WalletApi {
    Future<String> createWallet(String mnemonic);
    Future<String> getReceiveAddress();
    Future<int> getBalance();
    Future<void> sync();
    Future<String> signPsbt(String psbt);
  }
  ```
- [ ] Implementare `BdkWalletService implements WalletApi`
- [ ] Mock `FakeWalletService` per testing senza BDK
- [ ] Dependency injection in `app_state.dart`

**Rischi:**
- Sync timing variabile (Electrum può essere lento)
- Error handling per network failures

**Stima complessità:** MEDIA

---

### 2. Mnemonic Generation & Backup

#### 2.1 First-Time Setup Flow
**UI Screens:**
- [ ] `WalletSetupScreen`:
  - "Create new wallet" button
  - Show 12-word mnemonic
  - Checkbox "I saved my backup phrase"
  - Warning: "Never share this phrase"
- [ ] `WalletConfirmScreen`:
  - User re-enters 3 random words per conferma
  - Proceed solo se corretto

**Backend:**
- [ ] `BdkWalletService.createWallet()`:
  - Generate 12-word mnemonic (BDK)
  - Derive descriptor (BIP84 native segwit)
  - Persist encrypted wallet DB (BDK SQLite)
- [ ] Secure storage del mnemonic (opzionale):
  - iOS: Keychain
  - Android: EncryptedSharedPreferences
  - Warning: Backup cartaceo è più sicuro

**Localizzazione:**
- [ ] Stringhe EN/IT per wallet setup

**Rischi:**
- Utente perde mnemonic → fondi persi (UX deve essere chiara)
- Secure storage può avere bug (fallback a warning)

**Stima complessità:** MEDIA

---

#### 2.2 Wallet Recovery
**UI:**
- [ ] `WalletRecoveryScreen`:
  - TextFields per 12 parole
  - Autocomplete wordlist BIP39
  - Validation in real-time
  - "Restore wallet" button

**Backend:**
- [ ] `BdkWalletService.restoreWallet(String mnemonic)`:
  - Validate mnemonic (BIP39)
  - Derive descriptor
  - Full sync (può richiedere minuti)
  - Progress indicator

**Testing:**
- [ ] Test recovery da backup noto (regtest)
- [ ] Test recovery con typo (fail gracefully)
- [ ] Test recovery con wallet già esistente (overwrite warning)

**Rischi:**
- Sync iniziale può timeout (gestire con retry)
- Utente inserisce mnemonic sbagliato (validazione chiara)

**Stima complessità:** MEDIA

---

### 3. Receive Address & Balance

#### 3.1 Replace Rails Reserve Address
**Attuale:** `POST /api/v1/reserve` → Rails genera address da bitcoind.

**Nuovo flusso:**
- [ ] `AddFundsScreen` chiama `BdkWalletService.getReceiveAddress()`
- [ ] BDK genera address BIP84 (bc1q... per mainnet, bcrt1... per regtest)
- [ ] Show QR code (già implementato)
- [ ] "Copy address" (già implementato)

**Backend:**
- [ ] `BdkWalletService.getReceiveAddress()`:
  - `wallet.getAddress(addressIndex: AddressIndex.lastUnused())`
  - Cache ultimo address per evitare address reuse

**Rails deprecation:**
- [ ] Mantenere `GET /api/v1/reserve` per compatibilità Fase 1
- [ ] Aggiungere flag `use_local_wallet: bool` in `SettingsState`
- [ ] If `use_local_wallet == true` → skip Rails reserve endpoint

**Testing:**
- [ ] Generate address regtest
- [ ] Verify address format (bech32 for mainnet, bech32 for regtest)
- [ ] QR code scan test

**Rischi:**
- Address reuse (risolto con `lastUnused()`)
- Network mismatch (regtest vs testnet vs mainnet)

**Stima complessità:** BASSA

---

#### 3.2 Balance Sync via Esplora
**Attuale:** Rails chiama `bitcoind getbalance`.

**Nuovo flusso:**
- [ ] `BdkWalletService.sync()`:
  - Connect to Electrum (regtest: `127.0.0.1:50001`)
  - `blockchain.sync()`
  - Return new balance
- [ ] `AddFundsScreen` polling ogni N secondi (10s?)
- [ ] Pull-to-refresh gesture

**Config:**
- [ ] `WalletConfig.regtestElectrumUrl` (già creato)
- [ ] Support per testnet/mainnet Electrum URLs
- [ ] Timeout configurabile (già `regtestElectrumTimeoutSec: 15`)

**Testing:**
- [ ] Sync su wallet vuoto → balance 0
- [ ] Admin funds address → sync → balance updated
- [ ] Sync failure (Electrum down) → error message + retry

**Rails deprecation:**
- [ ] `POST /api/v1/reserve/sync` diventa no-op se `use_local_wallet`

**Rischi:**
- Electrum regtest su `./bin/regtest up` potrebbe non essere subito ready
- Timing: sync dopo funding richiede ~5-10s (electrs indexing)

**Stima complessità:** MEDIA

---

### 4. PSBT Signing for DLC Funding

#### 4.1 Coin Selection
**Attuale:** Rails `L1::UserWallet.select_utxos_for_sats(amount)`

**Nuovo flusso:**
- [ ] `BdkWalletService.selectUtxos(int amountSats)`:
  - `wallet.listUnspent()`
  - Custom coin selection logic (smallest-first? largest-first?)
  - Return lista UTXO per funding
- [ ] Validation: balance >= amountSats + fee buffer

**Testing:**
- [ ] Select da wallet con 1 UTXO
- [ ] Select da wallet con N UTXOs
- [ ] Fail se insufficient funds

**Rischi:**
- Coin selection strategy diversa da Rails → DLC tests potrebbero fallire
- Fee estimation (BDK ha fee estimator, Rails usa fisso)

**Stima complessità:** ALTA (critical per Fase 3)

---

#### 4.2 PSBT Signing
**Attuale:** Rails firma PSBT con bitcoind `walletprocesspsbt`.

**Nuovo flusso (preparazione Fase 3):**
- [ ] `BdkWalletService.signPsbt(String psbtBase64)`:
  - Parse PSBT
  - `wallet.sign(psbt)`
  - Return signed PSBT (partial per 2-of-2)
- [ ] Non broadcast (Fase 3 gestirà broadcast dopo controparte firma)

**Testing:**
- [ ] Sign PSBT con singolo input
- [ ] Sign PSBT con N inputs
- [ ] Verify signature con `finalizePsbt()` (solo testing)

**Rischi:**
- PSBT format mismatch Rails ↔ BDK
- Descriptor mismatch (BIP84 deve match Rails setup)

**Stima complessità:** ALTA (critical per Fase 3)

---

### 5. Integration with Existing Flows

#### 5.1 Dashboard Reserve Balance
**Attuale:** `GET /api/v1/dashboard` → Rails legge `btc_accounts.balance_sats`

**Nuovo flusso:**
- [ ] If `use_local_wallet`:
  - Dashboard legge `BdkWalletService.getBalance()`
  - No chiamata `/api/v1/dashboard` per reserve
- [ ] Else:
  - Keep current behavior

**UI:**
- [ ] Badge "Local wallet" su dashboard se `use_local_wallet == true`
- [ ] Sync button per force refresh

**Testing:**
- [ ] Toggle `use_local_wallet` in Settings
- [ ] Dashboard aggiorna balance da BDK

**Stima complessità:** BASSA

---

#### 5.2 Top-Up Deal (Phase 3 prep)
**Attuale:** `Budgets::CreateService` → select UTXOs da Rails wallet

**Nuovo flusso (skeleton Fase 3):**
- [ ] `POST /api/v1/deals` passa `funding_utxos` in payload (Fase 3)
- [ ] Rails valida ma non seleziona (utente già selezionò via BDK)
- [ ] Fase 2: ancora usa Rails per activation (Fase 3 sostituirà)

**Stima complessità:** BASSA (prep only)

---

### 6. Testing Strategy

#### 6.1 Unit Tests
- [ ] `BdkWalletService`:
  - Mock BDK responses
  - Test address generation
  - Test balance calculation
  - Test PSBT signing
- [ ] `WalletConfig`:
  - Test Electrum URL platform selection

**Tools:**
- `flutter_test` + `mockito`

---

#### 6.2 Integration Tests
- [ ] Full flow regtest:
  - Create wallet
  - Generate address
  - Admin funds via `rails.fundRegtestAddress()` (già creato!)
  - Sync balance
  - Assert balance == funded amount
- [ ] Recovery flow:
  - Create wallet
  - Save mnemonic
  - Delete wallet DB
  - Restore da mnemonic
  - Assert address match

**Tools:**
- `integration_test/wallet_bdk_test.dart`
- `RailsTestBridge.fundRegtestAddress()` (già disponibile)

---

#### 6.3 E2E Tests
- [ ] Multi-user regtest:
  - Alice: BDK wallet
  - Bob: BDK wallet
  - Alice creates deal (Rails still handles DLC)
  - Bob accepts (Rails still handles DLC)
  - Verify UTXOs selected correttamente

**Blockers Fase 3:**
- [ ] DLC activation richiede Fase 3 (P2P signing)
- [ ] Per ora: test solo deposit/balance

---

### 7. Documentation

#### 7.1 User Docs
- [ ] `mobile/docs/wallet-backup.md`:
  - Come fare backup mnemonic
  - Recovery procedure
  - Security best practices

#### 7.2 Developer Docs
- [ ] `mobile/docs/bdk-architecture.md`:
  - BDK FFI flow diagram
  - WalletApi interface
  - Electrum config

#### 7.3 Migration Guide
- [ ] `docs/rails-to-mobile-phase2-migration.md`:
  - Quali endpoint Rails deprecati
  - Backward compatibility flags
  - Testing checklist

---

## Dependency Chain

```
1.1 BDK FFI Setup
    ↓
1.2 Wallet Service Refactor
    ↓
2.1 Mnemonic Generation ────┐
    ↓                        │
2.2 Wallet Recovery          │
    ↓                        │
3.1 Receive Address ←────────┘
    ↓
3.2 Balance Sync
    ↓
4.1 Coin Selection ──→ 4.2 PSBT Signing ──→ (Fase 3: DLC activation)
    ↓
5.1 Dashboard Integration
    ↓
5.2 Deal Top-Up Prep
    ↓
6.1-6.3 Testing
    ↓
7.1-7.3 Documentation
```

**Critical Path:**
1. FFI setup → Wallet refactor → Mnemonic → Receive address → Sync balance
2. In parallelo: Coin selection + PSBT signing (prep Fase 3)
3. Integration testing

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| BDK native build fails | **HIGH** - blocca tutto | Test su iOS/Android early; fallback a older BDK version |
| Electrum regtest timing | **MEDIUM** - tests flaky | Increase timeout; add retry logic |
| Coin selection mismatch | **HIGH** - DLC fails Fase 3 | Test vectors from Rails; document differences |
| Mnemonic loss | **CRITICAL** - user funds | Strong UX warnings; backup confirmation flow |
| PSBT format incompatibility | **HIGH** - Fase 3 blocco | Early PSBT round-trip tests con Rails |

---

## Phase 2 Complete Checklist

- [ ] BDK builds su iOS/Android
- [ ] Wallet creation + recovery funzionano
- [ ] Address generation BIP84 corretto
- [ ] Balance sync via Electrum regtest
- [ ] PSBT signing tested (anche se non usato ancora)
- [ ] Integration tests green
- [ ] `use_local_wallet` flag funziona
- [ ] Docs complete
- [ ] Zero dipendenze da `L1::UserWallet`, `L1::DepositReserveService`, `L1::SyncReserveBalanceService`

**Quando tutto ✅ → Fase 3 (DLC) può iniziare.**

---

## Estimated Effort (Technical Complexity)

| Task Group | Complexity | Notes |
|------------|-----------|-------|
| 1. BDK FFI | BASSA | Già integrato come spike |
| 2. Mnemonic/Backup | MEDIA | UX critical ma straightforward |
| 3. Address/Balance | BASSA | BDK API diretta |
| 4. PSBT Signing | ALTA | Critical per Fase 3; richiede testing estensivo |
| 5. Integration | MEDIA | Refactor UI esistente |
| 6. Testing | ALTA | E2E regtest può essere flaky |
| 7. Docs | BASSA | Writing |

**Totale:** ~15-25 task principali, alcuni sequenziali (critical path ~8-10 task).

**Next Action:** Iniziare con Task 1.2 (Wallet Service Refactor) su branch esistente `feature/mobile-independence-phase0-2`.
