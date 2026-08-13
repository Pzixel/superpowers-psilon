---
name: superpowers-clickhouse-table-design-psilon
description: Use before proposing, planning, reviewing, generating, or applying any ClickHouse table creation or schema change, including DDL, migrations, engines, columns, types, defaults, codecs, keys, partitioning, TTLs, indexes, projections, and materialized-view storage. Read the bundled guide completely first. Skip query-only and data-only changes that leave table definitions untouched.
---

# ClickHouse Table Design

Read the bundled optimization guide before creating or modifying a ClickHouse table, then ground the change in the exact workload and deployment target.

## Mandatory First Step

Before inspecting candidate designs, recommending a change, writing a plan, or editing files:

1. Read [references/clickhouse-query-optimization-definitive-guide-2026-formatted.md](references/clickhouse-query-optimization-definitive-guide-2026-formatted.md) completely from start to finish.
2. Read it again on every skill invocation. Do not substitute memory, a summary, selected excerpts, or an earlier session's read.
3. If the reference cannot be read completely, stop the table-design work and report the blocker.

No ClickHouse table definition may be proposed or changed before this step is complete.

## Apply the Guide

Treat the guide as required design input, not as evidence that a recommendation fits the target. Follow repository authority and verify the exact ClickHouse version, existing schema, ingestion semantics, retention needs, data distribution, and important query patterns.

For each applicable table decision, consider:

- engine and merge-time behavior;
- column types, nullability, cardinality, defaults, and codecs;
- `ORDER BY` and `PRIMARY KEY` against frequent filters and granule pruning;
- `PARTITION BY` against lifecycle operations and partition cardinality;
- TTLs, projections, skipping indexes, and materialized-view storage;
- migration, replication, compatibility, rollback, and backfill consequences.

Do not copy a generic optimization without proving its prerequisites for the target. Preserve required data semantics even when a narrower type, non-null default, denormalization, or precomputation appears faster.

## Finish the Change

State which guide principles affected the design and which were inapplicable. Validate the resulting DDL with repository-owned checks. For performance-motivated changes, compare representative evidence such as selected granules, rows and bytes read, latency, memory, and ingest cost when the environment permits it.
