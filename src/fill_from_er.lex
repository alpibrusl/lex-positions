# lex-positions — ExecutionReport → Fill adapter
#
# Bridges lex-fix ExecutionReports into the Fill type used by position_update.
# Only ExecFill and ExecPartialFill reports carry position-relevant data;
# all other exec_types return None.
#
# Effects: none.

import "lex-fix/src/v44/execution_report" as er
import "lex-fix/src/v44/enums"            as en

import "./position" as pos

fn is_fill_report(exec_type :: en.ExecType) -> Bool
  examples {
    is_fill_report(ExecFill)        => true,
    is_fill_report(ExecPartialFill) => true,
    is_fill_report(ExecNew)         => false,
    is_fill_report(ExecCanceled)    => false,
  }
{
  match exec_type {
    ExecFill        => true,
    ExecPartialFill => true,
    _               => false,
  }
}

fn fill_from_er(report :: er.ExecutionReport) -> Option[pos.Fill] {
  if not is_fill_report(report.exec_type) {
    None
  } else {
    match report.last_qty {
      None          => None,
      Some(qty_str) => match report.last_px {
        None         => None,
        Some(px_str) => match pos.parse_price(qty_str) {
          None          => None,
          Some(qty_dec) => match pos.decimal_to_int(qty_dec) {
            None      => None,
            Some(qty) => match pos.parse_price(px_str) {
              None        => None,
              Some(price) => {
                let is_buy := match report.side {
                  Buy  => true,
                  Sell => false,
                }
                if qty <= 0 {
                  None
                } else {
                  Some({
                    exec_id: report.exec_id,
                    qty:     qty,
                    price:   price,
                    is_buy:  is_buy,
                  })
                }
              },
            },
          },
        },
      },
    }
  }
}
