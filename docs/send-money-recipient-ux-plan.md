# Plan: Send Money recipient selection UX

**Branch:** `feature/send-money-recipient-ux`  
**Depends on:** `feature/mobile-relay-phase1` (relay API + mobile Send money shell)  
**Sibling plan (fees / rail):** [ln-zero-fee-transfers-plan.md](./ln-zero-fee-transfers-plan.md) — *how* money moves (LN zero-fee). This plan is only **who to pay**.

> **Branch discipline:** implement recipient UX only on `feature/send-money-recipient-ux`. Do **not** mix commits with `feature/ln-zero-fee-transfers`. Merge both into `feature/mobile-relay-phase1` (or main) independently when ready.

---

## Problem

Today **Send money** (`mobile/lib/screens/send_money_screen.dart`) loads recipients from `GET /api/v1/users` — a demo list of all other non-admin users — and posts `POST /api/v1/transfers` with `to_user_id`.

That works for a PoC with seeded users. It does **not** scale to real phones:

- Users cannot find friends who already have MAT.
- There is no offline / in-person handoff when two people are together.
- Exposing a global user directory is a privacy and abuse risk.

Product goal: destination selection supports **either** address-book discovery **or** QR provided by the receiver — then the existing (or future LN) transfer path runs with a resolved recipient + optional amount.

---

## Goals

1. **Contacts path:** With explicit OS permission, read the phone address book; use a privacy-preserving relay directory to show which contacts also have MAT; pick one as recipient.
2. **QR path:** Receiver shows a payment-request QR (LN invoice and/or RGB receive payload); sender scans to fill recipient and optionally amount — offline-friendly where possible.
3. Keep **rail / fee behaviour** out of scope here; recipient resolution must plug into today’s `POST /api/v1/transfers` and later into LN send without redesigning this UX.
4. Consent, App Store / Play permission copy, GDPR-aligned retention and revoke, rate limits, and a clear threat model for the phone directory.

## Non-goals

- Changing how RGB / LN settles or eliminating L1 fees (see sibling [ln-zero-fee-transfers-plan.md](./ln-zero-fee-transfers-plan.md)).
- Full social graph, messaging, or “invite friends via SMS” product (invite deep links may be a later work package; not required for v1).
- Storing plaintext MSISDN on the relay.
- Replacing wallet-level `POST /transfers` with a new payment protocol in this plan (QR may *carry* an invoice, but settlement still goes through the chosen rail).
- Email / username search as primary discovery (optional stretch only).

---

## Current codebase (baseline)

| Layer | Today |
|-------|--------|
| Mobile UI | `SendMoneyScreen` — `DropdownButtonFormField` over `api.fetchUsers()` |
| API | `GET /api/v1/users` (demo picker); `POST /api/v1/transfers` `{ to_user_id, amount_eur_cents }` |
| Rail | On-chain RGB via RLN (`Tokens::WalletTransferService` → `sendrgb`) |
| QR precedent | `AddFundsScreen` already uses `qr_flutter` for a Bitcoin receive address — reuse display patterns; add a *scanner* for send |

---

## Threat model — phone-number directory

### Assets

- Mapping “this phone number belongs to a MAT user” (social graph + account existence).
- Ability to spam lookups / enumerate the user base.
- Linkability of hashed numbers across apps/services if a weak or unsalted scheme is reused.

### Adversaries

| Adversary | Capability | Concern |
|-----------|------------|---------|
| Curious relay operator / DB leak | Reads stored hashes + user_ids | Reverse numbers if salt is weak/public; learn who is on MAT |
| Malicious client | Authenticated API, can upload many hashes | Bulk enumeration of “is this number on MAT?” |
| Compromised device | Reads local contacts + tokens | Already has address book; directory adds little beyond confirming MAT peers |
| Network observer | Sees TLS endpoints | Traffic analysis of lookup batch sizes |

### Desired properties

1. **No plaintext MSISDN** in relay DB, logs, or analytics.
2. **One-way** transformation: knowing the hash should not trivially yield the number without an expensive offline attack (and preferably a **server-side pepper** unknown to clients).
3. **Consent:** registration and contact matching only after OS permission + in-app explanation; easy revoke.
4. **Rate limits / abuse:** per-user and per-IP caps on register and lookup; batch size limits; anomaly alerts.
5. **Minimal retention:** hashes tied to account; delete on revoke / account deletion (GDPR erase).
6. **No global directory dump:** lookup is “here are *my* contact hashes — which match?”, not “list all users”.

### Hashing / KDF sketch (decision needed in spike)

Recommended direction for PoC → production path:

```
normalized_e164 = E.164(phone)           # e.g. +393331234567
client_blind   = HMAC-SHA256(client_key, normalized_e164)  # optional client-side blind
server_hash    = HMAC-SHA256(server_pepper, client_blind or normalized_e164)
store (user_id, server_hash, created_at)
```

| Approach | Pros | Cons |
|----------|------|------|
| **A. Server-peppered HMAC** (preferred) | Pepper never leaves server; offline reverse harder after DB leak | Client must send something the server can hash; still enumerable via online API |
| **B. Public salt + slow KDF (e.g. Argon2)** | Slows bulk offline attacks | Public salt alone is weak if space is phone numbers; CPU cost on every lookup |
| **C. Blinded / PSI-style match** | Stronger privacy vs relay learning contact set | Much higher complexity; defer past PoC |

**PoC recommendation:** Option A with E.164 normalization, per-user rate limits, max batch size (e.g. 500 hashes/request), and no logging of raw or hashed numbers in app logs. Document App Store purpose string: *“Find friends who already use MAT so you can send them money.”*

**Explicitly reject:** storing raw MSISDN; using MD5/SHA1 of bare national numbers; sharing one global public salt reused across unrelated products.

---

## Relay API sketches

All authenticated with existing bearer token. Paths under `/api/v1`. Names are provisional.

### Register / update own phone hash

```http
PUT /api/v1/me/phone_directory
Authorization: Bearer <token>
Content-Type: application/json

{
  "schema_version": 1,
  "phone_hash": "<hex or base64 of client preimage>",
  "consent_version": "contacts-v1"
}
```

**Server:** normalize already done on client; apply `HMAC(server_pepper, phone_hash)` (or accept E.164 only over TLS and hash entirely server-side — see open questions). Upsert one row per user. Return `204` or `{ "registered": true }`.

### Lookup contacts

```http
POST /api/v1/phone_directory/lookup
Authorization: Bearer <token>

{
  "schema_version": 1,
  "phone_hashes": ["...", "..."]   // max N, e.g. 500
}
```

**Response `200`**

```json
{
  "schema_version": 1,
  "matches": [
    {
      "phone_hash": "...",
      "user_id": 42,
      "display_name": "Claude"
    }
  ]
}
```

Only return matches for hashes that exist. Do **not** return non-matches (avoid confirming negatives beyond absence). Optionally omit `display_name` and let the client use the local contact name (better UX, less PII egress).

### Revoke

```http
DELETE /api/v1/me/phone_directory
Authorization: Bearer <token>
```

Deletes stored hash(es) for the user. Matching stops until re-register.

### Rate limits (sketch)

| Endpoint | Limit (starting point) |
|----------|-------------------------|
| `PUT .../phone_directory` | 5 / hour / user |
| `POST .../lookup` | 30 / hour / user; ≤ 500 hashes / request; ≤ 5k hashes / day |
| Global | Soft ban on burst patterns |

### QR-related (optional relay assist)

QR payloads should preferably be **self-contained** (offline). Optional helpers:

```http
GET /api/v1/me/receive_request?amount_eur_cents=5000
→ { "payload": "mat:pay/1?...", "expires_at": "..." }
```

Use only if LN invoice / RGB invoice generation must be server-coordinated in Phase 1; prefer client/RLN-generated invoices when the LN sibling plan lands.

---

## Mobile UX flows

### A. Contacts → match list → send

```
Send money
  → Choose “From contacts”
  → System permission dialog (Contacts)
       deny → explain + offer QR path
       allow → read contacts, normalize phones to E.164
  → Hash locally → POST lookup
  → Show “On MAT” list (local contact name + maybe avatar initial)
  → Tap contact → amount screen (existing field) → POST /transfers
```

Settings / privacy:

- Toggle “Discoverable by phone number” (calls register / revoke).
- Copy: what we store (hash only), how to delete, link to privacy policy.
- Never upload the full contact book in plaintext.

### B. Receiver shows QR

```
Receive / “Get paid”
  → Generate payment request:
       - PoC now: deep link with user_id (+ optional amount)
       - Later: LN invoice and/or RGB invoice from sibling LN plan
  → Show QR (reuse qr_flutter patterns from Add funds)
  → Optional: amount lock on QR
```

### C. Sender scans QR

```
Send money
  → “Scan QR”
  → Camera permission
  → Parse payload
       - mat:pay/1?...  → resolve user_id / invoice
       - lightning:... / LNURL → hand off to LN rail when available
       - rgb invoice string → RGB path when applicable
  → Prefill recipient + amount if present
  → Confirm → send
```

**Offline-friendly:** a QR that embeds a signed receive payload or invoice does not need the directory. Directory is only for “pick from contacts.” Deep link format (draft):

```
mat:pay/1?u=<user_id>&a=<amount_eur_cents>&n=<display_name_urlencoded>
```

Version the scheme (`pay/1`). When LN lands, extend:

```
mat:pay/1?inv=<bech32_or_url_encoded_invoice>
```

or use raw `lightning:` / BOLT11 as the QR content when the rail is invoice-native.

---

## Branching strategy

```text
feature/mobile-relay-phase1          ← shared base (current HEAD for this plan)
        │
        ├── feature/send-money-recipient-ux     ← THIS PLAN (who)
        │         contacts directory + QR UX
        │
        └── feature/ln-zero-fee-transfers       ← sibling (how / fees)
                  LN path for POST /transfers
```

| Rule | Detail |
|------|--------|
| Develop recipient UX on | `feature/send-money-recipient-ux` only |
| Do not mix with | `feature/ln-zero-fee-transfers` commits |
| Integration | Either branch can merge first; recipient UX should resolve to `user_id` (or invoice) that both rails can consume |
| Conflict hotspots | `send_money_screen.dart`, `relay_api_client.dart`, `POST /transfers` request shape — coordinate via thin “ResolvedRecipient” model |

---

## Work packages

### WP0 — Product / privacy spike (docs + decisions)

- Finalize hashing scheme (server pepper vs client-only).
- Permission / GDPR copy (EN + IT to match existing l10n).
- Confirm QR v1 payload (user_id deep link vs wait for LN invoice).

### WP1 — Relay phone directory

- Migration: `phone_directory_entries (user_id unique, hash unique, consent_version, timestamps)`.
- `PUT` / `POST lookup` / `DELETE` endpoints + rate limiting.
- Pepper via Rails credentials / ENV; never commit pepper.
- Request specs: match, no-match, revoke, rate limit, auth required.

### WP2 — Mobile contacts flow

- `permission_handler` (or equivalent) for contacts.
- Read + E.164 normalize (libphonenumber).
- Hash + lookup client; “On MAT” list UI replacing demo `GET /users` dropdown (keep demo picker behind debug flag if useful for tests).
- Discoverability toggle in Settings.

### WP3 — QR receive + scan

- Receive screen / entry from dashboard (“Show my QR”).
- Encode `mat:pay/1?...` (PoC).
- Scanner screen (e.g. `mobile_scanner`); parse → prefill Send money.
- Camera permission copy; fallback paste payload from clipboard.

### WP4 — Wire to transfer API

- Unified `ResolvedRecipient { userId?, invoice?, amountCents? }` into existing `sendMoney`.
- When LN sibling merges: if invoice present, take LN path; else `to_user_id` path.
- Remove or gate production use of full `GET /users` directory.

### WP5 — Hardening

- Abuse metrics, CAPTCHA/backoff if needed, account deletion cascade, penetration notes for App Store review.

---

## Test plan

| Area | Tests |
|------|--------|
| Hashing | Same E.164 → same server hash; different pepper → different hash; revoke removes match |
| Lookup API | Empty batch; partial matches; oversize batch → 413/422; unauthenticated → 401; rate limit → 429 |
| Privacy | Assert no plaintext phone in DB, logs, or Sentry breadcrumbs |
| Mobile contacts | Permission denied path; empty address book; match highlights local display name |
| QR | Encode/decode round-trip; invalid QR error; amount prefill; offline scan without network for self-contained payload |
| Regression | Existing integration `sendMoneyTo` helpers still pass with debug recipient picker or seeded hash |
| Cross-rail | Manual: resolve contact → send on current RGB path; after LN branch, same recipient → LN path |

---

## Open questions

1. **Hash where?** Client sends E.164 over TLS and server is sole hasher (simpler, more trust in relay) vs client pre-hash then server pepper (less raw MSISDN in app memory dumps / server request logs if logging is sloppy).
2. **Display name on lookup:** return from server vs always use local contact name?
3. **Multi-SIM / number change:** one hash per user or allow multiple? Re-verify via SMS OTP before register?
4. **SMS OTP:** required for discoverability (proves number ownership) or soft-launch without OTP for internal PoC?
5. **QR v1 content:** ship `user_id` deep links now, or block on LN invoice format from sibling plan?
6. **Non-MAT contacts:** show “Invite to MAT” with store / deep link, or hide entirely in v1?
7. **EU GDPR legal basis:** consent vs legitimate interest for directory; DPA text ownership.
8. **Apple/Google:** contacts permission rejection rates; whether limited Photos-style contact picker APIs change the design.

---

## Explicit separation from LN fee work

| This plan | Sibling [ln-zero-fee-transfers-plan.md](./ln-zero-fee-transfers-plan.md) |
|-----------|------------------------------------------------------------------------|
| Who to pay (contacts + QR) | How to pay with ~0 fees (RGB-LN / hub) |
| Branch `feature/send-money-recipient-ux` | Branch `feature/ln-zero-fee-transfers` |
| May still call today’s on-chain `POST /transfers` | Replaces rail behind the same (or extended) transfer API |

Do **not** implement Flutter/Rails feature work for fees on the recipient UX branch. Cross-link only.
