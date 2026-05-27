# lex-positions — mark-to-market PnL helpers
#
# unrealized_pnl — MTM gain/loss on an open position.
# total_pnl      — realized + unrealized.
#
# mark_price is the current mid/last price used for valuation.
#
# Effects: none.

import "lex-money/src/decimal" as d

import "./position" as pos

fn unrealized_pnl(position :: pos.Position, mark_price :: d.Decimal) -> d.Decimal
  examples {
    unrealized_pnl(
      { key: { account: "A", symbol: "X" }, qty: 100,
        avg_cost: { coefficient: 1000, exponent: -2 },
        realized_pnl: { coefficient: 0, exponent: 0 } },
      { coefficient: 1050, exponent: -2 }
    ) => { coefficient: 5000, exponent: -2 },
  }
{
  if pos.is_flat(position) {
    d.zero()
  } else {
    let qty_dec := d.from_int(pos_abs_qty(position))
    let price_diff := if pos.is_long(position) {
      d.sub(mark_price, position.avg_cost)
    } else {
      d.sub(position.avg_cost, mark_price)
    }
    d.mul(price_diff, qty_dec)
  }
}

fn total_pnl(position :: pos.Position, mark_price :: d.Decimal) -> d.Decimal {
  d.add(position.realized_pnl, unrealized_pnl(position, mark_price))
}

fn pos_abs_qty(position :: pos.Position) -> Int {
  if position.qty < 0 { 0 - position.qty } else { position.qty }
}
