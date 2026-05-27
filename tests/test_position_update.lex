# Tests for position_update — pure WAAC and realized-PnL arithmetic.
#
# All tests are pure (no effects). Prices use { coefficient, exponent }
# notation: { coefficient: 1050, exponent: -2 } = 10.50.

import "lex-money/src/decimal" as d

import "../src/position"        as pos
import "../src/position_update" as pu

# ---- Fixtures -------------------------------------------------------

fn key() -> pos.PositionKey { { account: "ACC1", symbol: "AAPL" } }
fn flat_pos() -> pos.Position { pos.flat(key()) }

fn price(coeff :: Int, exp :: Int) -> d.Decimal { { coefficient: coeff, exponent: exp } }

fn buy_fill(exec_id :: Str, qty :: Int, coeff :: Int, exp :: Int) -> pos.Fill {
  { exec_id: exec_id, qty: qty, price: price(coeff, exp), is_buy: true }
}

fn sell_fill(exec_id :: Str, qty :: Int, coeff :: Int, exp :: Int) -> pos.Fill {
  { exec_id: exec_id, qty: qty, price: price(coeff, exp), is_buy: false }
}

# ---- Open from flat -------------------------------------------------

test "buy fill on flat position opens long" {
  let result := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  assert result.qty == 100
  assert result.avg_cost == price(1000, -2)
  assert d.is_zero(result.realized_pnl)
}

test "sell fill on flat position opens short" {
  let result := pu.apply_fill(flat_pos(), sell_fill("E2", 50, 2000, -2))
  assert result.qty == 0 - 50
  assert result.avg_cost == price(2000, -2)
  assert d.is_zero(result.realized_pnl)
}

# ---- Adding to existing direction -----------------------------------

test "second buy on long position updates WAAC" {
  let after_first  := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  let after_second := pu.apply_fill(after_first, buy_fill("E2", 100, 1100, -2))
  # WAAC = (100 * 10.00 + 100 * 11.00) / 200 = 10.50
  assert after_second.qty == 200
  assert after_second.avg_cost == { coefficient: 1050000000, exponent: -8 }
  assert d.is_zero(after_second.realized_pnl)
}

test "second sell on short position updates WAAC" {
  let after_first  := pu.apply_fill(flat_pos(), sell_fill("E1", 50, 2000, -2))
  let after_second := pu.apply_fill(after_first, sell_fill("E2", 50, 2200, -2))
  # WAAC = (50 * 20.00 + 50 * 22.00) / 100 = 21.00
  assert after_second.qty == 0 - 100
  assert after_second.avg_cost == { coefficient: 2100000000, exponent: -8 }
}

# ---- Partial close --------------------------------------------------

test "partial sell on long realizes PnL, qty decreases" {
  let long_pos := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  # buy 100 @ 10.00
  let result := pu.apply_fill(long_pos, sell_fill("E2", 40, 1100, -2))
  # sell 40 @ 11.00; realized = (11.00 - 10.00) * 40 = 40.00
  assert result.qty == 60
  assert result.avg_cost == price(1000, -2)
  assert result.realized_pnl == d.mul(price(100, -2), d.from_int(40))
}

test "partial buy on short realizes PnL" {
  let short_pos := pu.apply_fill(flat_pos(), sell_fill("E1", 100, 2000, -2))
  # short 100 @ 20.00
  let result := pu.apply_fill(short_pos, buy_fill("E2", 30, 1800, -2))
  # cover 30 @ 18.00; realized = (20.00 - 18.00) * 30 = 60.00
  assert result.qty == 0 - 70
  assert result.realized_pnl == d.mul(price(200, -2), d.from_int(30))
}

# ---- Exact close ----------------------------------------------------

test "exact close resets qty to 0 and avg_cost to zero" {
  let long_pos := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  let result   := pu.apply_fill(long_pos, sell_fill("E2", 100, 1200, -2))
  assert result.qty == 0
  assert d.is_zero(result.avg_cost)
  # realized = (12.00 - 10.00) * 100 = 200.00
  assert result.realized_pnl == d.mul(price(200, -2), d.from_int(100))
}

# ---- Cross-zero ----------------------------------------------------

test "cross-zero sell flips long to short" {
  let long_pos := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  # long 100 @ 10.00; sell 150 @ 11.00
  let result := pu.apply_fill(long_pos, sell_fill("E2", 150, 1100, -2))
  # close 100 longs: realized = (11.00 - 10.00) * 100 = 100.00
  # open 50 short @ 11.00
  assert result.qty == 0 - 50
  assert result.avg_cost == price(1100, -2)
  assert result.realized_pnl == d.mul(price(100, -2), d.from_int(100))
}

test "cross-zero buy flips short to long" {
  let short_pos := pu.apply_fill(flat_pos(), sell_fill("E1", 50, 2000, -2))
  # short 50 @ 20.00; buy 80 @ 18.00
  let result := pu.apply_fill(short_pos, buy_fill("E2", 80, 1800, -2))
  # cover 50 shorts: realized = (20.00 - 18.00) * 50 = 100.00
  # open 30 long @ 18.00
  assert result.qty == 30
  assert result.avg_cost == price(1800, -2)
  assert result.realized_pnl == d.mul(price(200, -2), d.from_int(50))
}

# ---- Realized PnL accumulates across multiple trades ----------------

test "realized PnL accumulates across multiple partial closes" {
  let p0 := pu.apply_fill(flat_pos(), buy_fill("E1", 200, 1000, -2))
  let p1 := pu.apply_fill(p0, sell_fill("E2", 50, 1050, -2))
  # realized1 = (10.50 - 10.00) * 50 = 25.00
  let p2 := pu.apply_fill(p1, sell_fill("E3", 50, 1100, -2))
  # realized2 = (11.00 - 10.00) * 50 = 50.00; total = 75.00
  assert p2.qty == 100
  assert p2.realized_pnl == d.mul(price(7500, -2), d.from_int(1))
}
