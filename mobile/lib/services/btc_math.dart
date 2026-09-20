/// Client-side helpers mirroring Rails BtcConversion / ReserveRequirement.
class BtcMath {
  static const satsPerBtc = 100000000;
  static const fundingFeeBufferSats = 10000;

  static int maxEurCentsForSats(int sats, double eurPerBtc) {
    if (sats <= 0 || eurPerBtc <= 0) return 0;
    final eur = sats / satsPerBtc * eurPerBtc;
    return (eur * 100).floor();
  }

  static int maxBorrowableEurCents(int balanceSats, double eurPerBtc) {
    final available = balanceSats - fundingFeeBufferSats;
    return maxEurCentsForSats(available, eurPerBtc);
  }

  static int eurCentsToSats(int eurCents, double eurPerBtc) {
    if (eurPerBtc <= 0) return 0;
    final eur = eurCents / 100.0;
    final btc = eur / eurPerBtc;
    return (btc * satsPerBtc).round();
  }

  static int borrowerRequiredSats(int amountEurCents, double eurPerBtc) {
    return eurCentsToSats(amountEurCents, eurPerBtc) + fundingFeeBufferSats;
  }

  /// Placeholder compressed pubkey for recovery metadata (not used for signing).
  /// Always 33 bytes hex (`02` + 32 bytes) so bitcoind/dlc-rs accept the field.
  static String placeholderIdentityPubkey(String seed) {
    final bytes = seed.codeUnits;
    final buf = StringBuffer('02');
    for (var i = 0; i < 32; i++) {
      final raw = bytes.isEmpty ? i : bytes[i % bytes.length] ^ (i * 17);
      final b = raw & 0xff;
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }
}
