# `claim_mailbox_batch.lua` — optimization notes

Measured on Dragonfly **df-v1.34.0** (image digest `sha256:366e34f4…95db`) in Docker with the production
flags `--proactor_threads=4 --cache_mode=false --maxmemory=2048Mi` and nothing else, 14 keys under
`{email-stats-inbound}`, `candidate_window=1024`, `batch_size=32`, ~2 KB records, 1024 due mailboxes.

## Result

| script | n | p50 µs | p95 µs | p99 µs | mean µs |
|---|---|---|---|---|---|
| original | 100 | **101224** | 120421 | **170109** | 100034 |
| optimized | 100 | **3289** | 6318 | **8645** | 3621 |

p50 **30.8x**, p99 **19.7x**. Server-side `SCRIPT LATENCY` for the two shas: avg 99455 µs -> 2966 µs.
`bench_script.py --compare` asserted the two replies byte-identical (164 fields, only the 33 TIME-derived
positions ignored) before reporting. Raw output: `bench_result.txt`.

## Why it was slow (regime first)

Both variants report `eval_io_coordination_total +1.00` and `eval_shardlocal_coordination_total +0.00` per
invocation: the script is **io-coordinated**. The shared `{email-stats-inbound}` hashtag does *not*
co-locate the 14 keys without `--lock_on_hashtags`, so every synchronous `redis.call` costs a
coordinator->shard hop (~27 µs measured on this lab class of host). The original issues roughly
`2*1024 + 1024 + 32*6 + …` ≈ **3300+ calls** per invocation; the rewrite issues about **35**. The dominant
term was call count, not CPU or bytes — which is why the fix is batching, not trimming work.

## Every change, and why it is safe

1. **Candidate metadata: 2 x 1024 `HGET` -> chunked `HMGET` (256/chunk).** Versions (`KEYS[5]`/`KEYS[12]`)
   and leases (`KEYS[7]`) for the whole window are now fetched in 4+4 calls. Missing fields come back as
   Lua `false`, which every predicate in the script already treats exactly like the `false` a missing
   `HGET` returned.
2. **Records: per-candidate `HGET KEYS[13]` -> chunked `HMGET`.** The `record_missing` check is still
   performed for **every** candidate in the window that has a version and a free/expired lease, not only
   for the ≤32 that get claimed. Narrowing that check would change the contract for inputs where the
   invariant does not hold, so it was deliberately left alone (it is an owner decision worth ~1.1–1.8x on
   its own, i.e. small next to the batching).
3. **Receipts: per-token `HGET KEYS[8]` -> chunked `HMGET`,** both in the recovery prologue (batch_size
   tokens in 1 call) and in the scan (all lease tokens seen, in 1 call).
4. **Two-pass scan instead of read-inside-decide.** Pass 1 only *decides which reads the original would
   have issued* and never returns; pass 2 replays the original's per-candidate logic in the original
   candidate order and returns the first failure. Because reads have no side effects, issuing a few reads
   the original would have skipped (after an early return) cannot change any reply: the first
   `PROTOCOL …` / `CLEANUP_REQUIRED` reported is still the same one, for the same candidate.
   `CLEANUP_REQUIRED` still returns *before* any write, exactly as before.
5. **Fences: 4 `GET` -> one `MGET`, 3 descriptor `HGET` -> one `HMGET`.** The fences are still evaluated in
   the original order with the original comparisons, so the same `FENCED …` reason wins. The extra
   `generation` field read for the legacy layout is discarded.
6. **Writes: 192+ per-item calls -> ~10 multi-field calls, via a pending-state table.** Instead of
   emitting writes inside the loop, the script accumulates the *final* state per key (`{set, del}` with
   last-write-wins per field, and `due_add`/`due_del` per zset member) and then flushes one `HDEL` + one
   `HSET` per hash and one `ZREM` + one `ZADD` on `KEYS[6]`. This reproduces the sequential writes exactly,
   including the contrived case where a later iteration deletes a field an earlier iteration wrote (the
   pending table resolves that the same way a sequential replay would). Ordering *across* keys is
   irrelevant because the script performs no read of a key after writing it — the one apparent exception,
   `delete_matching_poll_start`'s `HGET KEYS[10]`, is hoisted to a single `HMGET` issued *before* any
   write: every claimed `mailbox_id` is distinct (zset members) and the original only ever wrote
   `poll_starts` for the mailbox it was processing, so no earlier write could have changed the value a
   later iteration read.
7. **`redis.acall` for the hash writes whose replies are discarded** (buffered/squashed instead of one
   flush per call). The `ZREM`/`ZADD` on `KEYS[6]` stay synchronous `redis.call` because the reply path
   reads the zset back via `earliest_due()`; correctness there must not depend on when the async buffer
   flushes.
8. **Chunking at 256 fields** (and 256 field/value pairs) keeps every `unpack` far below the Lua stack
   ceiling (~8163 arguments), so the script cannot blow up as the window grows. The loop is still bounded
   by `candidate_window`/`batch_size` from ARGV — there is no script timeout or `SCRIPT KILL` on
   Dragonfly, so that bound is a correctness property and it was preserved.

Not changed: the reply protocol (shape, order, status codes, `tostring` formatting), the argument
validation and its error order, the fence set and their reasons, the recovery/`RESOLVED` semantics, the
`RETRY_IMMEDIATELY`/`NOT_DUE` decision, the KEYS arity and order, and which keys are written.

## Verification

1. `bench_script.py --spec … --seed … --reseed --compare orig.lua new.lua` — `--reseed` re-seeds before
   every call (untimed), so both variants are measured on the real claim path rather than on the
   nothing-left-to-claim second-call path, and `--compare` fails the run outright if the replies differ.
   Replies were identical and the coordination counters matched (io 1.00/invocation for both).
2. `differential_paths.py` (in this directory) runs 14 seeded scenarios covering every reply path —
   `RESOLVED` happy path, receipt recovery (active and expired), reclaim of an expired lease with and
   without a receipt, poll-start token mismatch, removals + rescores, `CLEANUP_REQUIRED`,
   `PROTOCOL record_missing`, `PROTOCOL lease`, `NOT_DUE`, `RETRY_IMMEDIATELY`, `FENCED`, and the
   `mutable_v2` descriptor layout — and compares, for each, **the reply and a full dump of all 14 keys**
   after the call (clock-derived values normalised). All 14 scenarios: reply and resulting database state
   identical between the original and the rewrite.

## Not done, on purpose

- **`--lock_on_hashtags`** would move this script to the shard-local regime, but the workload has exactly
  one hashtag against 4 shards, so it would serialise all of this tag's work onto one shard while the other
  three idle; the flag is only worth considering when distinct tags are at least the shard count. It is
  also a server-flag change, and the brief fixes the flags. After batching, the remaining ~35 hops are
  ~1 ms of the 3.3 ms anyway.
- **`--!df flags=…`** is not an optimization here: `disable-atomicity` and `allow-undeclared-keys` both
  remove the single-shard fast path (the latter promotes the script to a global transaction).
- **Bounding the record reads to `batch_size`** — see change 2; it is a contract change, so it belongs to
  the owner of the data, and it is worth little next to the batching.
