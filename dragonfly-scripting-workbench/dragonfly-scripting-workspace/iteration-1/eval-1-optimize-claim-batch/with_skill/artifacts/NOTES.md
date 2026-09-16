# `claim_mailbox_batch.lua` — optimization notes

Target: Dragonfly **v1.34.0**, `--proactor_threads=4 --cache_mode=false --maxmemory=2048Mi`, no other
flags. Production call: `candidate_window=1024`, `batch_size=32`, ~1000 due mailboxes, ~2 KB records,
all 14 keys under `{email-stats-inbound}`.

**Reply protocol and recovery semantics are unchanged.** Every terminal form
(`RESOLVED`/`NOT_DUE`/`RETRY_IMMEDIATELY`/`CLEANUP_REQUIRED`/`FENCED`/`PROTOCOL`), every reason string,
the order in which competing failures are reported, and the resulting keyspace are identical — see
*Verification*.

## 1. Regime first: this is the io-coordinated regime

`bench_script.py` reports `eval_io_coordination_total +1.00`, `eval_shardlocal_coordination_total +0.00`
per invocation, for both the old and the new script. A shared `{hashtag}` does **not** co-locate keys on
default flags, so every synchronous `redis.call` is a coordinator→shard hop (~27 µs measured in the skill
lab, `[lab Q5]`). The cost of this script was therefore **the number of `redis.call`s**, not its payload
bytes or its Lua.

Counted per invocation on the production shape (1024 candidates, 32 claims):

| | old | new |
|---|---|---|
| `redis.call` round trips | ~3 300 | ~20 |
| `tx_shard_polls` delta (measured, one invocation) | **4 268** | **24** |
| `eval_squashed_flushes` delta | 0 | 8 |

That single ratio is the whole optimization; everything below is how it was obtained without moving the
contract.

## 2. Changes, one by one

### 2.1 Receipt-recovery scan: 32 `HGET` → 3 `HMGET`
`HMGET KEYS[8] <32 request tokens>`, then one `HMGET KEYS[7]` for the mailbox ids those receipts name and
one `HMGET KEYS[14]` for the captures of the non-expired ones.
*Safe because*: these are pure reads with no side effects, so performing them eagerly cannot change state.
The decisions still run in a second loop over slots `1..batch_size` in the original order and apply the
original checks in the original order (`receipt` → `receipt_token` → `lease` → `receipt_lease_mismatch` →
expiry → `record_missing`), so the *first* failure reported is the same one. A `bad_receipt` flag keeps
the `PROTOCOL receipt` reply for a malformed receipt even when no valid receipt exists, which is the case
the naive "only enter the block if `has_receipt`" shortcut would have lost.
Prefetching a capture for a slot that a later check rejects reads a field the old script would not have
read — a read, not an effect.

### 2.2 Fences: 4 `GET` → 1 `MGET`
`MGET KEYS[1] KEYS[2] KEYS[3] KEYS[4]`. All four keys are declared in `KEYS`, so no undeclared-key
promotion to a GLOBAL transaction. A missing key arrives as `false`, exactly as `GET` returned, and
`tonumber(fences[4] or '')` reproduces `tonumber(redis.call('GET', KEYS[4]) or '')` including the
"missing ⇒ `catalog_not_fresh`" behaviour. Checks stay in their original order, so the FENCED reason is
unchanged.

### 2.3 Catalog descriptor: up to 3 `HGET` → 1 `HMGET`
`HMGET KEYS[11] storage_format state generation`. `generation` is now always fetched and only *compared*
in the branch that compared it before.

### 2.4 Candidate scan: 2 048 `HGET` + up to 1 024 `HGET` → 6 chunked `HMGET`
- `HMGET <versions_key> <candidates…>` and `HMGET KEYS[7] <candidates…>`, chunked at 512 fields
  (`unpack` into `redis.call` breaks at 8 163 arguments, `[lab Q9]`; 512 is the measured-variant chunk).
- A pure classification pass then decides, per candidate, which `KEYS[13]` record field and which
  `KEYS[8]` stale-receipt token the decision pass can need; those are fetched with two more chunked
  `HMGET`s.
- The decision pass is the original loop verbatim, reading prefetched values instead of calling.
*Safe because*: the original performed **no writes inside this loop** — `removals`, `rescores` and
`claimable` were accumulated and applied afterwards. So the loop was already a pure function of values
read during it, and hoisting those reads cannot change which terminal reply (`PROTOCOL lease`,
`CLEANUP_REQUIRED`, `PROTOCOL receipt`, `receipt_lease_mismatch`, `record_missing`) is produced first.

**The whole-window `record_missing` check was deliberately kept.** The old script verified
`HGET KEYS[13] <mailbox>:<version>` for *every* eligible candidate in the window, not only for the ≤32 it
claims, and answers `PROTOCOL record_missing` if any of them is missing. Narrowing that to the claimed
subset is a contract change for the data owner, not an optimization we may take unilaterally; the skill
lab isolates its value at only 1.1–1.8x (`[lab Q3, Q10]`) while the batching above is the bulk of the
win. Scenario `record_missing_past_bound` (record for candidate #40 removed while 32 claimable candidates
sort ahead of it) pins this: both scripts answer `PROTOCOL record_missing`.

### 2.5 Writes: 192+ calls → 8 calls, and they are `redis.acall`
- `ZREM KEYS[6] <removals…>`, `HDEL KEYS[9] <removals…>`, `ZADD KEYS[6] <score member …>` for rescores.
- Per claim the five `HSET`s and the `ZADD` are accumulated into six multi-field/multi-member calls, plus
  two batched `HDEL`s for the receipts/captures of the leases being replaced.
- All of them use `redis.acall`, whose reply the script discards anyway; `acall` buffers instead of
  flushing (28.05 → 2.93 µs/call measured in the skill lab, `[lab Q5]`). `eval_squashed_flushes +8`
  confirms the buffer is used.
*Safe because*: multi-field `HSET`/`HDEL` and multi-member `ZADD`/`ZREM` apply exactly the same field→value
mapping as the per-item calls (mailbox ids come from a zset, so they are unique; a repeated request token
would be last-write-wins in both versions). Atomicity is unchanged — same declared key set, no `--!df`
flags, still one multi-transaction.

### 2.6 One trailing synchronous read on every path
The buffered writes must be flushed before the script returns. `earliest_due()` (`ZRANGE … WITHSCORES`) is
a synchronous call the script already made on two of its three exits; it is now computed **once, after the
writes, on all three**, and the value is passed into `resolved_response` instead of being fetched there.
*Safe because*: the old script also evaluated `earliest_due()` after the writes (inside `resolved_response`
or at the `NOT_DUE` tail), so the value it observes is the same. The only behavioural delta is one extra
`ZRANGE` on the `RETRY_IMMEDIATELY`-because-`not saw_active` path, whose reply does not contain the value.
The `removals` and `rescores` scenarios exercise exactly that path and confirm the buffered `ZREM`/`HDEL`/
`ZADD` are applied.

### 2.7 Removed the `poll_starts` read-and-delete
`delete_matching_poll_start(mailbox_id, old_lease.token)` did `HGET KEYS[10] <mailbox>` and conditionally
`HDEL`ed the field — and two statements later the same field was unconditionally
`HSET` to `<request_token>:<now>`. A field that is deleted and then rewritten in the same atomic script is
indistinguishable from a field that is only rewritten, and each mailbox id occurs at most once in
`claimable` (candidates come from a zset). So this pair (up to 64 calls per invocation) was removed. The
`expired_lease_claim` scenario seeds pre-existing `poll_starts` entries for mailboxes whose leases are
being taken over and asserts the final hash is identical.

### 2.8 Deletes before inserts within the claim batch
The old loop interleaved per slot: delete slot *i*'s stale receipt/capture, then write slot *i*. The batched
version issues both `HDEL`s before the five `HSET`s. These touch different fields unless a *fresh request
token* collides with an *old lease token* — and the recovery scan has already proven every request token is
absent from `KEYS[8]`, on top of the tokens being freshly generated UUIDv4s. Not a supported input.

### 2.9 Mechanical Lua
`local rcall/racall/unpack` aliases, `table.insert` → indexed writes, reply table filled by index. Shard CPU
only; worth little in this regime but free.

### Explicitly *not* done
- **No `--!df flags=`**: `allow-undeclared-keys` promotes the script to a GLOBAL transaction and
  `disable-atomicity` removes the fast path — both are slower, not faster (`[lab Q5]`).
- **No narrowing of any whole-window check** (see 2.4).
- **No change to the bound**: `candidate_window`/`batch_size` still come from ARGV and still bound the work,
  which on Dragonfly is a correctness property (no script timeout, no `SCRIPT KILL`).
- **`--lock_on_hashtags` not recommended here** and not part of this deliverable: it would buy the
  shard-local path, but the skill's rule is to consider it only when distinct hashtags ≥ shard count. This
  workload has **one** tag and 4 proactor threads, so it would serialise the entire keyspace behind one
  shard; and after the batching above the script issues ~20 calls, so the remaining hop cost is small.

## 3. Verification

Local Dragonfly, same image digest, same flags:
`docker run -d --name eval-1-ws-df -p 0:6379 --memory 3g <digest> --proactor_threads=4 --cache_mode=false --maxmemory=2048Mi --dbfilename=dump`
(`df-v1.34.0`, `threads=4`; container torn down after the run).

### 3.1 Latency, production shape (1024 candidates, batch 32, ~2 KB records, 14 keys/1 hashtag)

`bench_script.py --spec spec.json --seed seed.py --reseed --compare baseline… optimized…`
(seed re-run untimed before every call, so both are measured on the first-call path; `--compare` asserts
byte-identical replies outside the clock fields *before* reporting). 100 timed iterations, 10 warm-up.

| run | script | p50 µs | p95 µs | p99 µs | mean µs | server `SCRIPT LATENCY` avg |
|---|---|---|---|---|---|---|
| 1 | baseline | 101 009.8 | 114 760.0 | 116 420.8 | 102 549.8 | 102 182 µs |
| 1 | **optimized** | **7 350.5** | **11 718.7** | **12 456.0** | **7 471.6** | **6 450 µs** |
| 2 | baseline | 68 614.2 | 73 400.7 | 84 398.8 | 66 246.2 | 65 783 µs |
| 2 | **optimized** | **3 906.7** | **6 462.2** | **8 854.9** | **4 086.2** | **3 299 µs** |

p50 speed-up **13.7x** (run 1) / **17.6x** (run 2); p99 **9.3x** / **9.5x**. The two runs are the same
comparison repeated; absolutes move with host co-tenancy (a second eval container was active during run 1),
which is why both runs are reported and the ratio comes from back-to-back arms, never from mixing runs.
Raw output: `bench-run2.txt` (run 1 is quoted in the table and in `transcript.md`).

Coordination counters, both scripts: `io=1.00 shardlocal=0.00` per invocation → regime (a) confirmed,
unchanged by the rewrite. Hop volume, one invocation each: `tx_shard_polls` 4 268 → 24 (`counters.txt`).

### 3.2 Equivalence: 32 scenarios, reply **and** final keyspace

`differential.py` builds each scenario twice from `FLUSHALL`, runs one script on each copy, and compares
the reply *and* a dump of all 14 keys (clock readings compared within 400 ms, everything else exactly).

```
32/32 scenarios identical (reply + final keyspace)
```

Covered: happy path (1024 and 64 candidates), `batch_size=1`, `candidate_window=4`, mutable_v2 descriptor
(`KEYS[12]` versions), descriptor `applying` / bad format / state-only / generation mismatch, all four
FENCE reasons plus a future `last_reconciliation`, `NOT_DUE`, `RETRY_IMMEDIATELY` via removals and via
rescores, `CLEANUP_REQUIRED`, claim over an expired lease with stale receipt/capture/poll_start, live-lease
mix, `record_missing` beyond the batch bound, recovery→`CLAIMED`, recovery→`RECEIPT_EXPIRED`, recovery with
missing capture, receipt/lease mismatch, receipt token mismatch, malformed receipt alone and after a valid
one, malformed lease, and the three `PROTOCOL arguments` forms.

### 3.3 Reproduce

```
docker run -d --name eval-1-ws-df -p 0:6379 --memory 3g \
  docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f415c22983dc1c4a1d575fa2d9c22b9a3998a9934bf1cc6d16c17695db \
  --proactor_threads=4 --cache_mode=false --maxmemory=2048Mi --dbfilename=dump
PORT=$(docker port eval-1-ws-df 6379 | head -1 | cut -d: -f2)
python3 -m venv .venv && ./.venv/bin/pip install redis
./.venv/bin/python <skill>/scripts/bench_script.py --host 127.0.0.1 --port $PORT \
  --spec spec.json --seed seed.py --reseed \
  --compare baseline_claim_mailbox_batch.lua claim_mailbox_batch.lua
./.venv/bin/python differential.py 127.0.0.1 $PORT baseline_claim_mailbox_batch.lua claim_mailbox_batch.lua
docker rm -f eval-1-ws-df
```

## 4. Files here

| file | what |
|---|---|
| `claim_mailbox_batch.lua` | the optimized script (drop-in; same 14 KEYS, same ARGV, same replies) |
| `baseline_claim_mailbox_batch.lua` | unmodified copy of the current production script, for A/B |
| `differential.py` | 32-scenario reply + keyspace equivalence harness |
| `seed.py`, `spec.json` | production-shape seed and bench spec (1024 mailboxes, ~2 KB records, batch 32) |
| `bench-run2.txt`, `counters.txt` | raw measurement output |

Note for the caller: the SHA changes, so reload it once at worker boot (`SCRIPT LOAD` + cached
`EVALSHA`, NOSCRIPT-reload-once). Nothing else on the client side changes.
