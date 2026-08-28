import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MAT'**
  String get appTitle;

  /// No description provided for @loginTagline.
  ///
  /// In en, this message translates to:
  /// **'EUR-nominal deals · Phase 1 shell'**
  String get loginTagline;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get logIn;

  /// No description provided for @hiUser.
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}'**
  String hiUser(String name);

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageItalian.
  ///
  /// In en, this message translates to:
  /// **'Italiano'**
  String get languageItalian;

  /// No description provided for @advancedFeatures.
  ///
  /// In en, this message translates to:
  /// **'Advanced features'**
  String get advancedFeatures;

  /// No description provided for @advancedFeaturesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show open deals available to invest in'**
  String get advancedFeaturesSubtitle;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @spendingSavings.
  ///
  /// In en, this message translates to:
  /// **'Spending / Savings'**
  String get spendingSavings;

  /// No description provided for @reserve.
  ///
  /// In en, this message translates to:
  /// **'Reserve'**
  String get reserve;

  /// No description provided for @availableReserve.
  ///
  /// In en, this message translates to:
  /// **'Available reserve'**
  String get availableReserve;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get pending;

  /// No description provided for @pendingTopUps.
  ///
  /// In en, this message translates to:
  /// **'Pending top ups'**
  String get pendingTopUps;

  /// No description provided for @pendingTopUpAmount.
  ///
  /// In en, this message translates to:
  /// **'€{amount} requested'**
  String pendingTopUpAmount(String amount);

  /// No description provided for @awaitingInvestor.
  ///
  /// In en, this message translates to:
  /// **'Awaiting investor'**
  String get awaitingInvestor;

  /// No description provided for @depositFunds.
  ///
  /// In en, this message translates to:
  /// **'Deposit funds'**
  String get depositFunds;

  /// No description provided for @sendMoney.
  ///
  /// In en, this message translates to:
  /// **'Send money'**
  String get sendMoney;

  /// No description provided for @receiveMoney.
  ///
  /// In en, this message translates to:
  /// **'Receive money'**
  String get receiveMoney;

  /// No description provided for @receiveMoneyTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive money'**
  String get receiveMoneyTitle;

  /// No description provided for @paymentRequest.
  ///
  /// In en, this message translates to:
  /// **'Payment request'**
  String get paymentRequest;

  /// No description provided for @optionalAmountEur.
  ///
  /// In en, this message translates to:
  /// **'Amount (EUR, optional)'**
  String get optionalAmountEur;

  /// No description provided for @generateRequest.
  ///
  /// In en, this message translates to:
  /// **'Generate request'**
  String get generateRequest;

  /// No description provided for @showThisQr.
  ///
  /// In en, this message translates to:
  /// **'Show this QR to the sender'**
  String get showThisQr;

  /// No description provided for @requestExpiresCountdown.
  ///
  /// In en, this message translates to:
  /// **'Expires in {countdown} (at {time})'**
  String requestExpiresCountdown(String countdown, String time);

  /// No description provided for @requestExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'This payment request has expired'**
  String get requestExpiredMessage;

  /// No description provided for @copyPaymentLink.
  ///
  /// In en, this message translates to:
  /// **'Copy payment link'**
  String get copyPaymentLink;

  /// No description provided for @paymentLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Payment link copied'**
  String get paymentLinkCopied;

  /// No description provided for @sharePaymentLink.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get sharePaymentLink;

  /// No description provided for @sharePaymentLinkMessage.
  ///
  /// In en, this message translates to:
  /// **'Pay me via MAT: {link}'**
  String sharePaymentLinkMessage(String link);

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// No description provided for @pastePaymentLink.
  ///
  /// In en, this message translates to:
  /// **'Paste payment link'**
  String get pastePaymentLink;

  /// No description provided for @payRequest.
  ///
  /// In en, this message translates to:
  /// **'Pay request'**
  String get payRequest;

  /// No description provided for @pay.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get pay;

  /// No description provided for @invalidPaymentLink.
  ///
  /// In en, this message translates to:
  /// **'Invalid or unsupported payment link'**
  String get invalidPaymentLink;

  /// No description provided for @payingTo.
  ///
  /// In en, this message translates to:
  /// **'Paying {name}'**
  String payingTo(String name);

  /// No description provided for @topUpSpending.
  ///
  /// In en, this message translates to:
  /// **'Top up spending'**
  String get topUpSpending;

  /// No description provided for @interests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get interests;

  /// No description provided for @noInterestsYet.
  ///
  /// In en, this message translates to:
  /// **'No interests yet.'**
  String get noInterestsYet;

  /// No description provided for @openToInvest.
  ///
  /// In en, this message translates to:
  /// **'Open to invest'**
  String get openToInvest;

  /// No description provided for @noPendingOffers.
  ///
  /// In en, this message translates to:
  /// **'No pending offers from other borrowers.'**
  String get noPendingOffers;

  /// No description provided for @addFunds.
  ///
  /// In en, this message translates to:
  /// **'Add funds'**
  String get addFunds;

  /// No description provided for @regtestReserve.
  ///
  /// In en, this message translates to:
  /// **'Regtest reserve ({network})'**
  String regtestReserve(String network);

  /// No description provided for @balanceSats.
  ///
  /// In en, this message translates to:
  /// **'Balance: {sats} sats'**
  String balanceSats(int sats);

  /// No description provided for @copyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get copyAddress;

  /// No description provided for @addressCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get addressCopied;

  /// No description provided for @syncBalance.
  ///
  /// In en, this message translates to:
  /// **'Sync balance'**
  String get syncBalance;

  /// No description provided for @reserveUpdated.
  ///
  /// In en, this message translates to:
  /// **'Reserve updated: {sats} sats'**
  String reserveUpdated(int sats);

  /// No description provided for @reserveInstructions.
  ///
  /// In en, this message translates to:
  /// **'Ask admin to send BTC from Exchange wallet to this address, then tap Sync.'**
  String get reserveInstructions;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @sendMoneyTitle.
  ///
  /// In en, this message translates to:
  /// **'Send money'**
  String get sendMoneyTitle;

  /// No description provided for @availableEur.
  ///
  /// In en, this message translates to:
  /// **'Available: €{amount}'**
  String availableEur(String amount);

  /// No description provided for @noSpendingBalance.
  ///
  /// In en, this message translates to:
  /// **'No spending balance yet. Activate a deal or receive EURT first.'**
  String get noSpendingBalance;

  /// No description provided for @recipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get recipient;

  /// No description provided for @amountEur.
  ///
  /// In en, this message translates to:
  /// **'Amount (EUR)'**
  String get amountEur;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent €{amount} to {name}'**
  String sentTo(String amount, String name);

  /// No description provided for @topUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Top up spending/savings account'**
  String get topUpTitle;

  /// No description provided for @topUp.
  ///
  /// In en, this message translates to:
  /// **'Top up'**
  String get topUp;

  /// No description provided for @topUpSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Top up submitted'**
  String get topUpSubmitted;

  /// No description provided for @noReserveToTopUp.
  ///
  /// In en, this message translates to:
  /// **'No reserve balance available to top up.'**
  String get noReserveToTopUp;

  /// No description provided for @maxFromReserve.
  ///
  /// In en, this message translates to:
  /// **'Maximum from reserve: €{amount}'**
  String maxFromReserve(String amount);

  /// No description provided for @estimatedExpiration.
  ///
  /// In en, this message translates to:
  /// **'Estimated expiration'**
  String get estimatedExpiration;

  /// No description provided for @expirationNote.
  ///
  /// In en, this message translates to:
  /// **'At expiration your funds will return to the reserve account.'**
  String get expirationNote;

  /// No description provided for @enterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get enterValidAmount;

  /// No description provided for @amountExceedsReserve.
  ///
  /// In en, this message translates to:
  /// **'Amount cannot exceed your reserve (€{amount})'**
  String amountExceedsReserve(String amount);

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @dealTitle.
  ///
  /// In en, this message translates to:
  /// **'Deal #{id}'**
  String dealTitle(String id);

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rate;

  /// No description provided for @ratePerMonth.
  ///
  /// In en, this message translates to:
  /// **'{rate}% / month'**
  String ratePerMonth(String rate);

  /// No description provided for @period.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get period;

  /// No description provided for @borrower.
  ///
  /// In en, this message translates to:
  /// **'Borrower'**
  String get borrower;

  /// No description provided for @investor.
  ///
  /// In en, this message translates to:
  /// **'Investor'**
  String get investor;

  /// No description provided for @peg.
  ///
  /// In en, this message translates to:
  /// **'Peg'**
  String get peg;

  /// No description provided for @pool.
  ///
  /// In en, this message translates to:
  /// **'Pool'**
  String get pool;

  /// No description provided for @poolSats.
  ///
  /// In en, this message translates to:
  /// **'{sats} sats'**
  String poolSats(int sats);

  /// No description provided for @liabilityAtMaturity.
  ///
  /// In en, this message translates to:
  /// **'Liability at maturity'**
  String get liabilityAtMaturity;

  /// No description provided for @tokenHolders.
  ///
  /// In en, this message translates to:
  /// **'Token holders'**
  String get tokenHolders;

  /// No description provided for @interestAmount.
  ///
  /// In en, this message translates to:
  /// **'+€{amount} interest'**
  String interestAmount(String amount);

  /// No description provided for @acceptAndActivate.
  ///
  /// In en, this message translates to:
  /// **'Accept & activate'**
  String get acceptAndActivate;

  /// No description provided for @dealActivated.
  ///
  /// In en, this message translates to:
  /// **'Deal activated'**
  String get dealActivated;

  /// No description provided for @transfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfers;

  /// No description provided for @sendEurt.
  ///
  /// In en, this message translates to:
  /// **'Send EURT'**
  String get sendEurt;

  /// No description provided for @transferSent.
  ///
  /// In en, this message translates to:
  /// **'Transfer sent'**
  String get transferSent;

  /// No description provided for @noTransfersYet.
  ///
  /// In en, this message translates to:
  /// **'No transfers yet'**
  String get noTransfersYet;

  /// No description provided for @settlement.
  ///
  /// In en, this message translates to:
  /// **'Settlement'**
  String get settlement;

  /// No description provided for @spotRate.
  ///
  /// In en, this message translates to:
  /// **'Spot rate'**
  String get spotRate;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @floorEurPayoff.
  ///
  /// In en, this message translates to:
  /// **'FloorEUR payoff'**
  String get floorEurPayoff;

  /// No description provided for @totalLiability.
  ///
  /// In en, this message translates to:
  /// **'Total liability'**
  String get totalLiability;

  /// No description provided for @holderSats.
  ///
  /// In en, this message translates to:
  /// **'Holder sats'**
  String get holderSats;

  /// No description provided for @investorRemainder.
  ///
  /// In en, this message translates to:
  /// **'Investor remainder'**
  String get investorRemainder;

  /// No description provided for @insolventNote.
  ///
  /// In en, this message translates to:
  /// **'Insolvent at this spot — capped by escrow'**
  String get insolventNote;

  /// No description provided for @holderAllocations.
  ///
  /// In en, this message translates to:
  /// **'Holder allocations'**
  String get holderAllocations;

  /// No description provided for @shareAmount.
  ///
  /// In en, this message translates to:
  /// **'€{amount} share'**
  String shareAmount(String amount);

  /// No description provided for @settlementPreviewNote.
  ///
  /// In en, this message translates to:
  /// **'Preview — amounts shown are recomputed on-device via mat_sdk; relay figures are compared for mismatch.'**
  String get settlementPreviewNote;

  /// No description provided for @settlementExecutedNote.
  ///
  /// In en, this message translates to:
  /// **'Settlement executed on relay (PoC admin path). Inputs included for offline FloorEUR audit.'**
  String get settlementExecutedNote;

  /// No description provided for @onDeviceFloorEur.
  ///
  /// In en, this message translates to:
  /// **'Recomputed on-device (mat_sdk)'**
  String get onDeviceFloorEur;

  /// No description provided for @settlementMismatchWarning.
  ///
  /// In en, this message translates to:
  /// **'On-device FloorEUR does not match the relay preview. Do not trust the server figures.'**
  String get settlementMismatchWarning;

  /// No description provided for @localWalletDebug.
  ///
  /// In en, this message translates to:
  /// **'Local wallet (BDK spike)'**
  String get localWalletDebug;

  /// No description provided for @localWalletDebugSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Phase 2: create/load mnemonic and show a receive address'**
  String get localWalletDebugSubtitle;

  /// No description provided for @localWalletCreate.
  ///
  /// In en, this message translates to:
  /// **'Create wallet'**
  String get localWalletCreate;

  /// No description provided for @localWalletReceiveAddress.
  ///
  /// In en, this message translates to:
  /// **'Receive address'**
  String get localWalletReceiveAddress;

  /// No description provided for @localWalletMnemonicSaved.
  ///
  /// In en, this message translates to:
  /// **'Mnemonic stored on device (debug only — not production-safe)'**
  String get localWalletMnemonicSaved;

  /// No description provided for @localWalletError.
  ///
  /// In en, this message translates to:
  /// **'Wallet error: {detail}'**
  String localWalletError(String detail);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
