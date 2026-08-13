# The definitive guide to ClickHouse query optimization (2026)

Al Brown, Tom Schreiber and Lionel Palacin

Last updated: Jan 26, 2026

ClickHouse achieves extraordinary performance, querying trillions of rows in milliseconds, through an obsessive attention to detail and a fundamentally different architecture than traditional databases. This guide teaches not just what to optimize, but *why* each technique works at the architectural level, enabling you to build intuition for optimizing any ClickHouse workload.

---

## Three principles of query optimization

Every optimization technique derives from these fundamental principles:

**1. Faster queries read less data** – The less data you read, the faster the query will be. Optimise indexes around common filters to minimise data reads.

**2. Avoid unnecessary work at query time** – Select only necessary columns and use specialised queries for specific tasks. Where possible, shift processing and transformations to ingest-time using materialised views.

**3. Filter first, then process** – Filter first to reduce dataset size, then apply expensive operations (joins, aggregations) to smaller result sets.

---

## What makes ClickHouse so fast?

To get the most out of your optimisations, it helps to understand how certain things work under-the-hood in ClickHouse. Every optimization strategy stems from these core architectural decisions.

### How ClickHouse stores data on disk with columnar storage

Traditional row-oriented databases store complete records together on disk. [ClickHouse stores each column separately as an independent file](https://clickhouse.com/resources/engineering/what-is-columnar-database?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide). When you execute `SELECT user_id, price FROM sales`, ClickHouse reads only those two columns - ignoring the other 20 columns in your table. This architectural choice has profound implications: **the less data you read, the faster your queries run**.

This explains why `SELECT *` is particularly expensive in ClickHouse. In a row-oriented database, reading all columns vs. specific columns makes little difference - you're reading complete rows either way. In ClickHouse, `SELECT *` forces reading every column file from disk, multiplying I/O operations. Conversely, querying wide tables (100+ columns) costs the same as narrow tables if you only select a few columns.

![](/uploads/eng_resource_0_columnstore_1c09a6321a.png)

### Sparse primary indexes: Efficiency at any scale

[ClickHouse uses sparse primary indexes that differ radically from traditional B-tree indexes](https://clickhouse.com/docs/guides/best-practices/sparse-primary-indexes?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide). Instead of indexing every row, ClickHouse indexes blocks of rows called **granules** - by default, 8,192 rows each.

Consider a table with 8.87 million rows. A traditional B-tree index would create 8.87 million entries (hundreds of megabytes). ClickHouse's sparse index creates only 1,083 entries (~97 KB), fitting entirely in memory even for petabyte-scale tables.

**Here's how it works:** Data is physically sorted on disk by your `ORDER BY` clause. The sparse index stores the first value from every 8,192nd row. When you query `WHERE user_id = 12345`, ClickHouse performs binary search (log₂ n complexity) over the 1,083 index entries to identify which granules might contain matching rows. It then streams only those granules from disk - skipping potentially terabytes of irrelevant data.

This design represents a smart architectural trade-off that enables massive scalability while maintaining fast performance at any scale. In the worst case, if your target value falls at the boundary between two granules, ClickHouse reads both - up to 16,384 rows when only one matches. This overhead is negligible compared to the benefit of keeping the entire index in memory, enabling consistent sub-second queries whether you're querying thousands or trillions of rows.

### Granules: The fundamental unit of data access

[Granules are the smallest indivisible units ClickHouse reads during query execution](https://clickhouse.com/docs/academic_overview#3-1-on-disk-format?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide). You cannot read half a granule - if a single row in a granule matches your filter, the entire granule must be read. This has critical implications for primary key design.

#### **The granule size (8,192 rows by default) represents a carefully tuned balance:**

- Small granules: More precise filtering but larger indexes and more overhead

- Large granules: Smaller indexes but less precise filtering (read more unnecessary data)

ClickHouse uses [adaptive granularity](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#mergetree-data-storage), creating a new granule when either condition is met: 8,192 rows accumulated OR combined row size reaches 10 MB. This prevents pathologically large granules with wide rows.

### Merge-time computation shifts work away from queries

ClickHouse is append-only by design. Each INSERT creates a new independent "part" (data structure) on disk. [Background processes continuously merge small parts into larger ones](https://clickhouse.com/docs/academic_overview#3-3-merge-time-data-transformation?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide).

ClickHouse can perform operations both at query time AND during merges. The merge-time operations are an optimization that pre-computes results for faster queries, not a limitation. During merges, ClickHouse can perform expensive operations: deduplication (ReplacingMergeTree), aggregation (AggregatingMergeTree), TTL-based expiration, and maintaining materialized views with intermediate states.

While data is append-only and immutable on disk, [ClickHouse fully supports SQL standard UPDATE and DELETE statements](https://clickhouse.com/blog/updates-in-clickhouse-2-sql-style-updates?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide) through a mutation mechanism that rewrites affected parts in the background.

This architectural choice means your queries can read pre-organized, pre-aggregated data rather than computing everything on demand - potentially accelerating queries by 1000× or more. Even raw data queries benefit from merged parts through fewer files to read and better compression.

### Query execution pipeline enables parallelism

[ClickHouse executes queries through a multi-stage pipeline](https://clickhouse.com/docs/guides/developer/understanding-query-execution-with-the-analyzer#query-pipeline?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide):

1. **Parsing and Analysis** – Create generic execution plan

2. **Optimization** – Prune unnecessary data, build query pipeline

3. **Pipeline Execution** – Parallel processing across CPU cores for filtering, aggregation, sorting

4. **Final Processing** – Merge results, format, return to client

By default, ClickHouse uses as many threads as CPU cores available. Each thread processes an independent data range in parallel, then results merge. This explains why ClickHouse shows "× N" notation in EXPLAIN PIPELINE output, where N equals the number of CPU cores - indicating N parallel threads processing data simultaneously. This parallelism level affects memory usage - each thread maintains its own buffers. You can control this with `max_threads` setting if memory is constrained.

---

## Optimisation 1: Sort data with ORDER BY

#### **This is the single most important optimization in ClickHouse - proper ORDER BY selection can improve query performance by 100× or more.**

[Primary key design has the single biggest impact on query performance](https://clickhouse.com/docs/best-practices/choosing-a-primary-key?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide). A well-designed primary key can reduce query time by 100× or more.

Note: In ClickHouse, the primary key and ORDER BY are often the same, and many users define tables with just ORDER BY and no explicit PRIMARY KEY. The primary key must be a prefix of the ORDER BY columns. Throughout this guide, we'll use 'primary key' to refer to the columns that determine both the sparse index and physical sort order.

The primary key determines how data is physically sorted on disk. This physical ordering enables ClickHouse to skip massive amounts of data during query execution.

#### **Without an appropriate primary key:**

```sql
-- Table with: ORDER BY (postcode, address)
SELECT county, price
FROM uk_price_paid
WHERE town = 'LONDON'
ORDER BY price DESC
LIMIT 3

-- Performance:
-- Processed: 27.64 million rows (full table scan)
-- Time: 44ms
-- Data read: 44.21 MB
```

In the example above, the table has been created with a primary key of `(postcode, address)`, while the query is filtering on `town = 'LONDON'`. The primary key cannot help because `town` was not used to order the table data. ClickHouse must scan every granule to find matching rows.

#### **With an appropriate primary key:**

```sql
-- New table with: ORDER BY (town, price)
SELECT county, price
FROM uk_price_paid_optimized
WHERE town = 'LONDON'
ORDER BY price DESC
LIMIT 3

-- Performance:
-- Processed: 81,920 rows (selected granules only)
-- Time: 5ms (8.8× faster)
-- Data read: 13.03 MB (3.4× less)
```

ClickHouse performs binary search over the sparse index, identifies granules where town = 'LONDON' exists, and reads only those granules - skipping 99.7% of the table.

### Designing effective primary keys

#### **Rule 1: Include columns used in WHERE clause filters**

Analyze your query patterns. Identify which columns appear most frequently in WHERE clauses. These columns should be in your primary key.

```sql
-- Query pattern analysis:
-- 70% of queries: WHERE pickup_datetime BETWEEN ... AND ...
-- 50% of queries: WHERE passenger_count IN (1, 2)
-- 30% of queries: WHERE trip_distance > X
```

#### **Rule 2: Order by cardinality - lower cardinality first**

This is counterintuitive coming from traditional databases, but in ClickHouse, lower cardinality columns should come first in the primary key. Here's why:

#### **Primary key column behavior differs by position:**

**First column** – Binary search applies with O(log₂ n) complexity. Highly efficient regardless of cardinality.

**Secondary columns** – Generic exclusion search algorithm applies. Efficiency depends on predecessor column's cardinality:

- **Low predecessor cardinality:** Effective filtering. Same predecessor value spans multiple granules, so secondary column values are sorted across those granules.

- **High predecessor cardinality:** Ineffective filtering. When the first column has high cardinality (like UUID), each unique value appears in very few granules. This means the secondary column values are essentially random across granules - there's no sorted sequence to leverage for exclusion.

#### **Rule 3: Include time-based components for time-series data**

Most analytical workloads are time-series based. Time range filters are extremely common: "show me last week's data," "compare Q1 to Q2," etc. Including timestamps in your primary key enables massive data pruning:

```sql
-- Time-series optimized primary key:
PRIMARY KEY (event_type, event_timestamp)

-- Efficient queries:
WHERE event_type = 'purchase'
  AND event_timestamp >= '2024-01-01'
  AND event_timestamp < '2024-02-01'
```

Note: Timestamp placement depends on your query patterns. If you always filter to small time ranges first, timestamp can be first. But if you frequently filter by low-cardinality dimensions (like event_type) and want temporal ordering within those groups, place timestamp second.

### Compound primary keys and query patterns

A compound primary key like `(user_id, timestamp, event_type)` efficiently supports queries in this order of specificity:

#### **Highly efficient:**

- `WHERE user_id = X` (first key column)

- `WHERE user_id = X AND timestamp > Y` (first two columns)

- `WHERE user_id = X AND timestamp > Y AND event_type = 'Z'` (all columns in order)

#### **Less efficient:**

- `WHERE timestamp > Y` (skips first column)

- `WHERE event_type = 'Z'` (skips first two columns)

ClickHouse can still use the index for these queries, but with reduced effectiveness. The more columns you skip from the left, the less effective the index becomes.

---

## Optimisation 2: Avoid Nullable columns

Instead of NULL, use sensible defaults: empty strings for text, 0 or -1 for numbers, or epoch time for dates. Configure these as DEFAULT values in your schema or have your application send them.

[Every Nullable column requires ClickHouse to process an additional UInt8 column](https://clickhouse.com/docs/optimize/avoid-nullable-columns?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide) tracking which values are NULL - one bit per row. This overhead manifests in multiple ways:

- **Storage increase:** Each Nullable column adds a separate null mask column

- **Memory overhead:** Both data and mask must be loaded during query execution

- **Processing cost:** Every operation must check the null mask

#### **Identify unnecessary Nullables by checking for actual NULL values:**

```sql
SELECT
    countIf(vendor_id IS NULL) AS vendor_id_nulls,
    countIf(pickup_datetime IS NULL) AS pickup_datetime_nulls,
    countIf(passenger_count IS NULL) AS passenger_count_nulls,
    countIf(mta_tax IS NULL) AS mta_tax_nulls
FROM trips

-- Results show:
-- vendor_id_nulls: 0         ← Nullable unnecessary
-- pickup_datetime_nulls: 0   ← Nullable unnecessary
-- mta_tax_nulls: 137946731   ← Keep as Nullable
```

---

## Optimisation 3: LowCardinality

For String columns with fewer than 10,000 unique values, [the LowCardinality type applies dictionary encoding](https://clickhouse.com/docs/sql-reference/data-types/lowcardinality?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide): storing unique values once in a dictionary, with each row storing only a small integer reference. For example, instead of storing a string like "Credit Card" millions of times (consuming 12 bytes per occurrence), ClickHouse stores it once in a dictionary and uses integer references (4 bytes each).

#### **Identify candidates by checking cardinality:**

```sql
SELECT
    uniq(vendor_id) AS vendor_unique,      -- Result: 3
    uniq(ratecode_id) AS ratecode_unique,  -- Result: 6
    uniq(payment_type) AS payment_unique   -- Result: 4
FROM trips
```

#### **Apply LowCardinality to appropriate columns:**

```sql
CREATE TABLE trips_optimized (
    vendor_id LowCardinality(String),     -- 3 unique values
    ratecode_id LowCardinality(String),   -- 6 unique values
    payment_type LowCardinality(String)   -- 4 unique values
) ENGINE = MergeTree
ORDER BY (pickup_datetime);
```

---

## Optimisation 4: Choose the smallest appropriate data types

Each byte saved per row multiplies across billions of rows. [Choosing the right data type can reduce storage by 50-90% and improve query speed proportionally](https://clickhouse.com/docs/best-practices/select-data-types?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide).

For example, if a numerical field represents states (0-10), use UInt8 (1 byte) instead of Int64 (8 bytes) - saving 7 bytes per row. Across billions of rows, this compounds to massive savings.

These savings directly translate to query speed - smaller data means less I/O, better cache utilization, and faster processing.

#### **For temporal data, choose appropriate precision:**

- Use **Date** instead of **DateTime** if you don't need time components

- Use **DateTime** instead of **DateTime64** if second-level precision suffices

- For DateTime64, choose the minimum precision: DateTime64(3) for milliseconds rather than DateTime64(6) for microseconds

---

## Optimisation 5: Pre-compute with Materialised Views

[Incremental materialized views](https://clickhouse.com/docs/materialized-view/incremental-materialized-view?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide) automatically maintain aggregates and transformations as data arrives:

```sql
CREATE MATERIALIZED VIEW daily_sales_mv
ENGINE = SummingMergeTree()
ORDER BY (date, product_id)
AS SELECT
    toDate(timestamp) AS date,
    product_id,
    sum(amount) AS total_sales,
    count() AS transaction_count
FROM sales
GROUP BY date, product_id;
```

#### **Benefits:**

- Automatically updates on INSERT to source table

- Pre-aggregates data at insert time

- Query the view for instant results on pre-computed data

- Perfect for dashboards and recurring reports

---

## Optimisation 6: Filter earlier with PREWHERE

The PREWHERE clause applies filters before reading all columns:

```sql
SELECT user_name, order_total, product_details
FROM orders
PREWHERE order_date = '2024-01-01'  -- Filter first, read only matching rows
```

#### **How it works:**

1. Read only PREWHERE condition columns (order_date)

2. Evaluate condition

3. Read remaining SELECT columns only for matching rows

#### **When effective:**

- WHERE condition filters many rows (high selectivity)

- Filter columns are small compared to SELECT columns

- Filtering on timestamps/IDs while selecting large text fields

**Performance example:** Reduced data read from 27.67 GB to 16.28 GB (41% less), improving query time from 96s to 61s (36% faster).

ClickHouse often automatically applies PREWHERE optimization. You can make it explicit for guaranteed behavior.

---

## Optimisation 7: Use approximates where appropriate

For analytical queries where approximate results are acceptable, use [approximate functions](https://clickhouse.com/docs/sql-reference/aggregate-functions/reference?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide):

```sql
-- Exact (slow, memory-intensive):
SELECT COUNT(DISTINCT user_id) FROM logs

-- Approximate (10-100× faster):
SELECT uniq(user_id) FROM logs
```

#### **Why approximate functions are faster:**

- **Exact COUNT DISTINCT:** Requires maintaining hash set of all unique values (O(n) memory)

- **Approximate (uniq):** Uses HyperLogLog probabilistic data structure (~12 KB fixed memory)

#### **Trade-offs:**

- **Error rate:** Typically 1-2% for uniq()

- **Performance:** 10-100× faster on large datasets

- **Memory:** Fixed memory usage regardless of cardinality

#### **Variants:**

- **uniq()**: Basic approximate distinct count

- **uniqCombined()**: Can be merged across distributed queries

- **uniqExact()**: Exact count when precision required

#### **When to use:**

- Large datasets (millions+ rows)

- High cardinality columns

- Dashboards and reports where approximate is acceptable

- Real-time analytics where speed > precision

---

## Optimisation 8: Denormalisation

[ClickHouse performs best with denormalized data](https://clickhouse.com/docs/data-modeling/denormalization?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide). Consider denormalization for read-heavy analytical workloads:

#### **Normalized (requires JOIN):**

```sql
-- orders table + customers table
SELECT o.order_id, c.customer_name, c.customer_email, o.total_amount
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
```

#### **Denormalized (no JOIN):**

```sql
-- Single table with customer details repeated
SELECT order_id, customer_name, customer_email, total_amount
FROM orders_denorm
```

#### **Trade-offs:**

- **Benefit:** Much faster queries (no hash table construction, single table scan)

- **Cost:** More storage (repeated data)

- **Mitigation:** Columnar compression reduces storage overhead significantly

#### **When to denormalize:**

- Read-heavy workloads

- JOIN on high-cardinality columns

- Customer/dimension details relatively stable

---

## Advanced optimisations for certain cases

### Projections

[Projections](https://clickhouse.com/docs/data-modeling/projections?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide) solve the limitation of having only one physical sort order per table by maintaining multiple copies with different orderings.

#### **Two types of projections:**

**1. Reordering projections** - Alternative sort orders:

```sql
ALTER TABLE events
ADD PROJECTION proj_by_user (
    SELECT * ORDER BY (user_id, event_time)
);
```

**2. Aggregating projections** - Pre-computed aggregates:

```sql
ALTER TABLE events
ADD PROJECTION proj_daily_stats (
    SELECT date, COUNT(), SUM(amount)
    GROUP BY date
);
```

#### **Key benefits:**

- ClickHouse automatically selects the best projection at query time

- [Multiple projections can be used to apply filters within a single query](https://clickhouse.com/blog/clickhouse-release-25-06#combining-projections-in-one-query?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide)

- Atomically updated with base table

- Transparent to queries - no code changes needed

#### **Trade-offs:**

- Projections incur some storage overhead, but [can use the `_part_offset` virtual column to avoid duplication](https://clickhouse.com/blog/clickhouse-release-25-06#smarter-storage-with-_part_offset?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide)

- Aggregating projections have minimal storage overhead

- Additional INSERT overhead for maintaining projections

### Hash long strings for grouping and aggregation

String operations are expensive. [When grouping by long strings, hash them to fixed-size integers](https://clickhouse.com/docs/community-wisdom/performance-optimization?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide):

```sql
-- SLOW: Grouping by variable-length strings
SELECT url, COUNT(*) FROM logs GROUP BY url

-- FAST: Grouping by fixed 64-bit integers
SELECT cityHash64(url) AS url_hash, COUNT(*) FROM logs GROUP BY url_hash
```

Performance improvement: 5-10× faster for strings longer than 20-30 characters. The hashing overhead is worth it when string comparison is the bottleneck - typically for long strings or when producing many distinct groups.

### Partitioning

[Partitioning](https://clickhouse.com/docs/partitions?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide) is primarily for data lifecycle management, not a typical optimization step.

#### **Key rules:**

- Keep low cardinality: 10-100 partitions (NOT thousands)

- Use for tables > 10 GB with clear retention needs

- Partition by month/week for time-series data

#### **Benefits:**

- Easy data expiration (DROP PARTITION)

- Tiered storage support

- Can help time-based queries

**Warning:** Too many partitions severely degrades performance.

### Data skipping indexes

[Skip indexes](https://clickhouse.com/docs/optimize/skipping-indexes?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide) are secondary indexes - use them as a last resort after optimizing primary key and projections.

#### **Main types:**

- **minmax**: Range queries on semi-sorted columns

- **set**: Low cardinality equality checks

- **bloom_filter**: High cardinality equality checks

- **tokenbf_v1**: Word search in text

- **ngrambf_v1**: Substring matching

#### **When effective:**

- Filtering columns not in primary key

- Sparse value searches (needles in haystacks)

- Column values correlated with sort order

**Critical:** Skip indexes only work when the indexed column correlates with your ORDER BY columns. Without correlation, they add overhead with no benefit.

### Multi-pass grouping for memory-intensive aggregations

It is possible to break GROUP BYs into multiple passes, which can help when you have very large GROUP BY operations. This is only applicable when the inner GROUP BYs matches the table's sorting key. The setting `optimize_aggregation_in_order` must be enabled.

```sql
-- Single-pass (may exhaust memory):
SELECT product_id, SUM(revenue) AS total_revenue
FROM orders
GROUP BY product_id

-- Multi-pass (more memory-efficient):
SELECT
    product_id,
    SUM(revenue) AS total_revenue
FROM (
    SELECT
        product_id,
        order_id,
        SUM(total_amount) AS revenue
    FROM orders
    GROUP BY product_id, order_id  -- Finer granularity, table's ORDER BY is `product_id, order_id`
)
GROUP BY product_id  -- Final aggregation
```

#### **Why this helps:**

- Intermediate results are smaller

- Better memory management

- Prevents disk spilling

- Can leverage primary index multiple times

### Using dictionaries as in-memory lookup tables

[Dictionaries provide an efficient alternative to JOINs for reference data](https://clickhouse.com/docs/dictionary?utm_medium=clickhouse&utm_source=engres&ref=query_optimisation_guide):

```sql
CREATE DICTIONARY product_dict (
    product_id UInt64,
    product_name String,
    category String
) PRIMARY KEY product_id
SOURCE(PostgreSQL('host:5432', 'db', 'products'))
LAYOUT(HASHED())
LIFETIME(300);  -- Refresh every 5 minutes
```

#### **Query using dictionary:**

```sql
SELECT
    order_id,
    dictGet('product_dict', 'product_name', product_id) AS product_name,
    total_amount
FROM orders
```

#### **Benefits:**

- O(1) or near-O(1) lookup times (data in RAM)

- No JOIN overhead (no hash table construction)

- Can pull from external sources (PostgreSQL, MySQL, files)

- Automatic refresh at specified intervals

#### **When to use:**

- Small to medium reference tables (<10-100 million rows)

- Data that changes infrequently

- Product catalogs, user profiles, geographic mappings

---

## Monitoring and debugging performance

Before optimizing, you need visibility into query execution. ClickHouse provides rich instrumentation for identifying bottlenecks.

### The system.query_log table

ClickHouse automatically logs every query execution to `system.query_log`:

```sql
SELECT
    type,
    event_time,
    query_duration_ms,
    query,
    read_rows,
    formatReadableSize(memory_usage) AS memory,
    normalized_query_hash
FROM system.query_log  -- Use clusterAllReplicas() for clusters
WHERE type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY query_duration_ms DESC
LIMIT 10
FORMAT VERTICAL
```

**Tip:** Use `normalized_query_hash` to identify expensive query patterns executed repeatedly rather than one-off ad-hoc queries. Optimizing a query run 10,000 times daily has 10,000× more impact than optimizing a query run once.

### EXPLAIN statements reveal execution plans

**EXPLAIN indexes = 1** shows which parts and granules ClickHouse selects:

```sql
EXPLAIN indexes = 1
SELECT AVG(total_amount)
FROM trips
WHERE pickup_datetime >= '2024-01-01'
  AND pickup_datetime < '2024-02-01'

-- Output shows:
-- Granules: 5061/40167  ← Only reading 12.6% of data!
```

The granule ratio is your key metric. Full table scans show all granules selected.

### Trace logging for deep analysis

For detailed execution information:

```sql
SET send_logs_level = 'trace';
```

This reveals binary search steps, index mark selection, and granule processing.

### Optimization methodology: Measure, change one thing, measure again

Always optimize iteratively. When testing, disable the filesystem cache to measure true performance:

```sql
SET enable_filesystem_cache = 0;
```

Optimize for the worst case (cold cache) to ensure consistent performance, but also validate with cache enabled since that's the typical production scenario.

### Finding slow queries

```sql
SELECT
    query,
    query_duration_ms,
    formatReadableQuantity(read_rows) AS rows_read,
    formatReadableSize(read_bytes) AS data_read,
    normalized_query_hash
FROM system.query_log
WHERE type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY query_duration_ms DESC
LIMIT 20
```

Focus on queries with:

- High execution time

- High read_rows (potential full table scans)

- High memory_usage (potential optimization opportunities)

- High normalized_query_hash frequency (regularly executed expensive queries)

---

## Summary: The path to optimized queries

ClickHouse achieves extraordinary performance through architectural choices fundamentally different from traditional databases. Every optimization strategy stems from understanding these core principles:

**Columnar storage** means reading only necessary columns dramatically reduces I/O. Always SELECT specific columns.

**Sparse primary indexes** enable skipping massive data volumes when queries filter by ORDER BY columns. Primary key design is your highest-leverage optimization point - it can improve performance by 100× or more.

**Granule-based storage** means ClickHouse reads data in 8,192-row blocks. Proper indexing allows skipping billions of rows by excluding irrelevant granules.

**Physical data ordering** determined by ORDER BY creates data locality. Lower-cardinality-first ordering maximizes both filtering efficiency and compression.

#### **Optimization priority:**

1. **Primary key (ORDER BY) design** - Biggest impact, can improve queries 100×+

2. **Data type optimization** - Nullable avoidance, LowCardinality, right-sizing

3. **Projections** - For multiple query patterns

4. **Materialized views** - Pre-compute expensive aggregations

5. **Query patterns** - Filter early, select only needed columns

6. **Skip indexes** - Last resort, test thoroughly

#### **The iterative process:**

1. Identify slow queries via system.query_log

2. Understand execution with EXPLAIN

3. Change ONE variable at a time

4. Measure with cache disabled

5. Focus on frequently executed queries for maximum ROI

Success requires understanding not just what to optimize, but why optimizations work at the architectural level. This knowledge lets you analyze any query pattern, understand the bottleneck, and apply the appropriate technique confidently. ClickHouse's unique architecture rewards this understanding with performance that often surprises even experienced database practitioners - queries over billions of rows completing in milliseconds when properly optimized.
