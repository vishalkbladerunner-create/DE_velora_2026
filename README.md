# Dream11 Fantasy Sports Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 10 CSV files (118,343 wallet transactions): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details (fill in before you start)

| Role | Name | Enrollment No. | GitHub Username |
|------|------|----------------|-----------------|
| Group Lead | Vishal Kumar | 2501010512 | vishalkbladerunner-create |
| Member 2 | Manav Garg | 2501010256 | manav363 |
| Member 3 | Yash Gupta | 2501010519 | yashhgupta-007 |
| Member 4 | Sanyam Garg | 2501010406 | sanyamgarg023-dev |

**Team No.:** T0020 · **Section:** B · **Repository URL:** https://github.com/vishalkbladerunner-create/DE_velora_2026

---

## How this project works

| Phase | What you do | You submit | Counts toward | Marks |
|-------|-------------|------------|---------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | Query Execution | 2 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | Query Execution | 5 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | Query Execution | 3 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | Code Optimization | 16 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | Code Optimization | 14 |
| | **Total** | | | **40** |

---

## Phase 1: Problem statements

Dream11 is a fantasy cricket platform. For every real **match** (IPL and international T20s), users build **fantasy teams** of exactly 11 **players** from the two real teams within 100 credits, picking a **captain** (2× points) and **vice-captain** (1.5×). After the match, each player's real performance is converted into **fantasy points**. Users join **contests** (mega contests, small contests, head-to-heads, private leagues with invite codes) by paying an entry fee from their **wallet**; winners get prize money. The wallet records deposits, entry fees, winnings, refunds (for abandoned matches), bonuses and withdrawals. You have joined the Dream11 data team.

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "The **lobby, player pool and contest list** must load instantly before a match locks." | User app | R01, R02, R04, R08 |
| P2 | "**My teams, team preview, leaderboards** and wallet history are slow during live matches." | User app | R03, R05, R07, R09 |
| P3 | "Creating teams, joining contests and debiting the wallet must never lag." | Contest engine | W01, W02, W03 |
| P4 | "**Fair play** needs rule-breaking teams and multi-team abuse found quickly." | Fair play | R06, R17 |
| P5 | "The finance audit of **paid entries with no wallet debit** always comes back **empty**—impossible." | Finance audit | R13 |
| P6 | "**Payouts and compliance** (pending withdrawals, banned states, KYC/TDS, missed refunds) are slow." | Payouts / Compliance | R10, R11, R18, R25, W05 |
| P7 | "The **points engine** and stats hub (player averages, form, selection report) time out." | Points engine / Stats | R12, R19, R24, W04 |
| P8 | "Product and finance reports (fill rate, winnings, head-to-head, deposits) are slow, and users will grow **20×**." | Product / Finance | R14, R15, R16, R20, R21, R22, R23 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P8, write in your own words what the business needs and which **stakeholder** is affected (fantasy player (user), contest/product team, points engine, fair-play team, finance & payouts, compliance (state laws, KYC/TDS), support).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 10 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `teams.csv` | 18 | Real cricket teams (IPL franchises and national teams) |
| `players.csv` | 450 | Real players (25-player squads) with role and credits |
| `matches.csv` | 212 | Real matches, Mar 2025 – Jul 2026 |
| `player_match_stats.csv` | 4,444 | Each player's performance and fantasy points in a match |
| `users.csv` | 50,000 | Dream11 users |
| `user_teams.csv` | 39,975 | Fantasy teams created by users for a match |
| `user_team_players.csv` | 439,925 | The 11 players in each fantasy team |
| `contests.csv` | 2,544 | Contests for each match |
| `contest_entries.csv` | 42,746 | Fantasy teams entered into contests (rank and winnings) |
| `wallet_transactions.csv` | 118,343 | Wallet ledger: deposits, entry fees, winnings, refunds, bonuses, withdrawals |

The first line of every file is the header (column names). Here are the headers and the first rows of each file:

**teams.csv**
```
team_id,team_name,short_name,team_type
1,Chennai Super Kings,CSK,FRANCHISE
2,Mumbai Indians,MI,FRANCHISE
```

**players.csv**
```
player_id,full_name,team_id,role,credits,is_active
1,Meera Khan,1,WK,6.5,t
2,Rahul Patel,1,WK,7.5,t
```

**matches.csv**
```
match_id,tournament,home_team_id,away_team_id,venue,starts_at,status
1,IPL 2025,1,2,"Wankhede, Mumbai",2025-03-22 15:30:00+05:30,COMPLETED
2,IPL 2025,2,3,"Chepauk, Chennai",2025-03-22 19:30:00+05:30,COMPLETED
```

**player_match_stats.csv**
```
match_id,player_id,runs,balls_faced,fours,sixes,wickets,catches,fantasy_points
1,1,48,49,4,1,0,0,58.0
1,2,59,60,4,2,0,0,79.0
```

**users.csv**
```
user_id,username,phone,email,state_code,kyc_status,created_at
1,VivaanSharma1,7300000001,vivaansharma1@gmail.com,TN,PENDING,2022-08-07 12:09:37+05:30
2,Aditya_11Sharma2,7300000002,adityasharma2@gmail.com,AP,VERIFIED,2023-11-12 04:32:29+05:30
```

**user_teams.csv**
```
user_team_id,user_id,match_id,team_label,captain_id,vice_captain_id,total_points,created_at
1,2075,121,T2,408,362,185.0,2026-02-17 17:00:00+05:30
2,4578,188,T3,115,26,242.0,2026-05-17 17:59:00+05:30
```

**user_team_players.csv**
```
user_team_id,player_id
1,355
1,358
```

**contests.csv**
```
contest_id,match_id,contest_name,contest_type,entry_fee,total_spots,prize_pool,is_guaranteed,invite_code
1,1,Mega Contest,MEGA,49.00,2000,83300.00,f,
2,1,Winner Takes More 2,SMALL,25.00,100,2125.00,t,
```

**contest_entries.csv**
```
entry_id,contest_id,user_team_id,joined_at,final_rank,winnings
1,9,31809,2025-03-20 18:12:00+05:30,1,340.00
2,2,31809,2025-03-20 18:13:00+05:30,9,0.00
```

**wallet_transactions.csv**
```
txn_id,user_id,txn_type,amount,reference_entry_id,status,created_at
1,40099,DEPOSIT,200.00,,SUCCESS,2025-01-01 00:46:14+05:30
2,12944,DEPOSIT,200.00,,SUCCESS,2025-01-01 00:58:29+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, timestamps with a time-zone offset, yes/no columns, small whole numbers, decimals and short codes.
3. **Primary key.** Is it one column, or a combination? (Look closely at `player_match_stats`, `user_team_players`, and what stops the same team joining a contest twice. `invite_code` is unique but often empty.)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why**, and decide which columns must never be empty. Why do some wallet transactions have no `reference_entry_id`? When are `total_points`, `final_rank`, `invite_code` and `email` empty?
6. **UNIQUE** columns (natural candidate keys such as emails, phone numbers, codes and handles).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Look for formats (team short names, usernames, team labels), allowed values (roles, statuses, contest and transaction types), ranges (credits, wickets), and rules tying columns together (home ≠ away, captain ≠ vice-captain, head-to-head has 2 spots, private ⇔ invite code, which transaction types need an entry reference). Which game rules (11 players, 100 credits, max 7 per side) can a CHECK enforce, and which need something else?
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: `player_match_stats.fantasy_points` vs the stats; `user_teams.total_points` vs player points and captaincy; `contests.prize_pool` vs fee × spots) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`dream11`**: `CREATE SCHEMA dream11;` and `SET search_path TO dream11;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO dream11;
\copy teams FROM 'seed_data/teams.csv' WITH (FORMAT csv, HEADER true)
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "every fantasy team has exactly 11 players, all from the two teams of that match", "no team was created after the match started", "every paid entry has exactly one entry-fee debit"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 10 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 25 reads (`R01`–`R25`) and 5 writes (`W01`–`W05`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W05`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **noticeably longer** than the others on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Lobby: upcoming matches with the number of contests and total prize money on offer | READ | | | | |
| R02: Create team screen: player pool of match 207 with credits and % of teams that picked each player | READ | | | | |
| R03: "My teams": user 1006's teams for match 130 with captain and vice-captain names | READ | | | | |
| R04: Contest list for match 207: spots left, biggest prize first | READ | | | | |
| R05: Leaderboard: contest 2185 ranked by team points | READ | | | | |
| R06: Fair play: teams that break the rules (not exactly 11 players, over 100 credits, or more than 7 from one side) | READ | | | | |
| R07: Team preview: points of each player in user 1006's first team for match 130 (captain 2x, vice-captain 1.5x) | READ | | | | |
| R08: Match insights: most-picked captains for match 207 | READ | | | | |
| R09: Wallet: user 1006's transactions with a running balance | READ | | | | |
| R10: Payouts team: withdrawals pending for more than 24 hours (checked at 23:59 on 30 Jun 2026) | READ | | | | |
| R11: Compliance: users from states where paid fantasy contests are not allowed who joined paid contests in 2026 | READ | | | | |
| R12: Stats hub: top players by average fantasy points in IPL 2026 (at least 5 matches) | READ | | | | |
| R13: Finance audit: paid contest entries that have no entry-fee debit in the wallet | READ | | | | |
| R14: Product analytics: average fill rate per contest type for completed 2026 matches | READ | | | | |
| R15: Leaderboards: top 20 users by winnings in 2026 | READ | | | | |
| R16: Player search | READ | | | | |
| R17: Fair play: users with more than one team in the same contest | READ | | | | |
| R18: Tax compliance: users without verified KYC who have won more than ₹1,000 in total | READ | | | | |
| R19: Selection report: in how many teams was each IPL player picked (all time) | READ | | | | |
| R20: Finance: successful deposits per day and running total, June 2026 | READ | | | | |
| R21: Engagement: users' head-to-head win rate (at least 3 head-to-head contests) | READ | | | | |
| R22: Support console: all wallet transactions, newest first, page 2,001 (25 per page) | READ | | | | |
| R23: Login with mobile number | READ | | | | |
| R24: Player form: last 5 fantasy scores of every Chennai Super Kings player | READ | | | | |
| R25: Refund audit: paid entries in abandoned matches that were never refunded | READ | | | | |
| W01: Create team: user 1006 saves team T9 for match 207 | WRITE | | | | |
| W02: Join contest: user 1006's newest team for match 207 joins the mega contest of that match | WRITE | | | | |
| W03: Wallet: debit the entry fee for the most recent contest entry | WRITE | | | | |
| W04: Points engine: recompute total points of every team for match 183 | WRITE | | | | |
| W05: Payouts: approve all withdrawals pending for more than 24 hours | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN index | for `ILIKE '%text%'` (extension `pg_trgm`), arrays or full-text search |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination; `UNION ALL` instead of `OR` across columns |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule about NULLs. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R09 | | e.g. Seq Scan on 118k wallet rows | e.g. index on `wallet_transactions(user_id, created_at, txn_id)` | | e.g. 99% (90×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which write queries got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 118,343 wallet transactions. Next year the business expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 10 CSV files with about **20× the rows** (≈ 8,798,000 user team players, ≈ 2,367,000 wallet transactions, ≈ 800,000 user teams, ≈ 855,000 contest entries, ≈ 1,000,000 users). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them could run for a very long time.
   - R22 pages with `OFFSET`; if you replaced it with keyset pagination, explain how the "last seen" value is chosen for the large data.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / match-day | R01, R02, R03, R04, R05, R07, R08, R09, R23, W01, W02, W03 | **under 5 ms** |
| Interactive tools | R06, R10, R13, R16, R22, R25, W04, W05 | **under 250 ms** |
| Reports and analytics | R11, R12, R14, R15, R17, R18, R19, R20, R21, R24 | **under 5,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100×:** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `wallet_transactions`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** Would you shard by user or by match? A contest leaderboard mixes thousands of users; a wallet is per user. Which queries become cross-shard, and how would you handle them?
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `wallet_transactions`, archiving old data, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
dream11-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Tue 3 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |
| Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | **CP5** Individual analysis |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

## Evaluation (40 marks)

These 40 marks are the DE part of the project: **Query Execution (10)** and **Code Optimization (30)**.
The AP project (20) and your Individual analysis (40) make up the rest of the 100.

| Phase | Criteria | Marks |
|-------|----------|------:|
| | **Query Execution** | **10** |
| 1 | Problems understood, stakeholders and query groups correctly identified | 2 |
| 2 | Correct data types (1), keys and foreign keys with justified delete rules (1), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (1), ER diagram + normal-form analysis (1), data loads cleanly + integrity checks (1) | 5 |
| 3 | All 30 queries measured with the required method: 3 runs, average (1), raw plans committed (1), scan type and reason for each query (1) | 3 |
| | **Code Optimization** | **30** |
| 4 | Speed-up achieved with appropriate techniques (6), every index justified (3), results proven unchanged (2), wrong-result query found and explained (2), write overhead and index storage reported (3) | 16 |
| 5 | Large-dataset results with all targets met or explained (4), growth analysis (3), scale-only problems found and fixed (3), partitioning DDL + sharding/replica design backed by your numbers (4) | 14 |
| | **Total** | **40** |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Lobby: upcoming matches with the number of contests and total prize money on offer**
```sql
SELECT m.match_id, h.short_name || ' vs ' || a.short_name AS fixture, m.starts_at,
       count(c.contest_id) AS contests, sum(c.prize_pool) AS prize_money
FROM matches m
JOIN teams h ON h.team_id = m.home_team_id
JOIN teams a ON a.team_id = m.away_team_id
LEFT JOIN contests c ON c.match_id = m.match_id
WHERE m.status = 'UPCOMING'
GROUP BY m.match_id, h.short_name, a.short_name, m.starts_at
ORDER BY m.starts_at;
```

**R02: Create team screen: player pool of match 207 with credits and % of teams that picked each player**
```sql
SELECT p.player_id, p.full_name, t.short_name, p.role, p.credits,
       round(100.0 * count(utp.user_team_id) / NULLIF((SELECT count(*) FROM user_teams WHERE match_id = 207), 0), 1) AS selected_pct
FROM matches m
JOIN players p ON p.team_id IN (m.home_team_id, m.away_team_id) AND p.is_active
JOIN teams t   ON t.team_id = p.team_id
LEFT JOIN user_teams ut         ON ut.match_id = m.match_id
LEFT JOIN user_team_players utp ON utp.user_team_id = ut.user_team_id AND utp.player_id = p.player_id
WHERE m.match_id = 207
GROUP BY p.player_id, p.full_name, t.short_name, p.role, p.credits
ORDER BY selected_pct DESC;
```

**R03: "My teams": user 1006's teams for match 130 with captain and vice-captain names**
```sql
SELECT ut.team_label, c.full_name AS captain, v.full_name AS vice_captain, ut.total_points
FROM user_teams ut
JOIN players c ON c.player_id = ut.captain_id
JOIN players v ON v.player_id = ut.vice_captain_id
WHERE ut.user_id = 1006 AND ut.match_id = 130
ORDER BY ut.team_label;
```

**R04: Contest list for match 207: spots left, biggest prize first**
```sql
SELECT c.contest_id, c.contest_name, c.entry_fee, c.prize_pool, c.total_spots,
       c.total_spots - count(ce.entry_id) AS spots_left
FROM contests c
LEFT JOIN contest_entries ce ON ce.contest_id = c.contest_id
WHERE c.match_id = 207 AND c.contest_type <> 'PRIVATE'
GROUP BY c.contest_id, c.contest_name, c.entry_fee, c.prize_pool, c.total_spots
ORDER BY c.prize_pool DESC;
```

**R05: Leaderboard: contest 2185 ranked by team points**
```sql
SELECT u.username, ut.team_label, ut.total_points,
       RANK() OVER (ORDER BY ut.total_points DESC) AS position
FROM contest_entries ce
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
JOIN users u       ON u.user_id = ut.user_id
WHERE ce.contest_id = 2185
ORDER BY position
LIMIT 100;
```

**R06: Fair play: teams that break the rules (not exactly 11 players, over 100 credits, or more than 7 from one side)**
```sql
SELECT ut.user_team_id, count(*) AS players, sum(p.credits) AS credits_used, max(side.cnt) AS max_from_one_team
FROM user_teams ut
JOIN user_team_players utp ON utp.user_team_id = ut.user_team_id
JOIN players p             ON p.player_id = utp.player_id
CROSS JOIN LATERAL (SELECT count(*) AS cnt FROM user_team_players x JOIN players px ON px.player_id = x.player_id
                    WHERE x.user_team_id = ut.user_team_id AND px.team_id = p.team_id) side
WHERE ut.match_id = 183
GROUP BY ut.user_team_id
HAVING count(*) <> 11 OR sum(p.credits) > 100 OR max(side.cnt) > 7;
```

**R07: Team preview: points of each player in user 1006's first team for match 130 (captain 2x, vice-captain 1.5x)**
```sql
SELECT p.full_name, p.role, coalesce(s.fantasy_points, 0) AS base_points,
       coalesce(s.fantasy_points, 0) * CASE WHEN p.player_id = ut.captain_id THEN 2
                                            WHEN p.player_id = ut.vice_captain_id THEN 1.5 ELSE 1 END AS team_points
FROM user_teams ut
JOIN user_team_players utp ON utp.user_team_id = ut.user_team_id
JOIN players p             ON p.player_id = utp.player_id
LEFT JOIN player_match_stats s ON s.match_id = ut.match_id AND s.player_id = p.player_id
WHERE ut.user_id = 1006 AND ut.match_id = 130 AND ut.team_label = 'T1'
ORDER BY team_points DESC;
```

**R08: Match insights: most-picked captains for match 207**
```sql
SELECT p.full_name, count(*) AS times_captain
FROM user_teams ut
JOIN players p ON p.player_id = ut.captain_id
WHERE ut.match_id = 207
GROUP BY p.full_name
ORDER BY times_captain DESC
LIMIT 10;
```

**R09: Wallet: user 1006's transactions with a running balance**
```sql
SELECT created_at, txn_type, amount,
       sum(CASE WHEN txn_type IN ('DEPOSIT', 'WINNINGS', 'BONUS', 'REFUND') THEN amount ELSE -amount END)
           OVER (ORDER BY created_at, txn_id) AS running_balance
FROM wallet_transactions
WHERE user_id = 1006 AND status = 'SUCCESS'
ORDER BY created_at, txn_id;
```

**R10: Payouts team: withdrawals pending for more than 24 hours (checked at 23:59 on 30 Jun 2026)**
```sql
SELECT txn_id, user_id, amount, created_at
FROM wallet_transactions
WHERE txn_type = 'WITHDRAWAL' AND status = 'PENDING'
  AND created_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '24 hours'
ORDER BY created_at;
```

**R11: Compliance: users from states where paid fantasy contests are not allowed who joined paid contests in 2026**
```sql
SELECT u.user_id, u.username, u.state_code, count(*) AS paid_entries
FROM users u
JOIN user_teams ut      ON ut.user_id = u.user_id
JOIN contest_entries ce ON ce.user_team_id = ut.user_team_id
JOIN contests c         ON c.contest_id = ce.contest_id AND c.entry_fee > 0
WHERE u.state_code IN ('AS', 'OD', 'TG', 'AP')
  AND ce.joined_at >= '2026-01-01'
GROUP BY u.user_id, u.username, u.state_code
ORDER BY paid_entries DESC;
```

**R12: Stats hub: top players by average fantasy points in IPL 2026 (at least 5 matches)**
```sql
SELECT p.full_name, t.short_name, count(*) AS matches, round(avg(s.fantasy_points), 1) AS avg_points
FROM player_match_stats s
JOIN players p ON p.player_id = s.player_id
JOIN teams t   ON t.team_id = p.team_id
JOIN matches m ON m.match_id = s.match_id AND m.tournament = 'IPL 2026'
GROUP BY p.full_name, t.short_name
HAVING count(*) >= 5
ORDER BY avg_points DESC
LIMIT 20;
```

**R13: Finance audit: paid contest entries that have no entry-fee debit in the wallet**
```sql
SELECT ce.entry_id, ce.contest_id, ce.joined_at
FROM contest_entries ce
JOIN contests c ON c.contest_id = ce.contest_id
WHERE c.entry_fee > 0
  AND ce.entry_id NOT IN (SELECT w.reference_entry_id FROM wallet_transactions w);
```

**R14: Product analytics: average fill rate per contest type for completed 2026 matches**
```sql
SELECT c.contest_type, count(DISTINCT c.contest_id) AS contests,
       round(100.0 * count(ce.entry_id) / sum(DISTINCT c.total_spots), 1) AS rough_fill_pct
FROM contests c
JOIN matches m ON m.match_id = c.match_id AND m.status = 'COMPLETED'
LEFT JOIN contest_entries ce ON ce.contest_id = c.contest_id
WHERE EXTRACT(YEAR FROM m.starts_at) = 2026
GROUP BY c.contest_type
ORDER BY contests DESC;
```

**R15: Leaderboards: top 20 users by winnings in 2026**
```sql
SELECT u.user_id, u.username, sum(ce.winnings) AS winnings, count(*) FILTER (WHERE ce.winnings > 0) AS wins
FROM contest_entries ce
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
JOIN users u       ON u.user_id = ut.user_id
WHERE ce.joined_at >= '2026-01-01'
GROUP BY u.user_id, u.username
ORDER BY winnings DESC
LIMIT 20;
```

**R16: Player search**
```sql
SELECT p.player_id, p.full_name, t.short_name, p.role, p.credits
FROM players p
JOIN teams t ON t.team_id = p.team_id
WHERE p.full_name ILIKE '%sharma%'
ORDER BY p.credits DESC;
```

**R17: Fair play: users with more than one team in the same contest**
```sql
SELECT ce.contest_id, ut.user_id, count(*) AS teams_in_contest
FROM contest_entries ce
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
GROUP BY ce.contest_id, ut.user_id
HAVING count(*) > 1
ORDER BY teams_in_contest DESC;
```

**R18: Tax compliance: users without verified KYC who have won more than ₹1,000 in total**
```sql
SELECT u.user_id, u.username, u.kyc_status, sum(w.amount) AS total_winnings
FROM users u
JOIN wallet_transactions w ON w.user_id = u.user_id AND w.txn_type = 'WINNINGS' AND w.status = 'SUCCESS'
WHERE u.kyc_status <> 'VERIFIED'
GROUP BY u.user_id, u.username, u.kyc_status
HAVING sum(w.amount) > 1000
ORDER BY total_winnings DESC;
```

**R19: Selection report: in how many teams was each IPL player picked (all time)**
```sql
SELECT p.player_id, p.full_name,
       (SELECT count(*) FROM user_team_players utp WHERE utp.player_id = p.player_id) AS times_picked
FROM players p
JOIN teams t ON t.team_id = p.team_id AND t.team_type = 'FRANCHISE'
ORDER BY times_picked DESC;
```

**R20: Finance: successful deposits per day and running total, June 2026**
```sql
SELECT day, deposits, sum(deposits) OVER (ORDER BY day) AS running_total
FROM (
    SELECT created_at::date AS day, sum(amount) AS deposits
    FROM wallet_transactions
    WHERE txn_type = 'DEPOSIT' AND status = 'SUCCESS'
      AND created_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;
```

**R21: Engagement: users' head-to-head win rate (at least 3 head-to-head contests)**
```sql
SELECT ut.user_id, count(*) AS h2h_played,
       round(100.0 * count(*) FILTER (WHERE ce.final_rank = 1) / count(*), 1) AS win_pct
FROM contest_entries ce
JOIN contests c    ON c.contest_id = ce.contest_id AND c.contest_type = 'HEAD_TO_HEAD'
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
WHERE ce.final_rank IS NOT NULL
GROUP BY ut.user_id
HAVING count(*) >= 3
ORDER BY win_pct DESC, h2h_played DESC
LIMIT 30;
```

**R22: Support console: all wallet transactions, newest first, page 2,001 (25 per page)**
```sql
SELECT txn_id, user_id, txn_type, amount, status, created_at
FROM wallet_transactions
ORDER BY created_at DESC
OFFSET 50000
LIMIT 25;
```

**R23: Login with mobile number**
```sql
SELECT user_id, username, kyc_status
FROM users
WHERE phone = '7300001042';
```

**R24: Player form: last 5 fantasy scores of every Chennai Super Kings player**
```sql
SELECT full_name, starts_at, fantasy_points
FROM (
    SELECT p.full_name, m.starts_at, s.fantasy_points,
           ROW_NUMBER() OVER (PARTITION BY p.player_id ORDER BY m.starts_at DESC) AS rn
    FROM player_match_stats s
    JOIN players p ON p.player_id = s.player_id
    JOIN teams t   ON t.team_id = p.team_id AND t.short_name = 'CSK'
    JOIN matches m ON m.match_id = s.match_id
) x
WHERE rn <= 5
ORDER BY full_name, starts_at DESC;
```

**R25: Refund audit: paid entries in abandoned matches that were never refunded**
```sql
SELECT ce.entry_id, ut.user_id, c.entry_fee, m.match_id
FROM contest_entries ce
JOIN contests c    ON c.contest_id = ce.contest_id AND c.entry_fee > 0
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
JOIN matches m     ON m.match_id = ut.match_id AND m.status = 'ABANDONED'
WHERE NOT EXISTS (SELECT 1 FROM wallet_transactions w WHERE w.reference_entry_id = ce.entry_id AND w.txn_type = 'REFUND')
ORDER BY m.match_id, ce.entry_id;
```

**W01: Create team: user 1006 saves team T9 for match 207**
```sql
INSERT INTO user_teams (user_team_id, user_id, match_id, team_label, captain_id, vice_captain_id, created_at)
SELECT 90000001, 1006, 207, 'T9',
       (m.home_team_id - 1) * 25 + 1, (m.away_team_id - 1) * 25 + 2, '2026-07-01 18:00:00+05:30'
FROM matches m WHERE m.match_id = 207;
```

**W02: Join contest: user 1006's newest team for match 207 joins the mega contest of that match**
```sql
INSERT INTO contest_entries (entry_id, contest_id, user_team_id, joined_at)
SELECT 90000001, c.contest_id, ut.user_team_id, '2026-07-01 18:05:00+05:30'
FROM contests c
JOIN user_teams ut ON ut.match_id = c.match_id
WHERE c.match_id = 207 AND c.contest_type = 'MEGA'
  AND ut.user_team_id = (SELECT max(user_team_id) FROM user_teams WHERE match_id = 207)
ON CONFLICT (contest_id, user_team_id) DO NOTHING;
```

**W03: Wallet: debit the entry fee for the most recent contest entry**
```sql
INSERT INTO wallet_transactions (txn_id, user_id, txn_type, amount, reference_entry_id, status, created_at)
SELECT 90000001, ut.user_id, 'ENTRY_FEE', c.entry_fee, ce.entry_id, 'SUCCESS', '2026-07-01 18:05:00+05:30'
FROM contest_entries ce
JOIN contests c    ON c.contest_id = ce.contest_id
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
WHERE ce.entry_id = (SELECT max(entry_id) FROM contest_entries);
```

**W04: Points engine: recompute total points of every team for match 183**
```sql
UPDATE user_teams ut
SET total_points = s.pts
FROM (SELECT ut2.user_team_id,
             sum(coalesce(pms.fantasy_points, 0) * CASE WHEN utp.player_id = ut2.captain_id THEN 2
                                                        WHEN utp.player_id = ut2.vice_captain_id THEN 1.5 ELSE 1 END) AS pts
      FROM user_teams ut2
      JOIN user_team_players utp ON utp.user_team_id = ut2.user_team_id
      LEFT JOIN player_match_stats pms ON pms.match_id = ut2.match_id AND pms.player_id = utp.player_id
      WHERE ut2.match_id = 183
      GROUP BY ut2.user_team_id) s
WHERE s.user_team_id = ut.user_team_id;
```

**W05: Payouts: approve all withdrawals pending for more than 24 hours**
```sql
UPDATE wallet_transactions
SET status = 'SUCCESS'
WHERE txn_type = 'WITHDRAWAL' AND status = 'PENDING'
  AND created_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '24 hours';
```
