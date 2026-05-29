# Tests for position_store — SQL-backed persistence.
#
# Uses in-memory SQLite via conn.connect_sqlite(":memory:").
# Effects: [positions, sql, fs_write]

import "std.list" as list

import "lex-orm/src/connection" as conn

import "lex-orm/src/error" as dbe

import "lex-money/src/decimal" as d

import "../src/position" as pos

import "../src/position_store" as store

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

fn price(c :: Int, e :: Int) -> d.Decimal {
  { coefficient: c, exponent: e }
}

fn open_db() -> [positions, sql, fs_write] Result[conn.ConnDb, Str] {
  match conn.connect_sqlite(":memory:") {
    Err(err) => Err(dbe.message(err)),
    Ok(db) => match store.init(db) {
      Err(err) => Err(dbe.message(err)),
      Ok(_) => Ok(db),
    },
  }
}

# ---- Tests ----------------------------------------------------------
fn test_fetch_empty_returns_flat() -> [positions, sql, fs_write] Result[Unit, Str] {
  match open_db() {
    Err(msg) => fail(msg),
    Ok(db) => {
      let k := { account: "ACC1", symbol: "AAPL" }
      match store.fetch(db, k) {
        Err(e) => fail(dbe.message(e)),
        Ok(p) => match assert_eq_int(p.qty, 0, "qty=0") {
          Err(e) => Err(e),
          Ok(_) => match assert_true(d.is_zero(p.avg_cost), "avg=0") {
            Err(e) => Err(e),
            Ok(_) => assert_true(d.is_zero(p.realized_pnl), "pnl=0"),
          },
        },
      }
    },
  }
}

fn test_store_and_fetch_roundtrip() -> [positions, sql, fs_write] Result[Unit, Str] {
  match open_db() {
    Err(msg) => fail(msg),
    Ok(db) => {
      let k := { account: "ACC1", symbol: "MSFT" }
      let fill := { exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true }
      let position := pu.apply_fill(pos.flat(k), fill)
      match store.store(db, position) {
        Err(e) => fail(dbe.message(e)),
        Ok(_) => match store.fetch(db, k) {
          Err(e) => fail(dbe.message(e)),
          Ok(p) => match assert_eq_int(p.qty, 100, "qty=100") {
            Err(e) => Err(e),
            Ok(_) => match assert_eq_dec(p.avg_cost, price(1000, -2), "avg=10.00") {
              Err(e) => Err(e),
              Ok(_) => assert_true(d.is_zero(p.realized_pnl), "pnl=0"),
            },
          },
        },
      }
    },
  }
}

fn test_apply_and_store_two_buys() -> [positions, sql, fs_write] Result[Unit, Str] {
  match open_db() {
    Err(msg) => fail(msg),
    Ok(db) => {
      let k := { account: "ACC2", symbol: "GOOG" }
      let f1 := { exec_id: "E1", qty: 50, price: price(2000, -2), is_buy: true }
      let f2 := { exec_id: "E2", qty: 50, price: price(2100, -2), is_buy: true }
      match store.apply_and_store(db, k, f1) {
        Err(e) => fail(dbe.message(e)),
        Ok(_) => match store.apply_and_store(db, k, f2) {
          Err(e) => fail(dbe.message(e)),
          Ok(p) => match assert_eq_int(p.qty, 100, "qty=100") {
            Err(e) => Err(e),
            Ok(_) => assert_eq_dec(p.avg_cost, { coefficient: 2050000000, exponent: -8 }, "avg=20.50 at 8dp"),
          },
        },
      }
    },
  }
}

fn test_apply_and_store_realizes_pnl() -> [positions, sql, fs_write] Result[Unit, Str] {
  match open_db() {
    Err(msg) => fail(msg),
    Ok(db) => {
      let k := { account: "ACC3", symbol: "TSLA" }
      let buy := { exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true }
      let sell := { exec_id: "E2", qty: 100, price: price(1200, -2), is_buy: false }
      let __lex_discard_1 := store.apply_and_store(db, k, buy)
      match store.apply_and_store(db, k, sell) {
        Err(e) => fail(dbe.message(e)),
        Ok(p) => {
          let expected_pnl := d.mul(price(200, -2), d.from_int(100))
          match assert_eq_int(p.qty, 0, "qty=0") {
            Err(e) => Err(e),
            Ok(_) => assert_eq_dec(p.realized_pnl, expected_pnl, "realized=200.00"),
          }
        },
      }
    },
  }
}

fn test_remove_leaves_flat() -> [positions, sql, fs_write] Result[Unit, Str] {
  match open_db() {
    Err(msg) => fail(msg),
    Ok(db) => {
      let k := { account: "ACC4", symbol: "NVDA" }
      let fill := { exec_id: "E1", qty: 10, price: price(50000, -2), is_buy: true }
      let __lex_discard_2 := store.apply_and_store(db, k, fill)
      match store.remove(db, k) {
        Err(e) => fail(dbe.message(e)),
        Ok(_) => match store.fetch(db, k) {
          Err(e) => fail(dbe.message(e)),
          Ok(p) => assert_eq_int(p.qty, 0, "qty=0 after remove"),
        },
      }
    },
  }
}

fn test_two_accounts_isolated() -> [positions, sql, fs_write] Result[Unit, Str] {
  match open_db() {
    Err(msg) => fail(msg),
    Ok(db) => {
      let k1 := { account: "ACC-A", symbol: "SPY" }
      let k2 := { account: "ACC-B", symbol: "SPY" }
      let f1 := { exec_id: "E1", qty: 200, price: price(50000, -2), is_buy: true }
      let f2 := { exec_id: "E2", qty: 50, price: price(50100, -2), is_buy: false }
      let __lex_discard_3 := store.apply_and_store(db, k1, f1)
      let __lex_discard_4 := store.apply_and_store(db, k2, f2)
      match store.fetch(db, k1) {
        Err(e) => fail(dbe.message(e)),
        Ok(p1) => match store.fetch(db, k2) {
          Err(e) => fail(dbe.message(e)),
          Ok(p2) => match assert_eq_int(p1.qty, 200, "acc-a qty=200") {
            Err(e) => Err(e),
            Ok(_) => assert_eq_int(p2.qty, 0 - 50, "acc-b qty=-50"),
          },
        },
      }
    },
  }
}

fn suite() -> [positions, sql, fs_write] List[Result[Unit, Str]] {
  [test_fetch_empty_returns_flat(), test_store_and_fetch_roundtrip(), test_apply_and_store_two_buys(), test_apply_and_store_realizes_pnl(), test_remove_leaves_flat(), test_two_accounts_isolated()]
}

fn run_all() -> [positions, sql, fs_write] Int {
  list.fold(suite(), 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => acc,
      Err(msg) => acc + 1,
    }
  })
}

