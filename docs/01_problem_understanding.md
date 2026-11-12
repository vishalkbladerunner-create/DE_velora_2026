# Phase 1 — Problem understanding

Dream11's current database has no documented schema; only ten CSV exports survive. The product, contest, points, fair-play, finance and compliance teams each report a different symptom. This page translates those symptoms into what the business actually needs, who is affected, and whether the work is on the match-day critical path or in reporting.

| # | Business need | Stakeholder | Class | Queries |
| --- | --- | --- | --- | --- |
| P1 | The lobby, player pool and contest list must render before a match locks. A user chooses a match, builds a team and sees the contests without waiting. | Fantasy player (user app) | Customer-facing, real-time | R01, R02, R04, R08 |
| P2 | "My teams", the team preview, leaderboards and wallet history must stay responsive while a match is live and traffic peaks. | Fantasy player (user app) | Customer-facing, real-time | R03, R05, R07, R09 |
| P3 | Creating a team, joining a contest and debiting the wallet must never lag; a slow write loses the entry or double-charges the user. | Contest engine | Transactional, real-time write | W01, W02, W03 |
| P4 | Fair play must find rule-breaking teams and users entering multiple teams in one contest quickly enough for an investigation before payouts. | Fair-play team | Reporting / analytics (interactive) | R06, R17 |
| P5 | The finance audit of paid entries with no wallet debit must return the missing rows, not an empty result. An empty result is impossible and hides a control failure. | Finance audit | Reporting / analytics | R13 |
| P6 | Payouts and compliance must find pending withdrawals, users in banned states, unverified KYC winners and missed refunds before money leaves the platform. | Payouts and compliance | Reporting / analytics | R10, R11, R18, R25, W05 |
| P7 | The points engine must recompute team totals after a match, and the stats hub must show player averages, form and selection counts without timing out. | Points engine and stats team | Real-time write plus analytics reads | W04, R12, R19, R24 |
| P8 | Product and finance reports — fill rate, winnings, head-to-head, deposits, search and paginated support views — must stay usable as volume grows 20×. | Product and finance | Reporting / analytics | R14, R15, R16, R20, R21, R22, R23 |

## What the classification changes

The customer-facing and transactional group (P1–P3, plus W04 in P7) is the group with hard latency expectations: a user is waiting at the screen or the contest engine is committing money. The reporting group (P4–P6, P8, plus the reads in P7) can take longer, but it must still return the right rows; P5 and P6 are control checks, so an empty or partial answer is a correctness bug, not a performance trade-off.

The Phase 5 targets follow the same split: real-time and match-day queries under 5 ms, interactive tools under 250 ms, and reports under 5 s on the 20× dataset.

## Assumptions

- The CSVs are a production export. Their column names and values are the contract; the 30 queries in `queries/workload_30.sql` must not be edited.
- The data is historical, so `total_points` and `final_rank` are only populated after a match or contest is settled.
- Timestamps carry the `+05:30` offset and are stored as `TIMESTAMPTZ`.
- Money is stored as `NUMERIC`, never floating point.
- Cross-row game rules — exactly 11 players, at most 100 credits, at most 7 from one side, captain and vice-captain in the XI — cannot be a single-column `CHECK`. They are application/trigger rules; R06 exists to find violations in the export.
- The seed data is not modified. Write queries are measured with `BEGIN; … ROLLBACK;`.
- The same laptop is used for the Phase 3 and Phase 4 benchmarks.
