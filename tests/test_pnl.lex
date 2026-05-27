# Tests for pnl — unrealized and total PnL helpers.
#
# All tests are pure (no effects).

import "lex-money/src/decimal" as d

import "../src/position"        as pos
import "../src/position_update" as pu
import "../src/pnl"             as pnl

fn key() -> pos.PositionKey { { account: "ACC1", symbol: "MSFT" } }
fn price(c :: Int, e :: Int) -> d.Decimal { { coefficient: c, exponent: e } }

test "unrealized_pnl on flat position is zero" {
  let p := pos.flat(key())
  assert d.is_zero(pnl.unrealized_pnl(p, price(1000, -2)))
}

test "unrealized_pnl long position with gain" {
  let p := pu.apply_fill(pos.flat(key()), {
    exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true
  })
  # long 100 @ 10.00; mark = 10.50
  let upnl := pnl.unrealized_pnl(p, price(1050, -2))
  # expected = (10.50 - 10.00) * 100 = 50.00
  assert d.is_positive(upnl)
  assert upnl == d.mul(price(50, -2), d.from_int(100))
}

test "unrealized_pnl long position with loss" {
  let p := pu.apply_fill(pos.flat(key()), {
    exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true
  })
  # long 100 @ 10.00; mark = 9.50
  let upnl := pnl.unrealized_pnl(p, price(950, -2))
  assert d.is_negative(upnl)
}

test "unrealized_pnl short position with gain" {
  let p := pu.apply_fill(pos.flat(key()), {
    exec_id: "E1", qty: 50, price: price(2000, -2), is_buy: false
  })
  # short 50 @ 20.00; mark = 18.00
  let upnl := pnl.unrealized_pnl(p, price(1800, -2))
  # expected = (20.00 - 18.00) * 50 = 100.00
  assert d.is_positive(upnl)
  assert upnl == d.mul(price(200, -2), d.from_int(50))
}

test "total_pnl sums realized and unrealized" {
  let p0 := pu.apply_fill(pos.flat(key()), {
    exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true
  })
  let p1 := pu.apply_fill(p0, {
    exec_id: "E2", qty: 50, price: price(1100, -2), is_buy: false
  })
  # realized = (11.00 - 10.00) * 50 = 50.00; remaining long 50 @ 10.00
  # mark = 10.50; unrealized = (10.50 - 10.00) * 50 = 25.00
  # total = 75.00
  let total := pnl.total_pnl(p1, price(1050, -2))
  let expected := d.add(
    d.mul(price(100, -2), d.from_int(50)),   # realized
    d.mul(price(50, -2), d.from_int(50))     # unrealized
  )
  assert total == expected
}
