//! Deal lifecycle FSM: `pending` → `active` → `settled`.
//!
//! Mirrors `Budget` status enum and activation/settlement guards.

use crate::constants::DEFAULT_RATE_BPS_MONTHLY;
use crate::months::{Period, symbolic_months_duration};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DealStatus {
    Pending,
    Active,
    Settled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Deal {
    pub id: String,
    pub status: DealStatus,
    pub borrower_pubkey: Option<String>,
    pub investor_pubkey: Option<String>,
    pub amount_eur_cents: u64,
    pub collateral_eur_cents: u64,
    pub rate_bps_monthly: u32,
    pub period: Period,
    pub peg_eur_per_btc: Option<u64>,
    pub genesis_block_height: Option<u32>,
    pub maturity_block_height: Option<u32>,
    pub pool_sats: u64,
}

impl Deal {
    pub fn new_offer(
        id: impl Into<String>,
        borrower_pubkey: impl Into<String>,
        amount_eur_cents: u64,
        period: Period,
        rate_bps_monthly: Option<u32>,
    ) -> Result<Self, DealError> {
        if amount_eur_cents == 0 {
            return Err(DealError::InvalidAmount);
        }
        if symbolic_months_duration(period) == 0 {
            return Err(DealError::InvalidPeriod);
        }

        Ok(Self {
            id: id.into(),
            status: DealStatus::Pending,
            borrower_pubkey: Some(borrower_pubkey.into()),
            investor_pubkey: None,
            amount_eur_cents,
            collateral_eur_cents: amount_eur_cents,
            rate_bps_monthly: rate_bps_monthly.unwrap_or(DEFAULT_RATE_BPS_MONTHLY),
            period,
            peg_eur_per_btc: None,
            genesis_block_height: None,
            maturity_block_height: None,
            pool_sats: 0,
        })
    }

    pub fn accept(
        &mut self,
        investor_pubkey: impl Into<String>,
        peg_eur_per_btc: u64,
        pool_sats: u64,
        genesis_block_height: u32,
    ) -> Result<(), DealError> {
        if self.status != DealStatus::Pending {
            return Err(DealError::InvalidTransition {
                from: self.status,
                to: DealStatus::Active,
            });
        }
        if peg_eur_per_btc == 0 {
            return Err(DealError::PegMissing);
        }
        if pool_sats == 0 {
            return Err(DealError::CollateralMissing);
        }

        let months = symbolic_months_duration(self.period);
        self.investor_pubkey = Some(investor_pubkey.into());
        self.peg_eur_per_btc = Some(peg_eur_per_btc);
        self.pool_sats = pool_sats;
        self.genesis_block_height = Some(genesis_block_height);
        self.maturity_block_height =
            Some(genesis_block_height + months * crate::constants::BLOCKS_PER_MONTH);
        self.status = DealStatus::Active;
        Ok(())
    }

    pub fn settle(&mut self) -> Result<(), DealError> {
        if self.status != DealStatus::Active {
            return Err(DealError::InvalidTransition {
                from: self.status,
                to: DealStatus::Settled,
            });
        }
        self.status = DealStatus::Settled;
        Ok(())
    }

    pub fn ready_for_settlement(&self, at_height: u32) -> bool {
        matches!(
            (self.status, self.maturity_block_height),
            (DealStatus::Active, Some(maturity)) if at_height >= maturity
        )
    }

    pub fn peg_set(&self) -> bool {
        self.peg_eur_per_btc.map(|p| p > 0).unwrap_or(false)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum DealError {
    #[error("amount_eur_cents must be positive")]
    InvalidAmount,
    #[error("period_end must be after period_start")]
    InvalidPeriod,
    #[error("peg must be set before activation")]
    PegMissing,
    #[error("collateral pool must be funded")]
    CollateralMissing,
    #[error("cannot transition from {from:?} to {to:?}")]
    InvalidTransition { from: DealStatus, to: DealStatus },
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::months::Date;

    fn demo_period() -> Period {
        Period {
            start: Date::new(2026, 1),
            end: Date::new(2026, 2),
        }
    }

    #[test]
    fn offer_starts_pending() {
        let deal = Deal::new_offer("deal-1", "borrower-pk", 100_000, demo_period(), None).unwrap();
        assert_eq!(deal.status, DealStatus::Pending);
        assert!(!deal.peg_set());
    }

    #[test]
    fn activate_transitions_to_active() {
        let mut deal =
            Deal::new_offer("deal-1", "borrower-pk", 100_000, demo_period(), None).unwrap();
        deal.accept("investor-pk", 50_000, 3_975_000, 800_000).unwrap();
        assert_eq!(deal.status, DealStatus::Active);
        assert_eq!(deal.peg_eur_per_btc, Some(50_000));
        assert_eq!(
            deal.maturity_block_height,
            Some(800_000 + crate::constants::BLOCKS_PER_MONTH)
        );
    }

    #[test]
    fn settle_requires_active() {
        let mut deal =
            Deal::new_offer("deal-1", "borrower-pk", 100_000, demo_period(), None).unwrap();
        assert!(deal.settle().is_err());
        deal.accept("investor-pk", 50_000, 3_975_000, 800_000).unwrap();
        deal.settle().unwrap();
        assert_eq!(deal.status, DealStatus::Settled);
        assert!(deal.settle().is_err());
    }

    #[test]
    fn ready_for_settlement_at_maturity() {
        let mut deal =
            Deal::new_offer("deal-1", "borrower-pk", 100_000, demo_period(), None).unwrap();
        deal.accept("investor-pk", 50_000, 3_975_000, 800_000).unwrap();
        let maturity = deal.maturity_block_height.unwrap();
        assert!(!deal.ready_for_settlement(maturity - 1));
        assert!(deal.ready_for_settlement(maturity));
    }
}
