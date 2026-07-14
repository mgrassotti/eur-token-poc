//! Shared deal economics and lifecycle for MAT mobile production.
//!
//! Ported from the Rails PoC (`Payoffs::FloorEurCalculator`, `Dlc::PayoutCurve`,
//! `Budget` lifecycle). Ruby remains the integration harness until Phase 3+.

pub mod constants;
pub mod deal;
pub mod floor_eur;
pub mod months;
pub mod numeric;
pub mod payout_curve;
pub mod wire;

pub use constants::*;
pub use deal::{Deal, DealError, DealStatus};
pub use floor_eur::{FloorEurCalculator, FloorEurResult, HolderAllocation};
pub use months::{months_elapsed, symbolic_months_duration, Period};
pub use numeric::Numeric;
pub use payout_curve::{PayoutCurve, PayoutPoint};
pub use wire::{
    DealAccept, DealOffer, FundingPackage, SettlementPackage, WIRE_FORMAT_VERSION,
};
