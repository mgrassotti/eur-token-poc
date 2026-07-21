//! Thin C ABI over `mat-core` for Flutter FFI.
//!
//! Build: `cargo build -p mat-ffi --release`
//! Dart loads the resulting `libmat_ffi` dylib when available; until then the
//! app uses the Dart mirror in `mobile/packages/mat_sdk`.

use mat_core::{FloorEurCalculator, FloorEurResult};
use serde_json::json;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Compute FloorEUR from a JSON request string; returns a heap JSON C string.
///
/// Request shape:
/// ```json
/// {
///   "notional_eur_cents": 100000,
///   "notional_total_cents": 100000,
///   "holder_shares_cents": [50000, 50000],
///   "spot_eur_per_btc": 50000,
///   "rate_bps_monthly": 100,
///   "months_elapsed": 1,
///   "escrow_total_sats": 4000000,
///   "mining_fee_sats": 5000
/// }
/// ```
///
/// Caller must free with [`mat_string_free`].
#[no_mangle]
pub unsafe extern "C" fn mat_floor_eur_json(request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return error_ptr("null request");
    }
    let Ok(raw) = CStr::from_ptr(request_json).to_str() else {
        return error_ptr("invalid utf8");
    };
    let Ok(value) = serde_json::from_str::<serde_json::Value>(raw) else {
        return error_ptr("invalid json");
    };

    let calc = FloorEurCalculator {
        notional_eur_cents: value["notional_eur_cents"].as_u64().unwrap_or(0),
        notional_total_cents: value["notional_total_cents"].as_u64().unwrap_or(0),
        holder_shares_cents: value["holder_shares_cents"]
            .as_array()
            .map(|a| a.iter().filter_map(|v| v.as_u64()).collect())
            .unwrap_or_default(),
        spot_eur_per_btc: value["spot_eur_per_btc"].as_u64().unwrap_or(0),
        rate_bps_monthly: value["rate_bps_monthly"].as_u64().unwrap_or(0) as u32,
        months_elapsed: value["months_elapsed"].as_u64().unwrap_or(0) as u32,
        escrow_total_sats: value["escrow_total_sats"].as_u64().unwrap_or(0),
        mining_fee_sats: value["mining_fee_sats"]
            .as_u64()
            .unwrap_or(mat_core::ESTIMATED_SETTLEMENT_FEE_SATS),
    };

    match calc.call() {
        Ok(result) => to_c_string(&result_json(&result)),
        Err(e) => error_ptr(&e.to_string()),
    }
}

/// Free a string returned by this crate.
#[no_mangle]
pub unsafe extern "C" fn mat_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}

fn result_json(result: &FloorEurResult) -> String {
    json!({
        "ok": true,
        "notional_eur_cents": result.notional_eur_cents,
        "months_elapsed": result.months_elapsed,
        "liability_eur_cents": result.liability_eur_cents,
        "gross_holder_sats": result.gross_holder_sats,
        "total_holder_sats": result.total_holder_sats,
        "distributable_sats": result.distributable_sats,
        "investor_remainder_sats": result.investor_remainder_sats,
        "mining_fee_sats": result.mining_fee_sats,
        "insolvent": result.insolvent,
        "holder_allocations": result.holder_allocations.iter().map(|a| json!({
            "share_cents": a.share_cents,
            "btc_sats": a.btc_sats,
        })).collect::<Vec<_>>(),
    })
    .to_string()
}

fn error_ptr(message: &str) -> *mut c_char {
    to_c_string(
        &json!({
            "ok": false,
            "error": message,
        })
        .to_string(),
    )
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn floor_eur_json_demo_case() {
        let req = CString::new(
            r#"{
              "notional_eur_cents": 100000,
              "notional_total_cents": 100000,
              "holder_shares_cents": [50000, 40000, 10000],
              "spot_eur_per_btc": 50000,
              "rate_bps_monthly": 100,
              "months_elapsed": 1,
              "escrow_total_sats": 3975000,
              "mining_fee_sats": 0
            }"#,
        )
        .unwrap();
        unsafe {
            let ptr = mat_floor_eur_json(req.as_ptr());
            let out = CStr::from_ptr(ptr).to_str().unwrap();
            assert!(out.contains("\"ok\":true"));
            assert!(out.contains("\"liability_eur_cents\":101000"));
            assert!(out.contains("\"total_holder_sats\":2020000"));
            mat_string_free(ptr);
        }
    }
}
