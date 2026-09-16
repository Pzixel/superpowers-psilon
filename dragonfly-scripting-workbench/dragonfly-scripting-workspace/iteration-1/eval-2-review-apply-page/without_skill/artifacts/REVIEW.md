# Review: `apply_new_mutable_mailbox_page.lua` — wasted server work

Target: `evals/inputs/apply_new_mutable_mailbox_page.lua` (705 lines), Dragonfly v1.34.0,
invoked via `EVALSHA`, every key under one hashtag, default flags plus `--proactor_threads=4`.

## Execution model that makes these findings cost what they cost

All keys share the `{email-stats-inbound}` tag, so every key resolves to one shard. Dragonfly
runs one shard per proactor thread, so with `--proactor_threads=4` this entire script — parsing,
`cjson`, pattern matching, and every `redis.call` — executes on **one** of four threads, while
the transaction holds that shard. The other three threads cannot absorb any of it. Consequently:

* Wall-clock cost of the script is a hard serialization point for all catalog traffic on that
  shard; concurrent commands on those keys queue behind it.
* Every `redis.call` from Lua pays Dragonfly's full inner-command path (build the argument
  vector off the Lua stack, command lookup and arity/ACL verification, run it against the shard
  under the already-held transaction, materialize a reply object back into Lua). This is on the
  order of a few microseconds each; it is small per call and ruinous at 8k calls.
* Dragonfly replicates Lua **effects**, i.e. the individual write commands the script executed,
  not the script. Every redundant write is journal bytes, replica bandwidth, and dirtied state
  for snapshotting — not just a local dict operation.

Findings are ordered by expected impact at the documented budgets (`MAX_RECORDS = 256`,
`MAX_GRANTS = 8192`, `MAX_OLD_GRANTS = 8192`).

---

## 1. Per-field `HGET` in the old-grant loop — up to 8192 inner commands (line 453)

```lua
-- line 440
for _, field in ipairs(fields) do
  ...
  local old_payload = redis.call('HGET', KEYS[7], field)   -- line 453
```

This is the single largest source of wasted work. The loop at lines 430–468 runs once per old
grant field across all updated records, bounded by `MAX_OLD_GRANTS = 8192`, and issues one
`HGET` per field.

**Cost on Dragonfly.** 8192 separate inner-command dispatches on one shard thread. The hash
lookup itself is trivial; the dispatch, reply allocation, and Lua/C boundary crossing are not.
At a conservative 3–6 µs per inner call this is 25–50 ms of pure overhead inside a transaction
that is holding the shard, per page. The script already knows how to avoid this: `chunked_call`
(lines 134–150) does exactly this batching with `HMGET` in 256-field chunks and is used five
times elsewhere (lines 339, 354, 403, 410, 421, 422, 513). One `HMGET` of 256 fields costs one
dispatch plus 256 cheap lookups — roughly a 200x reduction in dispatch count (8192 → 32).

**Extra waste layered on top:** line 410 already did `chunked_call('HMGET', KEYS[7], grant_fields)`
for all *new* grant fields. For a typical record update most grants are unchanged, so the same
hash field is read twice — once in the batched form at 410, once individually at 453.

**Refactor shape.** Split the loop into (a) a validation/collection pass that builds
`old_grant_fields` and its dedup set, (b) one `chunked_call('HMGET', KEYS[7], old_grant_fields)`
(or a single batched read over the union of old and new fields, reusing the line-410 results),
(c) a pass that computes `scope_entry` and `old_workspace_counts` from the batched replies.
This is safe: no write has occurred at that point in the script, the script is atomic, and the
ordering contract in the comment at lines 446–452 is about the emitted `HDEL 7` / `ZREM 8`
command list, not about when the read happens.

## 2. Delete-and-immediately-reinsert of unchanged grants (lines 612–615, plus 618, 629–634)

```lua
add_single_commands(commands, 'HDEL', 7, old_grant_fields)   -- 612
add_single_commands(commands, 'ZREM', 8, old_grant_fields)   -- 613
add_paired_commands(commands, 'HSET', 7, grant_rows)         -- 615
add_paired_commands(commands, 'ZADD', 8, membership_rows)    -- 616
```

`old_grant_fields` is *every* grant of every updated record and `grant_rows` is *every* grant of
the new record version. A record version bump that changes one grant out of 32 still emits
`HDEL`+`ZREM` for all 32 and `HSET`+`ZADD` for all 32. The script has already proven at lines
410–415 that any surviving field with an identical payload is byte-identical (otherwise it
returns `record_conflict`), so those four operations are a guaranteed no-op round trip.

**Cost on Dragonfly.** Four effects per unchanged grant instead of zero: two dict erases/inserts
in the grant hash, two skiplist/listpack removals and re-insertions in the membership zset
(key 8 holds every grant across workspaces, so it is a skiplist — `ZREM`+`ZADD` is 2×O(log N)
with node free/alloc), and four journal records replicated to every replica. At 8192 grants that
is up to 32k journalled effects and ~32k skiplist mutations that change nothing. It also inflates
`plan_raw` (finding 4) by the encoding of all four command lists.

**Fix.** Compute the set difference on the `(field, payload, workspace)` triple: only emit
`HDEL 7`/`ZREM 8` for fields absent from the new set or whose workspace changed, and only emit
`HSET 7`/`ZADD 8` for fields that are new or whose payload/score changed. The same applies to the
scope patch pairs built at lines 456–459 and 605–607: a grant whose `scope_entry` member string
is unchanged produces a `ZREM` at line 686 followed by an identical `ZADD` at line 688.
Keep `HDEL 7` and `ZREM 8` adjacent in the surviving list (see "Do not change", item 3).

## 3. Per-workspace `ZCOUNT`, and most of them cannot change the outcome (lines 549–561)

```lua
for _, workspace in ipairs(affected_workspaces) do
  local current = redis.call('ZCOUNT', KEYS[8], workspace, workspace)   -- 553
  ...
  if target == 0 then workspace_deletes[...] = tostring(workspace) end
```

`affected_workspaces` is the union of old and new workspaces, bounded by
`MAX_AFFECTED_WORKSPACES = 4096`. Two separate wastes:

1. **Dispatch count.** Up to 4096 inner commands, same per-call overhead as finding 1.
2. **Logically dead work.** `target = current - removals + new_count`, and the guard immediately
   above rejects `current < removals`. Therefore whenever `new_workspace_counts[workspace] > 0`,
   `target > 0` is guaranteed and `ZCOUNT` cannot influence `workspace_deletes`. The only
   workspaces that can reach zero are those in `old_workspace_counts` with **no** new grants —
   in the steady state (a page that re-writes the same workspaces) that set is empty, so *all*
   4096 `ZCOUNT` calls are pure waste.

**Cost on Dragonfly.** `ZCOUNT` on a large zset is a rank computation at both ends of the range,
O(log N) each, plus dispatch. Cheap individually; 4096 of them on the serialized shard thread is
the same order as finding 1.

**Fix.** Iterate only over `workspace` keys present in `old_workspace_counts` and absent from
`new_workspace_counts`. Note the trade-off explicitly: the `current < removals` corruption guard
(line 555) currently runs for every affected workspace and would then only run for the shrinking
subset. If that guard is load-bearing for the recovery story it should be kept as an explicit,
separately justified check rather than as a side effect of a count the plan does not need.

## 4. Redundant writes of values already proven identical (lines 615, 618–621)

Beyond finding 2, the same "prove it is equal, then write it anyway" pattern applies to records:
`existing_records` (line 403) proves each `record_field → record_json` entry either absent or
identical, yet line 618 `HSET 6 record_rows` writes all of them. Likewise `ZADD 9 workspace_rows`
(line 617) re-adds every new workspace with the score it already has.

**Cost on Dragonfly.** Each is a hash insert that replaces an identical value — allocation plus
free of the value string — and a journal record per command. For 256 records whose JSON may be
tens of kilobytes each, this is megabytes of replication traffic per page for zero state change,
and the same bytes appear a second time inside `plan_raw`.

**Fix.** Only emit rows whose fetched current value differs from the intended value. This does
not weaken the plan: the plan must reproduce the *end state*, and a field already holding the
target value is already in the end state. It does interact with resume — see "Do not change",
item 2 — so the plan must still be replay-safe if a concurrent writer could change those fields
between plan publication and replay. Under the fencing contract the script already relies on
(nothing else may write the catalog while the candidate generation holds the fence), it is.

## 5. Per-grant JSON decode and per-grant pattern construction (lines 79–100, 456, 605)

`scope_entry` is called once per removed grant (line 456) and once per added grant (line 605) —
up to 16384 times per page in delta mode. Each call does:

* `grant_workspace` → `string.match(field, '^(-?%d+):' .. mailbox_id .. ':')`. The pattern is
  **built by concatenation on every call**, allocating a ~70-byte string; Lua 5.1 does not cache
  compiled patterns, so the pattern is re-scanned each time as well.
* a second `string.match` for the public id, with another concatenated pattern;
* `pcall(cjson.decode, payload)` — a full JSON parse of the grant payload, producing a table that
  is used for exactly three fields and then discarded;
* `string.format('%.0f', workspace)` and two string concatenations to build the member.

`grant_workspace` is additionally called during argument validation (line 308) and again at
line 441, so each field's workspace is parsed two or three times.

**Cost on Dragonfly.** This is CPU burned inside the Lua interpreter on the shard thread, plus
garbage for the Lua collector — Dragonfly's interpreter GC runs on that same thread and its
pauses land inside the transaction. `cjson.decode` of 8192–16384 payloads is plausibly the
dominant non-dispatch cost once finding 1 is fixed. Note that the payload has already been
transported and materialized once as an `ARGV` string; decoding it in Lua is the second full pass
over the same bytes, and for adds the caller already knows `workspace_id`, `legacy_grant_id`, and
`mailbox_address` (it built the JSON).

**Fix options, in order of preference:** (a) have the caller pass `mailbox_address` as an extra
argument for adds so `scope_entry` on the add path needs no decode at all — the decode there is
purely a cross-check of data the caller just serialized; (b) hoist the per-mailbox patterns out
of the per-grant loop (one concatenation per record instead of per grant); (c) cache
`grant_workspace` results computed at line 308 on the grant record rather than recomputing.

## 6. Fence and mode reads issued as 8+ single-field commands (lines 113–131, 255–261, 334)

```lua
redis.call('GET', KEYS[1]);  redis.call('GET', KEYS[2])          -- 114,115
redis.call('HGET', KEYS[3], 'storage_format')                     -- 118
redis.call('HGET', KEYS[3], 'state')                              -- 119
redis.call('HGET', KEYS[4], 'mode')                               -- 120
redis.call('HGET', KEYS[4], 'generation') / 'expected_active'     -- 123,124 or 130,131
redis.call('HGET', KEYS[3], 'generation')                         -- 128
redis.call('HMGET', KEYS[4], <3 receipt fields>)                  -- 255
redis.call('HGET', KEYS[4], 'mode')                               -- 334 (re-read of line 120)
```

Nine to ten inner commands to read at most eight values from four keys. `KEYS[4]` alone is opened
four separate times, and `mode` is read twice with an identical result (the script is atomic, so
the second read cannot differ).

**Cost on Dragonfly.** ~8 avoidable dispatches. In absolute terms this is microseconds — but it
is paid on *every* invocation including the `#affected == 0` fast path (lines 373–384), which in
a steady-state feed is likely the most frequent outcome. On that path the script's total inner
command count is roughly ten, so collapsing to `MGET KEYS[1] KEYS[2]` + one `HMGET KEYS[3]` +
one `HMGET KEYS[4]` (fence fields and receipt fields together) roughly halves it.

**Fix.** One `MGET` for the two string fences, one `HMGET` per hash covering every field the
script needs from it, and reuse `mode` from that read at line 334 instead of re-fetching.

## 7. `request_bytes()` scans up to 65k arguments to enforce a budget already spent (lines 102–108, 248–250)

`request_bytes` iterates all of `ARGV` and `KEYS` summing `string.len`. `string.len` is O(1), so
this is ~65k loop iterations plus two `ipairs` iterator setups — perhaps a millisecond.

The deeper waste is that the bytes have already been received, parsed by Dragonfly's protocol
layer, and materialized as Lua strings by the time the check runs. `MAX_REQUEST_BYTES` can only
reject work after paying for it; it protects the *write* side, not the ingress side. The count
check on the preceding line (`#KEYS + #ARGV + 3 > MAX_REQUEST_ARGUMENTS`) is O(1) and does most
of the job. If the byte budget exists to bound `plan_raw`, it is redundant with the explicit
`MAX_PLAN_BYTES` check at line 675.

**Fix.** Keep the O(1) argument-count check; drop or move the byte scan, and enforce the true
ingress budget client-side or via `proto_max_bulk_len`.

## 8. Avoidable Lua-side copying in the batching helpers (lines 134–150, 152–168, 216–227)

`chunked_call` and `mget_dynamic` build a temporary `chunk` table element by element and then
`unpack` it. `unpack(values, first, last)` takes a range directly, so the copy is unnecessary:
for 8192 fields this is 8192 table stores plus 32 temporary tables for the collector to reclaim,
per call site. `execute_commands` (line 225) does `unpack(command.args)` on tables it does not
own and then discards every reply.

Also `decode_array` (lines 63–71) evaluates `#value` **inside** the loop, twice per iteration in
the worst case; `#` on a table is a border search in Lua 5.1, not a cached field. Hoist it.

Low absolute impact, essentially free to fix.

## 9. `execute_commands` blocks for replies it discards (lines 216–227, 689, 700, 701)

Every write in `commands`, `commit`, and `scope_commands` is issued with `redis.call` and its
reply is thrown away. With default flags Dragonfly executes each inner call synchronously and
builds a Lua reply object that is immediately garbage. Dragonfly supports fire-and-forget inner
calls (`redis.acall`, and the server-side `--lua_auto_async` flag) precisely for this shape.
**Verify availability and exact semantics on 1.34.0 before relying on it**, and note the
behavioural change: errors from an async call surface later, not at the call site. Given that
`execute_commands` currently ignores errors anyway (a failing `redis.call` raises and aborts the
script), the observable contract is close, but this is the one item on this list where the
recovery story deserves a second look before changing anything.

## 10. Sorting and set-materialization passes (lines 497–509, 535–547, 583–587)

Three build-a-set / flatten-to-array / `table.sort` passes over labels, affected workspaces, and
new workspaces (≤4000, ≤4096, ≤4096 elements). `table.sort` is n log n in the interpreter on the
shard thread. This is real but an order of magnitude below findings 1–5, and the sorts buy
byte-stable plan output, which is worth keeping. Listed for completeness, not as a target.

---

## What I would measure to confirm

All measurements against a dedicated Dragonfly 1.34.0 instance with `--proactor_threads=4` and
default flags, driven by a synthetic page generator with knobs for `record_count`,
grants-per-record, fraction of records that are updates, and fraction of grants unchanged within
an update.

1. **Inner-command counts.** Take `INFO ALL` (commandstats section) before and after a fixed run
   of N `EVALSHA` calls and diff `cmdstat_hget`, `cmdstat_hmget`, `cmdstat_zcount`,
   `cmdstat_hdel`, `cmdstat_zadd`, `cmdstat_zrem`, `cmdstat_hset`. First validate on a
   three-line throwaway script that Dragonfly 1.34 counts *inner* script calls in commandstats;
   if it does not, fall back to diffing `total_commands_processed` from `INFO STATS`, or read the
   counts off a replica's journal. Expectation that confirms findings 1 and 3:
   `cmdstat_hget` delta ≈ N × old-grant-count, `cmdstat_zcount` delta ≈ N × affected-workspaces.
2. **Where the time goes.** `usec_per_call` for `cmdstat_evalsha`, plus client-side p50/p99 over
   ≥1000 invocations. Then decompose by running instrumented copies of the script that return
   early at chosen points: (a) right after the fence check, (b) right after the ARGV parse loop
   ends at line 331, (c) right after the old-grant loop ends at line 468, (d) right after
   `cjson.encode(plan)` at line 674. The differences attribute latency to parse/`cjson`
   (finding 5), the `HGET` storm (finding 1), and plan encoding (the recovery cost) respectively.
3. **Scaling shape.** Sweep grants-per-record 1→32 at `record_count = 256` with updates=100%.
   Finding 1 predicts latency linear in total old grants with a slope of several µs per grant;
   after batching, the slope should drop by roughly the ratio of dispatch cost to hash-lookup
   cost. Sweep updates 0% → 100% to isolate the old-grant path from the addition path.
4. **Redundant effects.** Attach a replica, run a page in which every grant payload is unchanged
   (version bump only), and measure bytes on the replication link (socket counters or
   `INFO replication` byte counters) plus the `cmdstat_hdel`/`cmdstat_zadd` deltas. Finding 2
   predicts ~4 effects per unchanged grant and a byte volume of roughly 2× total payload size
   (once for the effects, once for the plan blob). After the diff-based fix, unchanged grants
   should produce zero effects.
5. **Thread imbalance.** `top -H` (or the Prometheus `/metrics` endpoint's per-thread CPU series)
   during sustained load. Expect one proactor pinned near 100% and three near idle, confirming
   that everything above lands on a single core and that vertical scaling of
   `--proactor_threads` will not help this workload while the single hashtag stands.
6. **Plan blob cost.** Return `string.len(plan_raw)` from an instrumented copy against a scratch
   DB and correlate with page size; watch `used_memory` / `used_memory_peak` and any allocator
   churn metrics across a burst of pages to size the transient spike (up to `MAX_PLAN_BYTES`
   = 32 MB in a single hash value on one shard's per-thread heap).
7. **Head-of-line blocking.** Run a light background workload against another key in the same
   hashtag and record its p99 while pages are applied. This quantifies the real cost of the
   script's duration: it is not just throughput of the page applier, it is the latency of
   everything else on that shard.

---

## What I would NOT change — recovery contract

These are deliberate and their cost is the price of the resume protocol described at lines 17–29,
446–452 and 678–691. Optimizing them would be optimizing away correctness.

1. **Publishing the full plan before applying it** — `cjson.encode(plan)` (line 674), the
   `HSET KEYS[4] page_receipt_header/page_receipt_plan` (lines 692–699), and the `HDEL` after
   `commit` (line 702). This is the largest single byte cost in the script (up to 32 MB
   materialized, written, and deleted per page) and it is exactly what `resume_mutable_page.lua`
   replays. The write-plan-then-apply-then-clear ordering, and the fact that the receipt becomes
   visible in one atomic `HSET`, are the crash-recovery guarantee. Do not stream, compress away,
   or skip it. (Reducing plan *size* by not emitting no-op commands — findings 2 and 4 — is a
   different thing and is safe.)
2. **`commit` kept as a separate list applied after `commands`** (lines 665, 700, 701) — the
   active-version `HSET KEYS[5]` is the linearization point. Merging it into `commands` would let
   a partial replay publish a version whose backing rows are not all present.
3. **`HDEL 7` and `ZREM 8` emitted adjacently in one command list** (lines 612–613) and the
   half-removed-mailbox reasoning in the comment at lines 446–452. Any change to finding 2 must
   preserve this adjacency for the fields that remain in the list.
4. **The scope/empty-streak patch running before the receipt becomes visible** (lines 678–689,
   keys `22 + n` … `24 + n`), and the rule that the stored plan uses no key index above
   `21 + n`. `resume_mutable_page` does not bind those keys; this is why those commands must be
   executed eagerly and must be idempotent. Do not move them into `commands` to save a pass.
5. **`SET ... NX` for cursor keys** (line 220) even though `mget_dynamic` at line 564 already
   proved them missing. The `NX` is not for this execution — it is for a replay that happens
   after the cursor exists. Likewise the `ZADD_NX` vs plain `ZADD` distinction for the due set
   (lines 381, 627, 634): `NX` preserves an existing due timestamp for additions while updates
   deliberately reset it.
6. **The `receipt_pending` pre-check** (lines 255–262) and the `fenced` check (lines 113–131,
   251–253). These are cheap relative to what they prevent; consolidating them into fewer
   commands (finding 6) is fine, but none of the individual conditions may be dropped.
7. **The `record_conflict` comparisons** at lines 403–415. They must keep reading the current
   values even after findings 2 and 4 eliminate the redundant writes — the reads are the conflict
   detector, and the diffing optimization is a consumer of the same reads, not a replacement.
8. **Deterministic ordering via `table.sort`** (lines 509, 547, 587). Byte-stable plan output
   makes a replayed plan comparable to the original and makes failures reproducible. The cost is
   n log n on ≤4096 elements; keep it.
9. **All validation that yields `protocol` / `over_budget`** (including the dedup sets
   `seen_mailboxes`, `seen_fields`, `unique_grant_fields`, `old_grant_field_set`). The one
   exception I would argue about is the `request_bytes()` scan (finding 7), because it cannot
   prevent the cost it names — and the `current < removals` guard at line 555, which should be
   made an explicit decision rather than a by-product of a `ZCOUNT` the plan does not need.

---

## Summary of expected impact

| # | Location | Waste | Expected saving |
|---|----------|-------|-----------------|
| 1 | line 453 | up to 8192 single-field `HGET` dispatches | 8192 → 32 inner commands; tens of ms/page |
| 2 | lines 612–616, 686–688 | delete+reinsert of unchanged grants | up to 32k no-op effects and journal records |
| 3 | line 553 | up to 4096 `ZCOUNT`, most logically dead | near-total elimination in steady state |
| 4 | lines 615, 617, 618 | rewriting values proven identical | MBs of replication traffic and plan bytes |
| 5 | lines 79–100, 456, 605 | per-grant JSON decode + pattern rebuild | dominant Lua CPU once #1 is fixed |
| 6 | lines 113–131, 334 | ~8 avoidable dispatches, `mode` read twice | halves the no-op fast path |
| 7 | lines 102–108 | 65k-iteration scan for a spent budget | ~1 ms/call |
| 8 | lines 134–168, 216–227, 63–71 | needless table copies, `#value` in loop | small, free |
| 9 | lines 216–227 | synchronous calls for discarded replies | needs verification on 1.34 |
| 10 | lines 509, 547, 587 | sorting passes | keep (plan stability) |
