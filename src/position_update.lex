# lex-positions — pure position update arithmetic
#
# apply_fill is the single entry point. It handles four cases:
#   1. Opening from flat → set qty and avg_cost from fill.
#   2. Adding to existing direction → WAAC formula.
#   3. Reducing position → realize PnL on the closed portion; avg_cost unchanged.
#   4. Cross-zero → close current side (realize PnL), open opposite side at fill price.
#
# WAAC formula: new_avg = (|old_qty| × old_avg + fill_qty × fill_price) / |new_qty|
# Computed with 8-decimal-place precision (HalfEven rounding).
#
# Effects: none.

import "lex-money/src/decimal" as d

import "lex-money/src/rounding" as r

import "./position" as pos

# ---- Public ---------------------------------------------------------
fn apply_fill(position :: pos.Position, fill :: pos.Fill) -> pos.Position {
  let signed_qty := if fill.is_buy {
    fill.qty
  } else {
    0 - fill.qty
  }
  if pos.is_flat(position) {
    { key: position.key, qty: signed_qty, avg_cost: fill.price, realized_pnl: position.realized_pnl }
  } else {
    let same_dir := fill.is_buy and position.qty > 0 or not fill.is_buy and position.qty < 0
    if same_dir {
      add_to_position(position, fill.qty, fill.price, signed_qty)
    } else {
      reduce_or_flip(position, fill)
    }
  }
}

# ---- Internal -------------------------------------------------------
fn abs_qty(n :: Int) -> Int {
  if n < 0 {
    0 - n
  } else {
    n
  }
}

fn waac(old_qty :: Int, old_avg :: d.Decimal, fill_qty :: Int, fill_price :: d.Decimal, new_abs_qty :: Int) -> d.Decimal {
  let numer := d.add(d.mul(d.from_int(old_qty), old_avg), d.mul(d.from_int(fill_qty), fill_price))
  let rounded := r.round_to(numer, -8, HalfEven)
  { coefficient: rounded.coefficient / new_abs_qty, exponent: -8 }
}

fn realized_pnl_delta(is_long :: Bool, close_qty :: Int, fill_price :: d.Decimal, avg_cost :: d.Decimal) -> d.Decimal {
  let price_diff := if is_long {
    d.sub(fill_price, avg_cost)
  } else {
    d.sub(avg_cost, fill_price)
  }
  d.mul(price_diff, d.from_int(close_qty))
}

fn add_to_position(position :: pos.Position, fill_qty :: Int, fill_price :: d.Decimal, signed_qty :: Int) -> pos.Position {
  let old_abs := abs_qty(position.qty)
  let new_qty := position.qty + signed_qty
  let new_avg := waac(old_abs, position.avg_cost, fill_qty, fill_price, abs_qty(new_qty))
  { key: position.key, qty: new_qty, avg_cost: new_avg, realized_pnl: position.realized_pnl }
}

fn reduce_or_flip(position :: pos.Position, fill :: pos.Fill) -> pos.Position {
  let abs_pos_qty := abs_qty(position.qty)
  let close_qty := if fill.qty < abs_pos_qty {
    fill.qty
  } else {
    abs_pos_qty
  }
  let pnl_delta := realized_pnl_delta(position.qty > 0, close_qty, fill.price, position.avg_cost)
  let new_realized := d.add(position.realized_pnl, pnl_delta)
  let remaining := fill.qty - close_qty
  if remaining == 0 {
    let new_qty := position.qty + if fill.is_buy {
      fill.qty
    } else {
      0 - fill.qty
    }
    let new_avg := if new_qty == 0 {
      d.zero()
    } else {
      position.avg_cost
    }
    { key: position.key, qty: new_qty, avg_cost: new_avg, realized_pnl: new_realized }
  } else {
    let new_signed := if fill.is_buy {
      remaining
    } else {
      0 - remaining
    }
    { key: position.key, qty: new_signed, avg_cost: fill.price, realized_pnl: new_realized }
  }
}

