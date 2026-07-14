//! FloorEUR DLC payout schedule — mirrors `lib/dlc/payout_curve.rb`.

use crate::constants::{
    DEFAULT_NUMERIC_BASE, DEFAULT_NUM_DIGITS, ESTIMATED_SETTLEMENT_FEE_SATS,
};
use crate::floor_eur::FloorEurCalculator;
use crate::months::{Date, Period, symbolic_months_duration};
use crate::numeric::Numeric;

/// Price anchors as multipliers of the peg (denser below peg in insolvency region).
pub const DEFAULT_PRICE_MULTIPLIERS: &[f64] = &[0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PayoutPoint {
    pub outcome: u64,
    pub peg_sats: u64,
    pub investor_sats: u64,
}

#[derive(Debug, Clone)]
pub struct PayoutCurveInput {
    pub amount_eur_cents: u64,
    pub peg_eur_per_btc: u64,
    pub rate_bps_monthly: u32,
    pub period: Period,
    pub pool_sats: u64,
    pub mining_fee_sats: u64,
    pub num_digits: u32,
    pub base: u32,
}

impl Default for PayoutCurveInput {
    fn default() -> Self {
        Self {
            amount_eur_cents: 0,
            peg_eur_per_btc: 0,
            rate_bps_monthly: crate::constants::DEFAULT_RATE_BPS_MONTHLY,
            period: Period {
                start: Date::new(2026, 1),
                end: Date::new(2026, 1),
            },
            pool_sats: 0,
            mining_fee_sats: ESTIMATED_SETTLEMENT_FEE_SATS,
            num_digits: DEFAULT_NUM_DIGITS,
            base: DEFAULT_NUMERIC_BASE,
        }
    }
}

pub struct PayoutCurve;

impl PayoutCurve {
    pub fn build(input: &PayoutCurveInput) -> Result<Vec<PayoutPoint>, PayoutCurveError> {
        if input.peg_eur_per_btc == 0 {
            return Err(PayoutCurveError::PegMissing);
        }

        let months = symbolic_months_duration(input.period);
        let anchors = price_anchors(input.peg_eur_per_btc, input.num_digits, input.base);

        Ok(anchors
            .into_iter()
            .map(|price| point_for(price, input, months))
            .collect())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PayoutCurveError {
    #[error("peg_eur_per_btc must be set")]
    PegMissing,
}

fn price_anchors(peg: u64, num_digits: u32, base: u32) -> Vec<u64> {
    let max_outcome = Numeric::max_value(num_digits, base);
    let mut anchors: Vec<u64> = DEFAULT_PRICE_MULTIPLIERS
        .iter()
        .map(|m| ((peg as f64) * m).round() as u64)
        .collect();
    anchors.push(1);
    anchors.push(max_outcome);
    anchors.sort_unstable();
    anchors.dedup();
    anchors
        .into_iter()
        .map(|p| p.clamp(1, max_outcome))
        .collect()
}

fn point_for(price: u64, input: &PayoutCurveInput, months: u32) -> PayoutPoint {
    let payoff = FloorEurCalculator {
        notional_eur_cents: input.amount_eur_cents,
        notional_total_cents: input.amount_eur_cents,
        holder_shares_cents: vec![input.amount_eur_cents],
        spot_eur_per_btc: price,
        rate_bps_monthly: input.rate_bps_monthly,
        months_elapsed: months,
        escrow_total_sats: input.pool_sats,
        mining_fee_sats: input.mining_fee_sats,
        ..Default::default()
    }
    .call()
    .expect("payout curve point");

    PayoutPoint {
        outcome: price,
        peg_sats: payoff.total_holder_sats,
        investor_sats: payoff.investor_remainder_sats,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn demo_budget_input() -> PayoutCurveInput {
        PayoutCurveInput {
            amount_eur_cents: 500_000,
            peg_eur_per_btc: 50_000,
            rate_bps_monthly: 100,
            period: Period {
                start: Date::new(2026, 1),
                end: Date::new(2026, 7),
            },
            pool_sats: 20_000_000,
            mining_fee_sats: ESTIMATED_SETTLEMENT_FEE_SATS,
            num_digits: 20,
            base: 2,
        }
    }

    #[test]
    fn rejects_missing_peg() {
        let mut input = demo_budget_input();
        input.peg_eur_per_btc = 0;
        assert!(matches!(
            PayoutCurve::build(&input),
            Err(PayoutCurveError::PegMissing)
        ));
    }

    #[test]
    fn samples_anchors_including_bounds() {
        let points = PayoutCurve::build(&demo_budget_input()).unwrap();
        let max = Numeric::max_value(20, 2);
        let outcomes: Vec<u64> = points.iter().map(|p| p.outcome).collect();
        assert!(outcomes.windows(2).all(|w| w[0] < w[1]));
        assert!(outcomes.contains(&1));
        assert!(outcomes.contains(&max));
    }

    #[test]
    fn conserves_distributable_pot() {
        let input = demo_budget_input();
        let distributable = input.pool_sats - input.mining_fee_sats;
        for point in PayoutCurve::build(&input).unwrap() {
            assert_eq!(point.peg_sats + point.investor_sats, distributable);
        }
    }

    #[test]
    fn peg_pot_monotonic_decreasing_with_price() {
        let peg_sats: Vec<u64> = PayoutCurve::build(&demo_budget_input())
            .unwrap()
            .into_iter()
            .map(|p| p.peg_sats)
            .collect();
        let mut sorted = peg_sats.clone();
        sorted.sort_by(|a, b| b.cmp(a));
        assert_eq!(peg_sats, sorted);
    }

    #[test]
    fn caps_peg_at_distributable_for_low_prices() {
        let input = demo_budget_input();
        let distributable = input.pool_sats - input.mining_fee_sats;
        let first = &PayoutCurve::build(&input).unwrap()[0];
        assert_eq!(first.peg_sats, distributable);
        assert_eq!(first.investor_sats, 0);
    }
}
