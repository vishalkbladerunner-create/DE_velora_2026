# Phase 4 — Optimization report

**Files:** `sql/05_indexes.sql` (8 indexes), `sql/06_optimized_queries.sql` (7 rewritten queries),
`benchmarks/results/optimized/` (summary + raw plans of all 3 runs).

**Result:** total time of all 30 queries went from **2,681.8 ms to 142.7 ms (94.7% less, 18.8× faster)**.
R19 alone went from 2.43 s to 19 ms. The NULL bug in R13 is found and fixed.

## How we measured

- Same method as Phase 3: `EXPLAIN (ANALYZE, BUFFERS)`, 3 runs, average. Writes inside `BEGIN; … ROLLBACK;`.
- **Before** and **After** were measured on the **same laptop and the same database** (PostgreSQL 14.20,
  Apple Silicon MacBook), as the brief requires. That is why the "Before" column is a fresh baseline
  run and not a copy of the Phase 3 table (Phase 3 was run on another team laptop; its numbers are
  close: R19 2,563.6 ms there vs 2,431.9 ms here).
- Steps: fresh database → `01_schema.sql` → `02_load_data.sql` → `VACUUM ANALYZE` → baseline
  benchmark → `05_indexes.sql` → optimized benchmark. Each benchmark was run once to warm the cache
  and then once more for the recorded numbers.

```bash
./benchmarks/run_benchmark.sh dream11 baseline
psql -d dream11 -f sql/05_indexes.sql
./benchmarks/run_benchmark.sh dream11 optimized 3 sql/06_optimized_queries.sql
```

**Note on sub-millisecond queries.** The script opens a new `psql` connection for every run, and the
first query in a new connection pays a one-time catalog-cache cost of about 1 ms. For queries that
already took under 1 ms (R03, R05, R07, W01–W03) this cost is bigger than the query itself, so the
numbers jump around even when the plan and the buffer count are identical. Example: R05 reads exactly
412 buffers with the same plan before and after; in one warm session it runs in 0.34 ms either way.
These rows are marked "noise" below.

## Optimization table

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01 | 0.238 | Seq Scan on contests (2,544 rows) for 6 upcoming matches | `contests_match_idx` → Index Scan | 0.307 | noise (sub-ms) | ✅ |
| R02 | 25.755 | Joins every player with every team of the match (11,730 rows), then 11,730 PK probes; Seq Scan on user_teams | Rewrite: count picks per player once in a subquery; `user_teams_match_idx` | 3.698 | 85.6% (7.0×) | ✅ |
| R03 | 0.036 | Already an Index Scan on the unique (user_id, match_id, team_label) index | none needed | 0.118 | noise (same plan) | ✅ |
| R04 | 0.235 | Seq Scan on contests | `contests_match_idx` → Index Scan | 0.328 | noise (sub-ms) | ✅ |
| R05 | 0.474 | Already Index Only Scan + PK lookups (412 buffers) | none needed | 1.865 | noise (same plan, same 412 buffers) | ✅ |
| R06 | 52.290 | LATERAL subquery runs 3,062 times, each scanning players; Seq Scan on 39,975 teams | Rewrite: window `count(*) OVER (PARTITION BY team, side)`; `user_teams_match_idx` | 5.497 | 89.5% (9.5×) | ✅ |
| R07 | 0.074 | Already index lookups only | none needed | 0.180 | noise (same plan) | ✅ |
| R08 | 1.557 | Seq Scan on 39,975 teams to find 255 | `user_teams_match_idx` → Bitmap Index Scan | 1.151 | 26.1% (1.4×) | ✅ |
| R09 | 5.249 | Seq Scan removes 118,335 wallet rows to find 8 | `wallet_user_time_idx (user_id, created_at, txn_id)` | 0.191 | 96.4% (27.5×) | ✅ |
| R10 | 6.847 | Seq Scan removes 118,243 rows to find 100 pending withdrawals, then sorts | Partial index `wallet_pending_withdrawal_idx` (already in created_at order, no Sort) | 0.111 | 98.4% (61.7×) | ✅ |
| R11 | 15.231 | Hash joins over 23% of users, half of entries and all teams | none: must read a large share of 3 tables (see below) | 21.138 | noise (same plan) | ✅ |
| R12 | 0.949 | Small tables (4,444 stat rows), hash joins | none needed | 0.877 | 7.6% | ✅ |
| R13 | 15.491 | `NOT IN` over a column with 63,000 NULLs → always 0 rows (**wrong answer**); hashed subplan over all wallet rows | Rewrite to `NOT EXISTS … AND txn_type = 'ENTRY_FEE'`; `wallet_reference_entry_idx` → Index Only Scan | 8.335 | 46.2% (1.9×) | ❌ on purpose: 0 → **192** rows (bug fixed) |
| R14 | 6.489 | `EXTRACT(YEAR FROM starts_at)` hides the column; `count(DISTINCT)` sorts every joined entry | Rewrite: sargable date range; count entries per contest first | 7.021 | noise in this run; warm, interleaved: 7.5–11.5 → 4.5–5.5 ms (≈1.7×) | ✅ |
| R15 | 19.876 | Hash joins of 22,485 entries of 2026 with all teams and users | none: report reads half of entries (see below) | 28.005 | noise (same plan) | ✅ |
| R16 | 0.134 | `ILIKE '%sharma%'` (leading wildcard) → Seq Scan on 450 players | none: a trigram GIN index would be ignored on 450 rows | 0.135 | 0% | ✅ |
| R17 | 14.765 | Groups every entry by (contest, user) | none: must read all 42,746 entries (see below) | 15.174 | ~0% | ✅ |
| R18 | 9.570 | Seq Scan on 118,343 wallet rows to find 12,302 winnings | Partial covering index `wallet_winnings_user_idx … INCLUDE (amount)` → Index Only Scan | 4.995 | 47.8% (1.9×) | ✅ |
| R19 | 2431.899 | Correlated subquery: 250 × Seq Scan of 439,925 rows (≈110 million rows read) | Rewrite: one `GROUP BY player_id` over user_team_players, then hash join | 18.985 | 99.2% (128.1×) | ✅ |
| R20 | 5.877 | `created_at::date BETWEEN …` casts every row → Seq Scan | Rewrite: `created_at >= '2026-06-01' AND < '2026-07-01'`; `wallet_time_idx` | 0.814 | 86.1% (7.2×) | ✅ |
| R21 | 6.956 | Hash joins over contests, entries and teams | none needed | 5.998 | 13.8% (noise) | ✅ |
| R22 | 26.806 | Seq Scan + sort of 118,343 rows, then `OFFSET` throws away 50,000 | Rewrite: keyset pagination on `(created_at, txn_id)`; `wallet_time_idx` → Index Scan Backward, reads 25 rows | 0.026 | 99.9% (1031×) | ✅ |
| R23 | 0.021 | Already Index Scan on unique phone | none needed | 0.022 | 0% | ✅ |
| R24 | 0.680 | Small tables, window over 115 rows | none needed | 0.574 | 15.6% | ✅ |
| R25 | 11.122 | Seq Scans on entries and wallet for the anti-join | `user_teams_match_idx`, `contest_entries_user_team_idx`, `wallet_reference_entry_idx` | 3.215 | 71.1% (3.5×) | ✅ |
| W01 | 0.560 | Single-row insert | none; now also updates `user_teams_match_idx` | 1.362 | slower (see write overhead) | ✅ (INSERT 1) |
| W02 | 0.395 | Seq Scan on contests | `contests_match_idx` → Index Scan; also updates `contest_entries_user_team_idx` | 0.699 | slower (see write overhead) | ✅ (INSERT 1) |
| W03 | 0.301 | Single-row insert, PK lookups only | none; now also updates 3 wallet indexes | 1.232 | slower (see write overhead) | ✅ (INSERT 1) |
| W04 | 12.208 | Seq Scan on user_teams to find the 278 teams of match 183 | `user_teams_match_idx` → Bitmap Index Scan | 9.105 | 25.4% (1.3×) | ✅ (UPDATE 278) |
| W05 | 9.675 | Seq Scan on 118,343 wallet rows for 100 pending withdrawals | Partial index `wallet_pending_withdrawal_idx` | 1.512 | 84.4% (6.4×) | ✅ (UPDATE 100) |
| **Total** | **2681.760** | | | **142.670** | **94.7% (18.8×)** | |

Improvement % = (before − after) / before × 100.

## The NULL bug (R13)

```sql
AND ce.entry_id NOT IN (SELECT w.reference_entry_id FROM wallet_transactions w)
```

63,000 wallet rows (deposits, bonuses, withdrawals) have `reference_entry_id = NULL`.
`x NOT IN (a, b, NULL)` means `x <> a AND x <> b AND x <> NULL`. The last part is `NULL` (unknown), so the
whole condition can never be `TRUE`, and the query **always returns 0 rows**. That is why the finance
team says the audit "always comes back empty".

Fix:

```sql
AND NOT EXISTS (SELECT 1 FROM wallet_transactions w
                WHERE w.reference_entry_id = ce.entry_id AND w.txn_type = 'ENTRY_FEE')
```

`NOT EXISTS` only asks "is there a matching row?", so NULLs do not matter. We also check
`txn_type = 'ENTRY_FEE'`, because the question is about a missing **entry-fee debit**:

| Version | Rows |
|---------|-----:|
| Original `NOT IN` | 0 (wrong) |
| `NOT EXISTS`, any wallet row for the entry | 128 |
| `NOT EXISTS`, ENTRY_FEE row for the entry (**our fix**) | **192** |

The 64 extra entries have a REFUND or WINNINGS row but never paid the fee; a refund is not a debit,
so they belong in the audit.

## Proof that results are unchanged

For every read query we ran the original (from `queries/workload_30.sql`, before any index) and the
optimized version (from `sql/06_optimized_queries.sql`, with all indexes) as

```sql
SELECT count(*), md5(string_agg(x::text, '|' ORDER BY x::text)) FROM (<query>) x;
```

and compared row count and checksum. **All 24 queries other than R13 have the same rows and the same
checksum.** Results of the 7 rewritten queries:

| Query | Rows before | Rows after | md5 of sorted rows (before = after) |
|-------|-----------:|----------:|-------------------------------------|
| R02 | 46 | 46 | `fbf40f46cdbc51f8e2c95f66dcf9a40b` |
| R06 | 51 | 51 | `878a492fbeb1e247bc6bb19fe6be3a99` |
| R13 | 0 | 192 | changed on purpose (bug fix above) |
| R14 | 4 | 4 | `d57f550264736edeb6c57deb5efa6c64` |
| R19 | 250 | 250 | `de721949fe6605eb852f93aae4d6eb0d` |
| R20 | 28 | 28 | `d67d776a7448668e9abfd4e35a6d4bf6` |
| R22 | 25 | 25 | `c9b9fec347bec262720c43a6b66d3ae6` |

**Order.** We also compared the checksum of the rows in the order they are returned. All match except
R02 and R18, and in both cases only rows with **equal sort values** swapped places (R02 sorts only by
`selected_pct`, R18 only by `total_winnings`; ties have no defined order in SQL). The sequence of sort
values is identical: R02 `md5(string_agg(selected_pct))` = `e397704086737d890b001082e340d0d2` before and
after, R18 the same with and without the index.

**R22 keyset.** The original page starts after row 50,000 of `ORDER BY created_at DESC`, which is
txn 68344 at `2025-12-25 00:48:00+05:30`. The keyset version starts right after that row. We checked
that the timestamps at both page edges (rows 50,000, 50,001, 50,025, 50,026) are unique, so ordering by
`(created_at, txn_id)` returns exactly the same 25 rows. In the app, the "last seen" pair is the last
row of the page the user is looking at.

**Writes** are not rewritten. With the indexes they still insert 1 / 1 / 1 row and update 278 / 100
rows, and everything is rolled back.

## Before / after plans: 5 biggest improvements

Plans are shortened (buffer lines removed). Full plans: `benchmarks/results/optimized/<id>.txt`.

### R19 — 2,431.9 ms → 19.0 ms (128×)

Before: the subquery runs once per IPL player and scans the whole table each time.
```
Sort  (actual time=2433.367..2433.373 rows=250 loops=1)
  ->  Hash Join  (rows=250)
        SubPlan 1
          ->  Aggregate  (actual time=9.732..9.733 rows=1 loops=250)
                ->  Seq Scan on user_team_players utp  (rows=1185 loops=250)
                      Filter: (player_id = p.player_id)
                      Rows Removed by Filter: 438740
Execution Time: 2433.423 ms
```
After: the table is read **once** (in parallel) and grouped.
```
Sort  (actual time=18.086..18.475 rows=250 loops=1)
  ->  Hash Left Join  (Hash Cond: (p.player_id = pk.player_id))
        ->  Hash Join players / teams  (rows=250)
        ->  Hash -> Subquery Scan on pk
              ->  Finalize GroupAggregate  (Group Key: player_id)
                    ->  Partial HashAggregate
                          ->  Parallel Seq Scan on user_team_players  (rows=219962 loops=2)
Execution Time: 18.515 ms
```

### R22 — 26.8 ms → 0.026 ms (1031×)

Before: read everything, sort, throw away 50,000 rows.
```
Limit  (rows=25)
  ->  Sort  (rows=50025)   Sort Key: created_at DESC
        ->  Seq Scan on wallet_transactions  (rows=118343)
Execution Time: 24.497 ms
```
After: walk the index backwards from the last seen row and stop after 25.
```
Limit  (rows=25)
  ->  Index Scan Backward using wallet_time_idx on wallet_transactions  (rows=25)
        Index Cond: (ROW(created_at, txn_id) < ROW('2025-12-25 00:48:00+05:30', 68344))
Execution Time: 0.026 ms
```

### R10 — 6.8 ms → 0.11 ms (62×)

Before:
```
Sort  (rows=100)   Sort Key: created_at
  ->  Seq Scan on wallet_transactions  (rows=100)
        Filter: (txn_type = 'WITHDRAWAL' AND status = 'PENDING' AND created_at < ...)
        Rows Removed by Filter: 118243
Execution Time: 7.183 ms
```
After: the partial index holds only the 100 pending withdrawals, already sorted.
```
Index Scan using wallet_pending_withdrawal_idx on wallet_transactions  (rows=100)
  Index Cond: (created_at < ('2026-06-30 23:59:00+05:30' - '24:00:00'))
Execution Time: 0.101 ms
```

### R09 — 5.2 ms → 0.19 ms (27×)

Before:
```
WindowAgg  (rows=8)
  ->  Sort   Sort Key: created_at, txn_id
        ->  Seq Scan on wallet_transactions  (rows=8)
              Filter: ((user_id = 1006) AND (status = 'SUCCESS'))
              Rows Removed by Filter: 118335
Execution Time: 5.256 ms
```
After:
```
WindowAgg  (rows=8)
  ->  Sort   Sort Key: created_at, txn_id
        ->  Bitmap Heap Scan on wallet_transactions  (rows=8)   Heap Blocks: exact=4
              ->  Bitmap Index Scan on wallet_user_time_idx   Index Cond: (user_id = 1006)
Execution Time: 0.195 ms
```

### R06 — 52.3 ms → 5.5 ms (9.5×)

Before: the LATERAL count runs 3,062 times (once per team-player row).
```
GroupAggregate  (rows=51)
  ->  Sort  (rows=3062)
        ->  Nested Loop  (rows=3062)
              ->  Hash Join ... Seq Scan on user_teams ut (Filter: match_id = 183, Rows Removed: 39697)
              ->  Aggregate  (loops=3062)
                    ->  Hash Join
                          ->  Seq Scan on players px  (loops=3062)  Filter: (team_id = p.team_id)
                          ->  Index Only Scan using user_team_players_pkey  (loops=3062)
Execution Time: 45.349 ms
```
After: one pass, the "players from this side" count is a window function.
```
GroupAggregate  (rows=51)
  ->  WindowAgg  (rows=3062)
        ->  Sort  Sort Key: ut.user_team_id, p.team_id
              ->  Hash Join
                    ->  Nested Loop
                          ->  Bitmap Heap Scan on user_teams ut
                                ->  Bitmap Index Scan on user_teams_match_idx  (match_id = 183)
                          ->  Index Only Scan using user_team_players_pkey  (loops=278)
                    ->  Seq Scan on players p  (rows=450)
Execution Time: 4.586 ms
```

(R02 is a close sixth: 25.8 → 3.7 ms, plans in the result files.)

## Write overhead

Every index on a table must also be updated when a row is inserted.

| Write | Before (ms) | After (ms) | Extra indexes it now updates | Acceptable? |
|-------|-----------:|----------:|------------------------------|-------------|
| W01 create team | 0.560 | 1.362 | `user_teams_match_idx` | Yes. +0.8 ms, part of it is the new-connection cost explained above; still far below the 5 ms target. |
| W02 join contest | 0.395 | 0.699 | `contest_entries_user_team_idx` | Yes. +0.3 ms; the contest lookup itself is now an Index Scan. |
| W03 debit wallet | 0.301 | 1.232 | `wallet_user_time_idx`, `wallet_time_idx`, `wallet_reference_entry_idx` (the two partial indexes skip ENTRY_FEE rows) | Yes. +0.9 ms for one row; these indexes make R09, R13, R20, R22, R25 10–1000× faster. |
| W04 recompute points | 12.208 | 9.105 | none (`total_points` is not in any index) | Faster. |
| W05 approve withdrawals | 9.675 | 1.512 | rows leave the partial pending index | Faster. |

We dropped an index we first tried, `user_team_players (player_id)`: after the R19 rewrite no query
used it, and it would cost 11 extra index writes for every team created.

## Index storage

| Index | Table | Index size | Table size | Index / table |
|-------|-------|-----------:|-----------:|--------------:|
| `user_teams_match_idx` | user_teams | 304 kB | 2,776 kB | 11.0% |
| `contests_match_idx` | contests | 40 kB | 232 kB | 17.2% |
| `contest_entries_user_team_idx` | contest_entries | 848 kB | 2,624 kB | 32.3% |
| `wallet_user_time_idx` | wallet_transactions | 4,704 kB | 8,424 kB | 55.8% |
| `wallet_winnings_user_idx` (partial) | wallet_transactions | 400 kB | 8,424 kB | 4.7% |
| `wallet_pending_withdrawal_idx` (partial) | wallet_transactions | 16 kB | 8,424 kB | 0.2% |
| `wallet_reference_entry_idx` (partial) | wallet_transactions | 1,720 kB | 8,424 kB | 20.4% |
| `wallet_time_idx` | wallet_transactions | 3,664 kB | 8,424 kB | 43.5% |
| **Total new indexes** | | **≈ 11 MB** | | |

The two partial indexes on the wallet are tiny because they store only the rows the query needs
(100 and 12,302 rows out of 118,343).

## Queries we could not (or did not need to) speed up

- **R03, R05, R07, R23** already used the primary-key / unique indexes from Phase 2 and run in well
  under 1 ms. Nothing to gain.
- **R12, R16, R24** work on tiny tables (450 players, 4,444 stats rows). A sequential scan of a few pages
  is the cheapest plan. For R16, `ILIKE '%sharma%'` has a leading wildcard, so only a `pg_trgm` GIN index
  could help, and the planner would still choose a Seq Scan on 450 rows.
- **R11** (compliance) must find all users in 4 states (11,713 users = 23%), all their teams and their
  22,485 entries from 2026 (53% of entries). When a query needs a quarter to a half of each table,
  hash joins over sequential scans are the right plan; the new indexes on `user_teams` and
  `contest_entries` were available and the planner correctly did not use them. Same plan before and after.
- **R15** (top users by 2026 winnings) has to sum the winnings of half of all entries before it can
  pick the top 20. Same reason as R11.
- **R17** (users with several teams in one contest) has to group **every** contest entry; there is no
  filter, so the whole table must be read.
- **R21** (head-to-head win rate) joins all head-to-head contests with their entries and teams; with
  hash joins this already runs in about 6 ms.

All of these are reports with a 5,000 ms target on the large dataset, and today they run in 6–28 ms.
