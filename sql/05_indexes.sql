-- Dream11 Fantasy Sports — Phase 4 indexes.
-- Run after 01_schema.sql and 02_load_data.sql:
--   psql -d dream11 -f sql/05_indexes.sql
--
-- Rule for column order: equality columns first, then the range / sort column.
-- Every index says which queries it serves and why it looks the way it does.

SET search_path TO dream11;

-- 1. Fantasy teams of one match.
--    Serves R02, R06, R08, R25, W04 (all filter user_teams by match_id).
--    The only existing index starts with user_id, so "match_id = 207" had to
--    scan all 39,975 teams. A plain B-tree on match_id turns that into a
--    lookup of ~190 teams.
CREATE INDEX user_teams_match_idx
    ON user_teams (match_id);

-- 2. Contests of one match.
--    Serves R01, R04, W02 (contests joined or filtered by match_id).
--    Small table today (2,544 rows) but it grows with every match.
CREATE INDEX contests_match_idx
    ON contests (match_id);

-- 3. Contest entries of one fantasy team.
--    Serves R25 (entries of the teams in abandoned matches).
--    The unique (contest_id, user_team_id) index cannot be used when only
--    user_team_id is known, because user_team_id is its second column.
CREATE INDEX contest_entries_user_team_idx
    ON contest_entries (user_team_id);

-- 4. One user's wallet history in time order.
--    Serves R09 (WHERE user_id = ... ORDER BY created_at, txn_id).
--    user_id is the equality column, then created_at, txn_id follow the
--    ORDER BY of the running balance. Replaces a scan of all 118,343 rows.
CREATE INDEX wallet_user_time_idx
    ON wallet_transactions (user_id, created_at, txn_id);

-- 5. Successful winnings per user (partial + covering index).
--    Serves R18 (unverified-KYC users who won more than 1,000).
--    Only the 12,302 WINNINGS/SUCCESS rows are stored, and INCLUDE (amount)
--    lets the sum be done with an Index Only Scan, never touching the table.
CREATE INDEX wallet_winnings_user_idx
    ON wallet_transactions (user_id) INCLUDE (amount)
    WHERE txn_type = 'WINNINGS' AND status = 'SUCCESS';

-- 6. Pending withdrawals only (partial index).
--    Serves R10 and W05. Only 100 of 118,343 rows are pending withdrawals, so
--    a partial index on just those rows is tiny. Ordered by created_at for
--    the "older than 24 hours" range and the ORDER BY. When W05 approves a
--    withdrawal its row simply leaves this index.
CREATE INDEX wallet_pending_withdrawal_idx
    ON wallet_transactions (created_at)
    WHERE txn_type = 'WITHDRAWAL' AND status = 'PENDING';

-- 7. Wallet rows that point to a contest entry (partial index).
--    Serves R13 (no ENTRY_FEE debit for an entry) and R25 (no REFUND for an
--    entry), both are NOT EXISTS lookups on (reference_entry_id, txn_type).
--    63,000 rows (deposits, bonuses, withdrawals) have no reference, so they
--    are left out with WHERE reference_entry_id IS NOT NULL.
CREATE INDEX wallet_reference_entry_idx
    ON wallet_transactions (reference_entry_id, txn_type)
    WHERE reference_entry_id IS NOT NULL;

-- 8. Whole wallet ledger in time order.
--    Serves R20 (June 2026 date range, after the sargable rewrite) and R22
--    (newest first, keyset pagination on created_at, txn_id).
--    txn_id is the tie-breaker so keyset paging never skips or repeats a row.
CREATE INDEX wallet_time_idx
    ON wallet_transactions (created_at, txn_id);

-- Fresh statistics and visibility map, so the planner knows the new indexes
-- and Index Only Scans do not have to visit the table.
VACUUM ANALYZE;
