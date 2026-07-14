# mat-core

Portable deal kernel for MAT mobile production: FloorEUR economics, DLC payout curve sampling, deal lifecycle FSM, and versioned wire formats.

Lifted from the Rails PoC:

- `app/services/payoffs/floor_eur_calculator.rb`
- `lib/dlc/payout_curve.rb`
- `app/models/budget.rb` (months, status)

## Quick start

```bash
cd mat-core
cargo test
```

## Modules

| Module | Purpose |
|--------|---------|
| `floor_eur` | Holder sats at settlement (liability, cap, pro-rata split) |
| `payout_curve` | DLC anchor points from FloorEUR |
| `months` | Symbolic month duration and block accrual |
| `numeric` | DLC outcome digit helpers |
| `deal` | `pending` → `active` → `settled` FSM |
| `wire` | JSON types + `WIRE_FORMAT_VERSION` |

## Wire formats

JSON schemas in `schemas/` (version **1**):

- `deal-offer.schema.json`
- `deal-accept.schema.json`
- `funding-package.schema.json`
- `settlement-package.schema.json`

See [docs/trust-boundaries.md](docs/trust-boundaries.md).

## Test vectors

Rust unit tests port:

- `spec/services/payoffs/floor_eur_calculator_spec.rb` (PAYOFF-SPEC §5, §7)
- `spec/scenarios/demo_interest_at_peg_spec.rb` (€505 Alice case)
- `spec/lib/dlc/payout_curve_spec.rb`
- `spec/lib/dlc/numeric_spec.rb`

## Related

- [docs/mobile-production-plan.md](../docs/mobile-production-plan.md) — Phase 0–6 roadmap
