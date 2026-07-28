# Phase 3 - P2P DLC Protocol Design

**Obiettivo:** Definire wire format e transport per scambio peer-to-peer di DLC offer/accept messages tra borrower e investor.

---

## Requirements

### Functional

- ✅ Borrower can send DLC offer to investor
- ✅ Investor can accept offer and return signed PSBT
- ✅ Both parties can verify message authenticity
- ✅ Support async exchange (investor offline quando borrower crea offer)
- ✅ Timeout/expiry handling

### Non-Functional

- ✅ Privacy: Contents encrypted (relay can't read deal terms)
- ✅ Integrity: Message tampering detected
- ✅ Minimal trust: Relay sees only metadata (user IDs, timestamp)
- ✅ UX: Simple flow (no manual key exchange)

---

## Wire Format

### Message Types

```json
{
  "version": 1,
  "type": "dlc_offer" | "dlc_accept",
  "sender_id": "alice@example.com",
  "recipient_id": "bob@example.com",
  "timestamp": 1722163200,
  "expires_at": 1722166800,  // 1 hour expiry
  "payload": "encrypted_base64..."
}
```

### Payload: DLC Offer (Encrypted)

```json
{
  "deal_id": "uuid-1234",
  "deal_terms": {
    "amount_eur": 1000,
    "months": 1,
    "rate_per_month": 0.3,
    "maturity_timestamp": 1725000000
  },
  "oracle": {
    "public_key": "hex...",
    "announcement": "serialized_announcement_hex",
    "event_id": "deal-1234-maturity"
  },
  "payout_curve": [
    { "outcome": 0, "holder_sats": 0, "investor_sats": 2000000 },
    { "outcome": 16384, "holder_sats": 500000, "investor_sats": 1500000 },
    ...
  ],
  "funding": {
    "my_collateral_sats": 500000,  // Borrower peg collateral
    "my_inputs": [
      { "txid": "abc123", "vout": 0, "value_sats": 600000, "script_pubkey": "hex" }
    ],
    "my_change_address": "bcrt1q...",
    "my_payout_address": "bcrt1q..."
  },
  "dlc_contract": {
    "funding_pubkey": "hex...",  // Borrower's 2-of-2 key
    "cet_signatures": ["hex...", "hex..."]  // Borrower's CET sigs (pre-signed)
  }
}
```

### Payload: DLC Accept (Encrypted)

```json
{
  "deal_id": "uuid-1234",
  "offer_hash": "sha256_of_offer",  // Verify offer not tampered
  "funding": {
    "my_collateral_sats": 1500000,  // Investor collateral
    "my_inputs": [
      { "txid": "def456", "vout": 1, "value_sats": 1600000, "script_pubkey": "hex" }
    ],
    "my_change_address": "bcrt1q...",
    "my_payout_address": "bcrt1q..."
  },
  "dlc_contract": {
    "funding_pubkey": "hex...",  // Investor's 2-of-2 key
    "cet_signatures": ["hex...", "hex..."]  // Investor's CET sigs
  },
  "funding_psbt": "base64_psbt..."  // Partially signed (investor's inputs)
}
```

---

## Encryption Scheme

### Option A: Symmetric (Shared Secret from Deal ID)

**Naive but simple:**
```dart
final key = sha256(dealId + sharedSecret);
final encrypted = AES-GCM.encrypt(payload, key, nonce);
```

**Pro:** No public key exchange needed  
**Con:** Weak (attacker with deal ID can decrypt)

---

### Option B: Asymmetric (User Public Keys)

**Better security:**
```dart
// Each user has Ed25519 keypair (stored in secure storage)
final senderPrivateKey = await secureStorage.read('my_private_key');
final recipientPublicKey = await fetchUserPublicKey(recipientId);

// ECDH shared secret
final sharedSecret = ECDH.derive(senderPrivateKey, recipientPublicKey);

// Encrypt payload
final encrypted = ChaCha20Poly1305.encrypt(payload, sharedSecret, nonce);
```

**Pro:** Strong crypto, replay protection with nonce  
**Con:** Requires public key distribution (via relay or cert)

---

### Recommendation: **Option B (ECIES)**

**Implementation:**
```dart
// packages/mat_sdk/lib/crypto/ecies.dart

import 'package:cryptography/cryptography.dart';

class Ecies {
  final algorithm = Xchacha20.poly1305Aead();

  Future<String> encrypt({
    required String plaintext,
    required String recipientPublicKeyHex,
    required String myPrivateKeyHex,
  }) async {
    // Parse keys
    final recipientPubKey = SimplePublicKey(hex.decode(recipientPublicKeyHex), type: KeyPairType.x25519);
    final myPrivKey = SimpleKeyPairData(hex.decode(myPrivateKeyHex), type: KeyPairType.x25519);

    // ECDH
    final sharedSecret = await algorithm.keyExchangeType!.sharedSecretKey(
      keyPair: myPrivKey,
      remotePublicKey: recipientPubKey,
    );

    // Encrypt
    final nonce = algorithm.newNonce(); // Random 24 bytes
    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: sharedSecret,
      nonce: nonce,
    );

    // Return: nonce + ciphertext + mac
    return base64.encode([...nonce, ...secretBox.cipherText, ...secretBox.mac.bytes]);
  }

  Future<String> decrypt({
    required String ciphertext,
    required String senderPublicKeyHex,
    required String myPrivateKeyHex,
  }) async {
    // Parse
    final bytes = base64.decode(ciphertext);
    final nonce = bytes.sublist(0, 24);
    final ciphertextBytes = bytes.sublist(24, bytes.length - 16);
    final mac = Mac(bytes.sublist(bytes.length - 16));

    // ECDH
    final senderPubKey = SimplePublicKey(hex.decode(senderPublicKeyHex), type: KeyPairType.x25519);
    final myPrivKey = SimpleKeyPairData(hex.decode(myPrivateKeyHex), type: KeyPairType.x25519);

    final sharedSecret = await algorithm.keyExchangeType!.sharedSecretKey(
      keyPair: myPrivKey,
      remotePublicKey: senderPubKey,
    );

    // Decrypt
    final secretBox = SecretBox(ciphertextBytes, nonce: nonce, mac: mac);
    final plaintext = await algorithm.decrypt(secretBox, secretKey: sharedSecret);

    return utf8.decode(plaintext);
  }
}
```

---

## Transport Layer

### Relay API Endpoints

#### POST /api/v1/p2p/messages

**Request:**
```json
{
  "recipient_user_id": "bob@example.com",
  "message_type": "dlc_offer",
  "encrypted_payload": "base64...",
  "expires_at": "2026-07-28T11:00:00Z"
}
```

**Response:**
```json
{
  "message_id": "msg-uuid-1234",
  "status": "pending",
  "created_at": "2026-07-28T10:00:00Z"
}
```

---

#### GET /api/v1/p2p/messages/inbox

**Response:**
```json
{
  "messages": [
    {
      "message_id": "msg-uuid-1234",
      "sender_user_id": "alice@example.com",
      "message_type": "dlc_offer",
      "encrypted_payload": "base64...",
      "created_at": "2026-07-28T10:00:00Z",
      "expires_at": "2026-07-28T11:00:00Z"
    }
  ]
}
```

---

#### DELETE /api/v1/p2p/messages/:id

Mark message as read/processed.

---

### Mobile Client

```dart
// lib/services/p2p_channel.dart

class P2PChannel {
  final RelayApiClient _apiClient;
  final Ecies _crypto;

  Future<void> sendDlcOffer({
    required String recipientId,
    required DlcOffer offer,
  }) async {
    // 1. Serialize offer
    final plaintext = jsonEncode(offer.toJson());

    // 2. Fetch recipient's public key
    final recipientPubKey = await _fetchPublicKey(recipientId);

    // 3. Encrypt
    final encrypted = await _crypto.encrypt(
      plaintext: plaintext,
      recipientPublicKeyHex: recipientPubKey,
      myPrivateKeyHex: await _getMyPrivateKey(),
    );

    // 4. Send to relay
    await _apiClient.post('/api/v1/p2p/messages', {
      'recipient_user_id': recipientId,
      'message_type': 'dlc_offer',
      'encrypted_payload': encrypted,
      'expires_at': DateTime.now().add(Duration(hours: 1)).toIso8601String(),
    });
  }

  Future<DlcOffer?> pollDlcOffer() async {
    // 1. Fetch inbox
    final response = await _apiClient.get('/api/v1/p2p/messages/inbox');
    final messages = response['messages'] as List;

    // 2. Filter DLC offers
    final offers = messages.where((m) => m['message_type'] == 'dlc_offer');
    if (offers.isEmpty) return null;

    // 3. Decrypt latest offer
    final latestOffer = offers.first;
    final senderPubKey = await _fetchPublicKey(latestOffer['sender_user_id']);

    final decrypted = await _crypto.decrypt(
      ciphertext: latestOffer['encrypted_payload'],
      senderPublicKeyHex: senderPubKey,
      myPrivateKeyHex: await _getMyPrivateKey(),
    );

    // 4. Mark as read
    await _apiClient.delete('/api/v1/p2p/messages/${latestOffer['message_id']}');

    // 5. Parse offer
    return DlcOffer.fromJson(jsonDecode(decrypted));
  }

  Future<String> _fetchPublicKey(String userId) async {
    // GET /api/v1/users/:id/public_key
    final response = await _apiClient.get('/api/v1/users/$userId/public_key');
    return response['public_key'];
  }

  Future<String> _getMyPrivateKey() async {
    // Stored in secure storage (generated on first run)
    final priv = await FlutterSecureStorage().read(key: 'ecies_private_key');
    if (priv == null) {
      // Generate new keypair
      final keyPair = await X25519().newKeyPair();
      final privBytes = await keyPair.extractPrivateKeyBytes();
      final pubKey = await keyPair.extractPublicKey();

      await FlutterSecureStorage().write(key: 'ecies_private_key', value: hex.encode(privBytes));
      await FlutterSecureStorage().write(key: 'ecies_public_key', value: hex.encode(pubKey.bytes));

      // Upload public key to relay
      await _apiClient.post('/api/v1/users/me/public_key', {
        'public_key': hex.encode(pubKey.bytes),
      });

      return hex.encode(privBytes);
    }
    return priv;
  }
}
```

---

## Flow Diagram: Full DLC Activation

```
Alice (Borrower)                          Relay                       Bob (Investor)
     │                                      │                               │
     ├─ Create deal locally                │                               │
     │  (amount, months, rate)              │                               │
     │                                      │                               │
     ├─ Fetch oracle announcement ─────────┤                               │
     │                                      │                               │
     ├─ Calculate payout curve (mat-core)  │                               │
     │                                      │                               │
     ├─ Select UTXOs (BDK)                 │                               │
     │                                      │                               │
     ├─ Create DLC offer (mat-dlc)         │                               │
     │                                      │                               │
     ├─ Encrypt offer (ECIES)              │                               │
     │                                      │                               │
     ├─ POST /p2p/messages ────────────────▶                               │
     │   (encrypted offer)                  │                               │
     │                                      │                               │
     ├─ Poll for accept... (wait)          │                               │
     │                                      │                               │
     │                                      │  ◀─ GET /p2p/messages/inbox ─┤
     │                                      │    (polling every 5s)         │
     │                                      │                               │
     │                                      │  ─────────────────────────────▶
     │                                      │    (encrypted offer)           │
     │                                      │                               │
     │                                      │                               ├─ Decrypt offer (ECIES)
     │                                      │                               │
     │                                      │                               ├─ Validate offer
     │                                      │                               │  (check payout curve, terms)
     │                                      │                               │
     │                                      │                               ├─ Select UTXOs (BDK)
     │                                      │                               │
     │                                      │                               ├─ Accept offer (mat-dlc)
     │                                      │                               │  (generate CET sigs)
     │                                      │                               │
     │                                      │                               ├─ Sign funding PSBT (BDK)
     │                                      │                               │
     │                                      │                               ├─ Encrypt accept (ECIES)
     │                                      │                               │
     │                                      │  ◀─ POST /p2p/messages ──────┤
     │                                      │    (encrypted accept)         │
     │                                      │                               │
     │  ◀─ GET /p2p/messages/inbox ────────┤                               │
     │    (encrypted accept)                │                               │
     │                                      │                               │
     ├─ Decrypt accept (ECIES)             │                               │
     │                                      │                               │
     ├─ Validate accept                    │                               │
     │  (verify CET sigs, PSBT)            │                               │
     │                                      │                               │
     ├─ Sign funding PSBT (BDK)            │                               │
     │  (my inputs)                         │                               │
     │                                      │                               │
     ├─ Finalize PSBT (mat-dlc)            │                               │
     │                                      │                               │
     ├─ Broadcast funding tx (BDK) ────────┼───────────────────────────────▶ Bitcoin L1
     │                                      │                               │
     ├─ Deal status: active                │                               │
     │                                      │                               ├─ Monitor funding tx
     │                                      │                               │
     │                                      │                               ├─ Deal status: active
```

**Total round-trips:** 2 (offer → accept)

**Latency:**
- Polling interval: 5 seconds
- Expected activation time: 10-30 seconds (investor online)
- If investor offline: up to 1 hour (expiry)

---

## Expiry & Timeout Handling

### Offer Expiry

**Problem:** Investor offline for hours → offer stale (BTC price moved, UTXOs spent).

**Solution:**
```dart
class DlcOffer {
  DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// Investor checks before accepting
Future<void> acceptOffer(DlcOffer offer) async {
  if (offer.isExpired) {
    throw OfferExpiredException('Offer expired at ${offer.expiresAt}');
  }
  // Proceed...
}
```

**Expiry duration:** 1 hour (configurable).

---

### Accept Timeout

**Problem:** Borrower waiting indefinitely for accept.

**Solution:**
```dart
Future<DlcAccept?> waitForAccept(String dealId) async {
  final deadline = DateTime.now().add(Duration(minutes: 10));

  while (DateTime.now().isBefore(deadline)) {
    final accept = await p2pChannel.pollDlcAccept();
    if (accept != null && accept.dealId == dealId) {
      return accept;
    }

    await Future.delayed(Duration(seconds: 5)); // Poll every 5s
  }

  // Timeout
  return null;
}

// UI shows: "Waiting for investor... (8:32 remaining)"
```

**Timeout:** 10 minutes (investor deve accettare entro questo tempo).

---

## Error Handling

### Offer Validation (Investor Side)

```dart
class OfferValidator {
  void validate(DlcOffer offer) {
    // 1. Check oracle announcement signature
    if (!offer.oracle.announcement.verifySignature(offer.oracle.publicKey)) {
      throw InvalidOfferException('Invalid oracle signature');
    }

    // 2. Check payout curve sums to pool
    final totalPayout = offer.payoutCurve.first.holderSats + offer.payoutCurve.first.investorSats;
    final expectedPool = offer.funding.myCollateralSats + _myCollateralSats;
    if (totalPayout != expectedPool) {
      throw InvalidOfferException('Payout curve sum mismatch');
    }

    // 3. Check maturity timestamp reasonable
    if (offer.dealTerms.maturityTimestamp < DateTime.now().millisecondsSinceEpoch) {
      throw InvalidOfferException('Maturity is in the past');
    }

    // 4. Check deal terms match app constraints
    if (offer.dealTerms.months > 12) {
      throw InvalidOfferException('Max 12 months deals supported');
    }

    // 5. Check funding inputs valid (not double-spent)
    for (final input in offer.funding.myInputs) {
      if (await _isUtxoSpent(input.txid, input.vout)) {
        throw InvalidOfferException('Input already spent: ${input.txid}:${input.vout}');
      }
    }
  }
}
```

---

### Network Errors

```dart
try {
  await p2pChannel.sendDlcOffer(offer: offer, recipientId: investorId);
} on HttpException catch (e) {
  if (e.statusCode == 404) {
    throw UserNotFoundException('Investor not found');
  } else if (e.statusCode == 429) {
    throw RateLimitException('Too many messages, try again later');
  } else {
    throw NetworkException('Failed to send offer: ${e.message}');
  }
}
```

---

## Security Considerations

### Replay Attack

**Attack:** Attacker intercepts `dlc_accept` message, replays it later.

**Mitigation:**
- Each offer has unique `deal_id` (UUID)
- Relay stores processed message IDs (dedupe)
- Nonce in encryption (AEAD mode)

---

### Man-in-the-Middle

**Attack:** Relay substitutes investor's public key with attacker's key.

**Mitigation:**
- Public keys certified via:
  - Option A: User verifies fingerprint out-of-band (QR code)
  - Option B: Relay signs public keys with HTTPS cert (trust relay CA)
  - Option C: Web of trust (users sign each other's keys)

**Recommendation:** Option B for v1 (pragmatic), Option C for future.

---

### Denial of Service

**Attack:** Flood relay with junk messages.

**Mitigation:**
- Rate limiting: 10 messages/hour per user
- Require auth token (logged-in users only)
- Auto-delete expired messages

---

## Alternative: Nostr Integration

### Nostr Advantages

- ✅ Decentralized (multiple relays)
- ✅ No single point of failure
- ✅ Built-in identity (Nostr public key = user ID)
- ✅ Existing ecosystem (wallets, clients)

### Nostr Disadvantages

- ❌ More complex (keypair management)
- ❌ Privacy (all messages on public relays, even if encrypted)
- ❌ No guaranteed delivery (relay may drop messages)

### Hybrid Approach

**Phase 3:** Use relay blob storage (simple, controlled)  
**Phase 4+:** Add Nostr as advanced option (user preference)

```dart
// lib/config/p2p_config.dart

enum P2PTransport {
  relay,  // Default (MAT relay)
  nostr,  // Advanced (user-configured Nostr relays)
}

class P2PConfig {
  static P2PTransport get transport {
    final pref = SharedPreferences.getInstance();
    return pref.getString('p2p_transport') == 'nostr'
        ? P2PTransport.nostr
        : P2PTransport.relay;
  }
}
```

---

## Testing Strategy

### Unit Tests

```dart
test('Ecies encrypt/decrypt round-trip', () async {
  final ecies = Ecies();
  final plaintext = 'secret message';

  final encrypted = await ecies.encrypt(
    plaintext: plaintext,
    recipientPublicKeyHex: bobPublicKey,
    myPrivateKeyHex: alicePrivateKey,
  );

  final decrypted = await ecies.decrypt(
    ciphertext: encrypted,
    senderPublicKeyHex: alicePublicKey,
    myPrivateKeyHex: bobPrivateKey,
  );

  expect(decrypted, plaintext);
});

test('DLC offer serialization', () {
  final offer = DlcOffer(...);
  final json = offer.toJson();
  final parsed = DlcOffer.fromJson(json);

  expect(parsed.dealId, offer.dealId);
  expect(parsed.funding.myCollateralSats, offer.funding.myCollateralSats);
});
```

---

### Integration Tests (Two-Device)

```dart
testWidgets('Alice sends offer, Bob accepts', (tester) async {
  // Setup two P2P channels (Alice + Bob)
  final aliceChannel = P2PChannel(apiClient: aliceApiClient, crypto: aliceEcies);
  final bobChannel = P2PChannel(apiClient: bobApiClient, crypto: bobEcies);

  // Alice creates offer
  final offer = DlcOffer(...);
  await aliceChannel.sendDlcOffer(recipientId: 'bob@example.com', offer: offer);

  // Bob polls inbox
  await Future.delayed(Duration(seconds: 2)); // Simulate network delay
  final receivedOffer = await bobChannel.pollDlcOffer();

  expect(receivedOffer, isNotNull);
  expect(receivedOffer!.dealId, offer.dealId);

  // Bob accepts
  final accept = DlcAccept(...);
  await bobChannel.sendDlcAccept(recipientId: 'alice@example.com', accept: accept);

  // Alice polls accept
  await Future.delayed(Duration(seconds: 2));
  final receivedAccept = await aliceChannel.pollDlcAccept();

  expect(receivedAccept, isNotNull);
  expect(receivedAccept!.dealId, offer.dealId);
});
```

---

## Open Questions

1. **Public key distribution:**
   - Trust relay to distribute keys? (yes for v1)
   - Or user-verified fingerprints? (future)

2. **Message retention:**
   - How long does relay keep unread messages? (24 hours?)
   - What happens if inbox full? (reject new, or FIFO?)

3. **Multi-device:**
   - User logged in on 2 phones → which receives offer? (all devices poll)
   - Coordination needed? (first to accept wins, others see "already accepted")

4. **Conflict resolution:**
   - Both parties sign conflicting funding txs → which wins? (first to broadcast)

---

## Next Steps

1. ✅ Define wire format (done above)
2. Implement Rails relay endpoints (`POST/GET /api/v1/p2p/messages`)
3. Implement mobile `Ecies` crypto
4. Implement mobile `P2PChannel` client
5. Test two-device round-trip (offer → accept)
6. Document message expiry/retry logic
7. Add UI for "Waiting for investor..." polling state

---

**Related:**
- [mobile-phase3-dlc-gaps.md](mobile-phase3-dlc-gaps.md) - What Rails code to replace
- [mobile-phase2-bdk-architecture.md](mobile-phase2-bdk-architecture.md) - PSBT signing foundation
- [mat-core/docs/trust-boundaries.md](../mat-core/docs/trust-boundaries.md) - What relay can/cannot see
