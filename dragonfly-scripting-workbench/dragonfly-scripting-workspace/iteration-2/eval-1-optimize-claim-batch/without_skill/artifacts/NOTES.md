# claim_mailbox_batch.lua — optimization notes

Target: Dragonfly v1.34.0 (`--proactor_threads=4 --cache_mode=false --maxmemory=2048Mi`),
EVALSHA, `candidate_window=1024`, `batch_size=32`, ~1000 due mailboxes, ~2 KB records,
all keys under `{email-stats-inbound}`.

## Result

| script | p50 | mean | min | max |
|---|---|---|---|---|
| original | 67.6 ms | 65.1 ms | 41.2 ms | 84.2 ms |
| optimized | 1.91 ms | 1.92 ms | 1.71 ms | 2.28 ms |

30 timed invocations each (3 warm-up discarded), same container, same seed, alternating runs;
a second alternating pass gave 95.7 ms vs 1.73 ms p50. ~35x.

## Root cause

Dragonfly executes every `redis.call` from a script as a separately scheduled command against
the shard set. Per-call overhead measured here is ~25-30 us. The original script issued about
**3300 `redis.call`s per invocation** for a 1024-candidate window:

* 2 x 1024 `HGET` (mailbox version, lease) — one pair per candidate;
* ~1000 `HGET` on `mailbox_records` — the 2 KB payload was fetched for **every** lease-free
  candidate, even though only the first 32 are ever used (~2 MB copied into Lua per call);
* 32 `HGET` on `lease_receipts` for the request tokens;
* 6 writes per claimed mailbox (5 `HSET` + `ZADD`) = 192;
* 3 `HGET` on the descriptor hash.

The optimized script issues about **27** for the same workload.

## Changes (each one, and why it cannot change behaviour)

All replaced reads are pure; the decision loop still walks candidates in the same order and
returns at exactly the same points, so the reply and the post-state are unchanged. This is
verified by a 35-case differential test (`difftest.py`) that compares reply *and* full dump of
all 14 keys between the original and the optimized script on identical seeds.

1. **`hmget_all` helper** — chunked `HMGET` (256 fields/call) returning a sparse array with
   `nil` for absent fields, i.e. the exact result shape of the per-field `HGET` it replaces.
   Dragonfly returns `false` for a missing field in Lua; the helper maps that to `nil` so all
   downstream `if not value` tests keep their original meaning.
2. **Request-token receipts**: 32 `HGET KEYS[8]` -> 1 `HMGET`. The recovery loop still iterates
   slots 1..batch_size in order, so the first `PROTOCOL receipt` / `receipt_token` /
   `receipt_lease_mismatch` / `record_missing` returned is the same one. The interleaved
   `HGET KEYS[7]` lease read in that loop is left per-slot (it only runs when a receipt exists,
   i.e. on the rare recovery path).
3. **Descriptor**: 3 `HGET KEYS[11]` -> 1 `HMGET storage_format state generation`. `generation`
   is now read unconditionally instead of only inside the `mutable_v2` branch — a pure read with
   no observable effect. Branch order and all `FENCED`/`PROTOCOL` outcomes are untouched.
4. **Candidate versions and leases**: 2048 `HGET` -> 8 chunked `HMGET` against `versions_key`
   and `KEYS[7]`.
5. **Pre-pass for secondary lookups**: after the leases are parsed, one pass decides which
   candidates the main loop will need a record or a receipt for, and those are fetched with
   chunked `HMGET` on `KEYS[13]` / `KEYS[8]`. Safety points:
   * the pre-pass stops collecting at the first malformed lease, which is precisely where the
     main loop can no longer advance (it returns `PROTOCOL lease` there);
   * the record set is exactly `{candidate : version present and (no lease or lease expired)}`,
     i.e. the candidates for which the original called `HGET KEYS[13]`. The
     `PROTOCOL record_missing` condition therefore still covers candidates **beyond**
     `batch_size` (verified by case `record_missing_beyond_batch`);
   * the receipt set is the lease tokens of candidates that carry a lease — the union of the
     stale-receipt read (missing version + expired lease) and the old-receipt read (takeover).
     Duplicate tokens are fine for `HMGET`.
   * Prefetching can read a few entries the main loop never consumes when it returns early
     (`CLEANUP_REQUIRED`, `PROTOCOL ...`). Those are reads, so no state or reply changes.
6. **Record payloads are no longer fetched one-by-one**: the same ~1000 values now arrive in 4
   `HMGET`s instead of ~1000 `HGET`s. Value volume is unchanged versus the original, so memory
   behaviour is no worse; only the call count drops.
7. **Batched cleanup writes**: the `removals` loop now issues chunked `ZREM`/`HDEL` (128
   members per call) and the `rescores` loop a chunked variadic `ZADD`. Inside a script the
   whole body is atomic, and each mailbox appears at most once in the due zset, so grouping
   these per-key is not observable.
8. **Batched claim writes, guarded**: when none of the claimed candidates had a previous lease
   (`any_old_lease == false`, the steady-state production case), the 32x6 single-field writes
   become 6 variadic calls (`HSET KEYS[7|8|9|10|14]`, `ZADD KEYS[6]`). When at least one
   candidate *is* a takeover, the original per-candidate interleaving of
   `delete_matching_poll_start` / `HDEL lease_receipts` / `HDEL lease_records` with the `HSET`s
   is kept verbatim. That guard exists because a batched write path would move all deletions
   before all writes, which is only provably equivalent when there is nothing to delete — e.g.
   a (pathological) request token equal to an earlier candidate's old lease token would
   otherwise survive in `lease_records` instead of being deleted.
9. **Micro-cleanups with no protocol effect**: `#ARGV` token validation now also caches the
   tokens in a table (needed for `HMGET`); `tostring(deadline)` is computed once instead of
   4x per claim; `#claimable` / `#candidates` are replaced with counters.

Not changed: the `TIME`-derived `now`, `earliest_due()` (`ZRANGE ... WITHSCORES`), the fence
order, the descriptor/legacy versions-key selection, the recovery short-circuit, all status
strings, the `RESOLVED` padding with `UNUSED` slots, and the `RETRY_IMMEDIATELY`/`NOT_DUE`
tail conditions.

## What was deliberately *not* done

* Shrinking the candidate window or stopping the scan at `batch_size` claims: the scan has
  observable side effects (`removals`, `rescores`) and feeds `saw_active`, which drives
  `RETRY_IMMEDIATELY`. Truncating it would change recovery semantics.
* Replacing the per-candidate record existence check with nothing (or with `HEXISTS`): an
  intermediate version used `HEXISTS` for candidates past the batch, which kept semantics but
  still cost ~968 calls (~28 ms measured). The `HMGET` pre-pass removes that cost entirely.
* Any `redis.setresp`, `redis.breakpoint`, script flags or key-set changes: KEYS/ARGV, reply
  protocol and the declared key set are identical.

## Reproducing

```
docker run -d --name eval3-ns-df -p 0:6379 \
  docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f415c22983dc1c4a1d575fa2d9c22b9a3998a9934bf1cc6d16c17695db \
  --proactor_threads=4 --cache_mode=false --maxmemory=2048Mi
PORT=$(docker port eval3-ns-df 6379 | head -1 | cut -d: -f2)
python bench.py    $PORT <script.lua> 30          # latency, 1000 mailboxes x ~2 KB, window 1024
python difftest.py $PORT <orig.lua> <opt.lua>     # 35-case reply + post-state equivalence
```
