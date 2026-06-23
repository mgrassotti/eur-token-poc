# frozen_string_literal: true

require "openssl"
require "digest"

module L1
  # secp256k1 keypair for regtest (OpenSSL — no native gems).
  class KeyMaterial
    attr_reader :private_key_hex, :public_key_hex

    def self.generate
      group = OpenSSL::PKey::EC.generate("secp256k1")
      priv_hex = group.private_key.to_s(16).rjust(64, "0")
      pub_hex = compress_public_key(group.public_key.to_octet_string(:uncompressed)).unpack1("H*")
      new(private_key_hex: priv_hex, public_key_hex: pub_hex)
    end

    def initialize(private_key_hex:, public_key_hex:)
      @private_key_hex = private_key_hex.downcase
      @public_key_hex = public_key_hex.downcase
    end

    def wif(testnet: true)
      Base58Check.encode([testnet ? 0xEF : 0x80].pack("C") + [private_key_hex].pack("H*") + [0x01].pack("C"))
    end

    def self.compress_public_key(uncompressed)
      raise ArgumentError, "expected uncompressed pubkey" unless uncompressed.bytesize == 65 && uncompressed.getbyte(0) == 0x04

      x = uncompressed.byteslice(1, 32)
      y_last = uncompressed.getbyte(64)
      prefix = y_last.even? ? "\x02" : "\x03"
      prefix + x
    end

    private_class_method :compress_public_key

    # Bitcoin Base58Check (WIF).
    module Base58Check
      ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

      module_function

      def encode(payload)
        checksum = Digest::SHA256.digest(Digest::SHA256.digest(payload))[0, 4]
        encode_base58(payload + checksum)
      end

      def encode_base58(data)
        int = data.bytes.inject(0) { |memo, byte| (memo << 8) + byte }
        encoded = +""
        while int.positive?
          int, remainder = int.divmod(58)
          encoded << ALPHABET[remainder]
        end
        data.each_byte { |byte| break unless byte.zero?; encoded << ALPHABET[0] }
        encoded.reverse
      end
    end
  end
end
