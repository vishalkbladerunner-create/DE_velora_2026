-- Phase 5 partitioning design.
-- Apply after 01_schema.sql, 02_load_data.sql (or 07_load_large.sql),
-- 05_indexes.sql and 09_scale_fixes.sql.
--
-- The live table stays unpartitioned. This creates a partitioned copy so the
-- pruning plan can be demonstrated without changing the workload's table.
-- A partitioned table's primary key must include the partition key, so the
-- key is (txn_id, created_at), not txn_id alone.
SET search_path TO dream11;

DROP TABLE IF EXISTS wallet_transactions_partitioned CASCADE;

CREATE TABLE wallet_transactions_partitioned (
    txn_id             INTEGER NOT NULL,
    user_id            INTEGER NOT NULL,
    txn_type           VARCHAR(12) NOT NULL,
    amount             NUMERIC(10, 2) NOT NULL,
    reference_entry_id INTEGER,
    status             VARCHAR(10) NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (txn_id, created_at),
    CONSTRAINT wallet_part_user_fk
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT wallet_part_entry_fk
        FOREIGN KEY (reference_entry_id) REFERENCES contest_entries (entry_id) ON DELETE RESTRICT,
    CONSTRAINT wallet_part_type_allowed
        CHECK (txn_type IN ('DEPOSIT', 'WITHDRAWAL', 'ENTRY_FEE', 'WINNINGS', 'REFUND', 'BONUS')),
    CONSTRAINT wallet_part_amount_positive CHECK (amount > 0),
    CONSTRAINT wallet_part_status_allowed CHECK (status IN ('SUCCESS', 'PENDING', 'FAILED')),
    CONSTRAINT wallet_part_reference_by_type
        CHECK ((txn_type IN ('ENTRY_FEE', 'WINNINGS', 'REFUND')) = (reference_entry_id IS NOT NULL))
) PARTITION BY RANGE (created_at);

CREATE TABLE wallet_transactions_p2025_01 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-02-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_02 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-02-01 00:00:00+05:30') TO ('2025-03-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_03 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-03-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_04 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-05-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_05 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-05-01 00:00:00+05:30') TO ('2025-06-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_06 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-06-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_07 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-08-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_08 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-08-01 00:00:00+05:30') TO ('2025-09-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_09 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-09-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_10 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2025-11-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_11 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-11-01 00:00:00+05:30') TO ('2025-12-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2025_12 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2025-12-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2026_01 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-02-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2026_02 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2026-02-01 00:00:00+05:30') TO ('2026-03-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2026_03 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2026-03-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2026_04 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-05-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2026_05 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2026-05-01 00:00:00+05:30') TO ('2026-06-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2026_06 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_p2026_07 PARTITION OF wallet_transactions_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-08-01 00:00:00+05:30');

CREATE TABLE wallet_transactions_pdefault PARTITION OF wallet_transactions_partitioned DEFAULT;

INSERT INTO wallet_transactions_partitioned SELECT * FROM wallet_transactions;

ANALYZE wallet_transactions_partitioned;
