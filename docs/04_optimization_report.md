# Phase 4 — Optimization report

**Files:** `sql/05_indexes.sql` (8 indexes), `sql/06_optimized_queries.sql` (7 rewritten queries),
`benchmarks/results/optimized/` (summary + raw plans of all 3 runs).

**Result:** total time of all 30 queries went from **2,795.9 ms to 101.6 ms (96.4% less, 27.5× faster)**.
R19 alone went from 2.56 s to 19 ms. The NULL bug in R13 is found and fixed.

## How we measured

- Same method as Phase 3: `EXPLAIN (ANALYZE, BUFFERS)`, 3 runs, average. Writes inside `BEGIN; … ROLLBACK;`.
- **Before** is the committed Phase 3 baseline in `benchmarks/results/baseline/summary.csv`:
  PostgreSQL 15.15 on the benchmark MacBook named in `team.json`.
- **After** is a fresh run on the **same laptop, same PostgreSQL version and same database**, after
  `05_indexes.sql` was applied. The two columns are directly comparable and both can be reproduced
  from the repository.
- Steps: fresh database → `01_schema.sql` → `02_load_data.sql` → baseline benchmark → `05_indexes.sql`
  → optimized benchmark. No server setting was changed.

```bash
createdb dream11
psql -d dream11 -f sql/01_schema.sql
psql -d dream11 -f sql/02_load_data.sql
./benchmarks/run_benchmark.sh dream11 baseline
psql -d dream11 -f sql/05_indexes.sql
./benchmarks/run_benchmark.sh dream11 optimized 3 sql/06_optimized_queries.sql
```

**Note on sub-millisecond queries.** The script opens a new `psql` connection for every run, so queries
that already take well under a millisecond move by a few hundredths of a millisecond between runs even
when the plan and buffer count are identical. R05 is the clearest example: it reads exactly 412 buffers
with the same plan before and after, yet the averages differ by 0.1 ms. Rows where the plan did not
change are marked **noise**; the raw plan files carry the evidence.

## Optimization table

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01 | 0.468 | Seq Scan on contests (2,544 rows) for 6 upcoming matches | `contests_match_idx` → Index Scan | 0.099 | 78.8% (4.7×) | ✅ |
| R02 | 18.225 | Joins every player with every team of the match (11,730 rows), then 11,730 PK probes; Seq Scan on user_teams | Rewrite: count picks per player once in a subquery; `user_teams_match_idx` | 1.056 | 94.2% (17.3×) | ✅ |
| R03 | 0.039 | Already an Index Scan on the unique (user_id, match_id, team_label) index | none needed | 0.034 | noise (same plan) | ✅ |
| R04 | 0.188 | Seq Scan on contests | `contests_match_idx` → Index Scan | 0.086 | 54.3% (2.2×) | ✅ |
| R05 | 0.543 | Already Index Only Scan + PK lookups (412 buffers) | none needed | 0.437 | noise (same 412 buffers) | ✅ |
| R06 | 51.223 | LATERAL subquery runs 3,062 times, each scanning players; Seq Scan on 39,975 teams | Rewrite: window `count(*) OVER (PARTITION BY team, side)`; `user_teams_match_idx` | 1.886 | 96.3% (27.2×) | ✅ |
| R07 | 0.064 | Already index lookups only | none needed | 0.064 | noise (same plan) | ✅ |
| R08 | 1.499 | Seq Scan on 39,975 teams to find 255 | `user_teams_match_idx` → Bitmap Index Scan | 0.289 | 80.7% (5.2×) | ✅ |
| R09 | 4.366 | Seq Scan removes 118,335 wallet rows to find 8 | `wallet_user_time_idx (user_id, created_at, txn_id)` | 0.058 | 98.7% (75.3×) | ✅ |
| R10 | 4.959 | Seq Scan removes 118,243 rows to find 100 pending withdrawals, then sorts | Partial index `wallet_pending_withdrawal_idx` (already in created_at order, no Sort) | 0.032 | 99.4% (155×) | ✅ |
| R11 | 13.410 | Hash joins over 23% of users, half of entries and all teams | none: must read a large share of 3 tables (see below) | 12.475 | noise (same plan) | ✅ |
| R12 | 0.950 | Small tables (4,444 stat rows), hash joins | none needed | 0.847 | noise (same plan) | ✅ |
| R13 | 17.873 | `NOT IN` over a column with 63,000 NULLs → always 0 rows (**wrong answer**); hashed subplan over all wallet rows | Rewrite to `NOT EXISTS … AND txn_type = 'ENTRY_FEE'`; `wallet_reference_entry_idx` → Index Only Scan | 6.441 | 64.0% (2.8×) | ❌ on purpose: 0 → **192** rows (bug fixed) |
| R14 | 6.359 | `EXTRACT(YEAR FROM starts_at)` hides the column; `count(DISTINCT)` sorts every joined entry | Rewrite: sargable date range; count entries per contest first | 4.120 | 35.2% (1.5×) | ✅ |
| R15 | 21.512 | Hash joins of 22,485 entries of 2026 with all teams and users | none: report reads half of entries (see below) | 20.396 | noise (same plan) | ✅ |
| R16 | 0.117 | `ILIKE '%sharma%'` (leading wildcard) → Seq Scan on 450 players | none: a trigram GIN index would be ignored on 450 rows | 0.123 | noise (same plan) | ✅ |
| R17 | 13.275 | Groups every entry by (contest, user) | none: must read all 42,746 entries (see below) | 12.540 | noise (same plan) | ✅ |
| R18 | 10.758 | Seq Scan on 118,343 wallet rows to find 12,302 winnings | Partial covering index `wallet_winnings_user_idx … INCLUDE (amount)` → Index Only Scan | 5.003 | 53.5% (2.2×) | ✅ |
| R19 | 2563.576 | Correlated subquery: 250 × Seq Scan of 439,925 rows (≈110 million rows read) | Rewrite: one `GROUP BY player_id` over user_team_players, then hash join | 19.470 | 99.2% (132×) | ✅ |
| R20 | 6.417 | `created_at::date BETWEEN …` casts every row → Seq Scan | Rewrite: `created_at >= '2026-06-01' AND < '2026-07-01'`; `wallet_time_idx` | 0.750 | 88.3% (8.6×) | ✅ |
| R21 | 6.087 | Hash joins over contests, entries and teams | none needed | 5.373 | noise (same plan) | ✅ |
| R22 | 27.980 | Seq Scan + sort of 118,343 rows, then `OFFSET` throws away 50,000 | Rewrite: keyset pagination on `(created_at, txn_id)`; `wallet_time_idx` → Index Scan Backward, reads 25 rows | 0.027 | 99.9% (1,036×) | ✅ |
| R23 | 0.032 | Already Index Scan on unique phone | none needed | 0.025 | noise (same plan) | ✅ |
| R24 | 0.545 | Small tables, window over 115 rows | none needed | 0.492 | noise (same plan) | ✅ |
| R25 | 9.639 | Seq Scans on entries and wallet for the anti-join | `user_teams_match_idx`, `contest_entries_user_team_idx`, `wallet_reference_entry_idx` | 1.397 | 85.5% (6.9×) | ✅ |
| W01 | 0.962 | Single-row insert | none; now also updates `user_teams_match_idx` | 0.830 | no measurable cost | ✅ (INSERT 1) |
| W02 | 0.502 | Seq Scan on contests | `contests_match_idx` → Index Scan; also updates `contest_entries_user_team_idx` | 0.368 | no measurable cost | ✅ (INSERT 1) |
| W03 | 0.736 | Single-row insert, PK lookups only | none; now also updates 3 wallet indexes | 0.725 | no measurable cost | ✅ (INSERT 1) |
| W04 | 7.597 | Seq Scan on user_teams to find the 278 teams of match 183 | `user_teams_match_idx` → Bitmap Index Scan | 5.552 | 26.9% (1.4×) | ✅ (UPDATE 278) |
| W05 | 6.016 | Seq Scan on 118,343 wallet rows for 100 pending withdrawals | Partial index `wallet_pending_withdrawal_idx` | 0.609 | 89.9% (9.9×) | ✅ (UPDATE 100) |
| **Total** | **2795.917** | | | **101.604** | **96.4% (27.5×)** | |

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

One run of the three is shown; the table above uses the three-run average.

### R19 — 2,563.6 ms → 19.5 ms (132×)

Before: the subquery runs once per IPL player and scans the whole table each time.
```
Sort  (actual time=2633.792..2633.798 rows=250 loops=1)
  ->  Hash Join  (rows=250)
        SubPlan 1
          ->  Aggregate  (actual time=10.532..10.532 rows=1 loops=250)
                ->  Seq Scan on user_team_players utp  (rows=1185 loops=250)
                      Filter: (player_id = p.player_id)
                      Rows Removed by Filter: 438740
Execution Time: 2633.847 ms
```
After: the table is read **once** (in parallel) and grouped.
```
Sort  (actual time=18.794..19.486 rows=250 loops=1)
  ->  Hash Left Join  (Hash Cond: (p.player_id = pk.player_id))
        ->  Hash Join players / teams  (rows=250)
        ->  Hash -> Subquery Scan on pk
              ->  Finalize GroupAggregate  (Group Key: player_id)
                    ->  Gather Merge  (Workers Launched: 1)
                          ->  Partial HashAggregate
                                ->  Parallel Seq Scan on user_team_players  (rows=219962 loops=2)
Execution Time: 19.526 ms
```

### R22 — 28.0 ms → 0.03 ms (1,036×)

Before: read everything, sort, throw away 50,000 rows.
```
Limit  (rows=25)
  ->  Sort  (rows=50025)   Sort Key: created_at DESC
        ->  Seq Scan on wallet_transactions  (rows=118343)
Execution Time: 27.755 ms
```
After: walk the index backwards from the last seen row and stop after 25.
```
Limit  (actual time=0.014..0.016 rows=25 loops=1)
  ->  Index Scan Backward using wallet_time_idx on wallet_transactions  (rows=25)
        Index Cond: (ROW(created_at, txn_id) < ROW('2025-12-25 00:48:00+05:30', 68344))
Execution Time: 0.030 ms
```

### R10 — 5.0 ms → 0.03 ms (155×)

Before:
```
Sort  (rows=100)   Sort Key: created_at
  ->  Seq Scan on wallet_transactions  (rows=100)
        Filter: (txn_type = 'WITHDRAWAL' AND status = 'PENDING' AND created_at < ...)
        Rows Removed by Filter: 118243
Execution Time: 4.949 ms
```
After: the partial index holds only the 100 pending withdrawals, already sorted.
```
Index Scan using wallet_pending_withdrawal_idx on wallet_transactions  (rows=100)
  Index Cond: (created_at < ('2026-06-30 23:59:00+05:30' - '24:00:00'::interval))
Execution Time: 0.033 ms
```

### R09 — 4.4 ms → 0.06 ms (75×)

Before:
```
WindowAgg  (rows=8)
  ->  Sort   Sort Key: created_at, txn_id
        ->  Seq Scan on wallet_transactions  (rows=8)
              Filter: ((user_id = 1006) AND (status = 'SUCCESS'))
              Rows Removed by Filter: 118335
Execution Time: 4.821 ms
```
After:
```
WindowAgg  (rows=8)
  ->  Sort   Sort Key: created_at, txn_id
        ->  Bitmap Heap Scan on wallet_transactions  (rows=8)   Heap Blocks: exact=4
              ->  Bitmap Index Scan on wallet_user_time_idx   Index Cond: (user_id = 1006)
Execution Time: 0.060 ms
```

### R06 — 51.2 ms → 1.9 ms (27×)

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
Execution Time: 51.002 ms
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
Execution Time: 1.878 ms
```

(R02 is a close sixth: 18.2 → 1.1 ms, plans in the result files.)

## Write overhead

Every index on a table must also be updated when a row is inserted.

| Write | Before (ms) | After (ms) | Extra indexes it now updates | Acceptable? |
|-------|-----------:|----------:|------------------------------|-------------|
| W01 create team | 0.962 | 0.830 | `user_teams_match_idx` | Yes. The one-row insert is unchanged within run-to-run spread. |
| W02 join contest | 0.502 | 0.368 | `contest_entries_user_team_idx` | Yes. The contest lookup itself is now an Index Scan. |
| W03 debit wallet | 0.736 | 0.725 | `wallet_user_time_idx`, `wallet_time_idx`, `wallet_reference_entry_idx` (the two partial indexes skip ENTRY_FEE rows) | Yes. Three index writes per row, but 0.01 ms at this size. |
| W04 recompute points | 7.597 | 5.552 | none (`total_points` is not in any index) | Faster by 1.4×. |
| W05 approve withdrawals | 6.016 | 0.609 | rows leave the partial pending index | Faster by 9.9×. |

On this dataset the maintenance cost is **below the measurement spread** — none of W01–W03 is slower
after the indexes. The cost is real and grows with the number of indexes and rows, so the index set is
kept to eight, each justified by a query. CP4 re-checks the write path on the 20× dataset.

## Index storage

| Index | Table | Index size | Table size | Index / table |
|-------|-------|-----------:|-----------:|--------------:|
| `user_teams_match_idx` | user_teams | 304 kB | 2,720 kB | 11.2% |
| `contests_match_idx` | contests | 40 kB | 232 kB | 17.2% |
| `contest_entries_user_team_idx` | contest_entries | 848 kB | 2,624 kB | 32.3% |
| `wallet_user_time_idx` | wallet_transactions | 4,704 kB | 8,400 kB | 56.0% |
| `wallet_winnings_user_idx` (partial) | wallet_transactions | 400 kB | 8,400 kB | 4.8% |
| `wallet_pending_withdrawal_idx` (partial) | wallet_transactions | 16 kB | 8,400 kB | 0.2% |
| `wallet_reference_entry_idx` (partial) | wallet_transactions | 1,720 kB | 8,400 kB | 20.5% |
| `wallet_time_idx` | wallet_transactions | 3,664 kB | 8,400 kB | 43.6% |
| **Total new indexes** | | **≈ 11.4 MB** | | |

The two partial indexes on the wallet are tiny because they store only the rows the query needs
(100 and 12,302 rows out of 118,343).

We dropped an index we first tried, `user_team_players (player_id)`: after the R19 rewrite no query
used it, and it would cost 11 extra index writes for every team created.

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
  hash joins this already runs in about 5 ms.

All of these are reports with a 5,000 ms target on the large dataset, and today they run in 5–20 ms.
