//! Deterministic DLC 2-of-2 fund key derived from a BIP39 mnemonic.
//!
//! PoC derivation: SHA256("mat-dlc-fund-v1" || mnemonic). This is independent of
//! the BIP84 spend path used by BDK, so a leaked CET adaptor signature cannot
//! spend the user's deposit UTXOs.

use bitcoin::hashes::{sha256, Hash};
use secp256k1_zkp::{PublicKey, Secp256k1, SecretKey};

const DOMAIN: &[u8] = b"mat-dlc-fund-v1";

pub fn fund_secret_from_mnemonic(mnemonic: &str) -> Result<SecretKey, String> {
    let mut data = Vec::from(DOMAIN);
    data.extend_from_slice(mnemonic.trim().as_bytes());
    let hash = sha256::Hash::hash(&data);
    SecretKey::from_slice(hash.as_byte_array())
        .or_else(|_| {
            let mut tweaked = hash.to_byte_array();
            tweaked[31] ^= 1;
            SecretKey::from_slice(&tweaked)
        })
        .map_err(|e| format!("fund secret: {e}"))
}

pub fn fund_pubkey_hex(mnemonic: &str) -> Result<String, String> {
    let secp = Secp256k1::new();
    let sk = fund_secret_from_mnemonic(mnemonic)?;
    let pk = PublicKey::from_secret_key(&secp, &sk);
    Ok(hex::encode(pk.serialize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fund_key_is_deterministic_and_compressed() {
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let a = fund_pubkey_hex(mnemonic).unwrap();
        let b = fund_pubkey_hex(mnemonic).unwrap();
        assert_eq!(a, b);
        assert_eq!(a.len(), 66);
        assert!(a.starts_with("02") || a.starts_with("03"));
        let other = fund_pubkey_hex("legal winner thank year wave sausage worth useful legal winner thank yellow").unwrap();
        assert_ne!(a, other);
    }
}
