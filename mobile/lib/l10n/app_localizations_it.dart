// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'MAT';

  @override
  String get loginTagline => 'Deal a nominale EUR · shell Fase 1';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get logIn => 'Accedi';

  @override
  String hiUser(String name) {
    return 'Ciao, $name';
  }

  @override
  String get settings => 'Impostazioni';

  @override
  String get refresh => 'Aggiorna';

  @override
  String get language => 'Lingua';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageItalian => 'Italiano';

  @override
  String get advancedFeatures => 'Funzioni avanzate';

  @override
  String get advancedFeaturesSubtitle =>
      'Mostra i deal aperti in cui investire';

  @override
  String get overview => 'Panoramica';

  @override
  String get spendingSavings => 'Spesa / Risparmio';

  @override
  String get reserve => 'Riserva';

  @override
  String get availableReserve => 'Riserva disponibile';

  @override
  String get pending => 'in sospeso';

  @override
  String get pendingTopUps => 'Ricariche in sospeso';

  @override
  String pendingTopUpAmount(String amount) {
    return '€$amount richiesti';
  }

  @override
  String get awaitingInvestor => 'In attesa di un investitore';

  @override
  String get depositFunds => 'Deposita fondi';

  @override
  String get sendMoney => 'Invia denaro';

  @override
  String get receiveMoney => 'Ricevi denaro';

  @override
  String get receiveMoneyTitle => 'Ricevi denaro';

  @override
  String get paymentRequest => 'Richiesta di pagamento';

  @override
  String get optionalAmountEur => 'Importo (EUR, opzionale)';

  @override
  String get generateRequest => 'Genera richiesta';

  @override
  String get showThisQr => 'Mostra questo QR al mittente';

  @override
  String requestExpiresCountdown(String countdown, String time) {
    return 'Scade tra $countdown (alle $time)';
  }

  @override
  String get requestExpiredMessage => 'Questa richiesta di pagamento è scaduta';

  @override
  String get copyPaymentLink => 'Copia link di pagamento';

  @override
  String get paymentLinkCopied => 'Link copiato';

  @override
  String get sharePaymentLink => 'Invia';

  @override
  String sharePaymentLinkMessage(String link) {
    return 'Pagami con MAT: $link';
  }

  @override
  String get scanQr => 'Scansiona QR';

  @override
  String get pastePaymentLink => 'Incolla link di pagamento';

  @override
  String get payRequest => 'Paga richiesta';

  @override
  String get pay => 'Paga';

  @override
  String get invalidPaymentLink =>
      'Link di pagamento non valido o non supportato';

  @override
  String payingTo(String name) {
    return 'Pagamento a $name';
  }

  @override
  String get topUpSpending => 'Ricarica spesa';

  @override
  String get interests => 'Interessi';

  @override
  String get noInterestsYet => 'Nessun interesse ancora.';

  @override
  String get openToInvest => 'Aperti all\'investimento';

  @override
  String get noPendingOffers =>
      'Nessuna offerta in sospeso da altri richiedenti.';

  @override
  String get addFunds => 'Aggiungi fondi';

  @override
  String regtestReserve(String network) {
    return 'Riserva regtest ($network)';
  }

  @override
  String balanceSats(int sats) {
    return 'Saldo: $sats sats';
  }

  @override
  String get copyAddress => 'Copia indirizzo';

  @override
  String get addressCopied => 'Indirizzo copiato';

  @override
  String get syncBalance => 'Sincronizza saldo';

  @override
  String reserveUpdated(int sats) {
    return 'Riserva aggiornata: $sats sats';
  }

  @override
  String get reserveInstructions =>
      'Chiedi all\'admin di inviare BTC dal wallet Exchange a questo indirizzo, poi tocca Sincronizza.';

  @override
  String get retry => 'Riprova';

  @override
  String get sendMoneyTitle => 'Invia denaro';

  @override
  String availableEur(String amount) {
    return 'Disponibile: €$amount';
  }

  @override
  String get noSpendingBalance =>
      'Nessun saldo di spesa ancora. Attiva un deal o ricevi EURT prima.';

  @override
  String get recipient => 'Destinatario';

  @override
  String get amountEur => 'Importo (EUR)';

  @override
  String get send => 'Invia';

  @override
  String sentTo(String amount, String name) {
    return 'Inviati €$amount a $name';
  }

  @override
  String get topUpTitle => 'Ricarica conto spesa/risparmio';

  @override
  String get topUp => 'Ricarica';

  @override
  String get topUpSubmitted => 'Ricarica inviata';

  @override
  String get noReserveToTopUp =>
      'Nessun saldo di riserva disponibile per la ricarica.';

  @override
  String maxFromReserve(String amount) {
    return 'Massimo dalla riserva: €$amount';
  }

  @override
  String get estimatedExpiration => 'Scadenza stimata';

  @override
  String get expirationNote =>
      'Alla scadenza i fondi torneranno sul conto di riserva.';

  @override
  String get enterValidAmount => 'Inserisci un importo valido';

  @override
  String amountExceedsReserve(String amount) {
    return 'L\'importo non può superare la riserva (€$amount)';
  }

  @override
  String get home => 'Home';

  @override
  String dealTitle(String id) {
    return 'Deal #$id';
  }

  @override
  String get amount => 'Importo';

  @override
  String get rate => 'Tasso';

  @override
  String ratePerMonth(String rate) {
    return '$rate% / mese';
  }

  @override
  String get period => 'Periodo';

  @override
  String get borrower => 'Richiedente';

  @override
  String get investor => 'Investitore';

  @override
  String get peg => 'Peg';

  @override
  String get pool => 'Pool';

  @override
  String poolSats(int sats) {
    return '$sats sats';
  }

  @override
  String get liabilityAtMaturity => 'Passività a scadenza';

  @override
  String get tokenHolders => 'Detentori di token';

  @override
  String interestAmount(String amount) {
    return '+€$amount interessi';
  }

  @override
  String get acceptAndActivate => 'Accetta e attiva';

  @override
  String get dealActivated => 'Deal attivato';

  @override
  String get transfers => 'Trasferimenti';

  @override
  String get sendEurt => 'Invia EURT';

  @override
  String get transferSent => 'Trasferimento inviato';

  @override
  String get noTransfersYet => 'Nessun trasferimento ancora';

  @override
  String get settlement => 'Settlement';

  @override
  String get spotRate => 'Cambio spot';

  @override
  String get ready => 'Pronto';

  @override
  String get yes => 'Sì';

  @override
  String get no => 'No';

  @override
  String get floorEurPayoff => 'Payoff FloorEUR';

  @override
  String get totalLiability => 'Passività totale';

  @override
  String get holderSats => 'Sats detentori';

  @override
  String get investorRemainder => 'Residuo investitore';

  @override
  String get insolventNote =>
      'Insolvente a questo spot — limitato dall\'escrow';

  @override
  String get holderAllocations => 'Allocazioni detentori';

  @override
  String shareAmount(String amount) {
    return 'quota €$amount';
  }

  @override
  String get settlementPreviewNote =>
      'Anteprima — gli importi sono ricalcolati sul dispositivo via mat_sdk; le cifre del relay sono confrontate per incongruenze.';

  @override
  String get settlementExecutedNote =>
      'Settlement eseguito sul relay (percorso admin PoC). Input inclusi per audit FloorEUR offline.';

  @override
  String get onDeviceFloorEur => 'Ricalcolato sul dispositivo (mat_sdk)';

  @override
  String get settlementMismatchWarning =>
      'Il FloorEUR sul dispositivo non coincide con l\'anteprima del relay. Non fidarti delle cifre del server.';

  @override
  String get localWalletDebug => 'Wallet locale (spike BDK)';

  @override
  String get localWalletDebugSubtitle =>
      'Fase 2: crea/carica mnemonic e mostra un indirizzo di ricezione';

  @override
  String get localWalletCreate => 'Crea wallet';

  @override
  String get localWalletReceiveAddress => 'Indirizzo di ricezione';

  @override
  String get localWalletMnemonicSaved =>
      'Mnemonic salvato sul dispositivo (solo debug — non sicuro in produzione)';

  @override
  String localWalletError(String detail) {
    return 'Errore wallet: $detail';
  }

  @override
  String get saveMoney => 'Risparmia';

  @override
  String get invest => 'Investi';

  @override
  String get savingsRequests => 'Richieste di risparmio';

  @override
  String get investmentRequests => 'Richieste di investimento';

  @override
  String get awaitingBankTransfer => 'In attesa del bonifico';

  @override
  String get awaitingBtcDeposit => 'In attesa del deposito BTC';

  @override
  String get awaitingMatch => 'In attesa di matching';

  @override
  String get contractActive => 'Contratto attivo';

  @override
  String get payoutKeepBtc => 'Tieni i BTC in app';

  @override
  String get payoutReinvest => 'Reinvesti il mese successivo';

  @override
  String get payoutEur => 'Ricevi EUR sul mio IBAN';

  @override
  String get yourIban => 'Il tuo IBAN';

  @override
  String get matIban => 'Bonifico a questo IBAN';

  @override
  String get onePercentMonth => '1% per 1 mese';

  @override
  String currentBtcRate(String rate) {
    return 'Cambio BTC corrente: $rate€/BTC';
  }

  @override
  String investorPnlAt(String date) {
    return 'Guadagno/perdita in base al prezzo al $date';
  }

  @override
  String get noPendingRequests => 'Nessuna richiesta in attesa.';

  @override
  String get signFundingAutomatically => 'Firma del contratto in corso…';
}
