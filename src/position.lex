# lex-positions — core position types and decimal parse/print helpers
#
# PositionKey  — (account, symbol) composite key.
# Position     — signed qty (positive=long, negative=short), WAAC avg_cost,
#                cumulative realized_pnl, all in exact Decimal arithmetic.
# Fill         — one execution: absolute qty, fill price, direction.
#
# parse_price / decimal_to_str bridge FIX string prices to Decimal and back.
# These are the only string-handling helpers in this module.
#
# Effects: none.

import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "lex-money/src/decimal" as d

type PositionKey = {
  account :: Str,
  symbol  :: Str,
}

type Position = {
  key          :: PositionKey,
  qty          :: Int,        # signed: > 0 = long, < 0 = short, 0 = flat
  avg_cost     :: d.Decimal,  # absolute average cost per unit
  realized_pnl :: d.Decimal,  # cumulative realized PnL
}

type Fill = {
  exec_id :: Str,
  qty     :: Int,        # always positive (absolute fill size)
  price   :: d.Decimal,  # fill price per unit
  is_buy  :: Bool,       # true → Buy, false → Sell
}

# ---- Constructors ---------------------------------------------------

fn flat(key :: PositionKey) -> Position
  examples {
    flat({ account: "ACC1", symbol: "AAPL" }) =>
      { key: { account: "ACC1", symbol: "AAPL" }, qty: 0,
        avg_cost: { coefficient: 0, exponent: 0 },
        realized_pnl: { coefficient: 0, exponent: 0 } },
  }
{
  { key: key, qty: 0, avg_cost: d.zero(), realized_pnl: d.zero() }
}

# ---- Predicates -----------------------------------------------------

fn is_long(pos :: Position) -> Bool
  examples {
    is_long({ key: { account: "A", symbol: "X" }, qty: 10,
              avg_cost: { coefficient: 0, exponent: 0 },
              realized_pnl: { coefficient: 0, exponent: 0 } }) => true,
    is_long({ key: { account: "A", symbol: "X" }, qty: 0,
              avg_cost: { coefficient: 0, exponent: 0 },
              realized_pnl: { coefficient: 0, exponent: 0 } }) => false,
  }
{ pos.qty > 0 }

fn is_short(pos :: Position) -> Bool
  examples {
    is_short({ key: { account: "A", symbol: "X" }, qty: 0 - 5,
               avg_cost: { coefficient: 0, exponent: 0 },
               realized_pnl: { coefficient: 0, exponent: 0 } }) => true,
  }
{ pos.qty < 0 }

fn is_flat(pos :: Position) -> Bool
  examples {
    is_flat({ key: { account: "A", symbol: "X" }, qty: 0,
              avg_cost: { coefficient: 0, exponent: 0 },
              realized_pnl: { coefficient: 0, exponent: 0 } }) => true,
  }
{ pos.qty == 0 }

# ---- String ↔ Decimal helpers (FIX prices arrive as strings) --------

fn char_to_digit(c :: Str) -> Option[Int] {
  if c == "0" { Some(0) }
  else { if c == "1" { Some(1) }
  else { if c == "2" { Some(2) }
  else { if c == "3" { Some(3) }
  else { if c == "4" { Some(4) }
  else { if c == "5" { Some(5) }
  else { if c == "6" { Some(6) }
  else { if c == "7" { Some(7) }
  else { if c == "8" { Some(8) }
  else { if c == "9" { Some(9) }
  else { None } } } } } } } } } }
}

fn parse_digits(s :: Str, pos :: Int, acc :: Int) -> Option[Int] {
  if pos >= str.len(s) {
    Some(acc)
  } else {
    match char_to_digit(str.slice(s, pos, pos + 1)) {
      None    => None,
      Some(digit) => parse_digits(s, pos + 1, acc * 10 + digit),
    }
  }
}

fn parse_uint(s :: Str) -> Option[Int] {
  if str.is_empty(s) { None } else { parse_digits(s, 0, 0) }
}

# parse_price "10.05" => Some({ coefficient: 1005, exponent: -2 })
fn parse_price(s :: Str) -> Option[d.Decimal] {
  let is_neg := str.len(s) > 0 and str.slice(s, 0, 1) == "-"
  let unsigned := if is_neg { str.slice(s, 1, str.len(s)) } else { s }
  let parts := str.split(unsigned, ".")
  if list.is_empty(parts) {
    None
  } else {
    if list.len(parts) == 1 {
      match parse_uint(unsigned) {
        None    => None,
        Some(n) => Some(if is_neg { d.negate(d.from_int(n)) } else { d.from_int(n) }),
      }
    } else {
      let int_s  := match list.head(parts) { None => "0", Some(x) => x }
      let frac_s := match list.head(list.tail(parts)) { None => "0", Some(x) => x }
      let frac_len := str.len(frac_s)
      match parse_uint(int_s) {
        None      => None,
        Some(i_n) => match parse_uint(frac_s) {
          None      => None,
          Some(f_n) => {
            let scale := d.pow10(frac_len)
            let coeff := i_n * scale + f_n
            let dec := { coefficient: coeff, exponent: 0 - frac_len }
            Some(if is_neg { d.negate(dec) } else { dec })
          },
        },
      }
    }
  }
}

# decimal_to_str { coefficient: 1005, exponent: -2 } => "10.05"
fn decimal_to_str(dec :: d.Decimal) -> Str {
  if dec.exponent == 0 {
    int.to_str(dec.coefficient)
  } else {
    if dec.exponent > 0 {
      int.to_str(dec.coefficient * d.pow10(dec.exponent))
    } else {
      let abs_exp   := 0 - dec.exponent
      let is_neg    := dec.coefficient < 0
      let abs_coeff := if is_neg { 0 - dec.coefficient } else { dec.coefficient }
      let scale     := d.pow10(abs_exp)
      let int_part  := abs_coeff / scale
      let frac_part := abs_coeff - int_part * scale
      let sign      := if is_neg { "-" } else { "" }
      sign + int.to_str(int_part) + "." + pad_left(int.to_str(frac_part), abs_exp)
    }
  }
}

fn pad_left(s :: Str, width :: Int) -> Str {
  if str.len(s) >= width {
    s
  } else {
    pad_left("0" + s, width)
  }
}

# Convert a whole-number Decimal to Int, returning None if fractional.
fn decimal_to_int(dec :: d.Decimal) -> Option[Int]
  examples {
    decimal_to_int({ coefficient: 100,   exponent:  0 }) => Some(100),
    decimal_to_int({ coefficient: 10000, exponent: -2 }) => Some(100),
    decimal_to_int({ coefficient: 1005,  exponent: -2 }) => None,
  }
{
  if dec.exponent == 0 {
    Some(dec.coefficient)
  } else {
    if dec.exponent > 0 {
      Some(dec.coefficient * d.pow10(dec.exponent))
    } else {
      let scale := d.pow10(0 - dec.exponent)
      let q := dec.coefficient / scale
      if dec.coefficient - q * scale == 0 { Some(q) } else { None }
    }
  }
}
