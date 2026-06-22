# frozen_string_literal: true

module ChainState
  # Bitcoin genesis block (mainnet), used to estimate height in the simulator.
  GENESIS_TIME_UTC = Time.utc(2009, 1, 3, 18, 15, 5).freeze
  SECONDS_PER_BLOCK = 600

  module_function

  def block_height
    MarketRate.current.bitcoin_block_height
  end

  def estimate_block_height(at: Time.current)
    elapsed_seconds = at.utc.to_f - GENESIS_TIME_UTC.to_f
    return 0 if elapsed_seconds.negative?

    (elapsed_seconds / SECONDS_PER_BLOCK).floor
  end

  def update_block_height!(height, auto_settle: true)
    MarketRate.current.update!(bitcoin_block_height: height)
    Budgets::AutoSettleService.call if auto_settle
  end
end
