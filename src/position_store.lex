# lex-positions — SQL-backed position store
#
# Persists Position records via lex-orm ConnDb (SQLite or PostgreSQL).
# The [positions] effect gates all public functions so callers must
# explicitly declare they hold the "positions" capability.
#
# Schema (DDL created by init):
#   positions (
#     account          TEXT NOT NULL,
#     symbol           TEXT NOT NULL,
#     qty              INTEGER NOT NULL DEFAULT 0,
#     avg_cost_str     TEXT NOT NULL DEFAULT '0',
#     realized_pnl_str TEXT NOT NULL DEFAULT '0',
#     PRIMARY KEY (account, symbol)
#   )
#
# fetch returns a flat (zero-qty) position when no row exists rather
# than an error, so callers can always treat an absent account/symbol
# pair as a fresh position.
#
# Effects: [sql]

import "std.sql" as sql

import "std.list" as list

import "std.str" as str

import "lex-orm/src/connection" as conn

import "lex-orm/src/query" as q

import "lex-orm/src/error" as dbe

import "./position" as pos

import "./position_update" as pu

fn init(db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  let ddl := "CREATE TABLE IF NOT EXISTS positions (account TEXT NOT NULL, symbol TEXT NOT NULL, qty INTEGER NOT NULL DEFAULT 0, avg_cost_str TEXT NOT NULL DEFAULT '0', realized_pnl_str TEXT NOT NULL DEFAULT '0', PRIMARY KEY (account, symbol))"
  match sql.exec(db.handle, ddl, []) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(_) => Ok(()),
  }
}

fn fetch(db :: conn.ConnDb, key :: pos.PositionKey) -> [sql] Result[pos.Position, dbe.DbErr] {
  let sq := q.for_dialect({ sql: "SELECT qty, avg_cost_str, realized_pnl_str FROM positions WHERE account = ? AND symbol = ?", params: [PStr(key.account), PStr(key.symbol)] }, db.dialect)
  let raw :: Result[List[{ qty :: Int, avg_cost_str :: Str, realized_pnl_str :: Str }], SqlError] := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(rows) => match list.head(rows) {
      None => Ok(pos.flat(key)),
      Some(row) => decode_row(key, row),
    },
  }
}

fn store(db :: conn.ConnDb, position :: pos.Position) -> [sql] Result[Unit, dbe.DbErr] {
  let avg_str := pos.decimal_to_str(position.avg_cost)
  let pnl_str := pos.decimal_to_str(position.realized_pnl)
  let sq := q.for_dialect({ sql: "INSERT INTO positions (account, symbol, qty, avg_cost_str, realized_pnl_str) VALUES (?, ?, ?, ?, ?) ON CONFLICT (account, symbol) DO UPDATE SET qty = EXCLUDED.qty, avg_cost_str = EXCLUDED.avg_cost_str, realized_pnl_str = EXCLUDED.realized_pnl_str", params: [PStr(position.key.account), PStr(position.key.symbol), PInt(position.qty), PStr(avg_str), PStr(pnl_str)] }, db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(_) => Ok(()),
  }
}

fn apply_and_store(db :: conn.ConnDb, key :: pos.PositionKey, fill :: pos.Fill) -> [sql] Result[pos.Position, dbe.DbErr] {
  match fetch(db, key) {
    Err(err) => Err(err),
    Ok(current) => {
      let updated := pu.apply_fill(current, fill)
      match store(db, updated) {
        Err(err) => Err(err),
        Ok(_) => Ok(updated),
      }
    },
  }
}

fn remove(db :: conn.ConnDb, key :: pos.PositionKey) -> [sql] Result[Unit, dbe.DbErr] {
  let sq := q.for_dialect({ sql: "DELETE FROM positions WHERE account = ? AND symbol = ?", params: [PStr(key.account), PStr(key.symbol)] }, db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(_) => Ok(()),
  }
}

# ---- Internal -------------------------------------------------------
fn decode_row(key :: pos.PositionKey, row :: { qty :: Int, avg_cost_str :: Str, realized_pnl_str :: Str }) -> Result[pos.Position, dbe.DbErr] {
  match pos.parse_price(row.avg_cost_str) {
    None => Err(dbe.decode_err(str.concat("invalid avg_cost_str: ", row.avg_cost_str))),
    Some(avg) => match pos.parse_price(row.realized_pnl_str) {
      None => Err(dbe.decode_err(str.concat("invalid realized_pnl_str: ", row.realized_pnl_str))),
      Some(pnl) => Ok({ key: key, qty: row.qty, avg_cost: avg, realized_pnl: pnl }),
    },
  }
}

