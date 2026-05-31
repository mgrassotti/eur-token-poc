# EUR Token PoC

Proof-of-concept Rails per budget di spesa mensili in token EUR-pegged, collateralizzati in BTC da un investitore che assume il rischio di cambio.

## Setup

```bash
cd ~/dev/eur-token-poc
bundle install
bin/rails db:setup
bin/rails server
```

Apri http://localhost:3000 e accedi con:

| Utente | Email | Password |
|--------|-------|----------|
| Alice | alice@example.com | password |
| Bob | bob@example.com | password |
| Claude | claude@example.com | password |
| David | david@example.com | password |

In development puoi usare il dropdown **Switch** nella navbar per cambiare utente rapidamente.

## Scenario demo

### Stato iniziale (seed)

- **Alice**: 0.1 BTC (10_000_000 sats) in risparmio — non usato dal budget
- **Bob**: 0.05 BTC (5_000_000 sats)
- Budget **pending** da 1000 EUR con collateral 2000 EUR

### 1. Attivazione budget (Bob)

1. Login come **Bob**
2. Dashboard → budget in attesa → **Dettagli**
3. Imposta peg **60_000 EUR/BTC** → **Accetta rischio e attiva budget**

Il sistema:
- Blocca ~3_333_333 sats da Bob (2000 EUR @ 60k)
- Mint 1000 EURT ad Alice

### 2. Spesa token (Alice → Claude → David)

1. Switch **Alice** → budget attivo → **Trasferisci token**
2. Invia 300 EUR a Claude
3. Switch **Claude** → invia 100 EUR a David

Saldi attesi: Alice 700, Claude 200, David 100 EURT.

### 3. Settlement fine mese

1. Apri il budget attivo → **Settlement fine mese**
2. Inserisci prezzo BTC finale (es. 70_000 o 50_000 EUR/BTC)
3. **Esegui settlement**

Il sistema:
- Brucia i token
- Accredita BTC ai detentori al **peg fisso** (token_EUR / 60_000)
- Restituisce il collateral residuo a **Bob** (rischio FX)

### Esempio numerico @ peg 60k

```
Collateral Bob:     3_333_333 sats
Payout holders:     1_666_667 sats  (1000 EUR / 60000)
Bob remainder:      1_666_666 sats
```

Il valore EUR del residuo di Bob dipende dal prezzo finale:
- @ 70k → ~1_166 EUR
- @ 50k → ~833 EUR

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
alice = User.find_by!(email: "alice@example.com")
bob = User.find_by!(email: "bob@example.com")
claude = User.find_by!(email: "claude@example.com")
david = User.find_by!(email: "david@example.com")

budget = Budget.pending.first
Budgets::ActivateService.call(budget: budget, investor: bob, peg_eur_per_btc: 60_000)

Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 30_000)
Tokens::TransferService.call(budget: budget, from_user: claude, to_user: david, amount_cents: 10_000)

result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 70_000)
result.payouts.each { |p| puts "#{p.user.name}: #{p.btc_sats} sats" }
puts "Bob: #{result.investor_btc_sats} sats"
```
