# Tests for fill_from_er — ExecutionReport → Fill conversion.
#
# All tests are pure (no effects).

import "lex-fix/src/v44/execution_report" as er
import "lex-fix/src/v44/enums"            as en

import "../src/position"     as pos
import "../src/fill_from_er" as filler

fn sample_er(exec_type :: en.ExecType, side :: en.Side, last_qty :: Option[Str], last_px :: Option[Str]) -> er.ExecutionReport {
  {
    exec_id:    "EXEC-001",
    order_id:   "ORD-001",
    cl_ord_id:  "CL-001",
    exec_type:  exec_type,
    ord_status: StatusPartiallyFilled,
    symbol:     "AAPL",
    side:       side,
    order_qty:  "200",
    cum_qty:    "100",
    leaves_qty: "100",
    avg_px:     "10.00",
    last_px:    last_px,
    last_qty:   last_qty,
    text:       None,
  }
}

test "ExecNew returns None" {
  let report := sample_er(ExecNew, Buy, Some("100"), Some("10.50"))
  assert filler.fill_from_er(report) == None
}

test "ExecCanceled returns None" {
  let report := sample_er(ExecCanceled, Buy, Some("100"), Some("10.50"))
  assert filler.fill_from_er(report) == None
}

test "ExecFill with no last_qty returns None" {
  let report := sample_er(ExecFill, Buy, None, Some("10.50"))
  assert filler.fill_from_er(report) == None
}

test "ExecFill with no last_px returns None" {
  let report := sample_er(ExecFill, Buy, Some("100"), None)
  assert filler.fill_from_er(report) == None
}

test "ExecFill Buy produces correct Fill" {
  let report := sample_er(ExecFill, Buy, Some("100"), Some("10.50"))
  match filler.fill_from_er(report) {
    None       => assert false,
    Some(fill) => {
      assert fill.exec_id == "EXEC-001"
      assert fill.qty     == 100
      assert fill.is_buy  == true
      assert fill.price   == { coefficient: 1050, exponent: -2 }
    },
  }
}

test "ExecPartialFill Sell produces correct Fill" {
  let report := sample_er(ExecPartialFill, Sell, Some("50"), Some("10.00"))
  match filler.fill_from_er(report) {
    None       => assert false,
    Some(fill) => {
      assert fill.qty    == 50
      assert fill.is_buy == false
      assert fill.price  == { coefficient: 1000, exponent: -2 }
    },
  }
}

test "is_fill_report correctly classifies exec types" {
  assert filler.is_fill_report(ExecFill)          == true
  assert filler.is_fill_report(ExecPartialFill)   == true
  assert filler.is_fill_report(ExecNew)           == false
  assert filler.is_fill_report(ExecRejected)      == false
  assert filler.is_fill_report(ExecPendingNew)    == false
  assert filler.is_fill_report(ExecPendingCancel) == false
}
