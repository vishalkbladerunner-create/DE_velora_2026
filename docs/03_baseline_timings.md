# Phase 3 — Baseline timings

All 30 queries from `queries/workload_30.sql`, run three times with `EXPLAIN (ANALYZE, BUFFERS)` on PostgreSQL 15.15. The database is `dream11`, loaded with all 698,657 seed rows on the benchmark laptop recorded in `team.json`. Write queries ran inside `BEGIN; … ROLLBACK;`; no data changed.

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
| --- | --- | ---: | ---: | ---: | ---: |
| R01: Lobby: upcoming matches with contests and prize money | READ | 0.726 | 0.282 | 0.397 | 0.468 |
| R02: Create team: player pool of match 207 | READ | 18.971 | 17.765 | 17.939 | 18.225 |
| R03: My teams: user 1006 teams for match 130 | READ | 0.041 | 0.035 | 0.040 | 0.039 |
| R04: Contest list for match 207 | READ | 0.199 | 0.186 | 0.179 | 0.188 |
| R05: Leaderboard: contest 2185 | READ | 0.714 | 0.457 | 0.457 | 0.543 |
| R06: Fair play: rule-breaking teams | READ | 51.002 | 51.117 | 51.549 | 51.223 |
| R07: Team preview: player points with captaincy | READ | 0.068 | 0.061 | 0.062 | 0.064 |
| R08: Match insights: most-picked captains | READ | 1.398 | 1.587 | 1.511 | 1.499 |
| R09: Wallet: user 1006 running balance | READ | 4.821 | 4.248 | 4.028 | 4.366 |
| R10: Payouts: withdrawals pending over 24 hours | READ | 4.949 | 5.035 | 4.894 | 4.959 |
| R11: Compliance: banned states in paid 2026 contests | READ | 13.091 | 13.417 | 13.721 | 13.410 |
| R12: Stats hub: top IPL 2026 players | READ | 0.924 | 1.058 | 0.868 | 0.950 |
| R13: Finance audit: paid entries without a debit | READ | 17.596 | 18.634 | 17.388 | 17.873 |
| R14: Product: fill rate by contest type | READ | 6.475 | 6.374 | 6.228 | 6.359 |
| R15: Leaderboards: top users by 2026 winnings | READ | 21.376 | 21.120 | 22.040 | 21.512 |
| R16: Player search | READ | 0.119 | 0.115 | 0.118 | 0.117 |
| R17: Fair play: users with more than one team in a contest | READ | 12.915 | 13.214 | 13.696 | 13.275 |
| R18: Tax: unverified KYC winners over 1,000 | READ | 10.950 | 10.675 | 10.650 | 10.758 |
| R19: Selection report: times each IPL player was picked | READ | 2633.847 | 2603.613 | 2453.268 | 2563.576 |
| R20: Finance: deposits per day, June 2026 | READ | 7.077 | 5.775 | 6.399 | 6.417 |
| R21: Engagement: head-to-head win rate | READ | 5.723 | 6.479 | 6.058 | 6.087 |
| R22: Support console: wallet page 2,001 | READ | 27.755 | 27.837 | 28.349 | 27.980 |
| R23: Login with mobile number | READ | 0.034 | 0.031 | 0.030 | 0.032 |
| R24: Player form: last 5 CSK scores | READ | 0.606 | 0.527 | 0.501 | 0.545 |
| R25: Refund audit: abandoned matches without a refund | READ | 9.854 | 9.518 | 9.544 | 9.639 |
| W01: Create team: user 1006, match 207 | WRITE | 1.384 | 0.758 | 0.745 | 0.962 |
| W02: Join contest: newest team joins the Mega contest | WRITE | 0.529 | 0.412 | 0.565 | 0.502 |
| W03: Wallet: debit the latest entry fee | WRITE | 0.689 | 0.980 | 0.539 | 0.736 |
| W04: Points engine: recompute every team for match 183 | WRITE | 7.990 | 7.292 | 7.509 | 7.597 |
| W05: Payouts: approve withdrawals pending over 24 hours | WRITE | 5.640 | 6.369 | 6.039 | 6.016 |
| **Total (sum of all 30)** | | | | | **2795.915** |

The raw plans are in `benchmarks/results/baseline/R01.txt` … `W05.txt`; `summary.csv` has the same averages plus median, min, max and scan nodes.

## Scan type and why

| Query | Scan type | Why it is slow or fast |
| --- | --- | --- |
| R01 | Seq Scan on contests; Seq Scan on matches; Seq Scan on teams | Only 18 teams, 212 matches and 2,544 contests; sequential scans and a small hash aggregate are cheaper than index work. |
| R02 | Seq Scan on user_teams; Seq Scan on matches; Seq Scan on players; Index Only Scan using user_team_players_pkey on user_team_players; Seq Scan on teams | Scans 39,975 fantasy teams and 439,925 team-player rows to count selections; the join is the cost. |
| R03 | Index Scan using user_teams_user_match_label_unique on user_teams; Index Scan using players_pkey on players | The unique index on (user_id, match_id, team_label) finds the teams, then two player PK lookups. |
| R04 | Seq Scan on contests; Index Scan using contest_entries_contest_team_unique on contest_entries | Contests are small enough to scan; the entries side uses the (contest_id, user_team_id) unique index. |
| R05 | Index Only Scan using contest_entries_contest_team_unique on contest_entries; Index Scan using user_teams_pkey on user_teams; Index Scan using users_pkey on users | The contest-entry unique index finds the field, then PK lookups for teams and users; very selective. |
| R06 | Seq Scan on user_teams; Index Only Scan using user_team_players_pkey on user_team_players; Seq Scan on players | Reads 39,975 teams and 439,925 team-player rows, with a lateral count per team; this is the fair-play cost. |
| R07 | Index Scan using user_teams_user_match_label_unique on user_teams; Index Only Scan using user_team_players_pkey on user_team_players; Index Scan using players_pkey on players; Index Scan using player_match_stats_pkey on player_match_stats | The unique team index and PK lookups make the captaincy calculation cheap. |
| R08 | Seq Scan on user_teams; Seq Scan on players | Scans 39,975 teams to count captain picks; only 212 matches, so the result is small but the input is not. |
| R09 | Seq Scan on wallet_transactions | Scans 118,343 wallet rows for one user and computes a window; a user/time index is the Phase 4 candidate. |
| R10 | Seq Scan on wallet_transactions | Scans 118,343 wallet rows for pending withdrawals; a partial index on (status, txn_type) is the candidate. |
| R11 | Seq Scan on contest_entries; Seq Scan on user_teams; Seq Scan on users; Seq Scan on contests | Joins 42,746 entries to 39,975 teams and 50,000 users with no selective index on state or date. |
| R12 | Seq Scan on player_match_stats; Seq Scan on matches; Seq Scan on players; Seq Scan on teams | Only 4,444 stat rows; the joins and the HAVING count are cheap. |
| R13 | Seq Scan on contest_entries; Seq Scan on wallet_transactions; Seq Scan on contests | Scans 42,746 entries and 118,343 wallet rows; the NOT IN also returns zero rows because of NULLs. Phase 4 must use NOT EXISTS. |
| R14 | Seq Scan on contests; Seq Scan on matches; Index Scan using contest_entries_contest_team_unique on contest_entries | Scans 2,544 contests and joins entries; the DISTINCT total_spots aggregate is the cost. |
| R15 | Seq Scan on contest_entries; Seq Scan on user_teams; Seq Scan on users | Groups 42,746 entries by user after joining 39,975 teams and 50,000 users. |
| R16 | Seq Scan on players; Seq Scan on teams | Leading-wildcard ILIKE cannot use the name index, so 450 players are scanned; still fast at this size. |
| R17 | Seq Scan on contest_entries; Seq Scan on user_teams | Groups 42,746 entries by contest and user after joining teams; no index covers the grouping. |
| R18 | Seq Scan on wallet_transactions; Seq Scan on users | Scans 118,343 wallet rows for winnings, then joins 50,000 users for KYC status. |
| R19 | Seq Scan on players; Seq Scan on teams; Seq Scan on user_team_players | The correlated subquery counts 439,925 team-player rows once per IPL player (250 times); this is the intentionally slow query. |
| R20 | Seq Scan on wallet_transactions | Scans 118,343 wallet rows, filters deposits in June, then computes a daily window. |
| R21 | Seq Scan on user_teams; Seq Scan on contest_entries; Seq Scan on contests | Joins 2,544 contests to 42,746 entries and 39,975 teams; the head-to-head filter is small. |
| R22 | Seq Scan on wallet_transactions | Scans and sorts 118,343 wallet rows, then discards 50,000 for the OFFSET page. |
| R23 | Index Scan using users_phone_key on users | The unique index on phone answers the login lookup directly. |
| R24 | Seq Scan on player_match_stats; Seq Scan on players; Seq Scan on teams; Seq Scan on matches | Only 4,444 stat rows; the window partitions by player and sorts a small set. |
| R25 | Seq Scan on contest_entries; Seq Scan on user_teams; Seq Scan on matches; Seq Scan on wallet_transactions; Seq Scan on contests | Anti-joins 42,746 entries against 118,343 wallet rows; no index on reference_entry_id and REFUND. |
| W01 | Seq Scan on matches | Single-row insert; the only read is the small matches table. |
| W02 | Index Scan using user_teams_pkey on user_teams; Seq Scan on contests | Single-row insert; the team PK lookup and the small contests scan are cheap. |
| W03 | Index Only Scan using contest_entries_pkey on contest_entries; Index Scan using contest_entries_pkey on contest_entries; Index Scan using contests_pkey on contests; Index Scan using user_teams_pkey on user_teams | Single-row insert; the entry, contest and team PK lookups are all index hits. |
| W04 | Seq Scan on user_teams; Index Only Scan using user_team_players_pkey on user_team_players; Bitmap Heap Scan on player_match_stats; Bitmap Index Scan on player_match_stats_pkey | Updates the teams for one match, but joins 439,925 team-player rows and 4,444 stat rows. |
| W05 | Seq Scan on wallet_transactions | Updates 100 pending withdrawals after scanning 118,343 wallet rows. |

## Notes

- **R19 is the outlier at about 2.56 s.** Its correlated subquery scans 439,925 `user_team_players` rows once per IPL player (250 times). The README warns that one query is intentionally slow; this is it, and it is the first Phase 4 target.

- **R13 returns zero rows for the wrong reason.** `NOT IN (SELECT reference_entry_id …)` sees 63,000 NULL references, so the predicate is never true. The plan still scans 118,343 wallet rows. Phase 4 must rewrite it as `NOT EXISTS`.

- **The small dimensions are sequential scans on purpose.** `teams` (18), `matches` (212) and `contests` (2,544) fit in a few pages; PostgreSQL correctly prefers a sequential scan to an index.

- **The write timings are rollback-safe.** W01–W05 were measured inside `BEGIN; … ROLLBACK;`, so the 118,343-row wallet and the 42,746 entries are unchanged.

- **Same laptop for Phase 4.** The timings were taken on the machine named in `team.json`; Phase 4 must use the same machine for a fair before/after comparison.
