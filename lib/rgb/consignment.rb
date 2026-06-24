# frozen_string_literal: true

module Rgb
  # Consignment export per validazione client-side (rgb-lib) — formato PoC deterministico.
  class Consignment
    GENESIS = "genesis"
    TRANSFER = "transfer_position"

    def self.for_genesis(position)
      position.validate!

      {
        type: GENESIS,
        schema: Rgb::FLOOR_EUR_POSITION_SCHEMA,
        version: Rgb::FLOOR_EUR_POSITION_VERSION,
        assignment: position.to_h,
        note: "Genesis FloorEURPosition — anchor L1 deferred in PoC spike"
      }
    end

    def self.for_transfer(input:, outputs:, transfer_id: nil)
      input.validate!
      outputs.each(&:validate!)

      input_total = input.notional_share
      output_total = outputs.sum(&:notional_share)
      raise Error, "conservazione notional violata" unless input_total == output_total

      {
        type: TRANSFER,
        schema: Rgb::FLOOR_EUR_POSITION_SCHEMA,
        version: Rgb::FLOOR_EUR_POSITION_VERSION,
        transfer_id: transfer_id || SecureRandom.uuid,
        input: input.to_h,
        outputs: outputs.map(&:to_h),
        conservation: {
          input_notional_share: input_total,
          output_notional_share: output_total
        },
        note: "TransferPosition — investor/bot non firmano (P2P-OPTIONS §7.4)"
      }
    end
  end
end
