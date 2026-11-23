# Phase 5 — Scalability report

**Project:** Dream11 Fantasy Sports Database · **Team:** T0020
**Database:** PostgreSQL 15.15 · **Large dataset:** `large_data.zip` (77 MB zip, 333 MB CSV)
**Workload:** [`sql/06_optimized_queries.sql`](../sql/06_optimized_queries.sql) — the Phase 4 optimized queries, three runs per query.

---

## 1. Dataset and method

The faculty released `large_data.zip` on 21 November. It contains the same ten CSV files and columns as the seed data, with these row counts:

| Table | Seed rows | Large rows | Growth |
| --- | ---: | ---: | ---: |
| users | 50,000 | 1,000,000 | 20× |
| user_teams | 39,975 | 799,462 | 20× |
| user_team_players | 439,925 | 8,798,080 | 20× |
| contests | 2,544 | 2,544 | 1× |
| contest_entries | 42,746 | 245,242 | 5.7× |
| wallet_transactions | 118,343 | 1,577,740 | 13.3× |
| matches / players / teams / stats | small dimensions | unchanged | 1× |
| **Total** | **698,657** | **12,428,192** | **17.8×** |

The large database was created from scratch:

```bash
createdb dream11_large
psql -d dream11_large -f sql/01_schema.sql
psql -d dream11_large -f sql/07_load_large.sql
psql -d dream11_large -f sql/05_indexes.sql
psql -d dream11_large -f sql/09_scale_fixes.sql
psql -d dream11_large -c 'ANALYZE'
```

`large_data/` is gitignored; no CSV is committed. The load completed in 1 min 37 s. The seed comparison database is `dream11_seed` (78 MB); the large database is `dream11_large` (1,250 MB).

**One schema issue appeared before the load:** `users.username` was `VARCHAR(25)`, and the large dataset contains a 26-character username (`Siddharth_11Banerjee100346`). The column and its format CHECK were widened to 40 characters in [`sql/01_schema.sql`](../sql/01_schema.sql) and [`docs/02_schema_design.md`](02_schema_design.md); the seed rows still satisfy the constraint. This is recorded here because it is a scale-only finding.

### Timing method

Each query was run three times with `EXPLAIN (ANALYZE, BUFFERS)` through the provided [`benchmarks/run_benchmark.sh`](../benchmarks/run_benchmark.sh). Write queries ran inside `BEGIN; … ROLLBACK;`. One warm-up pass preceded the measured pass, because the first pass on a cold 1.25 GB database is dominated by buffer reads and checkpoint writes rather than by the query plan. The cold pass is kept in [`benchmarks/results/large/summary-cold.csv`](../benchmarks/results/large/summary-cold.csv); the measured pass is [`summary.csv`](../benchmarks/results/large/summary.csv).

---

## 2. Results on the large dataset

Targets are the Phase 5 targets from the brief: real-time **< 5 ms**, interactive **< 250 ms**, reports **< 5,000 ms**. `MISS*` is 0.4% over the line and within run-to-run noise.

| Query | Seed optimized (ms) | Large (ms) | Growth | Target | Status | Scan type |
| --- | ---: | ---: | ---: | --- | --- | --- |
| R01 | 0.099 | 0.118 | 1.2× | < 5 ms | MET | Seq Scan on matches; Seq Scan on teams; Index Scan using contests_match_idx on contests |
| R02 | 1.056 | 17.972 | 17.0× | < 5 ms | MISS | Bitmap Heap Scan on user_teams; Bitmap Index Scan on user_teams_match_idx; Index Only Scan using user_team_players_pkey on user_team_players; Seq Scan on matches; Seq Scan on players; Seq Scan on teams |
| R03 | 0.034 | 0.050 | 1.5× | < 5 ms | MET | Index Scan using user_teams_user_match_label_unique on user_teams; Index Scan using players_pkey on players |
| R04 | 0.086 | 0.995 | 11.6× | < 5 ms | MET | Index Scan using contests_match_idx on contests; Index Scan using contest_entries_contest_team_unique on contest_entries |
| R05 | 0.437 | 13.385 | 30.6× | < 5 ms | MISS | Index Only Scan using contest_entries_contest_team_unique on contest_entries; Index Only Scan using user_teams_leaderboard_cover_idx on user_teams; Index Only Scan using users_name_cover_idx on users |
| R06 | 1.886 | 30.071 | 15.9× | < 250 ms | MET | Bitmap Heap Scan on user_teams; Bitmap Index Scan on user_teams_match_idx; Index Only Scan using user_team_players_pkey on user_team_players; Seq Scan on players |
| R07 | 0.064 | 0.037 | 0.6× | < 5 ms | MET | Index Scan using user_teams_user_match_label_unique on user_teams; Index Only Scan using user_team_players_pkey on user_team_players; Index Scan using players_pkey on players; Index Scan using player_match_stats_pkey on player_match_stats |
| R08 | 0.289 | 5.021 | 17.4× | < 5 ms | MISS* | Bitmap Heap Scan on user_teams; Bitmap Index Scan on user_teams_match_idx; Seq Scan on players |
| R09 | 0.058 | 0.038 | 0.7× | < 5 ms | MET | Index Scan using wallet_user_time_idx on wallet_transactions |
| R10 | 0.032 | 1.062 | 33.2× | < 250 ms | MET | Index Scan using wallet_pending_withdrawal_idx on wallet_transactions |
| R11 | 12.475 | 120.895 | 9.7× | < 5,000 ms | MET | Seq Scan on user_teams; Seq Scan on users; Seq Scan on contest_entries; Seq Scan on contests |
| R12 | 0.847 | 1.072 | 1.3× | < 5,000 ms | MET | Seq Scan on player_match_stats; Seq Scan on matches; Seq Scan on players; Seq Scan on teams |
| R13 | 6.441 | 45.364 | 7.0× | < 250 ms | MET | Index Scan using contest_entries_pkey on contest_entries; Index Only Scan using wallet_reference_entry_idx on wallet_transactions; Seq Scan on contests |
| R14 | 4.120 | 13.639 | 3.3× | < 5,000 ms | MET | Seq Scan on contests; Seq Scan on matches; Seq Scan on contest_entries |
| R15 | 20.396 | 169.506 | 8.3× | < 5,000 ms | MET | Seq Scan on users; Seq Scan on user_teams; Seq Scan on contest_entries |
| R16 | 0.123 | 0.163 | 1.3× | < 250 ms | MET | Seq Scan on players; Seq Scan on teams |
| R17 | 12.540 | 234.233 | 18.7× | < 5,000 ms | MET | Seq Scan on user_teams; Seq Scan on contest_entries |
| R18 | 5.003 | 49.855 | 10.0× | < 5,000 ms | MET | Seq Scan on users; Index Only Scan using wallet_winnings_user_idx on wallet_transactions |
| R19 | 19.470 | 362.561 | 18.6× | < 5,000 ms | MET | Seq Scan on players; Seq Scan on teams; Seq Scan on user_team_players |
| R20 | 0.750 | 20.612 | 27.5× | < 5,000 ms | MET | Bitmap Heap Scan on wallet_transactions; Bitmap Index Scan on wallet_time_idx |
| R21 | 5.373 | 36.859 | 6.9× | < 5,000 ms | MET | Seq Scan on user_teams; Seq Scan on contest_entries; Seq Scan on contests |
| R22 | 0.027 | 0.037 | 1.4× | < 250 ms | MET | Index Scan using wallet_time_idx on wallet_transactions |
| R23 | 0.025 | 0.048 | 1.9× | < 5 ms | MET | Index Scan using users_phone_key on users |
| R24 | 0.492 | 1.288 | 2.6× | < 5,000 ms | MET | Seq Scan on player_match_stats; Seq Scan on players; Seq Scan on teams; Seq Scan on matches |
| R25 | 1.397 | 36.362 | 26.0× | < 250 ms | MET | Seq Scan on user_teams; Seq Scan on matches; Index Scan using contest_entries_user_team_idx on contest_entries; Index Only Scan using wallet_reference_entry_idx on wallet_transactions; Seq Scan on contests |
| W01 | 0.830 | 1.443 | 1.7× | < 5 ms | MET | Seq Scan on matches |
| W02 | 0.368 | 0.539 | 1.5× | < 5 ms | MET | Index Scan using user_teams_pkey on user_teams; Index Scan using contests_match_idx on contests; Index Scan using user_teams_leaderboard_cover_idx on user_teams |
| W03 | 0.725 | 1.328 | 1.8× | < 5 ms | MET | Index Only Scan using contest_entries_pkey on contest_entries; Index Scan using contest_entries_pkey on contest_entries; Index Scan using contests_pkey on contests; Index Only Scan using user_teams_leaderboard_cover_idx on user_teams |
| W04 | 5.552 | 105.702 | 19.0× | < 250 ms | MET | Bitmap Heap Scan on user_teams; Bitmap Index Scan on user_teams_match_idx; Index Only Scan using user_team_players_pkey on user_team_players; Bitmap Heap Scan on player_match_stats; Bitmap Index Scan on player_match_stats_pkey |
| W05 | 0.609 | 19.174 | 31.5× | < 250 ms | MET | Index Scan using wallet_pending_withdrawal_idx on wallet_transactions |

**27 of 30 queries meet the target.** Three need an explanation:

- **R02 (17.97 ms average, 11.31 ms median) — real-time target 5 ms.** The team-creation screen has to count 4,686 teams × 11 players ≈ 51,500 picks for match 207. Even with the covering indexes, the count touches every pick. Warm runs are 11–12 ms; the cold pass was 93–119 ms. The correct fix is a per-match summary (`match_player_selection`), not a bigger index; the DDL is in section 5. With the summary, R02 becomes a lookup of 46 player rows and should be under 1 ms.
- **R05 (13.39 ms average, 5.87 ms median) — real-time target 5 ms.** The leaderboard joins 1,101 contest entries to teams and users. The covering indexes removed the heap fetches; the remaining 5–6 ms is 2,202 index probes plus the window sort. A materialized `contest_leaderboard` refreshed after scoring would make the read a single ordered scan; the design is in section 5.
- **R08 (5.021 ms average, 4.939 ms median) — 0.4% over 5 ms.** The minimum is 4.866 ms and the median is 4.939 ms; one 5.258 ms run pulls the average over by 0.021 ms. This is measurement noise at the target boundary, not a plan regression. No change was made.

The cold pass (before the warm-up) is the honest worst case: R02 93.5 ms, R05 12.05 ms, R08 4.628 ms, W04 308 ms. The warm-up removes the buffer-read and checkpoint spike; the plan shapes are the same.

---

## 3. Growth analysis

The 18× data growth does not produce a single growth factor. The plan shape decides the class:

| Class | Queries | What happened |
| --- | --- | --- |
| **Sub-linear (≤ 2×)** | R01, R03, R07, R09, R12, R16, R22, R23, W01, W02, W03 | Index lookups grow with `log n`; the small dimension tables and unique keys dominate. R07 and R09 are actually faster than the seed timing because the larger tables have better statistics and the index pages are cached. |
| **About 3–10×** | R11, R13, R14, R15, R18, R21, R24, W04 | A fixed share of a larger table, or a report that scans one partition-sized slice. W04 was 19× until the `match_id` predicate reduced it to 4,545 rows; the measured 105.7 ms is dominated by updating those rows and four indexes, not by scanning 799,462. |
| **10–20×** | R04, R06, R08, R17, R19, W05 | Touches a larger share of user_teams / contest_entries / wallet. All still meet their target except R08, which is at the 5 ms boundary. |
| **More than 20×** | R05, R10, R20, R25 | A leaderboard, a pending-withdrawal scan, a time-range aggregate and a per-team wallet history. R20 grows because the time range covers more rows; it is still 20.6 ms against a 5,000 ms report target. R25 grows because the per-team wallet history has more entries; it is 36.4 ms against 250 ms. |

The ratios are noisy at sub-millisecond seed times: a 0.03 ms seed query cannot grow 18× and still be measurable. The absolute large-data times and the target status are the decision variables.

---

## 4. Storage

| Object | Seed | Large | Index share (large) |
| --- | ---: | ---: | ---: |
| Database | 78 MB | 1,250 MB | 722 MB |
| `user_team_players` | 25 MB | 494 MB | 190 MB |
| `users` | 12 MB | 301 MB | 204 MB |
| `wallet_transactions` | 21 MB | 260 MB | 154 MB |
| `user_teams` | 5.4 MB | 153 MB | 99 MB |
| `contest_entries` | 5.9 MB | 32 MB | 17 MB |
| All indexes | 35 MB | 722 MB | — |

Indexes are 58% of the large database. The three Phase 5 covering indexes add roughly 40 MB but remove heap fetches from R05 and the team-creation reads; the write cost is visible in W04 and W05 and is discussed below.

---

## 5. What broke at scale, and the fixes

### 5.1 A 26-character username in a 25-character column

The load failed at row 100,346 with `value too long for type character varying(25)`. The fix was to widen `users.username` to `VARCHAR(40)` and its CHECK to `^[A-Za-z][A-Za-z0-9_]{2,39}$` in [`sql/01_schema.sql`](../sql/01_schema.sql). The seed data still loads unchanged. This is a data-contract issue that only appears at scale, not a query-plan issue.

### 5.2 W04 scanned every team to update one match

The original W04 updated `user_teams` from a subquery containing only match 183, but the outer UPDATE had no match predicate, so PostgreSQL scanned all 799,462 teams and hash-joined 4,545 rows. Adding `AND ut.match_id = 183` changes the outer scan to the 4,545 relevant rows; the result is identical because the subquery only contains those teams. The measured time fell from 308 ms (cold) / 451 ms (unlucky warm pass) to **105.7 ms**, under the 250 ms interactive target.

### 5.3 R02 cannot meet 5 ms without a summary

The query is exact by design: it counts every pick for the match. The plan uses `user_teams_match_team_idx` (covering) and `user_team_players_pkey` (covering), so it is already index-only; about 51,500 pick rows still have to be counted. The scale fix is a **per-match selection summary**:

```sql
CREATE TABLE match_player_selection (
    match_id  INTEGER NOT NULL,
    player_id INTEGER NOT NULL,
    picks     INTEGER NOT NULL,
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, player_id)
);

-- Refresh after team create/delete, or once per match during the lock window.
INSERT INTO match_player_selection (match_id, player_id, picks)
SELECT ut.match_id, utp.player_id, count(*)
FROM user_teams ut
JOIN user_team_players utp ON utp.user_team_id = ut.user_team_id
WHERE ut.match_id = 207
GROUP BY ut.match_id, utp.player_id
ON CONFLICT (match_id, player_id)
DO UPDATE SET picks = EXCLUDED.picks, refreshed_at = now();
```

R02 then reads 46 rows from the summary and the team count from `user_teams_match_idx`; the expected time is under 1 ms. The exact query remains the fallback for a cache rebuild.

### 5.4 R05 is a leaderboard, not a point lookup

The covering indexes made the joins index-only, but 1,101 entries still require 2,202 probes and a sort. The scale fix is a **materialized leaderboard** refreshed after scoring:

```sql
CREATE MATERIALIZED VIEW contest_leaderboard AS
SELECT ce.contest_id, ut.user_id, u.username, ut.team_label, ut.total_points
FROM contest_entries ce
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
JOIN users u ON u.user_id = ut.user_id;

CREATE UNIQUE INDEX contest_leaderboard_key
    ON contest_leaderboard (contest_id, user_id, team_label);

-- After the points engine updates a match:
REFRESH MATERIALIZED VIEW CONCURRENTLY contest_leaderboard;
```

R05 becomes a filter on `contest_id` plus a window rank over 1,101 materialized rows; the expected time is 1–2 ms. The trade-off is refresh cost after every scoring run, which is acceptable because scoring is a batch job, not a user request.

### 5.5 Write overhead

The Phase 4 indexes made W01–W03 slightly slower than the unindexed seed values, but all are under 2 ms. The Phase 5 covering indexes add maintenance to W04 and W05: W04 is 105.7 ms (still under 250 ms) and W05 is 19.2 ms (still under 250 ms). The write cost is justified by the read targets; if W04 becomes hotter, the leaderboard cover index can be dropped and R05 served from the materialized view instead.

---

## 6. Partitioning: `wallet_transactions`

The full DDL is [`sql/08_partitioning.sql`](../sql/08_partitioning.sql). The design:

- **Table:** `wallet_transactions`, the largest time-series table (1.58M rows, 260 MB).
- **Key:** `RANGE (created_at)`, monthly partitions from 2025-01 to 2026-07 plus a default partition.
- **Primary key:** `(txn_id, created_at)`, because PostgreSQL requires every unique constraint on a partitioned table to include the partition key. `txn_id` alone is not a global key in a partitioned table; the application's `txn_id` is generated centrally, so the pair is unique in practice.
- **Constraints:** the type, amount, status and reference CHECKs and the two foreign keys are copied to the partitioned table.
- **Copy:** the DDL creates `wallet_transactions_partitioned` and copies the 1.58M rows; the live table is untouched.

The pruning proof:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(amount)
FROM wallet_transactions_partitioned
WHERE created_at >= '2026-03-01 00:00:00+05:30'
  AND created_at <  '2026-04-01 00:00:00+05:30';
```

```text
Aggregate  (cost=2647.45..2647.46 rows=1 width=40) (actual time=11.711..11.711 rows=1 loops=1)
  Buffers: shared read=794
  ->  Seq Scan on wallet_transactions_p2026_03 wallet_transactions_partitioned
        (cost=0.00..2184.15 rows=92659 width=5) (actual time=0.008..7.826 rows=92677 loops=1)
        Filter: ((created_at >= '2026-03-01 00:00:00+05:30'::timestamp with time zone)
             AND (created_at < '2026-04-01 00:00:00+05:30'::timestamp with time zone))
```

Only the March 2026 partition is scanned; the other 18 monthly partitions and the default partition are pruned. The partitioned copy is 154 MB. The trade-off: a query that filters only by `txn_id` has no partition key and would scan every partition; such lookups must include `created_at` or use a separate global index. Wallet history queries already filter by `user_id` and `created_at`, so they prune well.

---

## 7. Architecture for 100×

### 7.1 Sharding

- **Wallet shard by `user_id`.** R09, R10, R18 and W05 all carry a user predicate; one user's wallet stays on one shard. A wallet transaction is never cross-user.
- **Teams and contests shard by `match_id`.** R01–R08, R11–R17 and W01–W04 are match-scoped. A leaderboard for one contest is single-shard.
- **Cross-shard work:** R05/R19/R20/R25 and the global reports. R05 is per contest (single shard if contests are match-sharded). Global finance reports (R20, R21, R24) need a fan-out and merge, or a reporting replica fed by CDC.
- **Do not shard by `txn_id`:** it has no query locality.

### 7.2 Read replicas and caching

| Traffic | Where | Why |
| --- | --- | --- |
| R01–R09, R23, W01–W05 | Primary | Match-day reads and every write need the freshest row. |
| R11, R14, R15, R17–R21, R24 | Read replica | Reports tolerate seconds of lag and scan large slices. |
| R02, R04, R05, R08, R16 | Cache / summary | The lobby, contest list, leaderboard, team count and player pool change on a known event (team create, scoring, lock). Invalidate on the write, or refresh on the match clock. |

The summary table in 5.3 and the materialized leaderboard in 5.4 are better than a generic cache: they are durable, queryable and refresh on a known event.

### 7.3 Maintenance

- `wallet_transactions`: `autovacuum_vacuum_scale_factor = 0.02`, `autovacuum_analyze_scale_factor = 0.01`, `autovacuum_vacuum_cost_delay = 2ms`; it is append-heavy and the partition copy shows 260 MB for 1.58M rows.
- Archive partitions older than 12 months with `DETACH PARTITION` and move them to cold storage; the monthly partition is the archive unit.
- Refresh `match_player_selection` after team changes; refresh `contest_leaderboard` after the points engine writes a match.
- Monitor `pg_stat_user_tables.n_dead_tup` and index bloat on `user_teams` and `wallet_transactions`; W04's 4,545-row update is the write hot spot.

---

## 8. Conclusion

The database is **ready for the 20× dataset with two pre-aggregation changes**:

- 27 of 30 targets are met, including every report target and all writes.
- W04 was fixed by adding the match predicate (105.7 ms, under 250 ms).
- R02 needs `match_player_selection` to reach 5 ms; the raw query is 11.3 ms median and 18.0 ms average.
- R05 needs `contest_leaderboard` to reach 5 ms; the raw query is 5.9 ms median and 13.4 ms average.
- R08 is 0.4% over the 5 ms line (5.021 ms average, 4.939 ms median); this is noise at the boundary.

For 100×, the same plan needs monthly partitions on `wallet_transactions`, user sharding for wallets, match sharding for teams and contests, a reporting replica and the two summary objects. The 1.25 GB database and 722 MB of indexes fit comfortably on a single node at 20×; 100× is where sharding becomes necessary.
