# frozen_string_literal: true

module ChainState
  module_function

  def block_height
    MarketRate.current.bitcoin_block_height
  end

  def update_block_height!(height, auto_settle: true)
    MarketRate.current.update!(bitcoin_block_height: height)
    Budgets::AutoSettleService.call if auto_settle
  end
end
