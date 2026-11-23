-- Dream11 Fantasy Sports — load the Phase 5 large dataset CSVs.
-- Run from the repository root, after 01_schema.sql, so that \copy can see
-- large_data/. The CSV files are gitignored and never committed.
--
--   psql -d dream11 -f sql/01_schema.sql
--   psql -d dream11_large -f sql/07_load_large.sql

SET search_path TO dream11;

-- Parents before children: teams, players, matches, stats, users, fantasy
-- teams, their players, contests, entries, wallet.
\copy teams FROM 'large_data/teams.csv' WITH (FORMAT csv, HEADER true)
\copy players FROM 'large_data/players.csv' WITH (FORMAT csv, HEADER true)
\copy matches FROM 'large_data/matches.csv' WITH (FORMAT csv, HEADER true)
\copy player_match_stats FROM 'large_data/player_match_stats.csv' WITH (FORMAT csv, HEADER true)
\copy users FROM 'large_data/users.csv' WITH (FORMAT csv, HEADER true)
\copy user_teams FROM 'large_data/user_teams.csv' WITH (FORMAT csv, HEADER true)
\copy user_team_players FROM 'large_data/user_team_players.csv' WITH (FORMAT csv, HEADER true)
\copy contests FROM 'large_data/contests.csv' WITH (FORMAT csv, HEADER true)
\copy contest_entries FROM 'large_data/contest_entries.csv' WITH (FORMAT csv, HEADER true)
\copy wallet_transactions FROM 'large_data/wallet_transactions.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;

-- The load is correct only when every count matches the brief.
SELECT 'contest_entries' AS table_name, count(*) AS actual, 42746 AS expected FROM contest_entries
UNION ALL SELECT 'contests', count(*), 2544 FROM contests
UNION ALL SELECT 'matches', count(*), 212 FROM matches
UNION ALL SELECT 'player_match_stats', count(*), 4444 FROM player_match_stats
UNION ALL SELECT 'players', count(*), 450 FROM players
UNION ALL SELECT 'teams', count(*), 18 FROM teams
UNION ALL SELECT 'user_team_players', count(*), 439925 FROM user_team_players
UNION ALL SELECT 'user_teams', count(*), 39975 FROM user_teams
UNION ALL SELECT 'users', count(*), 50000 FROM users
UNION ALL SELECT 'wallet_transactions', count(*), 118343 FROM wallet_transactions
ORDER BY table_name;
