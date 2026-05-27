# lex-positions — gross notional and margin checks
#
# gross_notional  — |qty| × mark_price; the raw market exposure.
# within_notional — true when notional ≤ limit.
# margin_ratio    — notional / equity (as a Decimal); useful for margin calls.
#
# Effects: none.

import "lex-money/src/decimal" as d

import "./position" as pos

fn gross_notional(position :: pos.Position, mark_price :: d.Decimal) -> d.Decimal
  examples {
    gross_notional(
      { key: { account: "A", symbol: "X" }, qty: 0 - 50,
        avg_cost: { coefficient: 0, exponent: 0 },
        realized_pnl: { coefficient: 0, exponent: 0 } },
      { coefficient: 2000, exponent: -2 }
    ) => { coefficient: 100000, exponent: -2 },
  }
{
  let abs_qty := if position.qty < 0 { 0 - position.qty } else { position.qty }
  d.mul(d.from_int(abs_qty), mark_price)
}

fn within_notional(position :: pos.Position, mark_price :: d.Decimal, limit :: d.Decimal) -> Bool {
  d.lte(gross_notional(position, mark_price), limit)
}

# net_exposure adds sign: positive = long exposure, negative = short.
fn net_exposure(position :: pos.Position, mark_price :: d.Decimal) -> d.Decimal {
  d.mul(d.from_int(position.qty), mark_price)
}
