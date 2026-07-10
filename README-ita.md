# MAT PoC (Rails + DLC + RGB on regtest)

Proof-of-concept Rails per deal P2P bilaterali (`Budget`), con:

- collateral BTC reale su regtest
- token EUR nominali trasferibili tra utenti
- settlement a scadenza via DLC (oracle-attested CET)

## Stato attuale di implementazione

- **Settlement unico:** DLC (Discreet Log Contract)
- **I**l funding del DLC usa UTXO reali delle riserve utente.
- **Single lock model:** il funding 2-of-2 del DLC e' il lock del collateral.
- **RGB stack:** nodi RGB Lightning reali su regtest (uno per utente + issuer).
- **Demo/test end-to-end:** integrazione e system test allineati al flusso reale.



## Architettura funzionale

Ogni `Budget` rappresenta un deal autonomo:

- il borrower apre la richiesta (importo EUR nominale)
- l'investitore attiva il deal
- vengono emessi i token EUR nominali al borrower
- i token possono essere trasferiti ad altri utenti
- a maturity il DLC esegue la CET, poi il `peg_pot` viene distribuito pro-rata agli holder

### Collateral e payout

- collateral borrower + investor bloccato nel **funding output DLC 2-of-2**
- output investor CET torna direttamente alla riserva dell'investitore
- output peg CET viene distribuito agli holder via `Dlc::Distribution`



## Architettura tecnica

### Componenti principali

- **Rails app:** orchestration, stato dominio, dashboard, demo flow
- **bitcoind regtest:** catena e wallet on-chain
- **Pythia oracle:** annuncio/attestazione dell'evento numerico DLC
- `dlc-rs` **sidecar (Rust):**
  - costruisce DLC tx set (funding/CET/refund)
  - riceve input reali da Ruby
  - restituisce funding tx unsigned
  - esegue CET alla maturity
  - distribuisce il `peg_pot` dagli output reali CET
- **RGB Lightning Nodes:** uno per utente + issuer

### Flusso di activation (stato corrente)

`Budgets::ActivateService` -> `L1::ProvisionEscrowService`:

1. annuncia evento oracle
2. seleziona UTXO reserve borrower/investor
3. chiama `Dlc::NodeClient#create_contract` con:
  - `peg_inputs` / `investor_inputs`
  - change addresses
  - investor payout address
4. firma funding tx con i wallet reserve in Ruby
5. broadcast funding tx
6. salva outpoint funding DLC su `Budget` (`escrow_txid` / `escrow_vout`)
7. issue RGB

### Flusso di settlement

`Settlements::ExecuteService`:

1. valida maturity + contratto funded
2. redemption token RGB
3. `Dlc::SettlementService` esegue CET con attestazione oracle
4. `Dlc::Distribution` distribuisce il `peg_pot` agli holder
5. sync riserve on-chain



## Modello dati (essenziale)

- `Budget`: ciclo vita deal + outpoint collateral lock (funding DLC)
- `DlcContract`: metadati contratto DLC e funding outpoint
- `DlcSettlement`: risultato CET (`cet_txid`, outcome, peg/investor sats)
- `TokenAccount` / `TokenTransfer` / `RgbAssignment`: stato token e ownership
- `CollateralLock`: tracking contabile lock collateral lato dominio
- `BtcAccount`: saldo riserva spendibile utente

Nota: alcune colonne legacy possono ancora esistere a DB per backward compatibility, ma il runtime segue il modello DLC-only sopra.



## Setup rapido

```bash
cd ~/dev/eur-token-poc
bundle install
bin/rails db:setup
bin/dev
```

`bin/dev` avvia Rails e lo stack regtest richiesto.

Login demo:

- `admin@example.com` / `password`
- `alice@example.com` / `password`
- `bob@example.com` / `password`
- `claude@example.com` / `password`
- `david@example.com` / `password`

## Stack regtest / RGB / DLC

```bash
./bin/regtest up
```

Servizi principali:

- bitcoind: `127.0.0.1:18443`
- RLN Alice/Bob/Claude/David: `3001..3004`
- RLN issuer: `3005`
- DLC node (`dlc-rs`): da config `DLC_NODE_URL`
- Oracle Pythia: da config `DLC_ORACLE_URL`

Reset ambiente demo:

```bash
./bin/regtest reset
```



## Demo flow (funzionale)

1. Admin imposta rate BTC/EUR
2. Alice e Bob depositano nella riserva
3. Alice crea budget
4. Bob attiva il budget (funding DLC da riserve reali)
5. Alice trasferisce parte dei token a Claude/David
6. Al maturity block avviene settlement DLC
7. Holder ricevono `peg_pot` distribuito, investor riceve output CET investor



## Test

```bash
bundle exec rspec
./bin/demo-spec
./bin/system-spec
```

- `bundle exec rspec`: suite completa (unit + integration + system)
- `bin/demo-spec`: scenario end-to-end non browser
- `bin/system-spec`: scenario end-to-end via UI



## File/servizi chiave

- `app/services/dlc/contract_setup_service.rb`
- `app/services/dlc/settlement_service.rb`
- `app/services/dlc/distribution.rb`
- `app/services/settlements/execute_service.rb`
- `app/services/l1/provision_escrow_service.rb`
- `lib/dlc/node_client.rb`
- `dlc-rs/src/main.rs`
- `spec/integration/demo_end_to_end_flow_spec.rb`
- `spec/system/demo_end_to_end_flow_spec.rb`



## Limitazioni note

- Ambiente orientato a regtest/demo, non hardening produzione.
- Dipendenza da stack locale Docker e servizi oracle/DLC.
- Alcune parti legacy DB restano solo per compatibilita' storica.

## Sviluppi futuri necessari

Per arrivare a un'architettura economicamente sostenibile e scalabile, il PoC
deve evolvere oltre il settlement e la distribuzione prevalentemente on-chain.

### 1. Ridurre l'uso di Layer 1

Lo stato attuale usa Bitcoin L1 per:

- funding del DLC / lock del collateral
- ritorno del collateral investitore via CET
- distribuzione del `peg_pot` agli holder

Questo e' corretto per un PoC verificabile, ma su volumi reali introduce:

- costi miner fee per activation / settlement / distribution
- latenza di conferma
- bassa efficienza per payout frazionati a molti holder

La direzione naturale e' mantenere su L1 solo il minimo necessario
(`funding`/`refund`/ancoraggio finale), spostando i payout operativi su
Lightning.

### 2. Distribuzione holder via Lightning anziche' payout L1

Oggi `Dlc::Distribution` spende l'output CET peg-side verso gli indirizzi di
riserva L1 degli holder. Per scalabilita' e costi, il passo successivo e':

- sostituire il fan-out on-chain con pagamenti Lightning
- usare invoice per-holder invece di UTXO per-holder
- evitare una transazione L1 con N output per ogni settlement

Questo riduce fee e dimensione dei payout, soprattutto quando il `peg_pot`
deve essere distribuito a molti destinatari.

### 3. Pending / HODL invoices per atomicita'

Il passaggio importante non e' solo "usare LN", ma usare **pending invoices**
(o HODL invoices) per legare atomicamente:

- redemption / burn / ritiro dei token lato RGB
- ricezione del payout BTC lato Lightning

L'obiettivo e':

1. l'holder presenta una invoice Lightning pending
2. il settlement DLC determina l'ammontare dovuto
3. il sistema prepara il pagamento ma non lo finalizza subito
4. il completamento avviene solo quando la condizione atomica e' soddisfatta
   (es. redemption valida / segreto oracle / stato applicativo coerente)

In questo modo si evita il rischio di:

- token ritirati ma payout non ricevuto
- payout inviato ma stato token non aggiornato

### 4. Fattibilita' pratica

Per passare a questo modello servono ancora alcuni passi infrastrutturali:

- supporto affidabile a pending/HODL invoices nel nodo Lightning usato
- gestione lifecycle invoice (`open` / `held` / `settled` / `cancelled`)
- mapping chiaro tra payout DLC, holder position e invoice LN
- recovery / retry in caso di errori parziali
- accounting applicativo che distingua:
  - collateral L1
  - payout CET
  - payout LN pendenti / regolati

### 5. Architettura target ragionevole

Una direzione realistica per una versione piu' matura e':

- **L1 Bitcoin**: collateral lock del DLC, refund, casi eccezionali / recovery
- **DLC**: settlement principale del deal e determinazione del payout
- **Lightning**: distribuzione dei payout agli holder
- **RGB**: ownership / trasferibilita' del nominale EUR

In questo assetto:

- L1 resta il layer di sicurezza e finalita'
- LN diventa il layer operativo per i payout frequenti
- i costi marginali per settlement multi-holder si abbassano molto

### 6. Stato del progetto rispetto a questa roadmap

Attualmente il repository copre:

- DLC reserve-funded funzionante su regtest
- investor return reale sulla riserva
- distribution holder reale ma ancora **on-chain**

Quindi il prossimo salto architetturale importante non e' il DLC in se', ma la
**migrazione della distribution verso LN con pending invoices**, mantenendo L1
solo dove serve davvero.

