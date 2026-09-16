# Review: `apply_new_mutable_mailbox_page.lua` — wasted server work

Target: Dragonfly v1.34.0, `EVALSHA`, all keys under `{email-stats-inbound}`, `--proactor_threads=4`, default flags.

## Platform facts the findings rest on

1. **One hashtag = one shard = one proactor thread.** Every key this script touches hashes to the same slot, so all of its work runs on 1 of the 4 proactor threads. There is no parallelism to reclaim; everything below is pure serial time on that one thread, and it is the same thread that serves every other command on the catalog.
2. **Scripts hold a transaction over their declared keys.** Dragonfly schedules the script as a transaction over `KEYS` (non-`allow-undeclared-keys` default) and keeps those keys locked for the *whole* script body, including time spent in pure Lua. So Lua CPU is not "free client-side work" — it is lock-hold time on the catalog hashes, directly visible as p99 on unrelated readers of keys 5–17.
3. **Squashing breaks on inspected replies.** Dragonfly batches a run of consecutive script commands into one shard hop and only flushes when the script needs a reply it will branch on. A `redis.call` inside a Lua loop whose result drives an `if` is therefore a *flush point*: one hop, one dispatch, one reply marshalled into a fresh Lua table, per iteration. Loops that issue one command per element are the most expensive shape a Dragonfly script can have, far more so than the equivalent loop in a pipeline.
4. **Effect journalling.** Writes are journalled/replicated as executed effects. A write that stores a value identical to the one already present still costs a dispatch, a dense-hash lookup, a journal record, and replica bandwidth. "No-op writes" are not free here.

---

## Findings, ordered by expected impact

### 1. Per-field `HGET` inside the old-grant loop — line 453

```lua
local old_payload = redis.call('HGET', KEYS[7], field)
```

This sits inside the `update_indices` × `old_grant_fields` loop (lines 432–470), bounded by `MAX_OLD_GRANTS = 8192`. It is one `redis.call` per old grant field, and its reply gates the `if old_payload then` branch, so per fact 3 **every one of them is a separate shard hop with squashing disabled**.

Cost on Dragonfly: 8192 × (transaction flush + command lookup + arg vector construction from the Lua stack + `HGET` on the grants dense hash + reply → Lua string allocation + interning). At a conservative 3–6 µs of dispatch overhead per call, that alone is 25–50 ms of locked-catalog time, on top of the actual hash lookups. It dwarfs the hash work itself.

The script *already owns the right tool*: `chunked_call('HMGET', KEYS[7], fields)` (line 134). It is even used four lines earlier at line 410 on `grant_fields`. The fix is structural, not clever: collect every old grant field across all updated records in a first pass (the set `old_grant_field_set` is already being built), issue one chunked `HMGET` on `KEYS[7]`, then run the classification/scope loop over the returned payloads with no I/O in it. 8192 calls become 32.

Note the loop also cannot be squashed *and* it interleaves with nothing else, so there is no ordering or atomicity property lost by hoisting the reads: the reads all happen before any write in this script (the first write is at line 682/693), so batching them changes nothing observable.

### 2. Per-workspace `ZCOUNT` — line 553

```lua
local current = redis.call('ZCOUNT', KEYS[8], workspace, workspace)
```

One call per affected workspace, bounded by `MAX_AFFECTED_WORKSPACES = 4096`, reply inspected → again a flush point per iteration (fact 3). Two costs stack:

* **Dispatch**, as in finding 1: up to 4096 non-squashable hops.
* **The `ZCOUNT` itself.** `KEYS[8]` is the *global* grant→workspace membership zset — every grant of every mailbox. If it has outgrown the listpack threshold it is a skiplist and each `ZCOUNT` is two rank lookups, `O(log N)`, plus rank arithmetic. If it is still listpack-encoded it is an `O(N)` linear scan *per workspace*, which is catastrophic at 4096 iterations. Either way this is the heaviest read in the script and it is issued in the worst possible shape.

**Most of these calls are provably unnecessary.** The result is used only to compute `target = current - removals + new` and to test `target == 0` (lines 555–560). For any workspace that appears in `new_workspace_counts`, `new >= 1`; and the guard `if current < removals then return {'protocol'}` means `current - removals >= 0`; therefore `target >= 1` and the workspace can never be deleted. The `ZCOUNT` is only needed for workspaces in `old_workspace_counts` that are **absent** from `new_workspace_counts`. On a steady-state delta page where mailboxes keep most of their workspaces, that is a small minority — often zero.

Caveat to state explicitly: skipping the call also skips the `current < removals` consistency assertion for those workspaces. That assertion is a defensive invariant check, not part of the recovery contract (it returns `protocol`, which aborts before any write). Decide deliberately whether to keep it; if you want it, keep it and batch instead — but there is no batched exact-score count, so the honest options are (a) restrict `ZCOUNT` to delete-candidate workspaces only, or (b) keep the invariant and accept the cost knowingly. Option (a) is the large win.

### 3. Unconditional re-write of grants and records that are already identical — lines 403–414 vs 612–618

Lines 403–414 fetch `existing_records` (`HMGET KEYS[6]`) and `existing_grants` (`HMGET KEYS[7]`) and use them **only** to detect conflicts. Both reply arrays are then discarded. Yet lines 615 and 618 unconditionally `HSET` every grant payload and every record JSON back — including the entries the script has just confirmed are byte-identical to what is stored.

Worse, for grant fields that appear in *both* `old_grant_fields` and `grant_rows` (the common case: a mailbox re-emits the same grant under a new record version), the command list does `HDEL 7` (line 612) → `ZREM 8` (line 613) → `HSET 7` (line 615) → `ZADD 8` (line 616): a delete-then-reinsert of an unchanged entry.

Cost, all of it on the single catalog thread:
* Four dispatched mutations per unchanged grant instead of zero.
* Dense-hash delete + reinsert churn on `KEYS[7]` and skiplist/listpack delete + reinsert on `KEYS[8]`, i.e. allocator traffic and, on the zset, `O(log N)` twice.
* Four journal records per unchanged grant replicated to every replica (fact 4).
* And — this compounds with finding 5 — every one of those four commands is serialised into the plan JSON with its full field and payload.

The information needed to skip them is already in hand and thrown away. Computing the intersection of `old_grant_field_set` with the new grant set, restricted to fields whose `existing_grants` payload equals the new payload, lets you drop the field from *both* the `HDEL`/`ZREM` lists and the `HSET`/`ZADD` lists. The `old_workspace_counts` / `new_workspace_counts` arithmetic stays consistent because such a field decrements and increments the same workspace, so `target` is unchanged. The half-removed-mailbox reasoning in the comment at lines 443–450 is preserved: a field absent from `KEYS[7]` is by definition not in the intersection and still takes the existing path.

Same argument, smaller scale, for `record_rows` (line 618): rows whose `existing_records` entry is non-nil were just verified equal at line 406 and need no `HSET`.

Expected effect on a typical delta page where grants are mostly stable: the bulk of the write commands, the bulk of the journal volume, and a proportional slice of the plan bytes disappear.

### 4. `scope_entry` runs `cjson.decode` once per grant, twice per page — lines 92–100, called at 456 and 605

`scope_entry` does `pcall(cjson.decode, payload)` to read exactly three fields (`workspace_id`, `legacy_grant_id`, `mailbox_address`). It is called once per *removed* grant (line 456) and once per *added* grant (line 605). At `MAX_GRANTS = 8192` + `MAX_OLD_GRANTS = 8192` that is up to 16384 full JSON parses, each allocating a complete Lua table that is read three times and discarded.

Per-call, on top of the decode:
* `grant_workspace` (line 79) builds its pattern by concatenation — `'^(-?%d+):' .. mailbox_id .. ':'` — allocating a ~70-byte string *per call*, and `grant_workspace` is invoked up to three times for the same field (validation at line 306, old-grant loop line 440, inside `scope_entry` line 93).
* `string.format('%.0f', workspace)` (lines 85, 97) allocates again.
* Every one of these strings is interned by Lua 5.1's global string table, so each allocation costs a hash of the full string plus a table probe.

All of this is pure Lua CPU, and per fact 2 it is executed while the catalog keys are locked. It is invisible in `commandstats` and will not show up as a slow command — only as latency on *other* clients. Cheap mitigations: hoist the pattern per record (it depends only on `mailbox_id`, which is constant across the inner loop), pass the already-validated `workspace` into `scope_entry` instead of re-deriving it, and — given finding 3 — never call `scope_entry` at all for grants in the unchanged intersection, which removes both the remove-side and add-side decode for them.

### 5. The plan is a full second copy of the page, encoded, written, journalled, and deleted — lines 656–674, 693–702

`plan` (line 663) embeds `commands` and `commit`, whose `args` arrays contain **every grant field and every grant payload already passed in `ARGV`**. `cjson.encode(plan)` at line 674 therefore re-serialises the entire page — up to `MAX_PLAN_BYTES = 32 MB`, against a `MAX_REQUEST_BYTES` of 16 MB, i.e. the plan is explicitly allowed to be *twice* the request. That value is then `HSET` into a field of `KEYS[4]` (line 693) and `HDEL`ed a few commands later (line 702).

Cost per apply: one full JSON encode of multi-MB data on the locked thread; one multi-MB hash value allocated on the shard; one multi-MB journal record replicated to every replica and written to AOF if enabled; then a delete, also journalled. Write amplification is roughly 2× the payload for a value whose lifetime is microseconds in the happy path.

**This is the recovery contract and I would not remove it** (see the section below). But two things around it are not contract:
* `header` (line 666) duplicates `ids`, `candidate` and `expected_active`, all of which are already inside `plan`. `header_raw` is a second encode of data the plan already carries. If the resume path needs a cheap "is there a receipt" probe, the `HMGET` at lines 255–261 already answers that from the plan field alone.
* The plan shrinks *for free* in proportion to finding 3: commands that are eliminated are not encoded, not stored, not journalled. That is the cheapest available lever on this cost, and it requires no change to the resume contract at all.

Also note `RECEIPT_REMOVE_FIELD` is read at line 259 but never written anywhere in this script — a third field in an `HMGET` that this code path can never set. Harmless, but if it is only written by a sibling remove-page script, say so in a comment; otherwise drop it from the probe.

### 6. `authorized()` issues 5–7 separate round trips to two keys — lines 113–131, plus 255 and 334

`authorized()` does `GET KEYS[1]`, `GET KEYS[2]`, `HGET KEYS[3] storage_format`, `HGET KEYS[3] state`, `HGET KEYS[4] mode`, then up to three more `HGET`s on `KEYS[3]`/`KEYS[4]`. Every reply is branched on, so every one is a flush point (fact 3). Lines 255–261 then issue a *fourth* command against `KEYS[4]`, and line 334 re-reads `mode` from `KEYS[4]` — a field `authorized()` already fetched at line 117 and let fall out of scope.

Collapsible to: one `HMGET KEYS[3] storage_format state generation`, one `HMGET KEYS[4] mode generation expected_active page_receipt_header page_receipt_plan`, and the two `GET`s (which could be one `MGET KEYS[1] KEYS[2]`). That is 8 hops → 3.

Absolute saving is small (tens of µs), but it is paid on **every** invocation including the `#affected == 0` fast path at lines 373–384 — which, for a polling caller in steady state, is the *majority* of invocations. On that path these auth round trips are most of the script's cost. Line 334's redundant `mode` read is a free fix regardless.

### 7. `chunked_call` / `mget_dynamic` copy every chunk before unpacking — lines 134–150, 152–167

```lua
local chunk = {}
for index = first, last do chunk[#chunk + 1] = values[index] end
local result = redis.call(operation, key, unpack(chunk))
```

`unpack` already takes a range: `unpack(values, first, last)` produces the same argument list with **no intermediate table and no copy**. The current form allocates a 256-slot table per chunk and does 256 `#chunk + 1` length operations (each `#` on a sequence is a binary search in Lua 5.1). For 8192 grants that is 32 throwaway tables and 8192 redundant length probes, plus the GC pressure. `mget_dynamic` genuinely needs its copy because it maps indices to keys; `chunked_call` does not.

`NATIVE_CHUNK_ITEMS = 256` is also conservative for Dragonfly, which handles wide argument vectors fine. Raising the chunk size for the *read* paths (`chunked_call`) cuts hop count proportionally — 8192 grants at 1024/chunk is 8 hops instead of 32. I would **not** raise it for chunks that land in the plan (`add_paired_commands` / `add_single_commands`) without checking the resume side, since the chunking there is baked into the stored plan.

### 8. `request_bytes()` walks all of `ARGV` and `KEYS` before authorisation — lines 102–111, called at 249

Up to `MAX_REQUEST_ARGUMENTS = 65536` Lua loop iterations with a `string.len` each, executed *before* `authorized()` at line 253. A fenced or duplicate caller pays the full scan before being rejected. Individually cheap (`string.len` is O(1)), but it is ~65k interpreter steps on the locked thread on a path that is about to return `{'fenced'}`.

The deeper cost is not fixable in this script but worth knowing when you interpret measurements: Dragonfly materialises all of `KEYS` and `ARGV` as interned Lua strings before the first line runs. A 16 MB request means 16 MB of string allocation plus hashing for interning, per invocation, before any of your logic. That sets a floor on latency that no amount of script tuning removes — the lever is page size, not code.

### 9. Minor, listed for completeness

* **Line 617, `ZADD 9 workspace_rows`** re-adds every workspace in `new_workspace_set` with an unchanged score on every apply. Score-unchanged `ZADD` still dispatches and still journals (fact 4). `ZADD ... NX` would at least skip the write path; better, skip workspaces already known present.
* **Lines 547 and 587** sort two overlapping sets — `workspaces` (from `new_workspace_set`) is a subset of `affected_workspaces` (line 547). One sorted list with a membership test would do. Trivial, but it is two `table.sort` calls on up to 4096 elements each.
* **Lines 564–572, the cursor `MGET` pre-check.** `MSET_MISSING` is executed as per-key `SET ... NX` (lines 218–221), which is already idempotent, so the `MGET` is not needed for *correctness* — its only effect is to keep already-present cursors out of the plan. At `record_count <= 256` that is 1–2 hops and a modestly smaller plan; it is a reasonable trade. Keep it, but do not mistake it for a safety check.
* **Lines 41–50, `is_uuid`** allocates via `string.gsub(value, '-', '')` on each of two calls. Irrelevant at 2 calls/invocation; noted only so it is not mistaken for a hot path.

---

## What I would measure to confirm, before changing anything

The findings above are ordered by *expected* impact. Confirm the order with measurements rather than assuming it, because the ranking of 1 vs 2 vs 3 depends entirely on your real page shape (grants per page, fraction of grants unchanged, workspaces per page, size of `KEYS[8]`).

1. **Confirm the call counts.** `INFO commandstats` (or `/metrics`) before and after a single representative `EVALSHA`, diffed. Dragonfly counts commands dispatched from inside Lua, so `cmdstat_hget`, `cmdstat_zcount`, `cmdstat_hmget`, `cmdstat_hset`, `cmdstat_zadd`, `cmdstat_hdel` will show exactly how many of each the script issues for one page. This directly sizes findings 1, 2, 3 and 6, and tells you whether the theoretical bounds (8192 / 4096) are anywhere near your real traffic. Do this first — it is cheap and it may reorder everything.
2. **Split "dispatch time" from "Lua time".** Total script wall time from `SLOWLOG GET` (the `EVALSHA` entry) minus the summed `usec` deltas from `commandstats` for the commands it issued ≈ time spent in the interpreter. If that residual is large, finding 4 (JSON decodes and string churn) and finding 5 (plan encode) matter more than the dispatch findings; if it is small, findings 1–3 dominate.
3. **Size `KEYS[8]`.** `ZCARD` plus `OBJECT ENCODING` / `MEMORY USAGE` on the grant-membership zset. If it is listpack-encoded, finding 2 is an `O(N)` scan per workspace and jumps to the top of the list. If it is a large skiplist, it is `O(log N)` per call and finding 2 is dominated by dispatch instead.
4. **Measure the lock-hold blast radius.** This is the number that actually matters to the product. Run `redis-cli --latency` (or a small looping `GET`) against any key sharing the `{email-stats-inbound}` hashtag while pages are being applied, and compare p99 with and without the apply load. Per fact 2 that latency *is* your script duration. Also watch per-thread CPU (`top -H`) to confirm the expected picture: one proactor pinned, three idle.
5. **Quantify the plan's write amplification.** With a replica attached, compare replication output bytes (`INFO replication` / `total_net_output_bytes` deltas) across one apply against the size of the request. A ratio near or above 2× confirms finding 5's cost model. Re-measure after finding 3 to see how much of it was redundant commands rather than the contract.
6. **A/B the two structural fixes in isolation.** Load a variant script under a second SHA with only finding 1 changed (loop `HGET` → chunked `HMGET`), replay identical recorded inputs, compare `SLOWLOG` p50/p99. Then a second variant with only finding 3. Do not bundle them; you want to know which one paid, and finding 3 changes stored state while finding 1 does not, so they need different levels of verification scrutiny.
7. **Vary page size deliberately.** Sweep `record_count` and grants-per-page and plot latency. If the curve is dominated by a fixed intercept, finding 6 and the interning floor from finding 8 are what matter and you should batch pages more aggressively; if it is dominated by slope, findings 1–4 are what matter.

---

## What I would NOT change, because it is part of the recovery contract

These are load-bearing for crash recovery and for `resume_mutable_page.lua`. Several of them *look* like waste and are not. Anyone optimising this file should treat the following as fixed:

* **Writing the full plan to `KEYS[4]` before applying it (line 693), and deleting it after (line 702).** This is the whole recovery mechanism: the receipt must become visible before any of keys 1..21+n mutate, so a crash mid-apply leaves a replayable description. The 2× write amplification in finding 5 is the price of that guarantee. Shrink the plan by removing redundant *commands* (finding 3); do not remove the plan, do not move the `HSET` later, do not defer the encode.
* **The ordering: scope patch (line 687) → receipt publish (line 693) → `commands` (line 700) → `commit` (line 701) → receipt delete (line 702).** The comments at lines 676–677 and 689–691 state exactly why: keys 22+n..24+n are outside the replayable key layout that `resume_mutable_page.lua` binds (keys 1..21+n per the header note at lines 18–29), so their commands *must* run before the receipt exists, and they must be idempotent so a resume does not repeat them. Reordering or folding the scope commands into `commands` would silently break resume.
* **`execute_commands` being a separate pass over a materialised command list.** The list exists to be serialised into the plan, not for elegance. Fusing "build" and "execute" would save Lua allocations and destroy the ability to resume.
* **`HDEL 7` and `ZREM 8` staying adjacent in one command list (lines 612–613).** The half-removed-mailbox reasoning at lines 443–450 depends on it. Do not separate them, do not reorder them relative to each other, and do not let an optimisation interleave other commands between them.
* **`ZADD_NX` on key 14 (lines 381, 630) vs plain `ZADD` (line 634), and `SET ... NX` for cursors (line 220).** The `NX` variants exist so that a replayed plan does not clobber a due-time or cursor that advanced after the original apply. Collapsing `ZADD_NX` and `ZADD` into one form, or turning `SET NX` into `SET`, would make replay destructive. This is also why the cursor `MGET` pre-check (finding 9) should be left alone rather than "simplified".
* **Deterministic ordering via `table.sort` (lines 509, 547, 587).** The stored plan must apply identically on replay. The sorts are cheap relative to everything above; the two overlapping sorts noted in finding 9 can be merged, but do not drop sorting.
* **The `receipt_pending` early return (lines 255–263).** Refusing to start a new page while a receipt is outstanding is what keeps recovery single-threaded. It may be folded into a batched `HMGET` with the `authorized()` reads (finding 6), but the check itself and its position before any mutation must stay.
* **`authorized()` as a fence (lines 113–131) and the `KEYS[20 + record_number] ~= cursor_key(mailbox_id)` binding check (line 306).** These bind the caller's declared keys to the payload it claims to be applying. Batching the round trips is fine; removing any individual condition is not.
* **The budget caps (`MAX_RECORDS`, `MAX_GRANTS`, `MAX_OLD_GRANTS`, `MAX_AFFECTED_*`, `MAX_REQUEST_BYTES`, `MAX_PLAN_BYTES`, lines 1–9) and the `over_budget` returns.** They bound both plan size and — given fact 2 — the maximum time the catalog stays locked. They are the only thing standing between a pathological page and a multi-second stall on the shared shard. If the optimisations above land, these caps become *less* binding, not obsolete; leave them where they are.
* **The `record_conflict` comparisons at lines 404–414.** Finding 3 proposes reusing their results to skip writes. It does not propose weakening the conflict detection, which must keep running over the same field set.
