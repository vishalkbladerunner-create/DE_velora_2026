-- Phase 5 scale fixes.
-- Run after 01_schema.sql, 02_load_data.sql (or 07_load_large.sql), 05_indexes.sql
-- and ANALYZE. Safe to re-run: every index uses IF NOT EXISTS.
SET search_path TO dream11;

-- R02: the team-creation pool needs the teams of one match and their ids.
-- The CP3 index on (match_id) still fetched the heap for user_team_id; this
-- covering index lets the count run index-only.
CREATE INDEX IF NOT EXISTS user_teams_match_team_idx
    ON user_teams (match_id) INCLUDE (user_team_id);

-- R05: the leaderboard reads username, label and points for a contest's teams.
-- These covering indexes remove the heap fetches from the two 1,100-row joins.
CREATE INDEX IF NOT EXISTS users_name_cover_idx
    ON users (user_id) INCLUDE (username);

CREATE INDEX IF NOT EXISTS user_teams_leaderboard_cover_idx
    ON user_teams (user_team_id) INCLUDE (user_id, total_points, team_label);

ANALYZE user_teams;
ANALYZE users;
