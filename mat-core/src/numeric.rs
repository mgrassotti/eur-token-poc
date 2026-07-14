//! DLC numeric outcome helpers — mirrors `lib/dlc/numeric.rb`.

use std::error::Error;
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NumericError {
    message: String,
}

impl fmt::Display for NumericError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl Error for NumericError {}

pub struct Numeric;

impl Numeric {
    pub fn max_value(num_digits: u32, base: u32) -> u64 {
        u64::from(base).pow(num_digits).saturating_sub(1)
    }

    pub fn digits(value: u64, num_digits: u32, base: u32) -> Result<Vec<u32>, NumericError> {
        if base < 2 {
            return Err(NumericError {
                message: format!("base must be >= 2 (got {base})"),
            });
        }
        if num_digits < 1 {
            return Err(NumericError {
                message: format!("num_digits must be positive (got {num_digits})"),
            });
        }
        let cap = Self::max_value(num_digits, base);
        if value > cap {
            return Err(NumericError {
                message: format!(
                    "outcome {value} exceeds {num_digits}-digit base-{base} capacity"
                ),
            });
        }

        let mut out = vec![0u32; num_digits as usize];
        let mut remaining = value;
        for i in (0..num_digits as usize).rev() {
            out[i] = (remaining % u64::from(base)) as u32;
            remaining /= u64::from(base);
        }
        Ok(out)
    }

    pub fn from_digits(digits: &[u32], base: u32) -> u64 {
        digits.iter().fold(0u64, |acc, &d| acc * u64::from(base) + u64::from(d))
    }

    pub fn required_digits(max_value: u64, base: u32) -> u32 {
        let mut n = 0u32;
        let mut cap = 1u64;
        while cap <= max_value {
            cap = cap.saturating_mul(u64::from(base));
            n += 1;
        }
        n.max(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn digits_decomposes_base2() {
        assert_eq!(Numeric::digits(5, 4, 2).unwrap(), vec![0, 1, 0, 1]);
    }

    #[test]
    fn digits_zero_pads() {
        assert_eq!(
            Numeric::digits(1, 8, 2).unwrap(),
            vec![0, 0, 0, 0, 0, 0, 0, 1]
        );
    }

    #[test]
    fn digits_max_value() {
        assert_eq!(Numeric::digits(255, 8, 2).unwrap(), vec![1; 8]);
    }

    #[test]
    fn digits_base10() {
        assert_eq!(Numeric::digits(123, 3, 10).unwrap(), vec![1, 2, 3]);
    }

    #[test]
    fn digits_rejects_overflow() {
        assert!(Numeric::digits(16, 4, 2).is_err());
    }

    #[test]
    fn from_digits_inverse() {
        let digits = Numeric::digits(54_321, 20, 2).unwrap();
        assert_eq!(Numeric::from_digits(&digits, 2), 54_321);
    }

    #[test]
    fn max_value_twenty_digits() {
        assert_eq!(Numeric::max_value(20, 2), 1_048_575);
    }

    #[test]
    fn required_digits() {
        assert_eq!(Numeric::required_digits(255, 2), 8);
        assert_eq!(Numeric::required_digits(256, 2), 9);
        assert_eq!(Numeric::required_digits(0, 2), 1);
    }
}
