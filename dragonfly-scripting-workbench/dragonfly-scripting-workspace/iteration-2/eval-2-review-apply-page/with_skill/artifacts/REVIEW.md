# Review: `apply_new_mutable_mailbox_page.lua` — wasted server work

Target: `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/evals/inputs/apply_new_mutable_mailbox_page.lua`
(705 lines, EVALSHA on Dragonfly v1.34.0, `--proactor_threads=4`, default flags, all keys under `{email-stats-inbound}`).

## 0. Regime first — this decides which findings matter

The script declares `24 + record_count` keys (line 227-231), up to 280 keys, all sharing one hashtag.

**A shared hashtag does not co-locate keys on one shard on default flags.** It is a lock/placement unit only
under `--lock_on_hashtags`, which is not in the stated flag set. So this script is in the **io-coordinated
regime (a)**: every synchronous `redis.call` flushes and pays one coordinator-to-shard hop, measured at
**26.95 µs/call** (8 keys/1 tag, `--proactor_threads=4`, default flags) versus 1.01 µs on the shard-local
path `[lab Q5]`.

Consequence: **the dominant cost term is the *number* of `redis.call`, not payload bytes or Lua CPU.**
Everything below is ordered on that basis. Confirm the regime before acting on any of it (§4).

### Call budget, worst case within the script's own caps

`n = 256` records, `MAX_GRANTS = 8192` new grants, `MAX_OLD_GRANTS = 8192` old grants, `MAX_AFFECTED_WORKSPACES = 4096`:

| site | calls | µs at 26.95 |
|---|---|---|
| `HGET KEYS[7]` per old grant field, line 453 | 8192 | ~221 ms |
| `ZCOUNT KEYS[8]` per affected workspace, line 553 | 4096 | ~110 ms |
| `SET .. NX` per missing cursor key, line 220 | ≤256 | ~7 ms |
| preamble (`authorized()` + receipt + mode), lines 113-129, 255, 334 | 6-9 | ~0.2 ms |
| all chunked `HMGET` reads, lines 339/354/403/410/421/422/513 | ~55 | ~1.5 ms |
| all batched writes via `execute_commands`, lines 612-687 | ~220 | ~6 ms |
| receipt `HSET`/`HDEL` + `TIME`, lines 638, 692, 702 | 3 | ~0.1 ms |

**~96% of the hop budget lives in two per-item loops.** A mid-sized page (32 records x 32 grants, ~200
workspaces) is the same shape: ~1224 of ~1300 calls are those two loops.

---

## 1. Line 453 — `HGET KEYS[7]` once per old grant field (highest impact)

```lua
-- line 440-467, inner loop over record.old_grant_fields
local old_payload = redis.call('HGET', KEYS[7], field)
```

**Cost.** Up to `MAX_OLD_GRANTS = 8192` hops, ~221 ms of pure coordination, serialised, with the script's
thread pinned for the whole time. This is checklist item 2 verbatim, and it is the pattern the lab measured
on a real script: per-candidate `HGET` to chunked `HMGET` moved p50 41183 -> 7814 µs and p99 52222 -> 17150 µs,
replies identical, standalone default flags `[lab Q7]`. Back-to-back that was 7.6x on default flags `[lab Q10]`.

**Why it is avoidable here.** The field list is already fully materialised before any write: `record.old_grant_fields`
comes from `decode_array(old_grant_fields_json[update_number])` at line 432, and *every* write in this script is
deferred into the `commands` table and executed at lines 700-701. There is no read-after-write hazard to preserve.
Restructure as two passes: (1) walk `update_indices` collecting `old_grant_fields` and the dup/`grant_workspace`
validation exactly as today, (2) one `chunked_call('HMGET', KEYS[7], old_grant_fields)`, (3) walk the replies to
build `scope_remove_*` and `old_workspace_counts`. 8192 calls -> 32 calls at the current chunk size, 9 at 1000.

**Extra win: the union with line 410.** `existing_grants = chunked_call('HMGET', KEYS[7], grant_fields)` at line 410
already reads the *new* grant fields from the same hash. A grant field that is unchanged between old and new
record versions — the common case for an update — is fetched **twice** from `KEYS[7]` in one invocation. One
chunked `HMGET` over the deduplicated union of `grant_fields` and `old_grant_fields` serves both the
`record_conflict` check (lines 411-415) and the old-payload branch, with no contract change: both consumers
need the same value of the same field at the same point in time.

**Not a contract change.** The comment at lines 445-451 justifies the `old_payload == nil` branch by the adjacency
of `HDEL 7` and `ZREM 8` in one command list and by the scope patch ordering. Batching the *read* touches neither.

---

## 2. Line 553 — `ZCOUNT KEYS[8]` once per affected workspace

```lua
for _, workspace in ipairs(affected_workspaces) do          -- line 552
  local current = redis.call('ZCOUNT', KEYS[8], workspace, workspace)
```

**Cost.** Up to `MAX_AFFECTED_WORKSPACES = 4096` hops, ~110 ms. Worse than a plain hop count: `KEYS[8]` is the
global grant-membership zset scored by workspace, so each `ZCOUNT` is O(log N) rank arithmetic over a set whose
size grows with the whole catalog, not with this page. The script pays that 4096 times serially, on one shard
thread, while the transaction holds its locks.

**What the result is actually used for.** Only two things: the `current < removals` assertion (line 555) and the
`target == 0` delete decision (line 559). For any workspace with `new_workspace_counts[workspace] > 0`,
`target = current - removals + additions` is strictly positive once `current >= removals` holds — so the `ZCOUNT`
for those workspaces buys nothing but the assertion. In a steady-state update most affected workspaces are in
both the old and new sets, so most of these 4096 calls are assertion-only.

Two candidate fixes, in increasing order of blast radius:

- **Script-only:** issue `ZCOUNT` only for workspaces in `old_workspace_counts` with no entry in
  `new_workspace_counts` (the only ones that can reach `target == 0`). This *narrows* the `current < removals`
  protocol check to workspaces that can be deleted. That is a contract change for inputs where the invariant
  does not hold, so it belongs to the owner of the data, not to a performance pass — the skill is explicit that
  narrowing whole-window checks is a separate decision from batching (§4, "Contract before speed").
- **Data-model:** maintain a `workspace -> grant count` hash alongside `KEYS[8]` and read it with one chunked
  `HMGET`, preserving the assertion for every workspace. 4096 calls -> 16. Spans `src/catalog.rs`.

I would measure fix 1 to size the prize before proposing fix 2.

---

## 3. Lines 673-674, 692-699 — `cjson.encode(plan)` and the 32 MiB plan blob

```lua
local header_raw = cjson.encode(header)
local plan_raw = cjson.encode(plan)
if string.len(plan_raw) > MAX_PLAN_BYTES then return {'over_budget'} end
```

The `plan` table contains `commands` and `commit`, i.e. **a second full copy of every grant payload, record JSON
and cursor value in the request**, re-boxed into ~220 per-chunk tables. `MAX_REQUEST_BYTES` is 16 MiB and
`MAX_PLAN_BYTES` is 32 MiB, so the encode is O(request size) and can legitimately reach tens of MiB.

**Cost on Dragonfly specifically.** `cjson.encode` runs on the shard thread with nothing else progressing on it.
The lab measured a 1 MiB plan encode+HSET at p50 1905 µs and 8 MiB at 15070 µs; **at 32 MiB the first call wrote
33.7 MB and the repeat failed with `Out of memory` under `--maxmemory=2048Mi`, because the old and new blob must
be resident at once** `[lab Q4]`. That is not a slow path, that is a cliff the current caps permit. Then the blob
is `HSET` into `KEYS[4]` (line 692), replicated and journalled in full, and `HDEL`ed three calls later (line 702)
— the whole round trip is write amplification proportional to the page.

**This is the recovery contract and I would not delete it** (see §5). What I would do:

- Reconcile `MAX_PLAN_BYTES = 32 MiB` (line 9) with the Q4 OOM cell and with `maxmemory`. The cap should be
  derived from the memory headroom that keeps two copies resident, not set at 2x `MAX_REQUEST_BYTES`.
- Note that `header` (lines 676-682) is a strict field-subset of `plan` (lines 683-691) including a second copy of
  `ids`; it is small, but it is a second encode and a second hash field for zero new information. Worth asking
  the owner whether the resume path needs the header separately from the plan.
- Consider a compact plan representation (argument indices instead of inlined payloads) — this is a joint change
  with `resume_mutable_page.lua`, so it is a design proposal, not a tuning edit.

Note also `string.len(plan_raw) > MAX_PLAN_BYTES` at line 675 rejects *after* paying for the encode. The budget
check cannot prevent the work it is budgeting.

---

## 4. Lines 403-415 and 612-616 — writes the script has already proven redundant

Three separate instances of the same waste. Checklist item 11: a write whose value does not change still costs a
shard mutation, journal bytes and replica bytes; Q6 measured a write script at +4.3% (per-call) / +41.6%
(batched) p50 with a replica attached versus standalone `[lab Q6]`.

- **Lines 403-409**: `existing_records` proves every already-present `record_field` is **byte-identical** to
  `record.record_json` (otherwise `record_conflict`). Line 618 then `HSET`s all of `record_rows` back anyway.
- **Lines 410-415**: identically for grants — proven byte-identical, then re-written wholesale at line 615.
- **Lines 612-616**: `HDEL 7` + `ZREM 8` over `old_grant_fields`, immediately followed by `HSET 7` over
  `grant_rows` and `ZADD 8` over `membership_rows`. Every grant field present in **both** the old and new record
  — the majority for a typical update — is deleted and re-inserted with the same value and the same score. Same
  key, same field, same bytes, two mutations plus two journal records.

The fix is set arithmetic on data the script has already computed: `HDEL`/`ZREM` only `old_grant_fields \ unchanged`,
`HSET`/`ZADD` only rows that were absent or differ. It also shrinks `commands`, which shrinks the plan blob in §3.

**Caveat to settle with the owner before shipping:** these writes also land in the replayed plan. Omitting a write
because the value was already correct *at original-run time* is only safe if nothing between the crash and the
resume can remove it. That follows from the receipt protocol as written, but it is an argument about the protocol,
not about the script, so I would get it confirmed rather than assume it.

---

## 5. Lines 113-129, 255-262, 334 — the fixed preamble costs 6-9 hops where 2 suffice

```lua
redis.call('GET', KEYS[1]);  redis.call('GET', KEYS[2])                      -- 114-115
redis.call('HGET', KEYS[3], 'storage_format'); redis.call('HGET', KEYS[3], 'state')  -- 118-119
redis.call('HGET', KEYS[4], 'mode')                                          -- 120
redis.call('HGET', KEYS[3], 'generation')                                    -- 127
redis.call('HGET', KEYS[4], 'generation'); redis.call('HGET', KEYS[4], 'expected_active')  -- 123-124, 128-129
redis.call('HMGET', KEYS[4], header, plan, remove)                           -- 255-262
local apply_mode = redis.call('HGET', KEYS[4], 'mode')                       -- 334  (already read at line 120)
```

Collapsible to three calls, or two: `MGET KEYS[1] KEYS[2]`; `HMGET KEYS[3] storage_format state generation`;
and one `HMGET KEYS[4]` carrying `mode`, `generation`, `expected_active` **plus** the three receipt fields that
line 255 fetches separately. Line 334 is a straight re-read of a value line 120 already had — return it from
`authorized()`.

**Absolute saving is small (~5-7 hops, ~160 µs) but it is the whole cost of the common page.** The `#affected == 0`
early return at lines 356-368 — a page where every record is already current, which is what a retry or a
no-change poll looks like — executes roughly 10-13 calls total. Halving the preamble halves that invocation.
If no-change pages dominate the call mix, this outranks §2 in aggregate server work; measure the mix.

Both `HMGET` merges are behaviour-preserving in one respect and not in another: today the `and` chain
short-circuits, so a failed fence stops issuing calls. Fetching all fields up front always issues them. That is
6 calls -> 2 on the success path against 2-4 -> 2 on the fenced path; still a win, but state it rather than
hide it.

---

## 6. Lines 216-227 — `execute_commands` discards every reply

Every call in `execute_commands` (lines 220, 223, 225) throws its reply away, and it is invoked three times
(scope commands line 687, main commands line 700, commit line 701) for ~220 calls on a large page. Switching
discarded writes to `redis.acall` measured **28.05 -> 2.93 µs/call** on 8 keys/1 tag, default flags `[lab Q5]`:
the calls stop forcing a flush-and-wait and get squashed. On a large page that is ~220 x 25 µs ≈ 5.5 ms; on a
small one it is proportionally similar.

This is a low-risk change *in shape* — no reply is consumed — but two things must hold and must be checked:
ordering across the three `execute_commands` invocations and the `HSET` receipt boundary (line 692) and the
`HDEL` at line 702 must still act as barriers, and error surfacing changes (an `acall` failure reports at the
flush point, not at the call). Verify with `--compare` on a seeded failure case, not only the happy path.

Do **not** reach for `--lua_auto_async` here: it applies to atomic scripts, and the `--!df flags=` directives are
not an optimisation — both real flags remove the fast path, and `no-writes` is parsed and ignored `[lab Q5]`.

---

## 7. Lines 217-221 — `MSET_MISSING` issues one `SET .. NX` per key

Up to `#additions` = 256 hops (~7 ms) for what is logically one write set. There is no exact batched
equivalent: `MSET` drops the `NX`, and `MSETNX` is all-or-nothing, which is *not* the same thing during a
replay where some keys already exist. **I would leave the `NX` alone** (§8) and instead note that the
already-executed `mget_dynamic` at line 564 has filtered the list to genuinely-missing keys, so the remaining
volume is bounded by real additions, not by `n`. Revisit only if pages are dominated by additions.

## 8. Line 1 — `NATIVE_CHUNK_ITEMS = 256`

Free hop reduction. The lab's stack-overflow boundary for `unpack` into `redis.call` is 8163 fields
(8164 overflows) `[lab Q9]`, and the recommended range is 256-1000. Moving to 1000 turns 8192 old-grant fields
from 32 hops into 9, and the same for the grant `HSET`/`ZADD`/`HDEL`/`ZREM` chunks. Note `add_paired_commands`
chunks at 256 *rows* = 512 arguments, so raising the constant to 1000 makes those chunks 2000 arguments — still
well inside the limit, but the two helpers scale differently and both must be checked against 8163.

## 9. Lines 79-98, 441, 453-460, 601-608 — repeated Lua-side work per grant (shard CPU, not hops)

Lower priority than anything above, because in regime (a) hops dominate — but this is real shard time, and it
becomes the top term the moment §1 and §2 are fixed, or if `--lock_on_hashtags` is adopted.

- `grant_workspace` (line 79) rebuilds the pattern string `'^(-?%d+):' .. mailbox_id .. ':'` on **every call** —
  a 64-char concatenation plus a fresh pattern compile per grant. Hoist the per-record prefix out of the loop.
- `grant_workspace` is computed for the same field up to three times: line 308 (request validation), line 441
  (old-field walk), and again inside `scope_entry` (line 89). Pass the value that is already in hand.
- `scope_entry` does a full `cjson.decode` of the grant payload (line 94) to read three fields, and it is called
  once per *old* grant (line 456) and once per *new* grant (line 604) in delta mode — up to 16384 JSON decodes
  of full payloads per invocation.
- `decode_array` (line 57) walks `pairs(value)` to reject non-array tables after `cjson.decode` already built
  the table; it runs once per record for `grant_fields_json` and once per update for the old field list.

## 10. Lines 288, 297-311 — grant fields are transmitted twice

Each record supplies `grant_fields_json` (a JSON array of all its grant fields, line 288) **and** every field
again as an individual `ARGV` entry (line 300), and line 305 validates that they agree
(`field ~= grant_fields[grant_number]`). The server pays twice: once in request bytes against the 16 MiB budget
and the 65536-argument budget (lines 247-250), once in Lua argument marshalling, plus 8192 string comparisons.
`grant_fields_json` must be transmitted because it is stored verbatim into `KEYS[11]` (line 619); the per-grant
field copies could be derived from the decoded array. This is a client/script contract change in `src/catalog.rs`,
so it is a proposal, not an edit.

---

## What I would measure to confirm

1. **Regime, first and authoritatively.** `INFO ALL` before and after one invocation; diff
   `eval_io_coordination_total` against `eval_shardlocal_coordination_total`. Exactly one goes up by 1. I expect
   `eval_io_coordination_total +1` given 280 keys on default flags — but detect it, do not infer it from the
   hashtag, and do not read it off `dragonfly --helpfull` (that prints a *new* binary's compiled defaults) or off
   `CONFIG GET lock_on_hashtags` (empty reply on v1.34.0). Read the running server's actual process arguments.
2. **Per-invocation call count**, to confirm the §0 budget empirically: delta of `total_commands_processed` around
   one EVALSHA on an idle node, for a seeded page at (n=8, few grants), (n=64, 32 grants), (n=256, 8192 grants).
   This turns "8192 hops" from arithmetic into an observation and shows which of §1/§2 dominates *your* page shape.
3. **Before/after, the only form that counts:**
   `scripts/bench_script.py --spec <spec.json> --seed <seed.py> --reseed --compare apply_new_mutable_mailbox_page.lua <variant>.lua`.
   `--compare` asserts byte-identical replies outside `ignore_reply_indices` before reporting and exits 2
   otherwise. `--reseed` is mandatory here: this script is **not idempotent** (it writes a receipt, mutates the
   catalog and returns `{'applied', ...}` the first time and would hit the `#affected == 0` path the second),
   so without `--reseed` you would be timing the second-call path, not the change.
4. **Seed the shapes that actually differ**: a page of pure additions, a page of updates with mostly-unchanged
   grants (this is what sizes §4 and the §1 union win), and a no-change page (this is what sizes §5). One seed
   will not expose all three.
5. **Report p50 and p99.** A change that improves p50 and worsens p99 is common here — Q7 was p50 5.3x but p99
   only 3.0x. Do not quote absolutes across runs: Q10 measured the same workloads twice on default flags and got
   1.3-2.2x different absolutes from co-tenancy alone.
6. **For §4 (redundant writes), attach a replica** and measure with and without, as Q6 did; the cost of a
   redundant write is journal and replica bytes, which a standalone run cannot see.
7. **Server-side confirmation:** `scripts/script_latency.py --sha <sha> --watch`. Difference the counters around
   the window — `SCRIPT FLUSH` does not reset an existing sha's histogram, and percentiles are bucket upper
   bounds, so quote them as bounds.
8. **If and only if the workload justifies it, evaluate `--lock_on_hashtags` as a separate arm.** It would move
   this script to ~1.5 µs/call and make most of §1-§2 moot, but it serialises all unrelated work behind
   `{email-stats-inbound}`'s shard. The rule: consider it only if distinct tags are at least the shard count, or
   total script CPU fits one core. A single tag for the whole inbound catalog fails the first test, so this needs
   measurement at real concurrency, not a config edit. **Batching (§1, §2) is the change that pays in both
   regimes; do this before touching flags.**

---

## What I would NOT change: the recovery contract

These are costs, and I am listing them as costs, but they buy crash recovery and I would leave every one alone.

1. **The whole receipt protocol** — the `HMGET` of the three receipt fields and the `receipt_pending` bail
   (lines 255-264), the `HSET` of `header_raw` + `plan_raw` *before* any command executes (lines 692-699), and
   the `HDEL` after commit (line 702). That is 3 extra round trips plus a large write and a large delete per
   page. It is the fence that lets `resume_mutable_page.lua` finish a half-applied page. Reducing the *size* of
   the plan (§3) is fair game; removing the plan is not.
2. **The `NX` on cursor writes** (line 220) and **`ZADD_NX`** (line 223) — these are what make plan replay
   idempotent. `MSETNX` is not a drop-in: it is all-or-nothing, and on replay some keys exist. Batching this
   loop correctly requires a different primitive, not a weaker one.
3. **The key-index restriction documented at lines 19-30** — the stored plan uses no key index above `21 + n`,
   and commands on keys `22 + n` .. `24 + n` are executed at line 687, before the receipt becomes visible,
   precisely because the resume path does not bind them. Any batching that moves a command between
   `scope_commands` and `commands` breaks the replay layout.
4. **The `HDEL 7` / `ZREM 8` adjacency** relied on by the comment at lines 445-451. The set-difference
   optimisation in §4 must preserve the relative order of those two commands in the list.
5. **`redis.call('TIME')` at line 638** — already correctly hoisted out of the loop and executed once, so the
   `now_ms` baked into the plan's `ZADD 16` rows is identical on the original run and on replay. Do not move it
   into `execute_commands` and do not recompute it per row; a replay must reproduce the same scores.
6. **Whole-window conflict checks** at lines 403-415. The skill's guidance is explicit: batch *every* read the
   original performs, but do not narrow a check to the subset you happen to act on. These already read the whole
   window via chunked `HMGET`; keep that shape when merging them with §1.
7. **Key names built by concatenation for comparison only.** `cursor_key()` (line 53) constructs a key name, but
   it is only ever compared against `KEYS[20 + record_number]` (line 306) — never used as a call target. Every
   command goes through `KEYS[...]`. That discipline is what keeps this script off the `allow-undeclared-keys`
   path, which would promote it to a GLOBAL transaction stalling every shard. Do not "simplify" it.
8. **The budget caps** at lines 2-8 and their `over_budget` returns. There is no script timeout, no `SCRIPT KILL`
   and no BUSY reply on Dragonfly — an unbounded script pins its thread until `kill -9`. Bounding is a
   correctness requirement here, not tuning. (`MAX_PLAN_BYTES` in §3 is a *recalibration* of one cap against
   measured memory behaviour, not a removal.)
9. **The flat, constant-arity reply** `{'applied', tostring(#additions), tostring(#update_indices)}` (line 704),
   with counts returned as strings. Lua arrays truncate at the first `nil`, drop string-keyed fields and truncate
   floats; the current shape is correct and should stay.
