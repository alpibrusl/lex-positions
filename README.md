# lex-positions

[![CI](https://github.com/alpibrusl/lex-positions/actions/workflows/ci.yml/badge.svg)](https://github.com/alpibrusl/lex-positions/actions/workflows/ci.yml)

**Part of the [Lex](https://lexlang.org) project** — Finance · [Manifesto](https://lexlang.org/manifesto) · [All packages](https://lexlang.org)

WAAC position book with realized PnL for Lex.

Tracks signed positions (positive = long, negative = short) per account/symbol pair. Every fill updates the weighted average acquisition cost using exact `Decimal` arithmetic from `lex-money`. Positions are persisted via `lex-orm` (SQLite or PostgreSQL).

---

## How position updates work

Four cases, all handled in `position_update.lex`:

| Case | Action |
|---|---|
| Flat → fill | Open new position; avg_cost = fill price |
| Same direction | Add to position; WAAC formula updates avg_cost |
| Opposite direction (partial) | Reduce position; realize PnL on closed portion |
| Opposite direction (cross-zero) | Close position fully, realize PnL; reopen in new direction |

WAAC computed at 8 decimal places with HalfEven rounding.

---

## Modules

- **`position.lex`** — `Position` record (`qty`, `avg_cost`, `realized_pnl`), `PositionKey` (`account`, `symbol`), `Fill` record, price string parsers.
- **`position_update.lex`** — pure `apply_fill(position, fill) -> Position`. No effects.
- **`position_store.lex`** — `[sql]`-effected store. `init` creates the table; `fetch` returns a flat zero-position for absent rows; `apply_and_store` applies a fill and persists atomically.
- **`pnl.lex`** — `unrealized_pnl(position, mark_price)` and `total_pnl`.
- **`exposure.lex`** — `gross_notional(position, mark_price)`, `net_exposure`, `within_notional`.
- **`fill_from_er.lex`** — converts a `lex-fix` `ExecutionReport` to a `Fill`.

---

## Usage

```lex
import "lex-positions/src/position"       as pos
import "lex-positions/src/position_store" as pstore

let key  := { account: "ACC-1", symbol: "AAPL" }
let fill := { exec_id: "EX-001", qty: 100, price: pos.parse_price("174.91"), is_buy: true }
let __   := pstore.apply_and_store(db, key, fill)
```

Pure modules (`position_update`, `pnl`, `exposure`) have no effects. `position_store` requires `[sql]`.

---

## In the stack

```
lex-money · lex-fix
    ↓
lex-positions  ←  portfolio state
    ↓
lex-risk · lex-trade · lex-finance · lex-oms
```

Every fill that flows through `lex-oms` updates positions here. `lex-risk` reads positions to compute Greeks and margin. `lex-trade` pre-trade checks query positions to enforce notional limits.

---

## Install

```toml
[dependencies]
"lex-positions" = { git = "https://github.com/alpibrusl/lex-positions" }
```

## License

Copyright (c) 2026 lex-positions contributors.

Licensed under the [EUPL-1.2](LICENSE) — the European Union Public Licence, as used across the `lex-*` ecosystem.
