# Tests for pnl — unrealized and total PnL helpers.
#
# All tests are pure (no effects).

import "std.list" as list

import "lex-money/src/decimal" as d

import "../src/position"        as pos
import "../src/position_update" as pu
import "../src/pnl"             as pnl

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }
fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond { pass() } else { fail(label) }
}
fn assert_eq_dec(a :: d.Decimal, b :: d.Decimal, label :: Str) -> Result[Unit, Str] {
  assert_true(d.eq(a, b), label)
}

fn key() -> pos.PositionKey { { account: "ACC1", symbol: "MSFT" } }
fn price(c :: Int, e :: Int) -> d.Decimal { { coefficient: c, exponent: e } }

fn test_unrealized_flat_is_zero() -> Result[Unit, Str] {
  assert_true(d.is_zero(pnl.unrealized_pnl(pos.flat(key()), price(1000, -2))),
    "unrealized flat = 0")
}

fn test_unrealized_long_gain() -> Result[Unit, Str] {
  let p := pu.apply_fill(pos.flat(key()), {
    exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true
  })
  # long 100 @ 10.00; mark = 10.50; upnl = 50.00
  let upnl := pnl.unrealized_pnl(p, price(1050, -2))
  let expected := d.mul(price(50, -2), d.from_int(100))
  match assert_true(d.is_positive(upnl), "upnl positive") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_dec(upnl, expected, "upnl=50.00"),
  }
}

fn test_unrealized_long_loss() -> Result[Unit, Str] {
  let p := pu.apply_fill(pos.flat(key()), {
    exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true
  })
  let upnl := pnl.unrealized_pnl(p, price(950, -2))
  assert_true(d.is_negative(upnl), "upnl negative on loss")
}

fn test_unrealized_short_gain() -> Result[Unit, Str] {
  let p := pu.apply_fill(pos.flat(key()), {
    exec_id: "E1", qty: 50, price: price(2000, -2), is_buy: false
  })
  # short 50 @ 20.00; mark = 18.00; upnl = 100.00
  let upnl := pnl.unrealized_pnl(p, price(1800, -2))
  let expected := d.mul(price(200, -2), d.from_int(50))
  match assert_true(d.is_positive(upnl), "short gain positive") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_dec(upnl, expected, "upnl=100.00"),
  }
}

fn test_total_pnl() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(pos.flat(key()), {
    exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true
  })
  let p1 := pu.apply_fill(p0, {
    exec_id: "E2", qty: 50, price: price(1100, -2), is_buy: false
  })
  # realized = 50.00; remaining 50 long @ 10.00; mark=10.50; unrealized=25.00; total=75.00
  let total := pnl.total_pnl(p1, price(1050, -2))
  let expected := d.add(
    d.mul(price(100, -2), d.from_int(50)),
    d.mul(price(50, -2), d.from_int(50))
  )
  assert_eq_dec(total, expected, "total pnl = 75.00")
}

fn suite() -> List[Result[Unit, Str]] {
  [
    test_unrealized_flat_is_zero(),
    test_unrealized_long_gain(),
    test_unrealized_long_loss(),
    test_unrealized_short_gain(),
    test_total_pnl(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_)    => acc,
      Err(msg) => acc + 1,
    }
  })
}
