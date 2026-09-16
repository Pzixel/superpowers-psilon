# `renew_leases_batch` — design

Dragonfly `df-v1.34.0` (`redis_version:7.4.0` compatibility), `EVALSHA` Lua script.
Renews up to 64 mailbox leases in one atomic, single-shard operation.

## 1. Data model

| Key | Type | Layout |
|---|---|---|
| `{t}:leases` | hash | field = `mailbox_id`, value = `"<token>:<deadline_ms>"` |
| `{t}:due` | zset | member = `mailbox_id`, score = `deadline_ms` |

Both keys carry the same `{t}` hash tag, so Dragonfly maps them to **one shard**. That is
a deliberate constraint of this design, not an accident — see §5 and §7.

`deadline_ms` is Unix epoch milliseconds. The token is opaque and **may contain colons**;
the value is split on the *last* colon (`^(.*):(%d+)$`), so `"a:b:c:1789529260618"` parses
as token `a:b:c`.

## 2. KEYS / ARGV contract

```
EVALSHA <sha> 2 {t}:leases {t}:due  <ttl_ms>  <mailbox_id> <token> [<mailbox_id> <token> ...]
```

* `KEYS[1]` — leases hash. Required.
* `KEYS[2]` — due zset. Required. Must share the hash tag of `KEYS[1]`.
* `ARGV[1]` — `ttl_ms`: positive integer, milliseconds.
* `ARGV[2..]` — `2*N` arguments, `N` in `1..64`, alternating `mailbox_id`, `token`.

Both keys must be declared in `KEYS`. Dragonfly enforces this; with `numkeys=0` the server
replies (verified):

```
ERR script tried accessing undeclared key, key: {t}:leases
```

Do **not** work around it with `#!lua flags=allow-undeclared-keys` — that flag makes the
script run as a global transaction and removes the single-shard fast path.

The script takes **no clock argument**. Time comes from `redis.call('TIME')` on the server,
so all callers share one clock and a client with a skewed clock cannot extend or kill a
lease. `TIME` is legal in Dragonfly scripts (verified) because Dragonfly replicates *effects*
(the resulting `HSET`/`ZADD`), not the script body.

### Rejected inputs (no writes performed)

| Condition | Reply |
|---|---|
| `#ARGV < 3` | `ERR ... need ttl_ms and at least one (mailbox_id, token) pair` |
| `(#ARGV-1)` odd | `ERR ... ARGV after ttl_ms must be (mailbox_id, token) pairs` |
| `N > 64` | `ERR ... batch of 65 exceeds max 64` |
| `ttl_ms` not a positive integer | `ERR ... ttl_ms must be a positive integer` |
| stored value not `<token>:<digits>` | `ERR ... corrupt lease value for field '<mailbox_id>'` |

All validation happens before any write, and the corrupt-value check aborts the whole call,
so a rejected batch is a no-op. Corruption is treated as a bug in the writer, not as a
per-item status: silently reporting `missing` would hide data loss.

## 3. Reply shape

A flat array of length `1 + 2*N`:

```
[1]      now_ms                  (integer) the single server timestamp used for this batch
[2i]     status for item i       (string)  "renewed" | "token_mismatch" | "expired" | "missing"
[2i+1]   new deadline_ms         (integer) the renewed deadline, or 0 if not renewed
```

Items are returned in request order, one entry per request item (duplicates included).
Example (`m1` ok, `m2` wrong token, `m3` already past, `m4` token contains colons, `m9` absent):

```
1) (integer) 1789529230618
2) "renewed"          3) (integer) 1789529260618
4) "token_mismatch"   5) (integer) 0
6) "expired"          7) (integer) 0
8) "renewed"          9) (integer) 1789529260618
10) "missing"        11) (integer) 0
```

Flat, not nested: one RESP array instead of `N+1`, and every element is a scalar, so clients
read it with a single `for` loop. `now_ms` is returned so the caller can compute its own
local-vs-server skew and schedule the next renewal without a second round trip. Deadlines are
millisecond epochs (`< 2^53`), so they survive the Lua-number → RESP-integer conversion exactly.

## 4. Renewal semantics

Per item, evaluated against one `now_ms` for the whole batch:

| Stored state | Result |
|---|---|
| field absent | `missing`, no write |
| stored token ≠ caller token | `token_mismatch`, no write |
| token matches, `stored_deadline <= now_ms` | `expired`, no write |
| token matches, `stored_deadline > now_ms` | `renewed`, new deadline `now_ms + ttl_ms` |

* The new deadline is `now + ttl_ms`, **not** `old_deadline + ttl_ms`: renewal is a sliding
  window anchored on server time, so a slow renewer cannot accumulate lease time.
* Expiry is checked with `<=`: a lease whose deadline equals now is over. It is not
  renewable — recovering it is the acquire path's job, not the renew path's.
* Hash and zset are updated together inside the script's transaction, so the zset score always
  equals the deadline embedded in the hash value. There is no window where a reaper scanning
  `{t}:due` sees a stale score for a live lease.
* One item's rejection never blocks another item's renewal; only malformed input aborts the batch.
* Duplicate `mailbox_id` in one batch is harmless: both entries read the same pre-batch value
  and get the same status and the same new deadline; the later `HSET` field/value pair simply
  overwrites the earlier identical one.

### Explicitly out of scope

The script never creates a lease (`missing` stays missing), never steals one, and never removes
`{t}:due` members for `expired`/`missing` mailboxes. Reaping belongs in the operation that
consumes `ZRANGEBYSCORE {t}:due -inf now`, which must hold the authority to reassign a mailbox.
Mixing reaping into renew would let a renew call by process A delete state owned by process B.

## 5. Why the script is bounded, and how

Dragonfly runs a Lua script inside the shard's transaction, on the shard's fiber. While it
runs, that shard executes nothing else. Dragonfly `v1.34.0` has **no `SCRIPT KILL`** (verified:
`ERR Unknown subcommand or wrong number of arguments for 'KILL'`), so a script that takes a
long time cannot be rescued — it must be *impossible to write* a slow call. Four properties
guarantee that:

1. **Item count is capped in the script, not by convention.** `MAX_ITEMS = 64` is checked
   before any read or write; a 65-item call is rejected with an error and does nothing. The
   cap cannot be bypassed by a buggy or malicious client.
2. **Command count is constant, not `O(N)`.** Whatever `N` is, the script issues at most four
   commands: `TIME`, one `HMGET` with `N` fields, and — only if at least one item renewed —
   one variadic `HSET` and one variadic `ZADD`. No per-item round trip through the Lua/engine
   boundary, so the Lua interpreter overhead is `O(N)` cheap string work, not `O(N)` command
   dispatches. (Verified against `INFO commandstats`: `hmget` and `hset` call counts track
   `evalsha` call count 1:1, not 64:1.)
3. **No unbounded primitives.** No `KEYS`, `SCAN`, `HGETALL`, `ZRANGE`, `SORT`, no loop whose
   bound comes from stored data, no recursion, no `pcall` retry loop. Every loop runs exactly
   `N <= 64` times. `ZADD` is `O(log M)` per member, so per call the worst case is
   `64 * log2(M)` — for a million-member zset that is ~1280 comparisons.
4. **No unbounded allocation.** Peak Lua memory is the `N` field names, `N` stored values, the
   `<=128`-element write argument lists and the `1+2N` reply — all proportional to the request
   the client already sent, never to the size of the stored data.

The `{t}` hash tag keeps the transaction on one shard: Dragonfly takes locks on two keys in
one shard instead of coordinating a multi-shard transaction. That bounds the *blast radius*
(other shards keep serving) but also concentrates load — see §7 item C.

## 6. The script's structure

Read → decide → write, in that order and in that order only:

* `TIME` and one `HMGET` acquire all facts.
* A pure loop over the request turns `(stored value, caller token, now_ms, ttl_ms)` into a
  status per item and accumulates two write-argument lists. It calls nothing.
* Two variadic writes apply the accumulated decisions.

That shape is what makes the cost analysis above checkable by reading 90 lines, and it is why
the same decision table can be unit-tested outside Redis by feeding it the same four inputs.

## 7. How to measure the cost on Dragonfly before shipping

Measured on `dragonflydb/dragonfly@sha256:366e34f4…` (`df-v1.34.0`) in Docker on macOS,
loopback, default flags, 100k seeded leases. These numbers are the *method's output*, not a
production SLO — Docker Desktop's VM inflates both RTT and jitter. Re-run A–F on the target
hardware with production `--proactor_threads`/`--maxmemory` before shipping.

**Setup, once.** Seed a realistic dataset — the cost of `ZADD` depends on zset size and the
cost of `HMGET` on hash encoding, so benchmarking against 10 keys proves nothing:

```
python3 -c "…print HSET {t}:leases m:%012d tok:<deadline> / ZADD {t}:due <deadline> m:%012d…" \
  | redis-cli -p $PORT --pipe          # 100k leases
SHA=$(redis-cli -p $PORT -x SCRIPT LOAD < renew_leases_batch.lua)
```
Always benchmark `EVALSHA`, never `EVAL`: `EVAL` re-parses and re-compiles and measures the
compiler, not the operation.

**A. Correctness first, and it gates the benchmark.** Drive all four statuses plus every
rejected input from §2 against a known fixture and diff `HGETALL`/`ZRANGE … WITHSCORES`
afterwards, asserting the zset score equals the deadline inside the hash value for renewed
items and that non-renewed items are byte-identical to their pre-call state. A fast wrong
script is not shippable.

**B. Uncontended per-call cost — the number that belongs in a capacity model.**
`redis-benchmark -c 1` removes queueing, so latency ≈ RTT + server CPU:

```
for N in 1 8 16 32 64; do
  redis-benchmark -p $PORT -n 20000 -c 1 -r 100000 --csv \
    evalsha $SHA 2 '{t}:leases' '{t}:due' 30000 <N copies of: m:__rand_int__ tok>
done
```

Observed (avg / p95 / p99 ms): `N=1` 0.282 / 0.335 / 0.423 · `N=16` 0.295 / 0.367 / 0.503 ·
`N=64` 0.413 / 0.479 / 0.607. Fit a line: fixed cost ≈ 0.28 ms (almost all loopback RTT),
**marginal cost ≈ 2.1 µs per additional item**. That is the ship/no-ship shape — cost must be
affine in `N` with a small slope. A superlinear curve means an accidental `O(N²)` (typically
string concatenation in the loop, or a per-item `redis.call`).

**C. Server-side CPU, excluding the network.** Take an `INFO commandstats` delta around a
fixed run — Dragonfly reports per-command `usec`:

```
redis-cli -p $PORT INFO commandstats | grep -E 'evalsha|hmget|hset|zadd'   # before
… fixed 20000-call run at N=64 …                                           # after
```

Observed at `N=64`, `c=1`: `Δusec/Δcalls = 5824726/20000 =` **291 µs of server time per call**,
i.e. ~4.5 µs per lease renewed end to end including both writes. Budget that against the
shard's 1 s of wall time per second: 64-item batches at 291 µs cap one shard at ~3.4k calls/s
≈ 220k renewals/s, and every millisecond spent here is a millisecond the shard is not serving
mailbox traffic.

**D. Saturation and hot-shard behaviour — the failure mode this design actually has.**
Repeat B with `-c 32`, `-c 64`, `-c 128` and watch where rps stops rising and p99 starts
climbing linearly (that is queueing, not work):

Observed at `-c 32`: `N=1` 7338 rps p99 8.4 ms · `N=16` 5919 rps p99 8.7 ms · `N=64` 3890 rps
p99 12.5 ms, and `SLOWLOG LEN` climbed to 320 entries (default `slowlog_log_slower_than`
= 10000 µs). Note that per-call `evalsha` time in `commandstats` jumped from 291 µs to ~5.9 ms:
that gap is lock/queue wait on the single `{t}` shard, not script cost. Because every lease
lives under one hash tag, **`renew_leases_batch` does not scale by adding shards or cores** —
it scales by making batches bigger (fewer, fatter calls) or by splitting the tenant across
several `{t}` values. Decide, before shipping, which of those two the product needs, and if it
is sharding by tenant, confirm the p99 above is acceptable for the largest single tenant.

**E. Compare against not using a script.** Run the same workload as a pipelined
`HMGET` + `HSET` + `ZADD` from the client. The script must win on round trips and must be the
only variant that is atomic; if it does not win on latency, the batching, not the Lua, was the
value, and that is worth knowing before adopting a script at all.

**F. Worst legal call, tail only.** Run `N=64` with a fixture where *all 64 renew* (the maximum
write path) against the largest expected `{t}:due`, and read `max_latency_ms` and `SLOWLOG GET`
rather than the average. That single number is the longest this operation can block its shard;
it is the promise §5 exists to keep. Gate the release on it — e.g. reject if max exceeds
~1 ms of server-side time on production hardware — and re-measure it whenever `MAX_ITEMS` or
the zset size assumption changes.

**G. Replication, because `TIME` is non-deterministic.** Attach a replica, run a few thousand
renewals, then compare `HGETALL {t}:leases` and `ZRANGE {t}:due 0 -1 WITHSCORES` digests on
master and replica. This proves the effects-replication assumption in §2 on the actual build
rather than on documentation.

**After shipping**, the same two surfaces are the monitors: `cmdstat_evalsha` `usec_per_call`
(script cost plus queueing on the hot shard) and `SLOWLOG LEN` growth (the tail from F
escaping into production).
