import 'package:mat_sdk/mat_sdk.dart';
import 'package:test/test.dart';

FloorEurResult calc(
  int spot,
  List<int> holderSharesCents,
  int escrowTotalSats,
  int miningFeeSats,
) {
  return FloorEurCalculator(
    notionalEurCents: 500000,
    notionalTotalCents: 500000,
    holderSharesCents: holderSharesCents,
    spotEurPerBtc: spot,
    rateBpsMonthly: 100,
    monthsElapsed: 6,
    escrowTotalSats: escrowTotalSats,
    miningFeeSats: miningFeeSats,
  ).call();
}

void main() {
  // PAYOFF-SPEC §5 — mirrored from mat-core/src/floor_eur.rs
  test('payoff_spec_section5_three_spots', () {
    const liability = 530000;
    expect(calc(25000, [500000], 50000000, 0).liabilityEurCents, liability);
    expect(calc(25000, [500000], 50000000, 0).totalHolderSats, 21200000);
    expect(calc(50000, [500000], 50000000, 0).totalHolderSats, 10600000);
    expect(calc(100000, [500000], 50000000, 0).totalHolderSats, 5300000);
  });

  test('payoff_spec_section5_eur_value_stable_when_spot_rises', () {
    final low = calc(50000, [500000], 50000000, 0);
    final high = calc(100000, [500000], 50000000, 0);
    expect(low.liabilityEurCents, high.liabilityEurCents);
    expect(high.totalHolderSats, lessThan(low.totalHolderSats));
  });

  test('payoff_spec_section5_transfer_40_percent', () {
    final result = calc(50000, [300000, 200000], 50000000, 0);
    expect(result.totalHolderSats, 10600000);
    expect(result.holderAllocations[0].btcSats, 6360000);
    expect(result.holderAllocations[1].btcSats, 4240000);
  });

  test('payoff_spec_section7_cap_escrow', () {
    final result = calc(25000, [500000], 1500000, 0);
    expect(result.grossHolderSats, 21200000);
    expect(result.totalHolderSats, 1500000);
    expect(result.insolvent, isTrue);
    expect(result.investorRemainderSats, 0);
  });

  test('payoff_spec_section7_mining_fee_deducted_first', () {
    const fee = estimatedSettlementFeeSats;
    final escrow = 10600000 + fee;
    final result = calc(50000, [500000], escrow, fee);
    expect(result.distributableSats, 10600000);
    expect(result.totalHolderSats, 10600000);
    expect(result.investorRemainderSats, 0);
  });

  test('demo_interest_at_peg_holder_targets', () {
    final result = FloorEurCalculator(
      notionalEurCents: 100000,
      notionalTotalCents: 100000,
      holderSharesCents: [50000, 40000, 10000],
      spotEurPerBtc: 50000,
      rateBpsMonthly: 100,
      monthsElapsed: 1,
      escrowTotalSats: 3975000,
      miningFeeSats: 0,
    ).call();

    expect(result.liabilityEurCents, 101000);
    expect(result.totalHolderSats, 2020000);
    expect(result.holderAllocations[0].btcSats, 1010000);
    expect(result.holderAllocations[1].btcSats, 808000);
    expect(result.holderAllocations[2].btcSats, 202000);
    final sum = result.holderAllocations.fold<int>(0, (a, b) => a + b.btcSats);
    expect(sum, 2020000);
  });

  test('symbolic_months_duration', () {
    expect(
      symbolicMonthsDuration(const Period(startYear: 2026, startMonth: 1, endYear: 2026, endMonth: 2)),
      1,
    );
    expect(
      symbolicMonthsDuration(const Period(startYear: 2026, startMonth: 1, endYear: 2026, endMonth: 7)),
      6,
    );
  });
}
