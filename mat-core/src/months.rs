//! Symbolic month duration and block-based accrual.
//!
//! Mirrors `Budget#symbolic_months_duration` and `Budget#months_elapsed`.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Period {
    pub start: Date,
    pub end: Date,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Date {
    pub year: i32,
    pub month: u32,
}

impl Date {
    pub fn new(year: i32, month: u32) -> Self {
        Self { year, month }
    }
}

/// Calendar months between period start and end (exclusive of partial days).
pub fn symbolic_months_duration(period: Period) -> u32 {
    let end_months = period.end.year * 12 + period.end.month as i32;
    let start_months = period.start.year * 12 + period.start.month as i32;
    (end_months - start_months).max(0) as u32
}

/// Whole symbolic months elapsed since genesis, capped at chain height.
pub fn months_elapsed(genesis_block_height: Option<u32>, at_height: u32, period: Period) -> u32 {
    let duration = symbolic_months_duration(period);
    let Some(genesis) = genesis_block_height else {
        return duration;
    };

    let blocks_elapsed = at_height.saturating_sub(genesis);
    blocks_elapsed / crate::constants::BLOCKS_PER_MONTH
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn symbolic_months_matches_budget_demo() {
        let period = Period {
            start: Date::new(2026, 1),
            end: Date::new(2026, 2),
        };
        assert_eq!(symbolic_months_duration(period), 1);
    }

    #[test]
    fn symbolic_months_six_month_deal() {
        let period = Period {
            start: Date::new(2026, 1),
            end: Date::new(2026, 7),
        };
        assert_eq!(symbolic_months_duration(period), 6);
    }

    #[test]
    fn months_elapsed_without_genesis_uses_duration() {
        let period = Period {
            start: Date::new(2026, 1),
            end: Date::new(2026, 7),
        };
        assert_eq!(months_elapsed(None, 999_999, period), 6);
    }

    #[test]
    fn months_elapsed_from_blocks() {
        let period = Period {
            start: Date::new(2026, 1),
            end: Date::new(2026, 7),
        };
        let genesis = 100_000;
        let at = genesis + crate::constants::BLOCKS_PER_MONTH * 3;
        assert_eq!(months_elapsed(Some(genesis), at, period), 3);
    }
}
