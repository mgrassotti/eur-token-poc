class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.admin,
  });

  final int id;
  final String name;
  final String email;
  final bool admin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is User && id == other.id;

  @override
  int get hashCode => id.hashCode;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String? ?? '',
      admin: json['admin'] as bool? ?? false,
    );
  }
}

class DealPeriod {
  const DealPeriod({required this.start, required this.end});

  final String start;
  final String end;

  factory DealPeriod.fromJson(Map<String, dynamic> json) {
    return DealPeriod(
      start: json['start'] as String,
      end: json['end'] as String,
    );
  }
}

class Deal {
  const Deal({
    required this.id,
    required this.status,
    required this.amountEurCents,
    required this.rateBpsMonthly,
    required this.period,
    this.borrower,
    this.investor,
    this.pegEurPerBtc,
    this.poolSats = 0,
    this.readyForSettlement = false,
    this.tokenHolders = const [],
    this.liabilityEurCents,
    this.fundingAddress,
    this.investorFundingAddress,
    this.fundingPsbt,
    this.awaitingFundingSignatures = false,
    this.borrowerFundingSigned = false,
    this.investorFundingSigned = false,
    this.awaitingDlcSignatures = false,
    this.borrowerDlcSigned = false,
    this.investorDlcSigned = false,
    this.signPackage,
    this.saverPayoutMode,
    this.investorPayoutMode,
  });

  final String id;
  final String status;
  final int amountEurCents;
  final int rateBpsMonthly;
  final DealPeriod period;
  final User? borrower;
  final User? investor;
  final double? pegEurPerBtc;
  final int poolSats;
  final bool readyForSettlement;
  final List<TokenHolder> tokenHolders;
  final int? liabilityEurCents;
  final String? fundingAddress;
  final String? investorFundingAddress;
  final String? fundingPsbt;
  final bool awaitingFundingSignatures;
  final bool borrowerFundingSigned;
  final bool investorFundingSigned;
  final bool awaitingDlcSignatures;
  final bool borrowerDlcSigned;
  final bool investorDlcSigned;
  final Map<String, dynamic>? signPackage;
  final String? saverPayoutMode;
  final String? investorPayoutMode;

  double get amountEur => amountEurCents / 100.0;

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isSettled => status == 'settled';
  bool get awaitingSignatures => awaitingFundingSignatures || awaitingDlcSignatures;

  factory Deal.fromJson(Map<String, dynamic> json) {
    return Deal(
      id: json['id'] as String,
      status: json['status'] as String,
      amountEurCents: json['amount_eur_cents'] as int,
      rateBpsMonthly: json['rate_bps_monthly'] as int,
      period: DealPeriod.fromJson(json['period'] as Map<String, dynamic>),
      borrower: json['borrower'] != null
          ? User.fromJson(json['borrower'] as Map<String, dynamic>)
          : null,
      investor: json['investor'] != null
          ? User.fromJson(json['investor'] as Map<String, dynamic>)
          : null,
      pegEurPerBtc: (json['peg_eur_per_btc'] as num?)?.toDouble(),
      poolSats: json['pool_sats'] as int? ?? 0,
      readyForSettlement: json['ready_for_settlement'] as bool? ?? false,
      tokenHolders: (json['token_holders'] as List<dynamic>?)
              ?.map((e) => TokenHolder.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      liabilityEurCents: json['liability_eur_cents'] as int?,
      fundingAddress: json['funding_address'] as String?,
      investorFundingAddress: json['investor_funding_address'] as String?,
      fundingPsbt: json['funding_psbt'] as String?,
      awaitingFundingSignatures: json['awaiting_funding_signatures'] as bool? ?? false,
      borrowerFundingSigned: json['borrower_funding_signed'] as bool? ?? false,
      investorFundingSigned: json['investor_funding_signed'] as bool? ?? false,
      awaitingDlcSignatures: json['awaiting_dlc_signatures'] as bool? ?? false,
      borrowerDlcSigned: json['borrower_dlc_signed'] as bool? ?? false,
      investorDlcSigned: json['investor_dlc_signed'] as bool? ?? false,
      signPackage: json['sign_package'] as Map<String, dynamic>?,
      saverPayoutMode: json['saver_payout_mode'] as String?,
      investorPayoutMode: json['investor_payout_mode'] as String?,
    );
  }
}

class FundingRequest {
  const FundingRequest({
    required this.id,
    required this.role,
    required this.status,
    required this.amountEurCents,
    required this.payoutMode,
    required this.receiveAddress,
    required this.collectionIban,
    this.payoutIban,
    this.budgetId,
    this.remainingEurCents,
    this.requiredSats,
  });

  final String id;
  final String role;
  final String status;
  final int amountEurCents;
  final String payoutMode;
  final String receiveAddress;
  final String collectionIban;
  final String? payoutIban;
  final String? budgetId;
  final int? remainingEurCents;
  final int? requiredSats;

  double get amountEur => amountEurCents / 100.0;
  bool get isSaver => role == 'saver';
  bool get isInvestor => role == 'investor';
  bool get awaitingDeposit => status == 'awaiting_deposit';
  bool get queued => status == 'queued';
  bool get matched => status == 'matched';

  factory FundingRequest.fromJson(Map<String, dynamic> json) {
    return FundingRequest(
      id: json['id'].toString(),
      role: json['role'] as String,
      status: json['status'] as String,
      amountEurCents: json['amount_eur_cents'] as int,
      payoutMode: json['payout_mode'] as String,
      receiveAddress: json['receive_address'] as String,
      collectionIban: json['collection_iban'] as String? ?? '',
      payoutIban: json['payout_iban'] as String?,
      budgetId: json['budget_id']?.toString(),
      remainingEurCents: json['remaining_eur_cents'] as int?,
      requiredSats: json['required_sats'] as int?,
    );
  }
}

class TokenHolder {
  const TokenHolder({
    required this.user,
    required this.balanceCents,
    this.interestCents,
  });

  final User user;
  final int balanceCents;
  final int? interestCents;

  factory TokenHolder.fromJson(Map<String, dynamic> json) {
    return TokenHolder(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      balanceCents: json['balance_cents'] as int,
      interestCents: json['interest_cents'] as int?,
    );
  }
}

class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.amountCents,
    required this.fromUser,
    required this.toUser,
    required this.createdAt,
  });

  final int id;
  final int amountCents;
  final User fromUser;
  final User toUser;
  final String createdAt;

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    return TransferRecord(
      id: json['id'] as int,
      amountCents: json['amount_cents'] as int,
      fromUser: User.fromJson(json['from_user'] as Map<String, dynamic>),
      toUser: User.fromJson(json['to_user'] as Map<String, dynamic>),
      createdAt: json['created_at'] as String,
    );
  }
}

class SettlementPreview {
  const SettlementPreview({
    required this.status,
    required this.endBtcEurRate,
    required this.readyForSettlement,
    this.payoff,
    this.holderAllocations = const [],
    this.calculationInputs,
  });

  final String status;
  final double? endBtcEurRate;
  final bool readyForSettlement;
  final PayoffSummary? payoff;
  final List<HolderAllocation> holderAllocations;
  final SettlementCalculationInputs? calculationInputs;

  factory SettlementPreview.fromJson(Map<String, dynamic> json) {
    return SettlementPreview(
      status: json['status'] as String,
      endBtcEurRate: (json['end_btc_eur_rate'] as num?)?.toDouble(),
      readyForSettlement: json['ready_for_settlement'] as bool? ?? false,
      payoff: json['payoff'] != null
          ? PayoffSummary.fromJson(json['payoff'] as Map<String, dynamic>)
          : null,
      holderAllocations: (json['holder_allocations'] as List<dynamic>?)
              ?.map((e) => HolderAllocation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      calculationInputs: json['calculation_inputs'] != null
          ? SettlementCalculationInputs.fromJson(
              json['calculation_inputs'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// Inputs for on-device FloorEUR recompute (mirrors relay `calculation_inputs`).
class SettlementCalculationInputs {
  const SettlementCalculationInputs({
    required this.notionalEurCents,
    required this.notionalTotalCents,
    required this.holderSharesCents,
    required this.spotEurPerBtc,
    required this.rateBpsMonthly,
    required this.monthsElapsed,
    required this.escrowTotalSats,
    required this.miningFeeSats,
  });

  final int notionalEurCents;
  final int notionalTotalCents;
  final List<int> holderSharesCents;
  final int spotEurPerBtc;
  final int rateBpsMonthly;
  final int monthsElapsed;
  final int escrowTotalSats;
  final int miningFeeSats;

  factory SettlementCalculationInputs.fromJson(Map<String, dynamic> json) {
    return SettlementCalculationInputs(
      notionalEurCents: json['notional_eur_cents'] as int? ?? 0,
      notionalTotalCents: json['notional_total_cents'] as int? ?? 0,
      holderSharesCents: (json['holder_shares_cents'] as List<dynamic>? ?? const [])
          .map((e) => e as int)
          .toList(),
      spotEurPerBtc: json['spot_eur_per_btc'] as int? ?? 0,
      rateBpsMonthly: json['rate_bps_monthly'] as int? ?? 0,
      monthsElapsed: json['months_elapsed'] as int? ?? 0,
      escrowTotalSats: json['escrow_total_sats'] as int? ?? 0,
      miningFeeSats: json['mining_fee_sats'] as int? ?? 5000,
    );
  }
}

class PayoffSummary {
  const PayoffSummary({
    required this.liabilityEurCents,
    required this.totalHolderSats,
    required this.investorRemainderSats,
    required this.insolvent,
  });

  final int liabilityEurCents;
  final int totalHolderSats;
  final int investorRemainderSats;
  final bool insolvent;

  factory PayoffSummary.fromJson(Map<String, dynamic> json) {
    return PayoffSummary(
      liabilityEurCents: json['liability_eur_cents'] as int,
      totalHolderSats: json['total_holder_sats'] as int,
      investorRemainderSats: json['investor_remainder_sats'] as int,
      insolvent: json['insolvent'] as bool? ?? false,
    );
  }
}

class HolderAllocation {
  const HolderAllocation({
    required this.user,
    required this.shareCents,
    required this.btcSats,
  });

  final User user;
  final int shareCents;
  final int btcSats;

  factory HolderAllocation.fromJson(Map<String, dynamic> json) {
    return HolderAllocation(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      shareCents: json['share_cents'] as int,
      btcSats: json['btc_sats'] as int,
    );
  }
}

class ReserveInfo {
  const ReserveInfo({
    required this.network,
    required this.receiveAddress,
    required this.balanceSats,
    this.walletName,
    this.instructions,
  });

  final String network;
  final String receiveAddress;
  final int balanceSats;
  final String? walletName;
  final String? instructions;

  factory ReserveInfo.fromJson(Map<String, dynamic> json) {
    return ReserveInfo(
      network: json['network'] as String,
      receiveAddress: json['receive_address'] as String,
      balanceSats: json['balance_sats'] as int? ?? 0,
      walletName: json['wallet_name'] as String?,
      instructions: json['instructions'] as String?,
    );
  }
}

class FundPosition {
  const FundPosition({
    required this.dealId,
    required this.interestCents,
    required this.periodEnd,
  });

  final String dealId;
  final int interestCents;
  final String periodEnd;

  double get interestEur => interestCents / 100.0;

  factory FundPosition.fromJson(Map<String, dynamic> json) {
    return FundPosition(
      dealId: json['deal_id'] as String,
      interestCents: json['interest_cents'] as int? ?? 0,
      periodEnd: json['period_end'] as String,
    );
  }
}

class DashboardData {
  const DashboardData({
    required this.user,
    required this.marketRateEur,
    required this.spendingEurCents,
    required this.savingsSats,
    required this.maxBorrowableEurCents,
    required this.borrowedDeals,
    required this.fundPositions,
    this.investableDeals = const [],
    this.fundingRequests = const [],
    this.collectionIban,
  });

  final User user;
  final double? marketRateEur;
  final int spendingEurCents;
  final int savingsSats;
  final int maxBorrowableEurCents;
  final List<Deal> borrowedDeals;
  final List<FundPosition> fundPositions;
  final List<Deal> investableDeals;
  final List<FundingRequest> fundingRequests;
  final String? collectionIban;

  double get maxBorrowableEur => maxBorrowableEurCents / 100.0;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final market = json['market_rate'] as Map<String, dynamic>?;
    return DashboardData(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      marketRateEur: (market?['btc_eur_per_btc'] as num?)?.toDouble(),
      spendingEurCents: json['spending_eur_cents'] as int? ?? 0,
      savingsSats: (json['savings'] as Map<String, dynamic>?)?['sats'] as int? ?? 0,
      maxBorrowableEurCents: json['max_borrowable_eur_cents'] as int? ?? 0,
      borrowedDeals: (json['borrowed_deals'] as List<dynamic>? ?? const [])
          .map((e) => Deal.fromJson(e as Map<String, dynamic>))
          .toList(),
      fundPositions: (json['fund_positions'] as List<dynamic>? ?? const [])
          .map((e) => FundPosition.fromJson(e as Map<String, dynamic>))
          .toList(),
      investableDeals: (json['investable_deals'] as List<dynamic>? ?? const [])
          .map((e) => Deal.fromJson(e as Map<String, dynamic>))
          .toList(),
      fundingRequests: (json['funding_requests'] as List<dynamic>? ?? const [])
          .map((e) => FundingRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
      collectionIban: json['collection_iban'] as String?,
    );
  }
}

class ReceiveRequestInfo {
  const ReceiveRequestInfo({
    required this.id,
    required this.user,
    this.amountEurCents,
    required this.qrPayload,
    required this.expiresAt,
    required this.paid,
    required this.expired,
  });

  final String id;
  final User user;
  final int? amountEurCents;
  final String qrPayload;
  final DateTime expiresAt;
  final bool paid;
  final bool expired;

  factory ReceiveRequestInfo.fromJson(Map<String, dynamic> json) {
    return ReceiveRequestInfo(
      id: json['id'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      amountEurCents: json['amount_eur_cents'] as int?,
      qrPayload: json['qr_payload'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      paid: json['paid'] as bool? ?? false,
      expired: json['expired'] as bool? ?? false,
    );
  }
}

/// Parsed `mat:pay/1?...` deep link from a Receive QR.
class MatPayLink {
  const MatPayLink({
    required this.userId,
    required this.requestId,
    this.amountEurCents,
  });

  final int userId;
  final String requestId;
  final int? amountEurCents;

  static MatPayLink? tryParse(String raw) {
    final trimmed = raw.trim();
    final match = RegExp(
      r'^mat:pay/1\?(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) return null;

    final params = Uri.splitQueryString(match.group(1)!);
    final userId = int.tryParse(params['u'] ?? '');
    final rid = params['rid'];
    if (userId == null || rid == null || rid.isEmpty) return null;

    final amount = params['a'];
    return MatPayLink(
      userId: userId,
      requestId: rid,
      amountEurCents: amount != null ? int.tryParse(amount) : null,
    );
  }
}
