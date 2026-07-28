# Phase 3 - DLC On Device: Rails→Mobile Gap Analysis

**Obiettivo:** Identificare tutte le dipendenze Rails per DLC activation e settlement, e definire come sostituirle con logica on-device.

---

## Current Rails DLC Architecture

### Services da Eliminare (Fase 3)

| Service | LOC | Purpose | Complexity |
|---------|-----|---------|-----------|
| `Dlc::ContractSetupService` | ~200 | DLC contract creation, payout curve, funding tx | **ALTA** |
| `Dlc::SettlementService` | ~150 | CET execution, oracle attestation fetch | **ALTA** |
| `Dlc::NodeClient` | ~300 | HTTP client per dlc-rs sidecar | **MEDIA** |
| `Dlc::Distribution` | ~100 | L1 fan-out holder payouts | *(Fase 5)* |
| `Lib::Dlc::PayoutCurve` | ~150 | DLC payout points sampling | **MEDIA** |
| `Lib::Dlc::Numeric` | ~50 | Outcome digit helpers | **BASSA** |

**Totale:** ~950 LOC Rails da portare su device (Rust+Dart).

---

## Gap 1: DLC Contract Creation

### Rails Flow (Attuale)

```ruby
# app/services/budgets/activate_service.rb
def call
  # 1. Fetch oracle announcement
  announcement = oracle_client.announce_event(
    event_id: "#{budget.id}-maturity",
    maturity_timestamp: budget.maturity_timestamp
  )

  # 2. Calculate payout curve
  curve = Dlc::PayoutCurve.new(
    pool_sats: pool_sats,
    peg_sats: peg_sats,
    investor_sats: investor_sats,
    floor_eur_calculator: FloorEurCalculator
  )
  payout_points = curve.sample_points(n: 15)

  # 3. Select UTXOs from borrower + investor reserves
  peg_utxos = L1::UserWallet.for(borrower).select_utxos(peg_sats)
  investor_utxos = L1::UserWallet.for(investor).select_utxos(investor_sats)

  # 4. Call dlc-rs sidecar to create contract
  dlc_result = Dlc::NodeClient.create_contract(
    announcement: announcement,
    payout_function: payout_points,
    peg_inputs: peg_utxos,
    investor_inputs: investor_utxos,
    peg_change_address: borrower.reserve_address,
    investor_change_address: investor.reserve_address,
    investor_payout_address: investor.reserve_address
  )

  # 5. Sign funding tx with Rails wallets
  signed_funding_tx = L1::UserWallet.for(borrower).sign_psbt(dlc_result.funding_psbt)
  signed_funding_tx = L1::UserWallet.for(investor).sign_psbt(signed_funding_tx)

  # 6. Broadcast
  txid = Bitcoind::Client.new.sendrawtransaction(signed_funding_tx)

  # 7. Store contract data
  budget.update!(
    escrow_txid: txid,
    escrow_vout: dlc_result.funding_vout,
    dlc_contract_id: dlc_result.contract_id
  )
end
```

### Mobile Flow (Target Fase 3)

```dart
// Phase 3: On-device DLC activation

Future<void> activateDeal(Deal deal) async {
  // 1. Fetch oracle announcement (still from server)
  final announcement = await oracleClient.announceEvent(
    eventId: '${deal.id}-maturity',
    maturityTimestamp: deal.maturityTimestamp,
  );

  // 2. Calculate payout curve (mat-core via FFI)
  final curve = await MatCore.calculatePayoutCurve(
    poolSats: deal.poolSats,
    pegSats: deal.pegSats,
    investorSats: deal.investorSats,
    floor: deal.floorEur,
  );

  // 3. Select UTXOs (BDK - Phase 2 complete)
  final myUtxos = await bdkWallet.selectUtxos(deal.myCollateralSats);

  // 4. Create DLC offer (if borrower) or accept (if investor)
  if (deal.iAmBorrower) {
    // Borrower creates offer
    final offer = await MatDlc.createOffer(
      announcement: announcement,
      payoutCurve: curve,
      myInputs: myUtxos,
      myChangeAddress: await bdkWallet.getReceiveAddress(),
      myPayoutAddress: await bdkWallet.getReceiveAddress(),
    );

    // P2P: Send offer to investor (QR / Nostr / relay)
    await p2pChannel.sendOffer(offer, to: deal.investorId);

  } else {
    // Investor accepts offer
    final offer = await p2pChannel.receiveOffer(from: deal.borrowerId);

    final accept = await MatDlc.acceptOffer(
      offer: offer,
      myInputs: myUtxos,
      myChangeAddress: await bdkWallet.getReceiveAddress(),
      myPayoutAddress: await bdkWallet.getReceiveAddress(),
    );

    // Sign my part of funding tx
    final partiallySignedPsbt = await bdkWallet.signPsbt(accept.fundingPsbt);

    // P2P: Send signed PSBT back to borrower
    await p2pChannel.sendAccept(partiallySignedPsbt, to: deal.borrowerId);
  }

  // Borrower receives accept, signs their part, broadcasts
  if (deal.iAmBorrower) {
    final accept = await p2pChannel.receiveAccept(from: deal.investorId);
    final fullySignedPsbt = await bdkWallet.signPsbt(accept);

    // Finalize and broadcast
    final fundingTx = await MatDlc.finalizeFunding(fullySignedPsbt);
    final txid = await bdkWallet.broadcastTx(fundingTx);

    // Store contract
    deal.escrowTxid = txid;
    deal.status = DealStatus.active;
  }
}
```

### Gap Analysis

| Component | Rails | Mobile (Phase 3) | Status |
|-----------|-------|------------------|--------|
| Oracle announcement fetch | ✅ HTTP client | ✅ Keep (same API) | Ready |
| Payout curve calculation | ✅ Ruby | ❌ mat-core (Rust FFI) | **Need** |
| UTXO selection | ✅ Rails wallet | ✅ BDK (Phase 2) | Ready |
| DLC offer creation | ✅ dlc-rs sidecar | ❌ mat-dlc (Rust FFI) | **Need** |
| DLC accept/sign | ✅ dlc-rs sidecar | ❌ mat-dlc (Rust FFI) | **Need** |
| PSBT signing | ✅ Rails bitcoind | ✅ BDK (Phase 2) | Ready |
| P2P exchange | ❌ None (Rails is middleman) | ❌ New (QR/Nostr/relay) | **Need** |
| Funding tx broadcast | ✅ Rails bitcoind | ✅ BDK broadcast | Ready |

**Critical gaps:**
1. ❌ **mat-core FFI** (payout curve)
2. ❌ **mat-dlc FFI** (offer/accept/CET)
3. ❌ **P2P transport** (offer/accept exchange)

---

## Gap 2: Payout Curve Calculation

### Rails Implementation

```ruby
# lib/dlc/payout_curve.rb
class Dlc::PayoutCurve
  def sample_points(n:)
    # Sample n points from FloorEUR payout function
    oracle_outcomes = (0...2**oracle_digits).step(step_size)

    oracle_outcomes.map do |outcome|
      btc_eur = oracle_outcome_to_rate(outcome)
      peg_payout = floor_eur_calculator.holder_sats(
        btc_eur_rate: btc_eur,
        liability_eur: total_liability_eur
      )
      investor_payout = pool_sats - peg_payout

      [outcome, [peg_payout, investor_payout]]
    end
  end
end
```

### mat-core Implementation (Target)

```rust
// mat-core/src/payout_curve.rs

pub struct PayoutCurve {
    pub pool_sats: u64,
    pub floor_eur: Decimal,
    pub liability_eur: Decimal,
}

impl PayoutCurve {
    pub fn sample_points(&self, n_points: usize, oracle_base: u32, oracle_digits: u8) -> Vec<(u64, [u64; 2])> {
        let max_outcome = 2u64.pow(oracle_digits as u32);
        let step = max_outcome / (n_points as u64);

        (0..max_outcome)
            .step_by(step as usize)
            .map(|outcome| {
                let btc_eur_rate = numeric::outcome_to_rate(outcome, oracle_base);
                let holder_sats = floor_eur::calculate_holder_sats(
                    btc_eur_rate,
                    self.liability_eur,
                    self.pool_sats,
                );
                let investor_sats = self.pool_sats.saturating_sub(holder_sats);

                (outcome, [holder_sats, investor_sats])
            })
            .collect()
    }
}
```

### Flutter FFI Bindings (Generated)

```dart
// packages/mat_sdk/lib/mat_core.dart (generated by flutter_rust_bridge)

class MatCore {
  static Future<List<PayoutPoint>> calculatePayoutCurve({
    required int poolSats,
    required String floorEur,
    required String liabilityEur,
    required int nPoints,
    required int oracleBase,
    required int oracleDigits,
  }) async {
    // Calls Rust via FFI
    return _bindings.calculatePayoutCurve(...);
  }
}

class PayoutPoint {
  final int outcome;
  final int holderSats;
  final int investorSats;
}
```

**Status:** ✅ mat-core ha già `floor_eur` e `payout_curve` moduli. Serve solo FFI wrapper.

---

## Gap 3: DLC Contract Operations (dlc-rs → mat-dlc)

### Rails dlc-rs Sidecar

**Attuale:** Rails chiama HTTP sidecar che wrappa `rust-dlc` library.

```
Rails ──HTTP──▶ dlc-rs sidecar ──lib──▶ rust-dlc
```

**Problemi:**
- Shared custody (sidecar tiene chiavi)
- Richiede server-side deployment
- Non funziona su mobile

### Target: mat-dlc Embedded

```
Flutter App ──FFI──▶ mat-dlc (Rust) ──lib──▶ rust-dlc
```

**Cosa serve:**

#### 3.1 Port dlc-rs Sidecar → mat-dlc Library

```rust
// mat-dlc/src/lib.rs

pub struct DlcManager {
    secp: Secp256k1<All>,
}

impl DlcManager {
    /// Creates a DLC offer (borrower side)
    pub fn create_offer(
        &self,
        oracle_announcement: &OracleAnnouncement,
        payout_function: Vec<(u64, [u64; 2])>,
        collateral_sats: u64,
        my_inputs: Vec<TxIn>,
        my_change_spk: Script,
        my_payout_spk: Script,
    ) -> Result<DlcOffer, DlcError> {
        // Build DLC offer message
        // Generate funding output descriptor (2-of-2)
        // Create unsigned funding tx
        // Generate CETs for each outcome
        // Return offer struct
    }

    /// Accepts a DLC offer (investor side)
    pub fn accept_offer(
        &self,
        offer: &DlcOffer,
        my_collateral_sats: u64,
        my_inputs: Vec<TxIn>,
        my_change_spk: Script,
        my_payout_spk: Script,
    ) -> Result<DlcAccept, DlcError> {
        // Validate offer
        // Add my inputs to funding tx
        // Sign my CETs
        // Return accept message
    }

    /// Finalizes funding tx after both parties signed
    pub fn finalize_funding(
        &self,
        offer: &DlcOffer,
        accept: &DlcAccept,
        my_signatures: Vec<Signature>,
    ) -> Result<Transaction, DlcError> {
        // Combine signatures
        // Finalize funding PSBT
        // Return fully signed tx ready to broadcast
    }

    /// Executes CET at maturity
    pub fn execute_cet(
        &self,
        contract: &DlcContract,
        oracle_attestation: &OracleAttestation,
    ) -> Result<Transaction, DlcError> {
        // Verify attestation
        // Select correct CET based on outcome
        // Adapt signature with oracle secret
        // Return signed CET ready to broadcast
    }
}
```

#### 3.2 FFI Bindings

```dart
// packages/mat_sdk/lib/mat_dlc.dart

class MatDlc {
  static Future<DlcOffer> createOffer({
    required OracleAnnouncement announcement,
    required List<PayoutPoint> payoutCurve,
    required int collateralSats,
    required List<Utxo> myInputs,
    required String myChangeAddress,
    required String myPayoutAddress,
  }) async {
    // FFI call to mat-dlc
  }

  static Future<DlcAccept> acceptOffer({
    required DlcOffer offer,
    required int collateralSats,
    required List<Utxo> myInputs,
    required String myChangeAddress,
    required String myPayoutAddress,
  }) async {
    // FFI call to mat-dlc
  }

  static Future<String> finalizeFunding({
    required DlcOffer offer,
    required DlcAccept accept,
    required String mySignedPsbt,
  }) async {
    // FFI call to mat-dlc
    // Returns fully signed funding tx hex
  }

  static Future<String> executeCet({
    required DlcContract contract,
    required OracleAttestation attestation,
  }) async {
    // FFI call to mat-dlc
    // Returns signed CET hex
  }
}
```

**Stima effort:**
- Port dlc-rs sidecar logic: ~2-3k LOC Rust
- FFI bindings: ~500 LOC (generated + manual)
- Testing: ~1k LOC Rust + Dart

**Complessità:** **MOLTO ALTA** (crypto-critical code)

---

## Gap 4: P2P Offer/Accept Exchange

### Problema

Rails è attualmente il middleman:
```
Alice (borrower) ──HTTP──▶ Rails ──DB──▶ Bob (investor)
```

Fase 3 deve essere P2P:
```
Alice ───P2P───▶ Bob
```

### Transport Options

#### Option A: QR Code + Manual

**Pro:**
- Zero infrastructure
- User-friendly per deal face-to-face

**Con:**
- Non scala (Alice e Bob devono essere vicini)
- Due scansioni (offer → accept)

**Flow:**
```
Alice crea offer
  ↓
Alice mostra QR code
  ↓
Bob scansiona QR code
  ↓
Bob crea accept + firma
  ↓
Bob mostra QR code
  ↓
Alice scansiona QR code
  ↓
Alice firma e broadcasta
```

---

#### Option B: Nostr DM

**Pro:**
- Decentralizzato
- Persistent (messaggi salvati)
- Già esistente ecosystem

**Con:**
- Richiede Nostr keypair
- Privacy concerns (public relays)

**Integration:**
```dart
// Use nostr_dart package
class NostrP2PChannel {
  Future<void> sendOffer(DlcOffer offer, String recipientPubkey) async {
    final dm = NostrDirectMessage(
      content: jsonEncode(offer.toJson()),
      recipientPubkey: recipientPubkey,
    );
    await nostrClient.publish(dm);
  }

  Future<DlcOffer> receiveOffer(String senderPubkey) async {
    final messages = await nostrClient.fetchDMs(from: senderPubkey);
    final latestOffer = messages.first;
    return DlcOffer.fromJson(jsonDecode(latestOffer.content));
  }
}
```

---

#### Option C: Relay Blob Storage (Hybrid)

**Pro:**
- Semplice (HTTP POST/GET)
- Nessun account needed
- Encrypted payload

**Con:**
- Richiede relay server (trusted per metadata)
- Non decentralized come Nostr

**API Design:**
```
POST /api/v1/dlc_offers
{
  "recipient_user_id": "bob@example.com",
  "encrypted_offer": "base64...",
  "expires_at": "2026-07-29T10:00:00Z"
}

GET /api/v1/dlc_offers/pending
→ Returns encrypted offers for current user
```

**Mobile:**
```dart
class RelayP2PChannel {
  Future<void> sendOffer(DlcOffer offer, String recipientEmail) async {
    final encrypted = await encryptOffer(offer, recipientPublicKey);
    await apiClient.post('/api/v1/dlc_offers', {
      'recipient_user_id': recipientEmail,
      'encrypted_offer': encrypted,
    });
  }

  Future<DlcOffer?> pollPendingOffer() async {
    final response = await apiClient.get('/api/v1/dlc_offers/pending');
    if (response['offers'].isEmpty) return null;

    final encrypted = response['offers'][0]['encrypted_offer'];
    return decryptOffer(encrypted);
  }
}
```

---

### Recommendation: **Hybrid (C) for v1**

**Rationale:**
- QR (A) good for demo ma non pratico
- Nostr (B) aggiunge complessità (keypair management)
- Relay (C) minimal trust (solo metadata), user-friendly

**Future:** Aggiungere Nostr come opzione avanzata (Fase 4+).

---

## Gap 5: Oracle Attestation Fetch

### Rails Flow

```ruby
# app/services/settlements/execute_service.rb
def call
  oracle_attestation = oracle_client.fetch_attestation(
    event_id: "#{budget.id}-maturity"
  )

  # Verify signature
  unless oracle_attestation.verify?
    raise "Invalid oracle signature"
  end

  # Execute CET
  cet_result = Dlc::SettlementService.new(
    budget: budget,
    attestation: oracle_attestation
  ).call
end
```

### Mobile Flow (Fase 3)

```dart
Future<void> settleDeal(Deal deal) async {
  // 1. Fetch attestation from oracle
  final attestation = await oracleClient.fetchAttestation(
    eventId: '${deal.id}-maturity',
  );

  // 2. Verify oracle signature (mat-core)
  if (!await MatCore.verifyAttestation(attestation, deal.oraclePublicKey)) {
    throw Exception('Invalid oracle signature');
  }

  // 3. Execute CET (mat-dlc)
  final cetTx = await MatDlc.executeCet(
    contract: deal.dlcContract,
    attestation: attestation,
  );

  // 4. Broadcast CET
  await bdkWallet.broadcastTx(cetTx);

  // 5. Update deal status
  deal.status = DealStatus.settled;
}
```

**Gap:** ✅ Nessuno - oracle resta server-side (già deciso).

---

## Gap 6: Deal State Management

### Rails State Machine

```ruby
# app/models/budget.rb
class Budget < ApplicationRecord
  enum status: {
    pending: 0,      # Created, waiting investor
    active: 1,       # DLC funded
    settled: 2,      # CET executed
    cancelled: 3     # Refunded
  }
end
```

### Mobile State (Fase 3)

**Options:**

#### A) Keep Rails as Source of Truth
- Mobile polls `GET /api/v1/deals/:id`
- Rails DB tracks status
- Mobile is read-only display

**Pro:** Simple, no conflicts  
**Con:** Still dependent on Rails

---

#### B) Local-First, Sync to Rails
- Mobile SQLite stores deal state
- Background sync to Rails (optional)
- Rails becomes backup/metadata

**Pro:** Works offline, true self-custody  
**Con:** Conflict resolution needed

---

#### C) P2P State Sync
- No Rails DB
- Alice + Bob exchange status updates via P2P
- Local SQLite per device

**Pro:** Zero Rails dependency  
**Con:** Complex (what if Alice offline quando Bob settle?)

---

### Recommendation: **B) Local-First for Fase 3**

**Implementation:**
```dart
// Local SQLite schema
class DealsDatabase {
  Future<void> createTables() async {
    await db.execute('''
      CREATE TABLE deals (
        id TEXT PRIMARY KEY,
        status TEXT NOT NULL,  -- pending/active/settled
        borrower_id TEXT,
        investor_id TEXT,
        amount_eur REAL,
        escrow_txid TEXT,
        escrow_vout INTEGER,
        dlc_contract BLOB,  -- Serialized DlcContract
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
  }

  Future<void> updateDealStatus(String id, DealStatus status) async {
    await db.update('deals', {
      'status': status.name,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);

    // Optional: background sync to Rails
    _backgroundSyncToRelay(id);
  }
}
```

**Rails role (Fase 3):**
- Optional metadata backup
- Discovery (find other users)
- Oracle info (announcement, attestation)

---

## Summary: Critical Gaps

| Gap | Component | Status Phase 2 | Needed Phase 3 | Complexity |
|-----|-----------|----------------|----------------|-----------|
| 1 | Payout curve calc | ❌ None | ✅ mat-core FFI | MEDIA |
| 2 | DLC offer/accept | ❌ None | ✅ mat-dlc FFI | MOLTO ALTA |
| 3 | DLC CET execution | ❌ None | ✅ mat-dlc FFI | MOLTO ALTA |
| 4 | P2P transport | ❌ None | ✅ Relay blob storage | MEDIA |
| 5 | PSBT signing | ✅ BDK ready | ✅ Use BDK | BASSA (done) |
| 6 | UTXO selection | ✅ BDK ready | ✅ Use BDK | BASSA (done) |
| 7 | Funding broadcast | ✅ BDK ready | ✅ Use BDK | BASSA (done) |
| 8 | Oracle fetch | ✅ HTTP client | ✅ Keep same | BASSA (done) |
| 9 | Deal state | ❌ Rails DB | ✅ Local SQLite + sync | MEDIA |

**Blockers critici:**
1. ❌ **mat-dlc library non esiste** (port da dlc-rs sidecar)
2. ❌ **FFI bindings mat-dlc** (flutter_rust_bridge setup)
3. ❌ **P2P transport** (relay API o Nostr)

**Already solved (Phase 2):**
- ✅ UTXO selection (BDK)
- ✅ PSBT signing (BDK)
- ✅ Broadcast (BDK)

---

## Phase 3 Dependency Chain

```
Phase 2 Complete (BDK wallet)
    ↓
mat-core FFI (payout curve)
    ↓
mat-dlc library ────────────┐
    ↓                        │
mat-dlc FFI bindings         │
    ↓                        │
P2P transport (relay) ───────┤
    ↓                        │
Two-device test setup        │
    ↓                        │
Integration testing ←────────┘
    ↓
Phase 3 Complete
```

**Critical path bottleneck:** mat-dlc library development (~2-3 mesi effort).

---

## Recommended Approach

### Phase 3.0: Foundation
1. Setup mat-dlc Rust crate
2. Port dlc-rs core logic (no HTTP)
3. Unit tests (CET signing, offer/accept)

### Phase 3.1: FFI Integration
4. flutter_rust_bridge setup
5. Generate Dart bindings
6. Smoke test FFI calls

### Phase 3.2: P2P Transport
7. Implement relay blob storage API
8. Mobile P2P channel client
9. Encryption/decryption

### Phase 3.3: End-to-End
10. Two-device activation flow
11. Regtest integration test
12. Testnet real-money test

---

**Next:** Design P2P protocol wire format ([mobile-phase3-p2p-protocol.md](mobile-phase3-p2p-protocol.md))

---

**Related:**
- [mobile-phase2-bdk-roadmap.md](mobile-phase2-bdk-roadmap.md)
- [mobile-production-plan.md](mobile-production-plan.md)
- [dlc-rs/README.md](../dlc-rs/README.md) - Current sidecar implementation
