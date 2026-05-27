# Tests for position_store — SQL-backed persistence.
#
# Uses in-memory SQLite via conn.connect_sqlite(":memory:").
# Effects: [positions, sql, fs_write]

import "lex-orm/src/connection" as conn
import "lex-orm/src/error"      as dbe

import "lex-money/src/decimal" as d

import "../src/position"       as pos
import "../src/position_store" as store
import "../src/position_update" as pu

# ---- Helpers --------------------------------------------------------

fn key(account :: Str, symbol :: Str) -> pos.PositionKey {
  { account: account, symbol: symbol }
}

fn open_db() -> [positions, sql, fs_write] Result[conn.ConnDb, Str] {
  match conn.connect_sqlite(":memory:") {
    Err(err) => Err(dbe.message(err)),
    Ok(db)   => match store.init(db) {
      Err(err) => Err(dbe.message(err)),
      Ok(_)    => Ok(db),
    },
  }
}

fn db_err(e :: dbe.DbErr) -> Result[Unit, Str] { Err(dbe.message(e)) }

fn price(c :: Int, e :: Int) -> d.Decimal { { coefficient: c, exponent: e } }

# ---- Tests ----------------------------------------------------------

test "fetch on empty db returns flat position" {
  match open_db() {
    Err(msg) => assert false,
    Ok(db)   => {
      let k := key("ACC1", "AAPL")
      match store.fetch(db, k) {
        Err(_) => assert false,
        Ok(p)  => {
          assert p.qty == 0
          assert d.is_zero(p.avg_cost)
          assert d.is_zero(p.realized_pnl)
        },
      }
    },
  }
}

test "store then fetch round-trips a long position" {
  match open_db() {
    Err(_)  => assert false,
    Ok(db)  => {
      let k := key("ACC1", "MSFT")
      let fill := { exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true }
      let position := pu.apply_fill(pos.flat(k), fill)
      match store.store(db, position) {
        Err(err) => assert false,
        Ok(_)    => match store.fetch(db, k) {
          Err(_) => assert false,
          Ok(p)  => {
            assert p.qty == 100
            assert p.avg_cost == price(1000, -2)
            assert d.is_zero(p.realized_pnl)
          },
        },
      }
    },
  }
}

test "apply_and_store updates position on second fill" {
  match open_db() {
    Err(_)  => assert false,
    Ok(db)  => {
      let k := key("ACC2", "GOOG")
      let fill1 := { exec_id: "E1", qty: 50, price: price(2000, -2), is_buy: true }
      let fill2 := { exec_id: "E2", qty: 50, price: price(2100, -2), is_buy: true }
      match store.apply_and_store(db, k, fill1) {
        Err(_) => assert false,
        Ok(_)  => match store.apply_and_store(db, k, fill2) {
          Err(_) => assert false,
          Ok(p)  => {
            assert p.qty == 100
            # WAAC = (50*20.00 + 50*21.00)/100 = 20.50 at 8dp
            assert p.avg_cost == { coefficient: 2050000000, exponent: -8 }
          },
        },
      }
    },
  }
}

test "apply_and_store realizes PnL on sell" {
  match open_db() {
    Err(_)  => assert false,
    Ok(db)  => {
      let k := key("ACC3", "TSLA")
      let buy  := { exec_id: "E1", qty: 100, price: price(1000, -2), is_buy: true }
      let sell := { exec_id: "E2", qty: 100, price: price(1200, -2), is_buy: false }
      let _ := store.apply_and_store(db, k, buy)
      match store.apply_and_store(db, k, sell) {
        Err(_) => assert false,
        Ok(p)  => {
          assert p.qty == 0
          assert d.is_zero(p.avg_cost)
          # realized = (12.00 - 10.00) * 100 = 200.00
          assert p.realized_pnl == d.mul(price(200, -2), d.from_int(100))
        },
      }
    },
  }
}

test "store then remove leaves position flat" {
  match open_db() {
    Err(_)  => assert false,
    Ok(db)  => {
      let k := key("ACC4", "NVDA")
      let fill := { exec_id: "E1", qty: 10, price: price(50000, -2), is_buy: true }
      let _ := store.apply_and_store(db, k, fill)
      match store.remove(db, k) {
        Err(_) => assert false,
        Ok(_)  => match store.fetch(db, k) {
          Err(_) => assert false,
          Ok(p)  => assert p.qty == 0,
        },
      }
    },
  }
}

test "two accounts same symbol are isolated" {
  match open_db() {
    Err(_)  => assert false,
    Ok(db)  => {
      let k1 := key("ACC-A", "SPY")
      let k2 := key("ACC-B", "SPY")
      let fill1 := { exec_id: "E1", qty: 200, price: price(50000, -2), is_buy: true }
      let fill2 := { exec_id: "E2", qty: 50,  price: price(50100, -2), is_buy: false }
      let _ := store.apply_and_store(db, k1, fill1)
      let _ := store.apply_and_store(db, k2, fill2)
      match store.fetch(db, k1) {
        Err(_) => assert false,
        Ok(p1) => match store.fetch(db, k2) {
          Err(_) => assert false,
          Ok(p2) => {
            assert p1.qty == 200
            assert p2.qty == 0 - 50
          },
        },
      }
    },
  }
}
