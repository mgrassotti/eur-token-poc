//! Versioned JSON wire formats for P2P deal exchange.
//!
//! Schemas live in `mat-core/schemas/`. Bump `WIRE_FORMAT_VERSION` on breaking changes.

use crate::deal::DealStatus;
use crate::floor_eur::HolderAllocation;
use crate::months::Period;
use serde::{Deserialize, Serialize};

pub const WIRE_FORMAT_VERSION: u32 = 1;

/// Borrower-published deal terms (Phase 1 relay / Phase 3 P2P).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DealOffer {
    pub schema_version: u32,
    pub deal_id: String,
    pub borrower_pubkey: String,
    pub amount_eur_cents: u64,
    pub collateral_eur_cents: u64,
    pub rate_bps_monthly: u32,
    pub period: Period,
    pub created_at_epoch: u64,
}

impl DealOffer {
    pub fn new(
        deal_id: impl Into<String>,
        borrower_pubkey: impl Into<String>,
        amount_eur_cents: u64,
        period: Period,
        rate_bps_monthly: u32,
    ) -> Self {
        Self {
            schema_version: WIRE_FORMAT_VERSION,
            deal_id: deal_id.into(),
            borrower_pubkey: borrower_pubkey.into(),
            amount_eur_cents,
            collateral_eur_cents: amount_eur_cents,
            rate_bps_monthly,
            period,
            created_at_epoch: 0,
        }
    }

    pub fn validate(&self) -> Result<(), WireError> {
        if self.schema_version != WIRE_FORMAT_VERSION {
            return Err(WireError::UnsupportedSchema(self.schema_version));
        }
        if self.amount_eur_cents == 0 {
            return Err(WireError::InvalidAmount);
        }
        Ok(())
    }
}

/// Hodler acceptance: peg lock + investor collateral commitment.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DealAccept {
    pub schema_version: u32,
    pub deal_id: String,
    pub investor_pubkey: String,
    pub peg_eur_per_btc: u64,
    pub investor_collateral_sats: u64,
    pub oracle_event_id: String,
    pub accepted_at_epoch: u64,
}

impl DealAccept {
    pub fn validate(&self) -> Result<(), WireError> {
        if self.schema_version != WIRE_FORMAT_VERSION {
            return Err(WireError::UnsupportedSchema(self.schema_version));
        }
        if self.peg_eur_per_btc == 0 {
            return Err(WireError::PegMissing);
        }
        Ok(())
    }
}

/// Unsigned funding transaction package exchanged before broadcast.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FundingPackage {
    pub schema_version: u32,
    pub deal_id: String,
    pub unsigned_psbt_base64: String,
    pub funding_outpoint: Option<String>,
    pub peg_collateral_sats: u64,
    pub investor_collateral_sats: u64,
    pub oracle_announcement_hex: String,
}

impl FundingPackage {
    pub fn validate(&self) -> Result<(), WireError> {
        if self.schema_version != WIRE_FORMAT_VERSION {
            return Err(WireError::UnsupportedSchema(self.schema_version));
        }
        if self.unsigned_psbt_base64.is_empty() {
            return Err(WireError::MissingPsbt);
        }
        Ok(())
    }
}

/// Post-CET settlement bundle for holder payouts and recovery.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SettlementPackage {
    pub schema_version: u32,
    pub deal_id: String,
    pub status: DealStatus,
    pub end_btc_eur_rate: u64,
    pub cet_txid: String,
    pub peg_pot_sats: u64,
    pub investor_sats: u64,
    pub holder_allocations: Vec<WireHolderAllocation>,
    pub oracle_attestation_hex: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WireHolderAllocation {
    pub holder_id: String,
    pub share_cents: u64,
    pub btc_sats: u64,
}

impl From<(&str, &HolderAllocation)> for WireHolderAllocation {
    fn from((holder_id, alloc): (&str, &HolderAllocation)) -> Self {
        Self {
            holder_id: holder_id.to_string(),
            share_cents: alloc.share_cents,
            btc_sats: alloc.btc_sats,
        }
    }
}

impl SettlementPackage {
    pub fn validate(&self) -> Result<(), WireError> {
        if self.schema_version != WIRE_FORMAT_VERSION {
            return Err(WireError::UnsupportedSchema(self.schema_version));
        }
        if self.end_btc_eur_rate == 0 {
            return Err(WireError::InvalidSpot);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum WireError {
    #[error("unsupported schema_version {0}")]
    UnsupportedSchema(u32),
    #[error("amount must be positive")]
    InvalidAmount,
    #[error("peg must be set")]
    PegMissing,
    #[error("unsigned PSBT required")]
    MissingPsbt,
    #[error("settlement spot must be positive")]
    InvalidSpot,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::months::Date;

    #[test]
    fn offer_round_trips_json() {
        let offer = DealOffer::new(
            "deal-42",
            "02abc",
            100_000,
            Period {
                start: Date::new(2026, 1),
                end: Date::new(2026, 2),
            },
            100,
        );
        let json = serde_json::to_string(&offer).unwrap();
        let parsed: DealOffer = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, offer);
        parsed.validate().unwrap();
    }

    #[test]
    fn rejects_unsupported_schema() {
        let mut offer = DealOffer::new("x", "pk", 1, Period {
            start: Date::new(2026, 1),
            end: Date::new(2026, 2),
        }, 100);
        offer.schema_version = 99;
        assert!(matches!(
            offer.validate(),
            Err(WireError::UnsupportedSchema(99))
        ));
    }
}
