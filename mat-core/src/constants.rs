//! Constants shared with the Rails PoC (`Budget`, `Dlc::Config`).

/// Blocks per symbolic month (regtest pacing).
pub const BLOCKS_PER_MONTH: u32 = 4356;

/// Default monthly rate: 100 bps = 1%/month (`budgets.rate_bps_monthly` default).
pub const DEFAULT_RATE_BPS_MONTHLY: u32 = 100;

/// Estimated on-chain fee reserved at settlement (`Budget::ESTIMATED_SETTLEMENT_FEE_SATS`).
pub const ESTIMATED_SETTLEMENT_FEE_SATS: u64 = 5_000;

/// DLC numeric event width (`Dlc::Config.num_digits` default).
pub const DEFAULT_NUM_DIGITS: u32 = 20;

/// DLC numeric event base (`Dlc::Config.base` default).
pub const DEFAULT_NUMERIC_BASE: u32 = 2;
