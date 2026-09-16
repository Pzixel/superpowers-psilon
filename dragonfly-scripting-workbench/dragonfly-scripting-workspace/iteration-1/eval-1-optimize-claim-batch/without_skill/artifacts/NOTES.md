# `claim_mailbox_batch.lua` optimization notes

Target: Dragonfly v1.34.0 (`docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f4…`),
`--proactor_threads=4 --cache_mode=false --maxmemory=2048Mi`, single instance, all keys under
`{email-stats-inbound}`. Production call shape: `candidate_window=1024`, `batch_size=32`,
~1000 due mailboxes, ~2 KB records.

## Result

| measurement (30 samples each, A/B interleaved) | original | optimized | factor |
|---|---|---|---|
| claim against a freshly seeded 1000-mailbox due set, p50 | 64.60 ms | 1.81 ms | **35.7x** |
| same, mean / min / p90 / max | 59.57 / 32.48 / 67.07 / 82.85 ms | 1.84 / 1.52 / 1.97 / 3.03 ms | ~32x |
| 30 consecutive claims draining one seeded 1000-mailbox pool, total | 1083.25 ms | 43.77 ms | **24.7x** |
| server commands executed per invocation (from `INFO stats:total_commands_processed`) | 3234 | 22 | **147x fewer** |

Raw data: `bench_results.json`, `command_counts.json`. Reproduce with `bench.py` / `cmdcount.py`
(`DF_PORT=<host port> python3 bench.py`; helpers in `harness.py`).

## Why the original was slow

Per invocation with 1000 due mailboxes it issued ~3200 separate `redis.call`s:

* 32 `HGET` on `lease_receipts`, one per request token (line 89);
* 1000 `HGET` on `mailbox_versions` + 1000 `HGET` on `leases`, one pair per candidate (184–185);
* ~1000 `HGET` on `mailbox_records` — the loop fetched the **~2 KB record of every eligible
  candidate**, not just the 32 it could claim (215);
* 6 write calls per claimed mailbox plus one `ZADD`/`ZREM`/`HDEL` per rescored/removed mailbox
  (247–276).

Each `redis.call` from Lua is a full command dispatch (argument marshalling, key hashing, shard
hop, reply conversion into a Lua value). At ~20 µs of amortized cost that alone accounts for the
observed ~60 ms, and it runs inside the script's exclusive transaction, so it also blocks the
shards holding `{email-stats-inbound}` for that whole time.

## Changes (all behaviour-preserving)

The decision logic, the order in which failures are detected, and the reply construction are
character-for-character the same; only *how the facts are fetched and the effects applied* changed.

1. **Batched reads via `HMGET`/`MGET` (helper `hmget_all`, lines 12–32).**
   * request receipts: 32 `HGET` -> 1 `HMGET`;
   * fences `KEYS[1..4]`: 4 `GET` -> 1 `MGET` (all four keys share the hashtag and are declared
     keys, so this is slot-safe);
   * descriptor `storage_format`/`state`/`generation`: 3 `HGET` -> 1 `HMGET`;
   * candidate versions and candidate leases: 2000 `HGET` -> 2 x ceil(n/400) `HMGET`;
   * candidate records and stale receipts: one `HMGET` batch each.
   Safety: a missing hash field is returned as `false` by `HMGET` exactly as by `HGET`, and every
   test in the script is `if not x`, so `false` and `nil` behave identically. Reads have no side
   effects, so prefetching values for candidates the original would never have reached (because it
   returns early on the first corrupt row) cannot change any reply — the *decision* pass still walks
   candidates in the original order and returns on the first offending one. This is why the script
   is structured as “prefetch pass (no returns, no effects) -> decision pass (identical to the
   original)”. The prefetch pass derives exactly the same lookup set the original would perform:
   record field `mailbox_id:version` for every candidate with a version and no live lease, and the
   stale-receipt lookup for every candidate with an expired lease.
   * `record_missing` detection is deliberately **not** made lazy: the original validates the record
     of *every* eligible candidate, not just the 32 it claims, so the optimized version still reads
     them all (in 3 batched calls instead of ~1000). Fetching only the claimed 32 would be faster
     still (~2 MB less copied) but would change when `{'PROTOCOL','record_missing'}` is reported,
     i.e. recovery semantics; it was rejected for that reason.

2. **Batched writes (helpers `call_chunked`, `call_pairs_chunked`, lines 34–68).**
   * removals: n x (`ZREM` + `HDEL`) -> 1 `ZREM` + 1 `HDEL` with n members/fields;
   * rescores: n x `ZADD` -> 1 variadic `ZADD score member …`;
   * claims: 5 x 32 `HSET` + 32 `ZADD` -> 5 variadic `HSET` + 1 variadic `ZADD`;
   * stale receipt/capture deletions: grouped into one `HDEL` per key.
   Safety: the script already ran as one atomic unit, and the field/member sets involved are
   disjoint across groups (removals have no version, rescores hold a live lease, claims hold a
   version and no live lease; mailbox ids come from a zset so they are unique), so regrouping the
   writes yields exactly the same final state. Batches are chunked at 400 arguments to keep
   `unpack` and the argument vector bounded regardless of `candidate_window`.
   The one ordering hazard — a deletion of an old lease token that is also a request token being
   written in the same batch — is handled explicitly by `written_slot` (lines 404–447): the delete
   is skipped when the same token is written by an *earlier* claim slot, which is precisely the
   net effect of the original's sequential delete-then-write interleaving. (In practice phase 1
   guarantees no request token exists in `lease_receipts` when the claim path runs, so this is
   belt-and-braces.)

3. **Dropped the `poll_starts` read-modify-delete for claimed mailboxes.**
   The original called `delete_matching_poll_start(mailbox_id, old_lease.token)` (`HGET` + maybe
   `HDEL` on `KEYS[10]`) and then *unconditionally* `HSET KEYS[10] mailbox_id <new value>` for the
   same field two lines later. The `HDEL` is therefore invisible: field value after the pair is the
   new value either way. Removing it saves up to 64 calls and cannot change observable state.
   (Note this only applies on the claim path, where the overwrite always follows; no other
   `poll_starts` deletion exists in the script.)

4. **Micro-level, no semantic content:** `table.insert` replaced by explicit index writes in
   `resolved_response` and in the accumulation loops; `tostring(deadline)`/`tostring(now)` hoisted
   out of the claim loop; request tokens materialized once into `request_tokens`.

Not changed: `earliest_due()` still uses `ZRANGE … WITHSCORES` and returns `earliest[2]` verbatim
(Dragonfly returns that score as an integer reply element, and the client decodes it; rewriting it
to `ZRANGEBYSCORE`/`tostring` would alter the wire type of reply element 3). `TIME` is still the
single source of `now`. `candidate_window` is still applied by `ZRANGEBYSCORE … LIMIT 0 window`,
and the full candidate list is still scanned — stopping early once 32 claimables are found would
skip removals/rescores and the `CLEANUP_REQUIRED` / `PROTOCOL` detections that live further down
the list, i.e. it would change recovery semantics.

## Correctness evidence

`difftest.py` runs 30 scenarios; for each one it seeds the state, executes the **original** script,
captures the reply plus a full dump of all 14 keys, restores the same seed, executes the
**optimized** script, and compares reply *and* resulting state (timestamps normalized relative to
`now`, since the two runs observe different server clocks).

Scenarios: happy 200-candidate claim; mixed pool (removals, rescores, re-claim over expired leases
with and without old receipts); 1000-candidate pool with 450 removals / 500 rescores (exercises the
400-argument chunking on `HMGET`, `ZREM`, `HDEL`, `ZADD`); `CLEANUP_REQUIRED`; receipt recovery
(`CLAIMED` from capture + `RECEIPT_EXPIRED` + `UNUSED` slots); duplicate request tokens;
`NOT_DUE`; `RETRY_IMMEDIATELY`; all four `FENCED` fences plus `catalog_mutation_in_progress` and
descriptor-generation mismatch; `mutable_v2` descriptor (versions read from `KEYS[12]`);
`PROTOCOL` for `schema_version`, `arguments` (bad TTL, empty token), `receipt`, `receipt_token`,
`receipt_lease_mismatch`, `lease`, `record_missing`, `catalog_descriptor` (bad format, state
without format); `batch_size=1`; `candidate_window=5`; empty due set.

Result: **30/30 identical replies and identical post-state** (`FAILS 0`).

Verification command (with a Dragonfly of the pinned digest listening on `$DF_PORT`):

```
DF_PORT=<port> python3 difftest.py   # -> 30 x "ok", "FAILS 0"
DF_PORT=<port> python3 bench.py      # -> bench_results.json
```
