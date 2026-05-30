# Tests for position_update — pure WAAC and realized-PnL arithmetic.
#
# All tests are pure (no effects). Prices use { coefficient, exponent }
# notation: { coefficient: 1050, exponent: -2 } = 10.50.

import "std.list" as list

import "lex-money/src/decimal" as d

import "../src/position" as pos

import "../src/position_update" as pu

fn pass() -> Result[Unit, Str] {
  Ok(())
}

fn fail(why :: Str) -> Result[Unit, Str] {
  Err(why)
}

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    pass()
  } else {
    fail(label)
  }
}

fn assert_eq_int(a :: Int, b :: Int, label :: Str) -> Result[Unit, Str] {
  assert_true(a == b, label)
}

fn assert_eq_dec(a :: d.Decimal, b :: d.Decimal, label :: Str) -> Result[Unit, Str] {
  assert_true(d.eq(a, b), label)
}

# ---- Fixtures -------------------------------------------------------
fn key() -> pos.PositionKey {
  { account: "ACC1", symbol: "AAPL" }
}

fn flat_pos() -> pos.Position {
  pos.flat(key())
}

fn price(coeff :: Int, exp :: Int) -> d.Decimal {
  { coefficient: coeff, exponent: exp }
}

fn buy_fill(exec_id :: Str, qty :: Int, coeff :: Int, exp :: Int) -> pos.Fill {
  { exec_id: exec_id, qty: qty, price: price(coeff, exp), is_buy: true }
}

fn sell_fill(exec_id :: Str, qty :: Int, coeff :: Int, exp :: Int) -> pos.Fill {
  { exec_id: exec_id, qty: qty, price: price(coeff, exp), is_buy: false }
}

# ---- Open from flat -------------------------------------------------
fn test_buy_opens_long() -> Result[Unit, Str] {
  let result := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  match assert_eq_int(result.qty, 100, "qty=100") {
    Err(e) => Err(e),
    Ok(_) => match assert_eq_dec(result.avg_cost, price(1000, -2), "avg=10.00") {
      Err(e) => Err(e),
      Ok(_) => assert_true(d.is_zero(result.realized_pnl), "pnl=0"),
    },
  }
}

fn test_sell_opens_short() -> Result[Unit, Str] {
  let result := pu.apply_fill(flat_pos(), sell_fill("E2", 50, 2000, -2))
  match assert_eq_int(result.qty, 0 - 50, "qty=-50") {
    Err(e) => Err(e),
    Ok(_) => assert_eq_dec(result.avg_cost, price(2000, -2), "avg=20.00"),
  }
}

# ---- Adding to existing direction -----------------------------------
fn test_second_buy_waac() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  let p1 := pu.apply_fill(p0, buy_fill("E2", 100, 1100, -2))
  match assert_eq_int(p1.qty, 200, "qty=200") {
    Err(e) => Err(e),
    Ok(_) => assert_eq_dec(p1.avg_cost, { coefficient: 1050000000, exponent: -8 }, "avg=10.50 at 8dp"),
  }
}

fn test_second_sell_waac() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(flat_pos(), sell_fill("E1", 50, 2000, -2))
  let p1 := pu.apply_fill(p0, sell_fill("E2", 50, 2200, -2))
  match assert_eq_int(p1.qty, 0 - 100, "qty=-100") {
    Err(e) => Err(e),
    Ok(_) => assert_eq_dec(p1.avg_cost, { coefficient: 2100000000, exponent: -8 }, "avg=21.00 at 8dp"),
  }
}

# ---- Partial close --------------------------------------------------
fn test_partial_sell_realizes_pnl() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  let p1 := pu.apply_fill(p0, sell_fill("E2", 40, 1100, -2))
  let expected_pnl := d.mul(price(100, -2), d.from_int(40))
  match assert_eq_int(p1.qty, 60, "qty=60") {
    Err(e) => Err(e),
    Ok(_) => assert_eq_dec(p1.realized_pnl, expected_pnl, "realized=40.00"),
  }
}

fn test_partial_buy_realizes_pnl_on_short() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(flat_pos(), sell_fill("E1", 100, 2000, -2))
  let p1 := pu.apply_fill(p0, buy_fill("E2", 30, 1800, -2))
  let expected_pnl := d.mul(price(200, -2), d.from_int(30))
  match assert_eq_int(p1.qty, 0 - 70, "qty=-70") {
    Err(e) => Err(e),
    Ok(_) => assert_eq_dec(p1.realized_pnl, expected_pnl, "realized=60.00"),
  }
}

# ---- Exact close ----------------------------------------------------
fn test_exact_close_resets_position() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  let p1 := pu.apply_fill(p0, sell_fill("E2", 100, 1200, -2))
  let expected_pnl := d.mul(price(200, -2), d.from_int(100))
  match assert_eq_int(p1.qty, 0, "qty=0") {
    Err(e) => Err(e),
    Ok(_) => match assert_true(d.is_zero(p1.avg_cost), "avg_cost=0") {
      Err(e) => Err(e),
      Ok(_) => assert_eq_dec(p1.realized_pnl, expected_pnl, "realized=200.00"),
    },
  }
}

# ---- Cross-zero ----------------------------------------------------
fn test_cross_zero_sell_flips_to_short() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(flat_pos(), buy_fill("E1", 100, 1000, -2))
  let p1 := pu.apply_fill(p0, sell_fill("E2", 150, 1100, -2))
  let expected_pnl := d.mul(price(100, -2), d.from_int(100))
  match assert_eq_int(p1.qty, 0 - 50, "qty=-50") {
    Err(e) => Err(e),
    Ok(_) => match assert_eq_dec(p1.avg_cost, price(1100, -2), "avg=11.00") {
      Err(e) => Err(e),
      Ok(_) => assert_eq_dec(p1.realized_pnl, expected_pnl, "realized=100.00"),
    },
  }
}

fn test_cross_zero_buy_flips_to_long() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(flat_pos(), sell_fill("E1", 50, 2000, -2))
  let p1 := pu.apply_fill(p0, buy_fill("E2", 80, 1800, -2))
  let expected_pnl := d.mul(price(200, -2), d.from_int(50))
  match assert_eq_int(p1.qty, 30, "qty=30") {
    Err(e) => Err(e),
    Ok(_) => match assert_eq_dec(p1.avg_cost, price(1800, -2), "avg=18.00") {
      Err(e) => Err(e),
      Ok(_) => assert_eq_dec(p1.realized_pnl, expected_pnl, "realized=100.00"),
    },
  }
}

# ---- PnL accumulates -----------------------------------------------
fn test_pnl_accumulates() -> Result[Unit, Str] {
  let p0 := pu.apply_fill(flat_pos(), buy_fill("E1", 200, 1000, -2))
  let p1 := pu.apply_fill(p0, sell_fill("E2", 50, 1050, -2))
  let p2 := pu.apply_fill(p1, sell_fill("E3", 50, 1100, -2))
  let expected := d.mul(price(7500, -2), d.from_int(1))
  match assert_eq_int(p2.qty, 100, "qty=100") {
    Err(e) => Err(e),
    Ok(_) => assert_eq_dec(p2.realized_pnl, expected, "total realized=75.00"),
  }
}

# ---- Suite ----------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [test_buy_opens_long(), test_sell_opens_short(), test_second_buy_waac(), test_second_sell_waac(), test_partial_sell_realizes_pnl(), test_partial_buy_realizes_pnl_on_short(), test_exact_close_resets_position(), test_cross_zero_sell_flips_to_short(), test_cross_zero_buy_flips_to_long(), test_pnl_accumulates()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => acc,
      Err(msg) => acc + 1,
    }
  })
}

