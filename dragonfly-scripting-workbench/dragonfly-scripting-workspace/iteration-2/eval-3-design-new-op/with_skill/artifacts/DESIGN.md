# renew_leases_batch — design

Renew up to 64 leases in one atomic operation on Dragonfly v1.34.0.
Script: `renew_leases_batch.lua` (numkeys pinned to 2; treat the arity as part of the script
identity, i.e. deploy it as `renew_leases_batch-2.lua`).

## 1. KEYS / ARGV contract

```
EVALSHA <sha> 2 {t}:leases {t}:due  <ttl_ms>  <mailbox_id> <token> ...   (n <= 64 pairs)
```

| slot | meaning |
|---|---|
| `KEYS[1]` | `{t}:leases` — hash, field `mailbox_id`, value `'<token>:<deadline_ms>'` |
| `KEYS[2]` | `{t}:due` — zset, member `mailbox_id`, score `deadline_ms` |
| `ARGV[1]` | `ttl_ms`, positive integer; new deadline is `server_now_ms + ttl_ms` |
| `ARGV[2i]`, `ARGV[2i+1]` | `mailbox_id`, `token` for item `i = 1..n`; `n` may be 0 |

Key order is fixed and documented in the script header. Both keys must carry the same `{t}` tag:
they are written in one transaction, and under `--cluster_mode=yes` one slot per script is a
correctness requirement, not tuning. No key name is built by concatenation inside the script —
undeclared keys are a hard error by default and, when enabled, promote the script to a GLOBAL
transaction that stalls every shard.

### Decision rules (pure, evaluated over the HMGET snapshot and one server clock reading)

For each item, in this order:

1. no hash field → `missing`;
2. stored token ≠ supplied token → `token_mismatch` (checked **before** expiry: "you are not the
   owner" is the actionable answer, and an expired-and-stolen lease must not read as merely
   expired);
3. stored deadline `<= now_ms` → `expired` (boundary is inclusive: a lease that dies exactly now is
   dead);
4. otherwise → `renewed`, new deadline `now_ms + ttl_ms` written to **both** the hash field
   (`token` preserved verbatim) and the zset score.

`now_ms` comes from one `TIME` call — server clock, read once, applied to the whole batch, so all
items in a batch share one deadline and the reply is internally consistent.

The zset write is a plain `ZADD` (upsert), not `ZADD XX`: the hash is the authority for "a lease
exists", so a renewed lease whose `due` member drifted away is repaired rather than silently left
out of the due index.

Duplicate `mailbox_id` in one batch is allowed and harmless: both items see the same pre-image and
report the same status and deadline, and the two writes are identical.

### Reply shape

Flat array, arity exactly `1 + 2n`, positional — item `i` of the reply corresponds to ARGV pair `i`;
mailbox ids are not echoed back because the caller already holds the list in order.

```
[1]              server_now_ms          decimal string
[2i]             status                 integer   (i = 1..n)
[2i+1]           deadline_ms            decimal string
```

| status | meaning | `deadline_ms` |
|---|---|---|
| `1` | renewed | new deadline = `now_ms + ttl_ms` |
| `2` | token_mismatch | stored deadline, unchanged |
| `3` | expired | stored deadline, unchanged |
| `0` | missing | `'0'` |

Why this shape: a Lua array reply truncates at the first `nil`, drops string-keyed fields and
truncates floats, so the reply keeps constant arity, uses integer status codes instead of
`error_reply` on the hot path, uses `'0'` as the absence sentinel, and returns millisecond
timestamps as **strings** so nothing depends on float→int conversion. No `cjson` anywhere: encoding
is shard CPU time on a single-threaded shard, and there is nothing here that a flat array cannot say.

### Error protocol

`redis.error_reply` is reserved for protocol violations the caller cannot act on, and every one of
them is raised **before the first write**, so a rejected batch is a clean no-op:

- `ARGV[1]` not a positive integer;
- odd ARGV tail (not `(id, token)` pairs);
- `n > 64`; the caller's over-sized batch is rejected, never silently truncated;
- a stored lease value that does not match `'<token>:<digits>'` — that is a bug in whoever wrote the
  hash, and reporting it as `missing`/`expired` would hand a lease to a second owner.

Token parsing uses `string.match(v, '^(.*):(%d+)$')`: the greedy `.*` splits on the **last** colon,
so tokens that themselves contain `:` round-trip correctly (verified: `ns:tokE` renews).

Note for callers: buffered writes (`redis.acall`, see §3) are flushed when the script returns, even
when it returns an `error_reply` — measured on df-v1.34.0. That is why validation precedes the
writes rather than relying on a late error to undo them. Scripts do not roll back here.

## 2. Placement and execution regime

Two declared keys sharing one hashtag. On default flags that is **regime (a), io-coordinated**:
measured on df-v1.34.0 (`--proactor_threads=4`), one invocation moves
`eval_io_coordination_total` by +1 and leaves `eval_shardlocal_coordination_total` unchanged; a
single-key script on the same server moves the shardlocal counter instead. A shared `{hashtag}`
does **not** by itself co-locate keys on default flags — only `--lock_on_hashtags` makes the tag the
placement/lock unit.

Consequence for the design: the unit of cost is the **number of `redis.call`** (~27 µs each in that
regime on the skill's lab), not the bytes moved. Hence the script is written to issue a constant
number of calls.

`--lock_on_hashtags` would buy the shard-local path (~1 µs/call) but serialises unrelated work
behind that tag's shard. It is a deployment-wide trade-off, not a property of this script: consider
it only if the number of distinct `{t}` tags is at least the shard count, or the whole workload's
script CPU fits one core, and then measure both arms at the real concurrency. `{t}` is also a heat
unit — if one tenant owns one tag and one tenant is 90% of the traffic, that shard is the ceiling.

`--!df flags=` is not used: `allow-undeclared-keys` promotes the script to a GLOBAL transaction and
`disable-atomicity` removes the single-shard fast path; both are pessimisations here, and `no-writes`
is parsed and ignored.

## 3. Why the script is bounded, and how

Dragonfly has **no script timeout, no `SCRIPT KILL`, no BUSY reply**: a script that runs long pins
its shard thread until the process is killed. Bounding is a correctness requirement, not tuning.

- **Input bound.** `MAX_ITEMS = 64` is a constant in the script, not a caller hint. `n > 64` is
  rejected with an error. There is no "more available" marker because this operation does not scan —
  the work is exactly the caller's list, so the list length *is* the bound.
- **Constant call count.** `TIME` + `HMGET` + (`HSET` + `ZADD` when at least one lease renews) =
  **2 to 4 `redis.call`, independent of n**. The naive shape — `HGET`/`HSET`/`ZADD` per item — is
  `1 + 3n` = up to 193 calls for the same batch.
- **No unbounded `unpack`.** The largest splice is `ZADD` with 2×64 = 128 arguments, far under the
  measured Lua ceiling (8163 fields unpack, 8164 is a stack overflow). At 64 items no chunking loop
  is needed; if the cap were ever raised past ~1000, chunk `HMGET`/`HSET`/`ZADD` at 256–1000 and the
  call count becomes `ceil(n/chunk)` per verb, still bounded.
- **No loop whose trip count comes from the keyspace.** The only loops run `1..n`. Nothing iterates
  the hash, the zset, or a scan cursor, so a tenant with a million leases costs exactly as much as a
  tenant with 64.
- **Bounded output.** Reply arity is `1 + 2n <= 129` short strings/integers. No `cjson.encode`, no
  large blob rewrite (a 1 MiB encode+HSET is ~1.9 ms of shard time; 8 MiB is ~15 ms, and overwriting
  a huge field needs old and new resident at once).
- **Bounded per-item Lua work.** One `string.match` and one comparison per item; no allocation
  proportional to anything but `n`.
- **Reads before writes, all reads batched.** One `HMGET` fetches the whole window before any
  decision; the decision loop is pure Lua over that snapshot. This is not a narrowing of any check —
  every item the caller passed is read.
- **Discarded replies are buffered.** The two writes use `redis.acall`: their replies are never
  inspected, and buffering avoids the flush-and-hop that a synchronous call forces (the skill's lab
  measures 28.05 → 2.93 µs/call for discarded writes). Errors are **not** swallowed — a `WRONGTYPE`
  on an `acall` still aborts the script and reaches the client (verified on df-v1.34.0).

Upper bound on shard occupancy per invocation, then, is ~4 coordination hops plus O(64) trivial Lua
steps — a few hundred microseconds, with no input that can make it grow.

## 4. How I would measure its cost on Dragonfly before shipping

Never ship a script change on reasoning alone; the same workload measured twice on default flags
differs 1.3–2.2× with co-tenancy, so arms must be back-to-back on one server.

1. **Lab.** `scripts/lab.sh up` (add `--single` to get a 1-proactor node, which separates "slow
   script" from "slow because it fans out"). Pin df-v1.34.0 by digest, `--proactor_threads=4`,
   `--cache_mode=false`, `--maxmemory=2048Mi`. Confirm with `lab.sh status`.
2. **Seed + spec.** A seed script that builds `{t}:leases` and `{t}:due` with a realistic tenant size
   (e.g. 10k leases so the hash is not a toy), plus the 64 `(id, token)` pairs, and prints
   `{"keys": [...], "argv": [...], "ignore_reply_indices": [...]}`. Include the adversarial mix the
   contract cares about, not just the happy path: renewable / wrong-token / already-expired /
   absent, and a batch where **nothing** renews (that is the 2-call path).
   `ignore_reply_indices` = `[1]` (server clock) plus `2i+1` for every renewable item; assert the
   derived invariant instead — `deadline - now == ttl_ms` for every `status == 1`.
3. **Regime, authoritatively.** `scripts/bench_script.py` prints the
   `eval_io_coordination_total` / `eval_shardlocal_coordination_total` delta per invocation. Expect
   `io 1.00/invocation` on default flags. Do not infer this from `dragonfly --helpfull` (it prints a
   *new* binary's compiled defaults) and note that `CONFIG GET lock_on_hashtags` returns empty on
   v1.34.0 — read the running server's process arguments if the flag matters.
4. **Variant comparison on identical seeded state.**
   `scripts/bench_script.py --spec spec.json --seed seed.py --reseed --compare naive.lua renew_leases_batch.lua`.
   `--reseed` is mandatory: renewal is not idempotent across the expiry boundary, so without it the
   second call onwards measures a different code path. `--compare` asserts the replies are
   byte-identical outside `ignore_reply_indices` and exits 2 otherwise — two scripts that answer
   differently are not two versions of one script. Report **p50 and p99**; a change that improves p50
   and worsens p99 is common.
5. **Sweep the two axes that can actually move:** batch size 1 / 8 / 32 / 64 (should be near-flat —
   that is the claim this design makes, so it is the claim to falsify) and hit ratio 0% / 50% / 100%
   renewable (0% drops the two writes entirely).
6. **Server-side view under the real concurrency.** `scripts/script_latency.py --sha <sha> --watch`
   while N worker processes renew concurrently; read percentiles as **bucket upper bounds**, not
   precise percentiles. Caveat found here: the histogram is cumulative and, on df-v1.34.0,
   `SCRIPT FLUSH` did **not** reset an existing sha's samples — take a before/after difference or
   restart the node between arms.
7. **Flag arm.** If `--lock_on_hashtags` is on the table, run both arms back-to-back in one session
   at realistic tag cardinality and concurrency, and look at the co-tenant's latency, not only this
   script's.
8. **Ship gate.** Regime counter as expected, replies identical under `--compare`, p50/p99 flat in
   batch size, and no regression in the co-tenant arm. `SCRIPT LOAD` once per worker process and call
   `EVALSHA`, recovering from `NOSCRIPT` exactly once (detect both the typed error and the raw
   `NOSCRIPT` prefix); inside a pipeline send `EVAL`, because NOSCRIPT cannot be recovered
   mid-pipeline.

### Smoke numbers already taken (not the ship gate)

Throwaway container, df-v1.34.0 by digest, `--proactor_threads=4 --cache_mode=false
--maxmemory=2048Mi`, macOS Docker, one sequential `redis-cli` client, 64 leases all renewable, 220
invocations, **server-side** `SCRIPT LATENCY` (µs, bucket-interpolated median):

| variant | calls/invocation | median | max |
|---|---|---|---|
| `renew_leases_batch.lua` (batched) | 4 | ~201 | 618 |
| per-item `HGET`/`HSET`/`ZADD` | 193 | ~6482 | 9724 |

Both reported `eval_io_coordination_total +1` per invocation. This is a sanity check of the shape
(≈32× on this box, consistent with the call count being the unit of cost), **not** a shipping
number: it is server-side, single-client, no co-tenancy, and not produced by `bench_script.py`.
Client p50/p99 from step 4 are what carry the decision.

## 5. Alternatives considered and rejected

- **Caller-supplied `now_ms`** — saves one hop (25% of the call budget), but lease safety would then
  depend on every worker's clock. The operation is defined against server time; `TIME` stays.
- **`HGETALL` instead of `HMGET`** — cost becomes the tenant's whole lease set, which is exactly the
  unbounded shape this design exists to avoid.
- **Per-item calls** — 193 calls vs 4; measured ≈32× worse locally, same reply.
- **Deleting expired leases / repairing `{t}:due` for non-renewed items** — not part of the required
  behavior, and it would make the write set depend on state rather than on the caller's batch.
  Expiry reaping belongs in its own bounded operation.
- **`ZADD XX`** — would refuse to repair a missing due-index entry for a lease that legitimately
  renewed.
- **A sentinel-valued "more available" marker** — meaningless: this operation does not scan.
- **Native command instead of Lua** — there is none for compare-token-and-swap-deadline across a
  hash and a zset, and the operation must be atomic across both keys, so Lua is the right tool here
  (unlike, say, rate limiting, where `CL.THROTTLE` beats a hand-written sliding window).
