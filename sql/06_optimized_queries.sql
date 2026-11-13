-- =====================================================================
-- Dream11 DBMS Project: Phase 4 optimized workload
--   A copy of queries/workload_30.sql. Only these queries are rewritten:
--     R02, R06, R13 (NULL bug fix), R14, R19, R20, R22
--   Every other query is unchanged and gets faster from sql/05_indexes.sql.
--   Each rewrite has a "Rewrite:" comment saying what changed and why.
--
--   Benchmark:
--     ./benchmarks/run_benchmark.sh <database> optimized 3 sql/06_optimized_queries.sql
--   Safe to run directly: everything is inside BEGIN ... ROLLBACK.
-- =====================================================================
SET search_path TO dream11;
BEGIN;

-- @R01
-- Lobby: upcoming matches with the number of contests and total prize money on offer
SELECT m.match_id, h.short_name || ' vs ' || a.short_name AS fixture, m.starts_at,
       count(c.contest_id) AS contests, sum(c.prize_pool) AS prize_money
FROM matches m
JOIN teams h ON h.team_id = m.home_team_id
JOIN teams a ON a.team_id = m.away_team_id
LEFT JOIN contests c ON c.match_id = m.match_id
WHERE m.status = 'UPCOMING'
GROUP BY m.match_id, h.short_name, a.short_name, m.starts_at
ORDER BY m.starts_at;

-- @R02
-- Create team screen: player pool of match 207 with credits and % of teams that picked each player
-- Rewrite: the original joins every player of the match with every team of the
-- match (players x teams rows) before counting. Here the picks are counted once
-- per player in a small subquery, then joined to the player list.
SELECT p.player_id, p.full_name, t.short_name, p.role, p.credits,
       round(100.0 * coalesce(pk.picks, 0) / NULLIF((SELECT count(*) FROM user_teams WHERE match_id = 207), 0), 1) AS selected_pct
FROM matches m
JOIN players p ON p.team_id IN (m.home_team_id, m.away_team_id) AND p.is_active
JOIN teams t   ON t.team_id = p.team_id
LEFT JOIN (SELECT utp.player_id, count(*) AS picks
           FROM user_teams ut
           JOIN user_team_players utp ON utp.user_team_id = ut.user_team_id
           WHERE ut.match_id = 207
           GROUP BY utp.player_id) pk ON pk.player_id = p.player_id
WHERE m.match_id = 207
ORDER BY selected_pct DESC;

-- @R03
-- "My teams": user 1006's teams for match 130 with captain and vice-captain names
SELECT ut.team_label, c.full_name AS captain, v.full_name AS vice_captain, ut.total_points
FROM user_teams ut
JOIN players c ON c.player_id = ut.captain_id
JOIN players v ON v.player_id = ut.vice_captain_id
WHERE ut.user_id = 1006 AND ut.match_id = 130
ORDER BY ut.team_label;

-- @R04
-- Contest list for match 207: spots left, biggest prize first
SELECT c.contest_id, c.contest_name, c.entry_fee, c.prize_pool, c.total_spots,
       c.total_spots - count(ce.entry_id) AS spots_left
FROM contests c
LEFT JOIN contest_entries ce ON ce.contest_id = c.contest_id
WHERE c.match_id = 207 AND c.contest_type <> 'PRIVATE'
GROUP BY c.contest_id, c.contest_name, c.entry_fee, c.prize_pool, c.total_spots
ORDER BY c.prize_pool DESC;

-- @R05
-- Leaderboard: contest 2185 ranked by team points
SELECT u.username, ut.team_label, ut.total_points,
       RANK() OVER (ORDER BY ut.total_points DESC) AS position
FROM contest_entries ce
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
JOIN users u       ON u.user_id = ut.user_id
WHERE ce.contest_id = 2185
ORDER BY position
LIMIT 100;

-- @R06
-- Fair play: teams that break the rules (not exactly 11 players, over 100 credits, or more than 7 from one side)
-- Rewrite: the LATERAL subquery re-read the team's players once for every
-- player (11 x 11 lookups per team). A window count over (team, real side)
-- gives the same "players from this side" number in one pass.
SELECT user_team_id, count(*) AS players, sum(credits) AS credits_used, max(side_cnt) AS max_from_one_team
FROM (SELECT ut.user_team_id, p.credits,
             count(*) OVER (PARTITION BY ut.user_team_id, p.team_id) AS side_cnt
      FROM user_teams ut
      JOIN user_team_players utp ON utp.user_team_id = ut.user_team_id
      JOIN players p             ON p.player_id = utp.player_id
      WHERE ut.match_id = 183) x
GROUP BY user_team_id
HAVING count(*) <> 11 OR sum(credits) > 100 OR max(side_cnt) > 7;

-- @R07
-- Team preview: points of each player in user 1006's first team for match 130 (captain 2x, vice-captain 1.5x)
SELECT p.full_name, p.role, coalesce(s.fantasy_points, 0) AS base_points,
       coalesce(s.fantasy_points, 0) * CASE WHEN p.player_id = ut.captain_id THEN 2
                                            WHEN p.player_id = ut.vice_captain_id THEN 1.5 ELSE 1 END AS team_points
FROM user_teams ut
JOIN user_team_players utp ON utp.user_team_id = ut.user_team_id
JOIN players p             ON p.player_id = utp.player_id
LEFT JOIN player_match_stats s ON s.match_id = ut.match_id AND s.player_id = p.player_id
WHERE ut.user_id = 1006 AND ut.match_id = 130 AND ut.team_label = 'T1'
ORDER BY team_points DESC;

-- @R08
-- Match insights: most-picked captains for match 207
SELECT p.full_name, count(*) AS times_captain
FROM user_teams ut
JOIN players p ON p.player_id = ut.captain_id
WHERE ut.match_id = 207
GROUP BY p.full_name
ORDER BY times_captain DESC
LIMIT 10;

-- @R09
-- Wallet: user 1006's transactions with a running balance
SELECT created_at, txn_type, amount,
       sum(CASE WHEN txn_type IN ('DEPOSIT', 'WINNINGS', 'BONUS', 'REFUND') THEN amount ELSE -amount END)
           OVER (ORDER BY created_at, txn_id) AS running_balance
FROM wallet_transactions
WHERE user_id = 1006 AND status = 'SUCCESS'
ORDER BY created_at, txn_id;

-- @R10
-- Payouts team: withdrawals pending for more than 24 hours (checked at 23:59 on 30 Jun 2026)
SELECT txn_id, user_id, amount, created_at
FROM wallet_transactions
WHERE txn_type = 'WITHDRAWAL' AND status = 'PENDING'
  AND created_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '24 hours'
ORDER BY created_at;

-- @R11
-- Compliance: users from states where paid fantasy contests are not allowed who joined paid contests in 2026
SELECT u.user_id, u.username, u.state_code, count(*) AS paid_entries
FROM users u
JOIN user_teams ut      ON ut.user_id = u.user_id
JOIN contest_entries ce ON ce.user_team_id = ut.user_team_id
JOIN contests c         ON c.contest_id = ce.contest_id AND c.entry_fee > 0
WHERE u.state_code IN ('AS', 'OD', 'TG', 'AP')
  AND ce.joined_at >= '2026-01-01'
GROUP BY u.user_id, u.username, u.state_code
ORDER BY paid_entries DESC;

-- @R12
-- Stats hub: top players by average fantasy points in IPL 2026 (at least 5 matches)
SELECT p.full_name, t.short_name, count(*) AS matches, round(avg(s.fantasy_points), 1) AS avg_points
FROM player_match_stats s
JOIN players p ON p.player_id = s.player_id
JOIN teams t   ON t.team_id = p.team_id
JOIN matches m ON m.match_id = s.match_id AND m.tournament = 'IPL 2026'
GROUP BY p.full_name, t.short_name
HAVING count(*) >= 5
ORDER BY avg_points DESC
LIMIT 20;

-- @R13
-- Finance audit: paid contest entries that have no entry-fee debit in the wallet
SELECT ce.entry_id, ce.contest_id, ce.joined_at
FROM contest_entries ce
JOIN contests c ON c.contest_id = ce.contest_id
WHERE c.entry_fee > 0
  AND NOT EXISTS (SELECT 1 FROM wallet_transactions w
                  WHERE w.reference_entry_id = ce.entry_id AND w.txn_type = 'ENTRY_FEE');
-- Rewrite (bug fix): 63,000 wallet rows have reference_entry_id = NULL.
-- "x NOT IN (..., NULL)" is never TRUE (it is NULL or FALSE), so the original
-- always returned 0 rows. NOT EXISTS ignores NULLs. We also check txn_type,
-- because the question is about a missing ENTRY_FEE debit: a REFUND or
-- WINNINGS row for the entry is not a debit. Result: 192 rows instead of 0.

-- @R14
-- Product analytics: average fill rate per contest type for completed 2026 matches
-- Rewrite: (1) EXTRACT(YEAR FROM starts_at) = 2026 hides the column inside a
-- function; a plain date range is sargable. (2) Entries are counted per contest
-- first, so count(DISTINCT contest_id) becomes count(*) over one row per contest
-- and no longer sorts every entry row. sum(DISTINCT total_spots) is kept as is,
-- so the "rough" percentage is exactly the same number as before.
SELECT c.contest_type, count(*) AS contests,
       round(100.0 * sum(coalesce(e.entries, 0)) / sum(DISTINCT c.total_spots), 1) AS rough_fill_pct
FROM contests c
JOIN matches m ON m.match_id = c.match_id AND m.status = 'COMPLETED'
LEFT JOIN (SELECT contest_id, count(*) AS entries
           FROM contest_entries GROUP BY contest_id) e ON e.contest_id = c.contest_id
WHERE m.starts_at >= '2026-01-01' AND m.starts_at < '2027-01-01'
GROUP BY c.contest_type
ORDER BY contests DESC;

-- @R15
-- Leaderboards: top 20 users by winnings in 2026
SELECT u.user_id, u.username, sum(ce.winnings) AS winnings, count(*) FILTER (WHERE ce.winnings > 0) AS wins
FROM contest_entries ce
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
JOIN users u       ON u.user_id = ut.user_id
WHERE ce.joined_at >= '2026-01-01'
GROUP BY u.user_id, u.username
ORDER BY winnings DESC
LIMIT 20;

-- @R16
-- Player search
SELECT p.player_id, p.full_name, t.short_name, p.role, p.credits
FROM players p
JOIN teams t ON t.team_id = p.team_id
WHERE p.full_name ILIKE '%sharma%'
ORDER BY p.credits DESC;

-- @R17
-- Fair play: users with more than one team in the same contest
SELECT ce.contest_id, ut.user_id, count(*) AS teams_in_contest
FROM contest_entries ce
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
GROUP BY ce.contest_id, ut.user_id
HAVING count(*) > 1
ORDER BY teams_in_contest DESC;

-- @R18
-- Tax compliance: users without verified KYC who have won more than ₹1,000 in total
SELECT u.user_id, u.username, u.kyc_status, sum(w.amount) AS total_winnings
FROM users u
JOIN wallet_transactions w ON w.user_id = u.user_id AND w.txn_type = 'WINNINGS' AND w.status = 'SUCCESS'
WHERE u.kyc_status <> 'VERIFIED'
GROUP BY u.user_id, u.username, u.kyc_status
HAVING sum(w.amount) > 1000
ORDER BY total_winnings DESC;

-- @R19
-- Selection report: in how many teams was each IPL player picked (all time)
-- Rewrite: the correlated subquery counted user_team_players once per player
-- (250 full scans of 439,925 rows). Now the table is grouped once and joined.
SELECT p.player_id, p.full_name, coalesce(pk.picks, 0) AS times_picked
FROM players p
JOIN teams t ON t.team_id = p.team_id AND t.team_type = 'FRANCHISE'
LEFT JOIN (SELECT player_id, count(*) AS picks
           FROM user_team_players GROUP BY player_id) pk ON pk.player_id = p.player_id
ORDER BY times_picked DESC;

-- @R20
-- Finance: successful deposits per day and running total, June 2026
SELECT day, deposits, sum(deposits) OVER (ORDER BY day) AS running_total
FROM (
    SELECT created_at::date AS day, sum(amount) AS deposits
    FROM wallet_transactions
    WHERE txn_type = 'DEPOSIT' AND status = 'SUCCESS'
      AND created_at >= '2026-06-01' AND created_at < '2026-07-01'
    GROUP BY 1
) d
ORDER BY day;
-- Rewrite: created_at::date BETWEEN ... casts every row, so no index can be
-- used. The half-open range [1 Jun, 1 Jul) selects exactly the same days and
-- can use wallet_time_idx.

-- @R21
-- Engagement: users' head-to-head win rate (at least 3 head-to-head contests)
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

-- @R22
-- Support console: all wallet transactions, newest first, page 2,001 (25 per page)
-- Rewrite: keyset pagination. OFFSET 50000 reads and throws away 50,000 rows.
-- The app already has the last row of page 2,000 on screen
-- (txn_id 68344, created_at 2025-12-25 00:48:00+05:30), so the next page
-- starts right after it. txn_id breaks ties so no row is skipped or repeated.
SELECT txn_id, user_id, txn_type, amount, status, created_at
FROM wallet_transactions
WHERE (created_at, txn_id) < (TIMESTAMPTZ '2025-12-25 00:48:00+05:30', 68344)
ORDER BY created_at DESC, txn_id DESC
LIMIT 25;

-- @R23
-- Login with mobile number
SELECT user_id, username, kyc_status
FROM users
WHERE phone = '7300001042';

-- @R24
-- Player form: last 5 fantasy scores of every Chennai Super Kings player
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

-- @R25
-- Refund audit: paid entries in abandoned matches that were never refunded
SELECT ce.entry_id, ut.user_id, c.entry_fee, m.match_id
FROM contest_entries ce
JOIN contests c    ON c.contest_id = ce.contest_id AND c.entry_fee > 0
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
JOIN matches m     ON m.match_id = ut.match_id AND m.status = 'ABANDONED'
WHERE NOT EXISTS (SELECT 1 FROM wallet_transactions w WHERE w.reference_entry_id = ce.entry_id AND w.txn_type = 'REFUND')
ORDER BY m.match_id, ce.entry_id;

-- @W01
-- Create team: user 1006 saves team T9 for match 207
INSERT INTO user_teams (user_team_id, user_id, match_id, team_label, captain_id, vice_captain_id, created_at)
SELECT 90000001, 1006, 207, 'T9',
       (m.home_team_id - 1) * 25 + 1, (m.away_team_id - 1) * 25 + 2, '2026-07-01 18:00:00+05:30'
FROM matches m WHERE m.match_id = 207;

-- @W02
-- Join contest: user 1006's newest team for match 207 joins the mega contest of that match
INSERT INTO contest_entries (entry_id, contest_id, user_team_id, joined_at)
SELECT 90000001, c.contest_id, ut.user_team_id, '2026-07-01 18:05:00+05:30'
FROM contests c
JOIN user_teams ut ON ut.match_id = c.match_id
WHERE c.match_id = 207 AND c.contest_type = 'MEGA'
  AND ut.user_team_id = (SELECT max(user_team_id) FROM user_teams WHERE match_id = 207)
ON CONFLICT (contest_id, user_team_id) DO NOTHING;

-- @W03
-- Wallet: debit the entry fee for the most recent contest entry
INSERT INTO wallet_transactions (txn_id, user_id, txn_type, amount, reference_entry_id, status, created_at)
SELECT 90000001, ut.user_id, 'ENTRY_FEE', c.entry_fee, ce.entry_id, 'SUCCESS', '2026-07-01 18:05:00+05:30'
FROM contest_entries ce
JOIN contests c    ON c.contest_id = ce.contest_id
JOIN user_teams ut ON ut.user_team_id = ce.user_team_id
WHERE ce.entry_id = (SELECT max(entry_id) FROM contest_entries);

-- @W04
-- Points engine: recompute total points of every team for match 183
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

-- @W05
-- Payouts: approve all withdrawals pending for more than 24 hours
UPDATE wallet_transactions
SET status = 'SUCCESS'
WHERE txn_type = 'WITHDRAWAL' AND status = 'PENDING'
  AND created_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '24 hours';

-- @END
ROLLBACK;
