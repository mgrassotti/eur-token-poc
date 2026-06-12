# BTC wallet PoC

Proof-of-concept Rails per budget di spesa mensili in token EUR-pegged, collateralizzati in BTC da un investitore che assume il rischio di cambio.

## Setup

```bash
cd ~/dev/eur-token-poc
bundle install
bin/rails db:setup
bin/rails server
```

Apri http://localhost:3000 e accedi con:

| Utente | Email | Password | Ruolo |
|--------|-------|----------|-------|
| Admin | admin@example.com | password | Imposta peg e settlement |
| Alice | alice@example.com | password | Borrower |
| Bob | bob@example.com | password | Investor |
| Claude | claude@example.com | password | — |
| David | david@example.com | password | — |

In development puoi usare il dropdown **Switch** nella navbar per cambiare utente rapidamente.

## Scenario demo

### Stato iniziale (seed)

- **Alice**: 0.1 BTC (10_000_000 sats) in risparmio
- **Bob**: 0.2 BTC (20_000_000 sats) — investitore potenziale
- Budget **pending** da 1000 EUR (borrower + investitore bloccano ciascuno **1×**)

### 1. Imposta peg (Admin)

1. Login come **Admin**
2. Dashboard → pannello admin → budget in attesa di peg → **Imposta peg**
3. Conferma peg **60_000 EUR/BTC**

### 2. Attivazione budget (Bob)

1. Switch **Bob**
2. Dashboard → budget in attesa → **Dettagli**
3. **Accetta rischio e attiva budget** (usa il peg fissato dall'admin)

Il sistema (se Alice ha già creato il budget):
- Blocca ~1_666_667 sats da Bob (1000 EUR @ 60k, rischio FX)
- Mint 1000 EURT ad Alice

Alla **creazione** del budget Alice ha già bloccato altrettanto dal conto risparmio (collateral contratto, non rimborsato al settlement).

### 3. Spesa token (Alice → Claude → David)

1. Switch **Alice** → budget attivo → **Trasferisci token**
2. Invia 300 EUR a Claude
3. Switch **Claude** → invia 100 EUR a David

Saldi attesi: Alice 700, Claude 200, David 100 EURT.

### 4. Settlement fine mese (Admin)

1. Switch **Admin**
2. Dashboard → pannello admin → **Settlement** (o apri il budget attivo)
3. Inserisci prezzo BTC finale (es. 70_000 o 50_000 EUR/BTC)
4. **Esegui settlement**

Il sistema:
- Brucia i token
- Accredita BTC a **tutti i detentori** (inclusa Alice) al **cambio corrente**
- Il collateral del borrower resta nel pool (nessun rimborso separato del peg)
- L'**investitore** riceve il residuo e compensa la differenza di cambio sui token

### Esempio numerico @ peg 60k, budget 1000 EUR

```
Pool totale:             3_333_333 sats  (borrower 1× + investitore 1×)
Payout detentori:        al cambio finale (es. 2_000_000 sats @ 50k)
Investitore:             residuo (0 sats se BTC dimezza del 50%)
Borrower:                solo token residui convertiti — nessun rimborso del lock
```

Con calo del 50% (es. 100k → 50k) il pool copre esattamente i detentori: l'investitore perde tutto il suo 1×, il collateral di Alice finisce nei payout ai detentori.

## Test

```bash
bundle exec rspec
```

## Architettura

- **Ledger simulato** — saldi BTC e token nel database, nessuna blockchain
- **Services**: `Budgets::ActivateService`, `Tokens::TransferService`, `Settlements::ExecuteService`
- **Token EURT**: 1 centesimo = 0.01 EUR, peg fisso al mint

## Console walkthrough

```ruby
admin = User.find_by!(email: "admin@example.com")
alice = User.find_by!(email: "alice@example.com")
bob = User.find_by!(email: "bob@example.com")
claude = User.find_by!(email: "claude@example.com")
david = User.find_by!(email: "david@example.com")

budget = Budget.pending.first
Budgets::SetPegService.call(budget: budget, peg_eur_per_btc: 60_000)
Budgets::ActivateService.call(budget: budget, investor: bob)

Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 30_000)
Tokens::TransferService.call(budget: budget, from_user: claude, to_user: david, amount_cents: 10_000)

result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 70_000)
result.payouts.each { |p| puts "#{p.user.name}: #{p.btc_sats} sats" }
puts "Bob: #{result.investor_btc_sats} sats"
```
