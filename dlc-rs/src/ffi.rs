//! C ABI for Flutter: fund-key derivation, adaptor signing, CET completion.

use crate::keys::{fund_pubkey_hex, fund_secret_from_mnemonic};
use crate::sign::{complete_cet, complete_refund, sign_adaptor, serialize_tx, SignPackage};
use secp256k1_zkp::Secp256k1;
use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// JSON dispatcher. `op` is one of: fund_keys, sign_adaptor, complete_cet, complete_refund.
///
/// Caller must free the result with [`mat_dlc_string_free`].
#[no_mangle]
pub unsafe extern "C" fn mat_dlc_json(op: *const c_char, request_json: *const c_char) -> *mut c_char {
    if op.is_null() || request_json.is_null() {
        return error_ptr("null argument");
    }
    let Ok(op) = CStr::from_ptr(op).to_str() else {
        return error_ptr("invalid utf8 op");
    };
    let Ok(raw) = CStr::from_ptr(request_json).to_str() else {
        return error_ptr("invalid utf8 request");
    };
    match dispatch(op, raw) {
        Ok(v) => to_c_string(&v.to_string()),
        Err(e) => error_ptr(&e),
    }
}

#[no_mangle]
pub unsafe extern "C" fn mat_dlc_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}

fn dispatch(op: &str, raw: &str) -> Result<Value, String> {
    let value: Value = serde_json::from_str(raw).map_err(|e| format!("invalid json: {e}"))?;
    match op {
        "fund_keys" => {
            let mnemonic = value["mnemonic"]
                .as_str()
                .ok_or_else(|| "mnemonic required".to_string())?;
            let secret = fund_secret_from_mnemonic(mnemonic)?;
            let pubkey = fund_pubkey_hex(mnemonic)?;
            Ok(json!({
                "ok": true,
                "secret_hex": hex::encode(secret.secret_bytes()),
                "pubkey_hex": pubkey,
            }))
        }
        "sign_adaptor" => {
            let mnemonic = value["mnemonic"]
                .as_str()
                .ok_or_else(|| "mnemonic required".to_string())?;
            let package: SignPackage = serde_json::from_value(value["sign_package"].clone())
                .map_err(|e| format!("sign_package: {e}"))?;
            let sk = fund_secret_from_mnemonic(mnemonic)?;
            let secp = Secp256k1::new();
            let signed = sign_adaptor(&secp, &sk, &package).map_err(|e| e.to_string())?;
            Ok(json!({
                "ok": true,
                "adaptor_sigs": signed.adaptor_sigs,
                "refund_sig": signed.refund_sig,
            }))
        }
        "complete_cet" => {
            let package: SignPackage = serde_json::from_value(value["sign_package"].clone())
                .map_err(|e| format!("sign_package: {e}"))?;
            let offerer: Vec<String> = serde_json::from_value(value["offerer_adaptor_sigs"].clone())
                .map_err(|e| format!("offerer_adaptor_sigs: {e}"))?;
            let acceptor: Vec<String> =
                serde_json::from_value(value["acceptor_adaptor_sigs"].clone())
                    .map_err(|e| format!("acceptor_adaptor_sigs: {e}"))?;
            let att = value.get("attestation").cloned().unwrap_or(Value::Null);
            let (cet, outcome, peg_sats, investor_sats) =
                complete_cet(&package, &offerer, &acceptor, &att).map_err(|e| e.to_string())?;
            Ok(json!({
                "ok": true,
                "cet_hex": serialize_tx(&cet),
                "outcome": outcome,
                "peg_sats": peg_sats,
                "investor_sats": investor_sats,
            }))
        }
        "complete_refund" => {
            let package: SignPackage = serde_json::from_value(value["sign_package"].clone())
                .map_err(|e| format!("sign_package: {e}"))?;
            let offerer = value["offerer_refund_sig"]
                .as_str()
                .ok_or_else(|| "offerer_refund_sig required".to_string())?;
            let acceptor = value["acceptor_refund_sig"]
                .as_str()
                .ok_or_else(|| "acceptor_refund_sig required".to_string())?;
            let refund = complete_refund(&package, offerer, acceptor).map_err(|e| e.to_string())?;
            Ok(json!({
                "ok": true,
                "refund_hex": serialize_tx(&refund),
            }))
        }
        other => Err(format!("unknown op {other}")),
    }
}

fn error_ptr(message: &str) -> *mut c_char {
    to_c_string(&json!({ "ok": false, "error": message }).to_string())
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}
