# lex-positions

WAAC position book with realized PnL for the [Lex language](https://github.com/alpibrusl/lex-lang).

Tracks signed positions (positive = long, negative = short) per account/symbol pair. Every fill updates the weighted average acquisition cost (WAAC) and accumulates realized PnL using exact `Decimal` arithmetic from [lex-money](https://github.com/alpibrusl/lex-money). Positions are persisted via [lex-orm](https://github.com/alpibrusl/lex-orm) (SQLite or PostgreSQL).

## What it ships

- **`src/position.lex`** — `Position` record (`qty`, `avg_cost`, `realized_pnl`), `PositionKey`, `Fill`; `parse_price` / `decimal_to_str` helpers for FIX string prices.
- **`src/position_update.lex`** — pure `apply_fill` with four cases: open from flat, add to direction (WAAC formula), reduce (realize PnL), cross-zero (close + reopen opposite). WAAC computed at 8-decimal-place precision (HalfEven rounding).
- **`src/position_store.lex`** — `[sql]`-effected store. `init` creates the `positions` table; `fetch` returns a flat zero-position for absent rows; `apply_and_store` applies a fill and persists atomically.
- **`src/pnl.lex`** — `unrealized_pnl` (MTM vs avg_cost) and `total_pnl` (realized + unrealized).
- **`src/exposure.lex`** — `gross_notional` (`|qty| × mark`), `within_notional`, `net_exposure`.

## Usage

```lex
import "lex-positions/src/position"       as pos
import "lex-positions/src/position_store" as pstore

# Apply a fill; position is fetched from DB, updated, and written back
let key  := { account: "ACC-1", symbol: "AAPL" }
let fill := { exec_id: "EX-001", qty: 100, price: pos.parse_price("174.91"), is_buy: true }
let __   := pstore.apply_and_store(db, key, fill)
```

## Effects

Pure modules (`position.lex`, `position_update.lex`, `pnl.lex`, `exposure.lex`) have no effects. `position_store.lex` requires `[sql]`.

## Dependencies

- **lex-money** — `Decimal` arithmetic and rounding.
- **lex-fix** — `ExecutionReport` types used by `fill_from_er.lex`.
- **lex-orm** — SQL connection abstraction.

---

Built under the principles of [Trust Without Comprehension](https://alpibru.com/manifesto).
