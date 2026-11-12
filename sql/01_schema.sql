-- Dream11 Fantasy Sports — Phase 2 schema.
-- Run on an empty PostgreSQL 15+ database, before 02_load_data.sql.
-- Only primary keys, unique constraints, foreign keys, NOT NULL and CHECK
-- constraints are created here. No extra indexes: the Phase 3 baseline must
-- measure the un-tuned schema.

CREATE SCHEMA dream11;
SET search_path TO dream11;

CREATE TABLE teams (
    team_id    INTEGER PRIMARY KEY,
    team_name  VARCHAR(60) NOT NULL,
    short_name VARCHAR(4)  NOT NULL UNIQUE,
    team_type  VARCHAR(20) NOT NULL,

    CONSTRAINT teams_short_name_format
        CHECK (short_name ~ '^[A-Z]{2,4}$'),
    CONSTRAINT teams_type_allowed
        CHECK (team_type IN ('FRANCHISE', 'INTERNATIONAL'))
);

CREATE TABLE players (
    player_id INTEGER PRIMARY KEY,
    full_name VARCHAR(60) NOT NULL,
    team_id   INTEGER     NOT NULL,
    role      VARCHAR(4)  NOT NULL,
    credits   NUMERIC(4, 1) NOT NULL,
    is_active BOOLEAN     NOT NULL,

    CONSTRAINT players_team_fk
        FOREIGN KEY (team_id) REFERENCES teams (team_id) ON DELETE RESTRICT,
    CONSTRAINT players_role_allowed
        CHECK (role IN ('WK', 'BAT', 'AR', 'BOWL')),
    CONSTRAINT players_credits_range
        CHECK (credits > 0 AND credits <= 100)
);

CREATE TABLE matches (
    match_id      INTEGER PRIMARY KEY,
    tournament    VARCHAR(40) NOT NULL,
    home_team_id  INTEGER     NOT NULL,
    away_team_id  INTEGER     NOT NULL,
    venue         VARCHAR(80) NOT NULL,
    starts_at     TIMESTAMPTZ NOT NULL,
    status        VARCHAR(10) NOT NULL,

    CONSTRAINT matches_home_team_fk
        FOREIGN KEY (home_team_id) REFERENCES teams (team_id) ON DELETE RESTRICT,
    CONSTRAINT matches_away_team_fk
        FOREIGN KEY (away_team_id) REFERENCES teams (team_id) ON DELETE RESTRICT,
    CONSTRAINT matches_different_teams
        CHECK (home_team_id <> away_team_id),
    CONSTRAINT matches_status_allowed
        CHECK (status IN ('UPCOMING', 'LIVE', 'COMPLETED', 'ABANDONED'))
);

CREATE TABLE player_match_stats (
    match_id       INTEGER  NOT NULL,
    player_id      INTEGER  NOT NULL,
    runs           SMALLINT NOT NULL,
    balls_faced    SMALLINT NOT NULL,
    fours          SMALLINT NOT NULL,
    sixes          SMALLINT NOT NULL,
    wickets        SMALLINT NOT NULL,
    catches        SMALLINT NOT NULL,
    fantasy_points NUMERIC(6, 1) NOT NULL,

    CONSTRAINT player_match_stats_pkey
        PRIMARY KEY (match_id, player_id),
    CONSTRAINT player_match_stats_match_fk
        FOREIGN KEY (match_id) REFERENCES matches (match_id) ON DELETE CASCADE,
    CONSTRAINT player_match_stats_player_fk
        FOREIGN KEY (player_id) REFERENCES players (player_id) ON DELETE RESTRICT,
    CONSTRAINT player_match_stats_non_negative
        CHECK (runs >= 0 AND balls_faced >= 0 AND fours >= 0 AND sixes >= 0
               AND catches >= 0 AND fantasy_points >= 0),
    CONSTRAINT player_match_stats_wickets_range
        CHECK (wickets >= 0 AND wickets <= 10),
    CONSTRAINT player_match_stats_boundaries_fit_runs
        CHECK (fours * 4 + sixes * 6 <= runs),
    CONSTRAINT player_match_stats_fours_fit_balls
        CHECK (fours <= balls_faced)
);

CREATE TABLE users (
    user_id    INTEGER PRIMARY KEY,
    username   VARCHAR(25) NOT NULL UNIQUE,
    phone      VARCHAR(10) NOT NULL UNIQUE,
    email      VARCHAR(80) UNIQUE,
    state_code CHAR(2)     NOT NULL,
    kyc_status VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT users_username_format
        CHECK (username ~ '^[A-Za-z][A-Za-z0-9_]{2,24}$'),
    CONSTRAINT users_phone_format
        CHECK (phone ~ '^[6-9][0-9]{9}$'),
    CONSTRAINT users_email_format
        CHECK (email IS NULL OR email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$'),
    CONSTRAINT users_state_format
        CHECK (state_code ~ '^[A-Z]{2}$'),
    CONSTRAINT users_kyc_status_allowed
        CHECK (kyc_status IN ('PENDING', 'VERIFIED', 'REJECTED'))
);

CREATE TABLE user_teams (
    user_team_id  INTEGER PRIMARY KEY,
    user_id       INTEGER NOT NULL,
    match_id      INTEGER NOT NULL,
    team_label    VARCHAR(3) NOT NULL,
    captain_id    INTEGER NOT NULL,
    vice_captain_id INTEGER NOT NULL,
    total_points  NUMERIC(6, 1),
    created_at    TIMESTAMPTZ NOT NULL,

    CONSTRAINT user_teams_user_fk
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT user_teams_match_fk
        FOREIGN KEY (match_id) REFERENCES matches (match_id) ON DELETE RESTRICT,
    CONSTRAINT user_teams_captain_fk
        FOREIGN KEY (captain_id) REFERENCES players (player_id) ON DELETE RESTRICT,
    CONSTRAINT user_teams_vice_captain_fk
        FOREIGN KEY (vice_captain_id) REFERENCES players (player_id) ON DELETE RESTRICT,
    CONSTRAINT user_teams_user_match_label_unique
        UNIQUE (user_id, match_id, team_label),
    CONSTRAINT user_teams_different_captains
        CHECK (captain_id <> vice_captain_id),
    CONSTRAINT user_teams_label_format
        CHECK (team_label ~ '^T([1-9]|1[0-1])$'),
    CONSTRAINT user_teams_points_non_negative
        CHECK (total_points IS NULL OR total_points >= 0)
);

CREATE TABLE user_team_players (
    user_team_id INTEGER NOT NULL,
    player_id    INTEGER NOT NULL,

    CONSTRAINT user_team_players_pkey
        PRIMARY KEY (user_team_id, player_id),
    CONSTRAINT user_team_players_team_fk
        FOREIGN KEY (user_team_id) REFERENCES user_teams (user_team_id) ON DELETE CASCADE,
    CONSTRAINT user_team_players_player_fk
        FOREIGN KEY (player_id) REFERENCES players (player_id) ON DELETE RESTRICT
);

CREATE TABLE contests (
    contest_id    INTEGER PRIMARY KEY,
    match_id      INTEGER NOT NULL,
    contest_name  VARCHAR(40) NOT NULL,
    contest_type  VARCHAR(15) NOT NULL,
    entry_fee     NUMERIC(10, 2) NOT NULL,
    total_spots   INTEGER NOT NULL,
    prize_pool    NUMERIC(12, 2) NOT NULL,
    is_guaranteed BOOLEAN NOT NULL,
    invite_code   VARCHAR(8) UNIQUE,

    CONSTRAINT contests_match_fk
        FOREIGN KEY (match_id) REFERENCES matches (match_id) ON DELETE RESTRICT,
    CONSTRAINT contests_type_allowed
        CHECK (contest_type IN ('MEGA', 'SMALL', 'HEAD_TO_HEAD', 'PRIVATE')),
    CONSTRAINT contests_entry_fee_non_negative
        CHECK (entry_fee >= 0),
    CONSTRAINT contests_spots_positive
        CHECK (total_spots > 0),
    CONSTRAINT contests_prize_pool_non_negative
        CHECK (prize_pool >= 0),
    CONSTRAINT contests_private_has_code
        CHECK ((contest_type = 'PRIVATE') = (invite_code IS NOT NULL)),
    CONSTRAINT contests_invite_code_format
        CHECK (invite_code IS NULL OR invite_code ~ '^[A-Z0-9]{8}$'),
    CONSTRAINT contests_head_to_head_two_spots
        CHECK (contest_type <> 'HEAD_TO_HEAD' OR total_spots = 2)
);

CREATE TABLE contest_entries (
    entry_id      INTEGER PRIMARY KEY,
    contest_id    INTEGER NOT NULL,
    user_team_id  INTEGER NOT NULL,
    joined_at     TIMESTAMPTZ NOT NULL,
    final_rank    INTEGER,
    winnings      NUMERIC(10, 2) NOT NULL DEFAULT 0,

    CONSTRAINT contest_entries_contest_fk
        FOREIGN KEY (contest_id) REFERENCES contests (contest_id) ON DELETE RESTRICT,
    CONSTRAINT contest_entries_user_team_fk
        FOREIGN KEY (user_team_id) REFERENCES user_teams (user_team_id) ON DELETE RESTRICT,
    CONSTRAINT contest_entries_contest_team_unique
        UNIQUE (contest_id, user_team_id),
    CONSTRAINT contest_entries_final_rank_positive
        CHECK (final_rank IS NULL OR final_rank > 0),
    CONSTRAINT contest_entries_winnings_non_negative
        CHECK (winnings >= 0),
    CONSTRAINT contest_entries_unranked_has_no_winnings
        CHECK (final_rank IS NOT NULL OR winnings = 0)
);

CREATE TABLE wallet_transactions (
    txn_id             INTEGER PRIMARY KEY,
    user_id            INTEGER NOT NULL,
    txn_type           VARCHAR(12) NOT NULL,
    amount             NUMERIC(10, 2) NOT NULL,
    reference_entry_id INTEGER,
    status             VARCHAR(10) NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL,

    CONSTRAINT wallet_transactions_user_fk
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT wallet_transactions_entry_fk
        FOREIGN KEY (reference_entry_id) REFERENCES contest_entries (entry_id) ON DELETE RESTRICT,
    CONSTRAINT wallet_transactions_type_allowed
        CHECK (txn_type IN ('DEPOSIT', 'WITHDRAWAL', 'ENTRY_FEE', 'WINNINGS', 'REFUND', 'BONUS')),
    CONSTRAINT wallet_transactions_amount_positive
        CHECK (amount > 0),
    CONSTRAINT wallet_transactions_status_allowed
        CHECK (status IN ('SUCCESS', 'PENDING', 'FAILED')),
    CONSTRAINT wallet_transactions_reference_by_type
        CHECK ((txn_type IN ('ENTRY_FEE', 'WINNINGS', 'REFUND')) = (reference_entry_id IS NOT NULL))
);
