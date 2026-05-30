# lex-positions — ExecutionReport → Fill adapter
#
# Bridges lex-fix ExecutionReports into the Fill type used by position_update.
# Only ExecFill and ExecPartialFill reports carry position-relevant data;
# all other exec_types return None.
#
# Effects: none.

import "std.str" as str

import "lex-fix/src/v44/execution_report" as er

import "lex-fix/src/v44/enums" as en

import "./position" as pos

fn is_fill_report(exec_type :: en.ExecType) -> Bool
  examples {
    is_fill_report(ExecFill(())) => true,
    is_fill_report(ExecPartialFill(())) => true,
    is_fill_report(ExecNew(())) => false,
    is_fill_report(ExecCanceled(())) => false
  }
{
  match exec_type {
    ExecFill(_) => true,
    ExecPartialFill(_) => true,
    _ => false,
  }
}

fn fill_from_er(report :: er.ExecutionReport) -> List[pos.Fill] {
  if not is_fill_report(report.exec_type) {
    []
  } else {
    if str.is_empty(report.last_qty) {
      []
    } else {
      if str.is_empty(report.last_px) {
        []
      } else {
        match pos.parse_price(report.last_qty) {
          None => [],
          Some(qty_dec) => match pos.decimal_to_int(qty_dec) {
            None => [],
            Some(qty) => match pos.parse_price(report.last_px) {
              None => [],
              Some(price) => {
                let is_buy := match report.side {
                  Buy(_) => true,
                  Sell(_) => false,
                }
                if qty <= 0 {
                  []
                } else {
                  [{ exec_id: report.exec_id, qty: qty, price: price, is_buy: is_buy }]
                }
              },
            },
          },
        }
      }
    }
  }
}

