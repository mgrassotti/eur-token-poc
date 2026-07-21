import 'constants.dart';

/// FloorEUR payoff engine — Dart mirror of `mat-core::floor_eur`.
class HolderAllocation {
  const HolderAllocation({required this.shareCents, required this.btcSats});

  final int shareCents;
  final int btcSats;
}

class FloorEurResult {
  const FloorEurResult({
    required this.notionalEurCents,
    required this.monthsElapsed,
    required this.liabilityEurCents,
    required this.grossHolderSats,
    required this.totalHolderSats,
    required this.distributableSats,
    required this.investorRemainderSats,
    required this.miningFeeSats,
    required this.insolvent,
    required this.holderAllocations,
  });

  final int notionalEurCents;
  final int monthsElapsed;
  final int liabilityEurCents;
  final int grossHolderSats;
  final int totalHolderSats;
  final int distributableSats;
  final int investorRemainderSats;
  final int miningFeeSats;
  final bool insolvent;
  final List<HolderAllocation> holderAllocations;
}

class FloorEurCalculator {
  FloorEurCalculator({
    required this.notionalEurCents,
    required this.notionalTotalCents,
    required this.holderSharesCents,
    required this.spotEurPerBtc,
    required this.rateBpsMonthly,
    required this.monthsElapsed,
    required this.escrowTotalSats,
    this.miningFeeSats = estimatedSettlementFeeSats,
  });

  final int notionalEurCents;
  final int notionalTotalCents;
  final List<int> holderSharesCents;
  final int spotEurPerBtc;
  final int rateBpsMonthly;
  final int monthsElapsed;
  final int escrowTotalSats;
  final int miningFeeSats;

  FloorEurResult call() {
    if (spotEurPerBtc <= 0) {
      throw ArgumentError('spotEurPerBtc must be positive');
    }
    if (holderSharesCents.isNotEmpty && notionalTotalCents <= 0) {
      throw ArgumentError('notionalTotal must be positive when holders are present');
    }

    final liability = _liabilityEurCents(notionalEurCents, rateBpsMonthly, monthsElapsed);
    final gross = _grossHolderSats(liability, spotEurPerBtc);
    final distributable = (escrowTotalSats - miningFeeSats).clamp(0, escrowTotalSats);
    final totalHolder = gross < distributable ? gross : distributable;
    final insolvent = gross > distributable;

    return FloorEurResult(
      notionalEurCents: notionalEurCents,
      monthsElapsed: monthsElapsed,
      liabilityEurCents: liability,
      grossHolderSats: gross,
      totalHolderSats: totalHolder,
      distributableSats: distributable,
      investorRemainderSats: distributable - totalHolder,
      miningFeeSats: miningFeeSats,
      insolvent: insolvent,
      holderAllocations: _allocateHolders(totalHolder, holderSharesCents, notionalTotalCents),
    );
  }

  static int _liabilityEurCents(int notional, int rateBps, int months) {
    final factor = 10000 + rateBps * months;
    return (notional * factor) ~/ 10000;
  }

  static int _grossHolderSats(int liabilityEurCents, int spotEurPerBtc) {
    final numerator = liabilityEurCents * 100000000;
    final denominator = spotEurPerBtc * 100;
    return numerator ~/ denominator;
  }

  static List<HolderAllocation> _allocateHolders(
    int totalHolderSats,
    List<int> shares,
    int notionalTotalCents,
  ) {
    if (shares.isEmpty) return const [];
    if (notionalTotalCents <= 0) {
      throw ArgumentError('notionalTotal must be positive when holders are present');
    }

    final allocations = <HolderAllocation>[];
    var assigned = 0;
    for (var i = 0; i < shares.length - 1; i++) {
      final sats = (totalHolderSats * shares[i]) ~/ notionalTotalCents;
      allocations.add(HolderAllocation(shareCents: shares[i], btcSats: sats));
      assigned += sats;
    }
    allocations.add(
      HolderAllocation(
        shareCents: shares.last,
        btcSats: totalHolderSats - assigned,
      ),
    );
    return allocations;
  }
}
