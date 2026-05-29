# Tests for fill_from_er — ExecutionReport → Fill conversion.
#
# All tests are pure (no effects).

import "std.list" as list

import "lex-money/src/decimal" as d

import "lex-fix/src/v44/execution_report" as er

import "lex-fix/src/v44/enums" as en

import "../src/position" as pos

import "../src/fill_from_er" as filler

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

fn price(c :: Int, e :: Int) -> d.Decimal {
  d.decimal(c, e)
}

fn sample_er(exec_type :: en.ExecType, side :: en.Side, last_qty :: Str, last_px :: Str) -> er.ExecutionReport {
  { exec_id: "EXEC-001", order_id: "ORD-001", cl_ord_id: "CL-001", exec_type: exec_type, ord_status: StatusPartiallyFilled(()), symbol: "AAPL", side: side, order_qty: "200", cum_qty: "100", leaves_qty: "100", avg_px: "10.00", last_px: last_px, last_qty: last_qty, text: "" }
}

fn test_exec_new_returns_none() -> Result[Unit, Str] {
  let report := sample_er(ExecNew(()), Buy(()), "100", "10.50")
  assert_true(filler.fill_from_er(report) == [], "ExecNew → []")
}

fn test_exec_canceled_returns_none() -> Result[Unit, Str] {
  let report := sample_er(ExecCanceled(()), Buy(()), "100", "10.50")
  assert_true(filler.fill_from_er(report) == [], "ExecCanceled → []")
}

fn test_exec_fill_no_qty_returns_none() -> Result[Unit, Str] {
  let report := sample_er(ExecFill(()), Buy(()), "", "10.50")
  assert_true(filler.fill_from_er(report) == [], "ExecFill no qty → []")
}

fn test_exec_fill_no_px_returns_none() -> Result[Unit, Str] {
  let report := sample_er(ExecFill(()), Buy(()), "100", "")
  assert_true(filler.fill_from_er(report) == [], "ExecFill no px → []")
}

fn test_exec_fill_buy_produces_fill() -> Result[Unit, Str] {
  let report := sample_er(ExecFill(()), Buy(()), "100", "10.50")
  match list.head(filler.fill_from_er(report)) {
    None => fail("ExecFill Buy should produce a fill"),
    Some(fill) => match assert_true(fill.exec_id == "EXEC-001", "exec_id") {
      Err(e) => Err(e),
      Ok(_) => match assert_true(fill.qty == 100, "qty=100") {
        Err(e) => Err(e),
        Ok(_) => match assert_true(fill.is_buy == true, "is_buy=true") {
          Err(e) => Err(e),
          Ok(_) => assert_true(d.eq(fill.price, price(1050, -2)), "price=10.50"),
        },
      },
    },
  }
}

fn test_exec_partial_fill_sell_produces_fill() -> Result[Unit, Str] {
  let report := sample_er(ExecPartialFill(()), Sell(()), "50", "10.00")
  match list.head(filler.fill_from_er(report)) {
    None => fail("ExecPartialFill Sell should produce a fill"),
    Some(fill) => match assert_true(fill.qty == 50, "qty=50") {
      Err(e) => Err(e),
      Ok(_) => match assert_true(fill.is_buy == false, "is_buy=false") {
        Err(e) => Err(e),
        Ok(_) => assert_true(d.eq(fill.price, price(1000, -2)), "price=10.00"),
      },
    },
  }
}

fn test_is_fill_report_classification() -> Result[Unit, Str] {
  match assert_true(filler.is_fill_report(ExecFill(())), "ExecFill is fill") {
    Err(e) => Err(e),
    Ok(_) => match assert_true(filler.is_fill_report(ExecPartialFill(())), "ExecPartialFill is fill") {
      Err(e) => Err(e),
      Ok(_) => match assert_true(not filler.is_fill_report(ExecNew(())), "ExecNew not fill") {
        Err(e) => Err(e),
        Ok(_) => match assert_true(not filler.is_fill_report(ExecRejected(())), "ExecRejected not fill") {
          Err(e) => Err(e),
          Ok(_) => assert_true(not filler.is_fill_report(ExecPendingNew(())), "ExecPendingNew not fill"),
        },
      },
    },
  }
}

fn suite() -> List[Result[Unit, Str]] {
  [test_exec_new_returns_none(), test_exec_canceled_returns_none(), test_exec_fill_no_qty_returns_none(), test_exec_fill_no_px_returns_none(), test_exec_fill_buy_produces_fill(), test_exec_partial_fill_sell_produces_fill(), test_is_fill_report_classification()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => acc,
      Err(msg) => acc + 1,
    }
  })
}

