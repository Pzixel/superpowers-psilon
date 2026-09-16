# Transcript — optimize `claim_mailbox_batch.lua` (no-skill arm, run-1)

## Files read

1. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/evals/inputs/claim_mailbox_batch.lua`
2. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/evals/inputs/claim_mailbox_batch_CONTRACT.md`

No other repository files were read.

## Commands, in order

### 1. Output dir + throwaway server
```
mkdir -p .../without_skill/run-1/outputs
docker run -d --name eval3-ns-df -p 0:6379 \
  docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f4...695db \
  --proactor_threads=4 --cache_mode=false --maxmemory=2048Mi
docker port eval3-ns-df 6379   ->  0.0.0.0:32824
```

### 2. Wrote `outputs/bench.py`
Seeds the production shape: 1000 mailboxes (`%08x` hex ids), legacy layout (no descriptor
hash, versions in `KEYS[5]`), ~2 KB JSON records in `KEYS[13]`, all 1000 due in the past, no
leases, fences satisfied (`master_replid` read from `INFO replication`). Each round resets
leases/receipts/owners/poll_starts/lease_records, re-arms all due scores, refreshes
`last_reconciliation_started_ms`, then times one `EVALSHA` with 32 fresh UUID tokens,
`candidate_window=1024`, `batch_size=32`. 3 warm-up rounds discarded.

### 3. Baseline
```
bench.py 32824 <evals/inputs/claim_mailbox_batch.lua> 20
first reply head: ['RESOLVED', '1789540529466', 1789540469465, '32'] claimed: 32 len: 164
n=20 min=54.26ms p50=69.09ms p90=73.45ms max=86.06ms mean=68.39ms
```

### 4. First optimized version (batched HMGET for versions/leases/receipts/descriptor,
`HEXISTS` instead of a 2 KB `HGET` for candidates past the batch, batched writes)
```
n=20 min=26.31ms p50=30.81ms p90=32.10ms max=36.71ms mean=30.50ms
```

### 5. Isolating the residual cost — variant with the `HEXISTS` branch stubbed to `false`
```
n=15 min=1.63ms p50=2.33ms p90=2.40ms max=2.49ms mean=2.21ms
```
=> the ~968 remaining per-candidate `HEXISTS` calls cost ~28 ms. Confirms the bottleneck is
`redis.call` count (~25-30 us per call in Dragonfly's script path), not data volume.

### 6. Final optimized version
Replaced the per-candidate record/receipt lookups with a pre-pass that collects the fields the
main loop will need and fetches them with chunked `HMGET`.
```
bench.py 32824 outputs/claim_mailbox_batch.lua 20
first reply head: ['RESOLVED', '1789540673825', 1789540613824, '32'] claimed: 32 len: 164
n=20 min=1.66ms p50=1.89ms p90=2.08ms max=2.22ms mean=1.93ms
```

### 7. Equivalence: `outputs/difftest.py`
35 scenarios; for each one the DB is flushed and re-seeded identically for the original and the
optimized script, and both the reply and a full dump of all 14 keys are compared (clock-derived
fields normalized; `CLAIMED` deadlines asserted `> now`).

Scenarios: happy path; window smaller than due set; `NOT_DUE`; missing due key; all leases live
(rescore); removal of a versionless unleased candidate; `CLEANUP_REQUIRED`; orphan lease with no
receipt; takeover of an expired lease (with and without an old receipt); recovery via existing
receipts (live + expired mixed); recovery with missing capture; recovery lease mismatch;
malformed lease; malformed receipt; missing record inside the batch; missing record *beyond* the
batch; four fence failures + non-numeric and future reconciliation timestamps; `mutable_v2`
descriptor (committed / applying / bad format / state-only / generation mismatch / empty
versions); five argument-validation rejections; batch 32 against 5 due mailboxes.

```
... ok (35 lines) ...
ALL 35 CASES MATCH
```

### 8. Final A/B, two alternating passes, 30 timed rounds each
```
original  n=30 min=41.20ms p50=67.58ms p90=72.49ms max=84.17ms mean=65.05ms
optimized n=30 min=1.71ms  p50=1.91ms  p90=2.14ms  max=2.28ms  mean=1.92ms
original  n=30 min=56.77ms p50=95.71ms p90=114.36ms max=150.65ms mean=96.51ms
optimized n=30 min=1.57ms  p50=1.73ms  p90=2.01ms  max=2.25ms  mean=1.78ms
```

### 9. Teardown
```
docker rm -f eval3-ns-df
```

## Final answer

The script was call-bound, not data-bound: it issued ~3300 `redis.call`s per invocation
(2 x 1024 candidate `HGET`s, ~1000 x 2 KB record `HGET`s, 192 write calls, 32 receipt `HGET`s).
The optimized version issues ~27 by batching every per-candidate read into chunked `HMGET`s via
a pure pre-pass, and by grouping the cleanup and claim writes per key (the claim-write batching
is guarded so that takeovers keep the original delete/write interleaving). Reply protocol, key
set, fence order and recovery semantics are unchanged, confirmed by a 35-case reply +
post-state differential test.

p50 **67.6 ms -> 1.91 ms** (mean 65.1 -> 1.92 ms), same container and seed.

Deliverables:
- `/Users/pzixel/.../without_skill/run-1/outputs/claim_mailbox_batch.lua`
- `/Users/pzixel/.../without_skill/run-1/outputs/NOTES.md`
- `/Users/pzixel/.../without_skill/run-1/outputs/bench.py`
- `/Users/pzixel/.../without_skill/run-1/outputs/difftest.py`
