//! FloorEUR payoff engine — single source of truth for holder sats at settlement.
//!
//! Mirrors `app/services/payoffs/floor_eur_calculator.rb`.

use crate::constants::ESTIMATED_SETTLEMENT_FEE_SATS;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HolderAllocation {
    pub share_cents: u64,
    pub btc_sats: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FloorEurResult {
    pub notional_eur_cents: u64,
    pub months_elapsed: u32,
    pub liability_eur_cents: u64,
    pub gross_holder_sats: u64,
    pub total_holder_sats: u64,
    pub distributable_sats: u64,
    pub investor_remainder_sats: u64,
    pub mining_fee_sats: u64,
    pub insolvent: bool,
    pub holder_allocations: Vec<HolderAllocation>,
}

#[derive(Debug, Clone)]
pub struct FloorEurCalculator {
    pub notional_eur_cents: u64,
    pub notional_total_cents: u64,
    pub holder_shares_cents: Vec<u64>,
    pub spot_eur_per_btc: u64,
    pub rate_bps_monthly: u32,
    pub months_elapsed: u32,
    pub escrow_total_sats: u64,
    pub mining_fee_sats: u64,
}

impl FloorEurCalculator {
    pub fn call(self) -> Result<FloorEurResult, FloorEurError> {
        self.validate()?;
        let liability = liability_eur_cents(
            self.notional_eur_cents,
            self.rate_bps_monthly,
            self.months_elapsed,
        );
        let gross = gross_holder_sats(liability, self.spot_eur_per_btc);
        let distributable = self
            .escrow_total_sats
            .saturating_sub(self.mining_fee_sats);
        let total_holder = gross.min(distributable);
        let insolvent = gross > distributable;

        Ok(FloorEurResult {
            notional_eur_cents: self.notional_eur_cents,
            months_elapsed: self.months_elapsed,
            liability_eur_cents: liability,
            gross_holder_sats: gross,
            total_holder_sats: total_holder,
            distributable_sats: distributable,
            investor_remainder_sats: distributable.saturating_sub(total_holder),
            mining_fee_sats: self.mining_fee_sats,
            insolvent,
            holder_allocations: allocate_holders(
                total_holder,
                &self.holder_shares_cents,
                self.notional_total_cents,
            )?,
        })
    }

    fn validate(&self) -> Result<(), FloorEurError> {
        if self.spot_eur_per_btc == 0 {
            return Err(FloorEurError::InvalidSpot);
        }
        if !self.holder_shares_cents.is_empty() && self.notional_total_cents == 0 {
            return Err(FloorEurError::InvalidNotionalTotal);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum FloorEurError {
    #[error("spot_eur_per_btc must be positive")]
    InvalidSpot,
    #[error("notional_total must be positive when holders are present")]
    InvalidNotionalTotal,
}

fn liability_eur_cents(notional_eur_cents: u64, rate_bps_monthly: u32, months_elapsed: u32) -> u64 {
    let factor = 10_000u64 + u64::from(rate_bps_monthly) * u64::from(months_elapsed);
    (notional_eur_cents * factor) / 10_000
}

fn gross_holder_sats(liability_eur_cents: u64, spot_eur_per_btc: u64) -> u64 {
    let numerator = liability_eur_cents.saturating_mul(100_000_000);
    let denominator = spot_eur_per_btc.saturating_mul(100);
    numerator / denominator
}

fn allocate_holders(
    total_holder_sats: u64,
    holder_shares_cents: &[u64],
    notional_total_cents: u64,
) -> Result<Vec<HolderAllocation>, FloorEurError> {
    if holder_shares_cents.is_empty() {
        return Ok(vec![]);
    }
    if notional_total_cents == 0 {
        return Err(FloorEurError::InvalidNotionalTotal);
    }

    let mut allocations = Vec::with_capacity(holder_shares_cents.len());
    let mut assigned = 0u64;

    for &share_cents in &holder_shares_cents[..holder_shares_cents.len() - 1] {
        let sats = (total_holder_sats * share_cents) / notional_total_cents;
        allocations.push(HolderAllocation {
            share_cents,
            btc_sats: sats,
        });
        assigned += sats;
    }

    let last_share = *holder_shares_cents.last().expect("non-empty");
    allocations.push(HolderAllocation {
        share_cents: last_share,
        btc_sats: total_holder_sats.saturating_sub(assigned),
    });

    Ok(allocations)
}

impl Default for FloorEurCalculator {
    fn default() -> Self {
        Self {
            notional_eur_cents: 0,
            notional_total_cents: 0,
            holder_shares_cents: vec![],
            spot_eur_per_btc: 1,
            rate_bps_monthly: 0,
            months_elapsed: 0,
            escrow_total_sats: 0,
            mining_fee_sats: ESTIMATED_SETTLEMENT_FEE_SATS,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    fn calc(
        spot: u64,
        holder_shares_cents: Vec<u64>,
        escrow_total_sats: u64,
        mining_fee_sats: u64,
    ) -> FloorEurResult {
        let notional = 500_000u64;
        FloorEurCalculator {
            notional_eur_cents: notional,
            notional_total_cents: notional,
            holder_shares_cents,
            spot_eur_per_btc: spot,
            rate_bps_monthly: 100,
            months_elapsed: 6,
            escrow_total_sats,
            mining_fee_sats,
            ..Default::default()
        }
        .call()
        .expect("calc")
    }

    // PAYOFF-SPEC §5 — ported from spec/services/payoffs/floor_eur_calculator_spec.rb
    #[test]
    fn payoff_spec_section5_three_spots() {
        let liability = 530_000;
        assert_eq!(calc(25_000, vec![500_000], 50_000_000, 0).liability_eur_cents, liability);
        assert_eq!(calc(25_000, vec![500_000], 50_000_000, 0).total_holder_sats, 21_200_000);
        assert_eq!(calc(50_000, vec![500_000], 50_000_000, 0).total_holder_sats, 10_600_000);
        assert_eq!(calc(100_000, vec![500_000], 50_000_000, 0).total_holder_sats, 5_300_000);
    }

    #[test]
    fn payoff_spec_section5_eur_value_stable_when_spot_rises() {
        let low = calc(50_000, vec![500_000], 50_000_000, 0);
        let high = calc(100_000, vec![500_000], 50_000_000, 0);
        assert_eq!(low.liability_eur_cents, high.liability_eur_cents);
        assert!(high.total_holder_sats < low.total_holder_sats);
    }

    #[test]
    fn payoff_spec_section5_transfer_40_percent() {
        let result = calc(50_000, vec![300_000, 200_000], 50_000_000, 0);
        assert_eq!(result.total_holder_sats, 10_600_000);
        assert_eq!(result.holder_allocations[0].btc_sats, 6_360_000);
        assert_eq!(result.holder_allocations[1].btc_sats, 4_240_000);
    }

    #[test]
    fn payoff_spec_section7_cap_escrow() {
        let result = calc(25_000, vec![500_000], 1_500_000, 0);
        assert_eq!(result.gross_holder_sats, 21_200_000);
        assert_eq!(result.total_holder_sats, 1_500_000);
        assert!(result.insolvent);
        assert_eq!(result.investor_remainder_sats, 0);
    }

    #[test]
    fn payoff_spec_section7_mining_fee_deducted_first() {
        let fee = ESTIMATED_SETTLEMENT_FEE_SATS;
        let escrow = 10_600_000 + fee;
        let result = calc(50_000, vec![500_000], escrow, fee);
        assert_eq!(result.distributable_sats, 10_600_000);
        assert_eq!(result.total_holder_sats, 10_600_000);
        assert_eq!(result.investor_remainder_sats, 0);
    }

    // Demo interest at peg — ported from spec/scenarios/demo_interest_at_peg_spec.rb
    #[test]
    fn demo_interest_at_peg_holder_targets() {
        let result = FloorEurCalculator {
            notional_eur_cents: 100_000,
            notional_total_cents: 100_000,
            holder_shares_cents: vec![50_000, 40_000, 10_000],
            spot_eur_per_btc: 50_000,
            rate_bps_monthly: 100,
            months_elapsed: 1,
            escrow_total_sats: 3_975_000,
            mining_fee_sats: 0,
            ..Default::default()
        }
        .call()
        .expect("demo");

        assert_eq!(result.liability_eur_cents, 101_000);
        assert_eq!(result.total_holder_sats, 2_020_000);
        assert_eq!(result.holder_allocations[0].btc_sats, 1_010_000);
        assert_eq!(result.holder_allocations[1].btc_sats, 808_000);
        assert_eq!(result.holder_allocations[2].btc_sats, 202_000);
        let sum: u64 = result.holder_allocations.iter().map(|a| a.btc_sats).sum();
        assert_eq!(sum, 2_020_000);
    }
}
