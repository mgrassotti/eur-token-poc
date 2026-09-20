# Relay API v1

REST coordination API for Phase 1 mobile. Maps PoC `Budget` records to **deals**. No signing, no keys — identity via bearer token only.

Base URL: `http://localhost:3000/api/v1` (adjust for device/emulator — use `10.0.2.2:3000` on Android emulator).

All authenticated requests:

```http
Authorization: Bearer <token>
Content-Type: application/json
```

JSON responses include `schema_version: 1` where noted.

---

## Auth

### `POST /auth/login`

No auth required.

**Request**

```json
{
  "email": "alice@example.com",
  "password": "password"
}
```

**Response `200`**

```json
{
  "token": "<signed-bearer-token>",
  "user": {
    "id": 2,
    "name": "Alice",
    "email": "alice@example.com",
    "admin": false
  }
}
```

### `GET /auth/me`

Returns the current user (same shape as login `user`).

---

## Market rate

### `GET /market_rate`

```json
{
  "schema_version": 1,
  "btc_eur_per_btc": 50000.0,
  "bitcoin_block_height": 120000,
  "set": true,
  "updated_at": "2026-07-08T12:00:00Z"
}
```

---

## Dashboard

### `GET /dashboard`

Aggregated home screen data for the logged-in user.

```json
{
  "schema_version": 1,
  "user": { "id": 2, "name": "Alice", "email": "...", "admin": false },
  "market_rate": { "btc_eur_per_btc": 50000.0, "bitcoin_block_height": 0, "set": true },
  "savings": { "sats": 2100000, "eur": 1050.0 },
  "spending_eur_cents": 100000,
  "investment_sats": 0,
  "borrowed_deals": [ /* Deal */ ],
  "investable_deals": [ /* Deal */ ],
  "fund_positions": [ { "deal_id": "1", "balance_cents": 50000, "period_end": "2026-02-01" } ],
  "margin_call_deals": []
}
```

---

## Deals

Deal objects align with [mat-core wire schemas](../mat-core/schemas/deal-offer.schema.json) field names where applicable.

### `GET /deals`

List deals visible to the user (own deals, invested deals, and open offers).

### `GET /deals/:id`

Deal detail including `token_holders`, `liability_eur_cents`, `dlc_funded`.

### `POST /deals`

Create a pending deal (borrower offer).

```json
{
  "deal": {
    "amount_eur_cents": 100000,
    "period_start": "2026-01-01",
    "period_end": "2026-02-01"
  }
}
```

Alternative: `"amount_eur": "1000.00"`.

### `POST /deals/:id/accept`

Hodler activates the deal (runs `Budgets::ActivateService` — requires regtest infra in full PoC).

---

## Transfers

### `GET /deals/:deal_id/transfers`

Token transfer history for a deal.

### `POST /deals/:deal_id/transfers`

```json
{
  "to_user_id": 4,
  "amount_eur_cents": 50000
}
```

---

## Settlement

### `GET /deals/:deal_id/settlement`

- **`preview`** — FloorEUR payoff projection via `Payoffs::FloorEurCalculator` (Phase 1 mock path).
- **`executed`** — after admin settlement.

Both statuses include **`calculation_inputs`** so clients can recompute FloorEUR on-device (`mat_sdk` / mat-core) and audit after execution.

Preview example:

```json
{
  "schema_version": 1,
  "deal_id": "1",
  "status": "preview",
  "end_btc_eur_rate": 50000.0,
  "ready_for_settlement": false,
  "calculation_inputs": {
    "notional_eur_cents": 100000,
    "notional_total_cents": 100000,
    "holder_shares_cents": [100000],
    "spot_eur_per_btc": 50000,
    "rate_bps_monthly": 100,
    "months_elapsed": 1,
    "escrow_total_sats": 3975000,
    "mining_fee_sats": 5000
  },
  "payoff": {
    "liability_eur_cents": 101000,
    "total_holder_sats": 2020000,
    "investor_remainder_sats": 1955000,
    "insolvent": false
  },
  "holder_allocations": [
    { "user": { "id": 2, "name": "Alice" }, "share_cents": 100000, "btc_sats": 2020000 }
  ]
}
```

### `POST /deals/:deal_id/settlement`

Admin only. Executes `Settlements::ExecuteService`.

```json
{ "end_btc_eur_rate": 55000 }
```

---

## Users

### `GET /users`

Non-admin users except self — for transfer recipient picker.

---

## Reserve (add funds)

### `GET /reserve`

Returns the user's stored receive address (set by mobile client via `PUT /reserve/update_address`).

**Phase 2 change:** No longer generates addresses server-side. Mobile clients create wallets using BDK and register their address.

```json
{
  "schema_version": 1,
  "network": "regtest",
  "receive_address": "bcrt1q...",
  "balance_sats": 0,
  "instructions": "Send BTC on regtest to this address. An admin funds via Exchange wallet."
}
```

If the user hasn't registered an address yet:

```json
{
  "schema_version": 1,
  "network": "regtest",
  "receive_address": null,
  "balance_sats": 0,
  "instructions": "Create an on-device wallet first (Phase 2 BDK)."
}
```

### `PUT /reserve/update_address`

**Phase 2:** Mobile clients register their BDK-generated receive address.

```json
{
  "receive_address": "bcrt1q..."
}
```

**Response 200:**

```json
{
  "schema_version": 1,
  "receive_address": "bcrt1q...",
  "registered_at": "2026-07-31T10:00:00Z"
}
```

**Errors:**
- `400` `address_required` - Address is blank
- `422` `invalid_address` - Address format is invalid
- `409` `address_in_use` - Address already registered by another user

### `POST /reserve/sync`

**Phase 2 change:** Sync is now a no-op. Mobile clients use BDK sync directly. Balance updates happen when admin funds via the server.

```json
{
  "schema_version": 1,
  "balance_sats": 0,
  "synced_at": "2026-07-31T10:00:00Z",
  "note": "Phase 2: Balance synced by admin funding service. Use BDK sync on mobile for L1 state."
}
```

---

## Errors

```json
{ "error": "unauthorized" }
{ "error": "create_failed", "detail": "..." }
```

HTTP status: `401`, `403`, `404`, `422`.

---

## Trust boundary

See [mat-core/docs/trust-boundaries.md](../mat-core/docs/trust-boundaries.md). The relay stores deal metadata only; holder sats in settlement preview must be recomputed on-device in production (`mat-core`).

---

## Related

- [mobile-production-plan.md](mobile-production-plan.md) — Phase 1 exit criteria
- [mobile/README.md](../mobile/README.md) — Flutter app
