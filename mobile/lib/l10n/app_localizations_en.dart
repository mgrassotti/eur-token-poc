// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MAT';

  @override
  String get loginTagline => 'EUR-nominal deals · Phase 1 shell';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get logIn => 'Log in';

  @override
  String hiUser(String name) {
    return 'Hi, $name';
  }

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageItalian => 'Italiano';

  @override
  String get advancedFeatures => 'Advanced features';

  @override
  String get advancedFeaturesSubtitle =>
      'Show open deals available to invest in';

  @override
  String get overview => 'Overview';

  @override
  String get spendingSavings => 'Spending / Savings';

  @override
  String get reserve => 'Reserve';

  @override
  String get availableReserve => 'Available reserve';

  @override
  String get pending => 'pending';

  @override
  String get pendingTopUps => 'Pending top ups';

  @override
  String pendingTopUpAmount(String amount) {
    return '€$amount requested';
  }

  @override
  String get awaitingInvestor => 'Awaiting investor';

  @override
  String get depositFunds => 'Deposit funds';

  @override
  String get sendMoney => 'Send money';

  @override
  String get receiveMoney => 'Receive money';

  @override
  String get receiveMoneyTitle => 'Receive money';

  @override
  String get paymentRequest => 'Payment request';

  @override
  String get optionalAmountEur => 'Amount (EUR, optional)';

  @override
  String get generateRequest => 'Generate request';

  @override
  String get showThisQr => 'Show this QR to the sender';

  @override
  String requestExpiresCountdown(String countdown, String time) {
    return 'Expires in $countdown (at $time)';
  }

  @override
  String get requestExpiredMessage => 'This payment request has expired';

  @override
  String get copyPaymentLink => 'Copy payment link';

  @override
  String get paymentLinkCopied => 'Payment link copied';

  @override
  String get sharePaymentLink => 'Share';

  @override
  String sharePaymentLinkMessage(String link) {
    return 'Pay me via MAT: $link';
  }

  @override
  String get scanQr => 'Scan QR';

  @override
  String get pastePaymentLink => 'Paste payment link';

  @override
  String get payRequest => 'Pay request';

  @override
  String get pay => 'Pay';

  @override
  String get invalidPaymentLink => 'Invalid or unsupported payment link';

  @override
  String payingTo(String name) {
    return 'Paying $name';
  }

  @override
  String get topUpSpending => 'Top up spending';

  @override
  String get interests => 'Interests';

  @override
  String get noInterestsYet => 'No interests yet.';

  @override
  String get openToInvest => 'Open to invest';

  @override
  String get noPendingOffers => 'No pending offers from other borrowers.';

  @override
  String get addFunds => 'Add funds';

  @override
  String regtestReserve(String network) {
    return 'Regtest reserve ($network)';
  }

  @override
  String balanceSats(int sats) {
    return 'Balance: $sats sats';
  }

  @override
  String get copyAddress => 'Copy address';

  @override
  String get addressCopied => 'Address copied';

  @override
  String get syncBalance => 'Sync balance';

  @override
  String reserveUpdated(int sats) {
    return 'Reserve updated: $sats sats';
  }

  @override
  String get reserveInstructions =>
      'Ask admin to send BTC from Exchange wallet to this address, then tap Sync.';

  @override
  String get retry => 'Retry';

  @override
  String get sendMoneyTitle => 'Send money';

  @override
  String availableEur(String amount) {
    return 'Available: €$amount';
  }

  @override
  String get noSpendingBalance =>
      'No spending balance yet. Activate a deal or receive EURT first.';

  @override
  String get recipient => 'Recipient';

  @override
  String get amountEur => 'Amount (EUR)';

  @override
  String get send => 'Send';

  @override
  String sentTo(String amount, String name) {
    return 'Sent €$amount to $name';
  }

  @override
  String get topUpTitle => 'Top up spending/savings account';

  @override
  String get topUp => 'Top up';

  @override
  String get topUpSubmitted => 'Top up submitted';

  @override
  String get noReserveToTopUp => 'No reserve balance available to top up.';

  @override
  String maxFromReserve(String amount) {
    return 'Maximum from reserve: €$amount';
  }

  @override
  String get estimatedExpiration => 'Estimated expiration';

  @override
  String get expirationNote =>
      'At expiration your funds will return to the reserve account.';

  @override
  String get enterValidAmount => 'Enter a valid amount';

  @override
  String amountExceedsReserve(String amount) {
    return 'Amount cannot exceed your reserve (€$amount)';
  }

  @override
  String get home => 'Home';

  @override
  String dealTitle(String id) {
    return 'Deal #$id';
  }

  @override
  String get amount => 'Amount';

  @override
  String get rate => 'Rate';

  @override
  String ratePerMonth(String rate) {
    return '$rate% / month';
  }

  @override
  String get period => 'Period';

  @override
  String get borrower => 'Borrower';

  @override
  String get investor => 'Investor';

  @override
  String get peg => 'Peg';

  @override
  String get pool => 'Pool';

  @override
  String poolSats(int sats) {
    return '$sats sats';
  }

  @override
  String get liabilityAtMaturity => 'Liability at maturity';

  @override
  String get tokenHolders => 'Token holders';

  @override
  String interestAmount(String amount) {
    return '+€$amount interest';
  }

  @override
  String get acceptAndActivate => 'Accept & activate';

  @override
  String get dealActivated => 'Deal activated';

  @override
  String get transfers => 'Transfers';

  @override
  String get sendEurt => 'Send EURT';

  @override
  String get transferSent => 'Transfer sent';

  @override
  String get noTransfersYet => 'No transfers yet';

  @override
  String get settlement => 'Settlement';

  @override
  String get spotRate => 'Spot rate';

  @override
  String get ready => 'Ready';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get floorEurPayoff => 'FloorEUR payoff';

  @override
  String get totalLiability => 'Total liability';

  @override
  String get holderSats => 'Holder sats';

  @override
  String get investorRemainder => 'Investor remainder';

  @override
  String get insolventNote => 'Insolvent at this spot — capped by escrow';

  @override
  String get holderAllocations => 'Holder allocations';

  @override
  String shareAmount(String amount) {
    return '€$amount share';
  }

  @override
  String get settlementPreviewNote =>
      'Preview only — Phase 1 uses relay FloorEUR math. Production settles on-device via mat-core.';

  @override
  String get settlementExecutedNote =>
      'Settlement executed on relay (PoC admin path).';
}
