# Review: `apply_new_mutable_mailbox_page.lua` (705 lines, df-v1.34.0, EVALSHA, `--proactor_threads=4`, default flags)

## 0. Establish the regime first — it sets the price of everything below

The script declares `24 + record_count` keys (up to 280 at `MAX_RECORDS = 256`), all under the single
hashtag `{email-stats-inbound}`. **On default flags a shared hashtag does not co-locate keys on one
shard** — placement is by full key name, so this is regime (a), io-coordinated: every synchronous
`redis.call` flushes the async buffer and costs one coordinator-to-shard hop, measured at **26.95 µs**
(8 keys/1 tag, 2048B values, `--proactor_threads=4`, n=200) versus **1.01 µs** shard-local
`[lab Q5][S1]`. The 8-keys-one-tag and 8-keys-eight-tags scripts measured 26.95 vs 27.00 µs/call —
the tag buys nothing without `--lock_on_hashtags` `[lab Q5][S1]`.

Confirm, do not assume: diff `eval_io_coordination_total` against `eval_shardlocal_coordination_total`
across one invocation; exactly one goes up by 1 `[df-src server_family.cc][S2]`. Do not read the regime
off `dragonfly --helpfull` (it prints a fresh binary's compiled defaults) and note that
`CONFIG GET lock_on_hashtags` returns empty on v1.34.0 — the running flags come from the process
arguments.

**Therefore the dominant cost term in this script is the *number* of `redis.call`, not the bytes.**
Every finding below is ordered by how many hops it removes, and ~27 µs/hop is the conversion rate.

**And `--lock_on_hashtags` is not the escape hatch here.** The rule is: consider it only if the number of
distinct tags is at least the shard count, or the workload's total script CPU fits one core. This layout
has exactly *one* tag for the entire inbound catalog against 4 proactor threads, so the flag would
serialise the whole workload behind one shard — it buys 26.95 to 1.54 µs/call `[lab Q5][S1]` and pays
for it by queuing every unrelated operation on that tag `[lab Q11d][S1]`. It stays on the table only as a
measured two-arm experiment (§5), never as a default. Likewise, `--!df flags=` is not an optimisation:
both real flags remove the fast path and `allow-undeclared-keys` promotes the script to a GLOBAL
transaction that stalls every shard `[df-src DetermineMultiMode][S2]`.

One correctness framing that makes finding 1 urgent rather than cosmetic: **Dragonfly has no script
timeout, no `SCRIPT KILL` and no BUSY reply** — an over-long script pins its proactor thread until
`kill -9` `[df-doc issue #8269][S10]`. The script is right to have `MAX_*` budgets; the problem is that
one of those budgets authorises 8192 *round trips*.

---

## Findings, ordered by expected impact

### 1. Line 453 — per-field `HGET` inside the old-grant loop. Up to 8192 hops (~220 ms).

```lua
441:    local workspace = grant_workspace(field, record.mailbox_id)
...
453:    local old_payload = redis.call('HGET', KEYS[7], field)
```

`MAX_OLD_GRANTS = 8192` (line 4) bounds this loop, so a worst-case page issues 8192 synchronous `HGET`
against one key. At 26.95 µs/hop that is **~221 ms of pure coordination** in a script that cannot be
interrupted. A realistic 256-record page with 8 grants each (2048 old grants) is still ~55 ms of hops for
what is a single-key lookup table.

This is checklist item 2 exactly, and it has a directly comparable measurement on a script of the same
shape (`claim_mailbox_batch.lua`, 14 keys one hashtag, ~2048B records): per-item `HGET` to chunked
`HMGET` is **p50 41183 to 7814 µs, p99 52222 to 17150 µs, replies identical**, standalone default flags
`[lab Q7][S1]`; back-to-back it is 7.6x on default flags and still 2.6x under `--lock_on_hashtags`
`[lab Q10][S1]`.

**Why it is avoidable with no contract change.** Every field this loop reads is already known before the
loop starts: `old_grant_fields_json` for *all* updated mailboxes is fetched in one batched call at line
421, and no write happens anywhere between line 421 and line 466. So the read set is fixed and the
read-before-write ordering is unchanged. Split the loop in two: pass 1 decodes each record's stored field
array and accumulates `old_grant_fields` with the existing duplicate/`grant_workspace` protocol checks
(lines 440-446, 462-465); then one `chunked_call('HMGET', KEYS[7], old_grant_fields)`; then pass 2 runs
the `old_payload` branch (454-461) against the batched replies. This batches *every* read the original
performs — it does not narrow the check to a subset, which would be a contract change and the data
owner's call, not a reviewer's.

**Free dedup on top.** Line 410 already does `chunked_call('HMGET', KEYS[7], grant_fields)` for the *new*
grant fields. Old and new field sets overlap heavily on a typical update (a mailbox usually keeps most of
its grants), so those overlapping fields are read twice from the same hash. One `HMGET` over the union,
with the two result views taken from an index map, removes that second read entirely.

### 2. Line 220 — `MSET_MISSING` executed as one `SET ... NX` per key. Up to 256 hops, all replies discarded.

```lua
219:      for index, key_index in ipairs(command.keys) do
220:        redis.call('SET', KEYS[key_index], command.values[index], 'NX')
```

`add_mset_missing_commands` (lines 197-213) carefully chunks the cursor keys at 256, and then
`execute_commands` throws the chunking away and issues one call per key. With 256 new-mailbox records
that is 256 hops ≈ 6.9 ms, for writes whose replies are never inspected.

Two independent wins, both measured:

- **Discarded replies belong in `redis.acall`.** 256 discarded `HSET` over 8 keys/1 tag goes
  **28.05 to 2.93 µs/call** (~9.6x) `[lab Q5][S1]`; async calls are buffered into
  `MultiCommandSquasher::Execute` instead of flushing per call `[df-src main_service.cc:2034][S2]`. This
  applies to *all* of `execute_commands` (lines 216-227) and to both `execute_commands(commands)` (700)
  and `execute_commands(scope_commands)` (687) — the script never reads a write reply. On the batched Q2
  write workload the end-to-end effect was p50 339 vs 398 µs default flags `[lab Q10][S1]`; on this
  script the per-key `SET NX` path is where the 9.6x figure actually applies, because it is the one place
  that is still one call per item.
- Keep `SET ... NX` per key rather than `MSETNX` — see §"not to change".

**Boundary to preserve:** the receipt `HSET` (line 692), `execute_commands(commit)` (701) and the receipt
`HDEL` (702) delimit the recovery contract. Leave those three synchronous so the buffer is flushed at each
boundary in order, and verify where an `acall` error surfaces (at flush, not at the call site) before
converting anything whose failure must abort *before* the receipt is written. That verification is a
prerequisite, not a detail.

### 3. Lines 113-132, 255, 334 — the authorisation prelude costs 8-10 hops where 3 suffice. Paid on *every* invocation, including the no-op path.

```lua
114:  if redis.call('GET', KEYS[1]) ~= ARGV[1]
115:    or redis.call('GET', KEYS[2]) ~= ARGV[3] then
118:  local storage_format = redis.call('HGET', KEYS[3], 'storage_format')
119:  local state = redis.call('HGET', KEYS[3], 'state')
120:  local mode = redis.call('HGET', KEYS[4], 'mode')
123/124/128/130/131: four more single-field HGET on KEYS[3] and KEYS[4]
255: HMGET KEYS[4] <three receipt fields>
334: local apply_mode = redis.call('HGET', KEYS[4], 'mode')   -- already read at line 120
```

The happy path runs **8 calls in `authorized()`**, plus the receipt `HMGET` (255), plus a *literal
re-read of a field it already has* (334): 10 hops ≈ 270 µs of fixed overhead before any work.

Collapse to three: `MGET KEYS[1] KEYS[2]`; `HMGET KEYS[3] storage_format state generation`;
`HMGET KEYS[4] mode generation expected_active page_receipt_header page_receipt_plan page_receipt_remove`.
Pass `mode` down instead of re-reading it at 334. That is ~190 µs off every call.

This matters more than the µs suggest because of *which* path pays it. The steady state of a page applier
is "nothing changed": `#affected == 0` returns at line 383 after ~12 hops total (10 above + the two
`chunked_call` at 339/354). Cutting 7 of those is roughly **2.4x on the most frequent invocation shape**.

Trade-off to state honestly: `authorized()` currently short-circuits, so a *fenced* caller costs 1-2 hops
today and would cost 3 after batching. Fencing rejection is the rare path; batching is still right, but
measure both replies.

### 4. Line 553 — one `ZCOUNT` per affected workspace. Up to 4096 hops (~110 ms). Contract-entangled.

```lua
552:for _, workspace in ipairs(affected_workspaces) do
553:  local current = redis.call('ZCOUNT', KEYS[8], workspace, workspace)
```

`MAX_AFFECTED_WORKSPACES = 4096` (line 5) bounds this at 4096 synchronous calls on a single key. There is
no native multi-range `ZCOUNT`, so this one cannot be batched away by a command swap — which is why it is
below findings 1-3 despite the hop count.

The *cheap* narrowing is a contract change, so flag it rather than do it: the loop serves two purposes at
once — deciding `workspace_deletes` (only possible when `target == 0`, i.e. only when
`new_workspace_counts[workspace]` is absent) and enforcing the whole-window invariant `current >= removals`
for every affected workspace (555-557, returning `protocol`). Skipping the `ZCOUNT` for workspaces that
gain new grants would cut the loop to the shrinking workspaces only, and would also stop validating the
invariant for the growing ones. That is a narrowing of a protocol check for inputs where the invariant does
not hold — the data owner's decision, not a performance edit. The measured value of this class of change
in isolation was 1.1x standalone / 1.3-1.8x back-to-back `[lab Q3, Q10][S1]`, i.e. real but not where the
win is.

If the shrinking-only set is still large, the durable fix is a maintained per-workspace counter hash so the
decision becomes one batched `HMGET` — a data-model change, out of scope for this review, but the right
place to spend if measurement shows this loop dominating.

### 5. Lines 673-675, 692 — the plan blob: encoded first, bounded afterwards, at a bound that is measured-fatal.

```lua
673:local header_raw = cjson.encode(header)
674:local plan_raw  = cjson.encode(plan)
675:if string.len(plan_raw) > MAX_PLAN_BYTES then   -- MAX_PLAN_BYTES = 32 MiB (line 9)
```

Three separate costs:

1. **The bound is checked after the work it is meant to prevent.** The script encodes up to 32 MiB of JSON
   on the shard thread and *then* decides it was too big. Measured: a 1 MiB plan encode+HSET is p50
   1905 µs, 8 MiB is 15070 µs, and **at 32 MiB the first call wrote 33.7 MB and the repeat failed with
   `Out of memory` under `--maxmemory=2048Mi`, because the old and new blob must be resident at once**
   `[lab Q4][S1]`. `MAX_PLAN_BYTES` is set exactly at the size that was observed to kill the server.
2. **The bound is reachable.** `MAX_REQUEST_BYTES` is 16 MiB (line 7) and the plan embeds the grant
   payloads verbatim inside `commands`, so `plan_raw` is plausibly ~2x the request. Pre-bound it from
   `request_bytes()` (already computed at line 249) before building the command tables, and lower
   `MAX_PLAN_BYTES` to a size the shard can encode inside the latency budget — 8 MiB already costs 15 ms
   of shard CPU `[lab Q4][S1]`.
3. **Write amplification.** Each grant payload is resident four times on the success path: in `ARGV`, in
   `grant_rows`, in `plan_raw`, and in the value written to `KEYS[4]` at 692. The shard is busy for the
   whole encode and the whole `HSET`. The *existence* of the receipt is the recovery contract (see below)
   and stays; its *size* is a tuning knob the owner controls via `MAX_RECORDS`/`MAX_GRANTS`.

Also minor: `header` (657-663) re-encodes `ids`, which `plan` encodes again — up to 256 x 64-char ids
serialised twice.

### 6. Line 1 — `NATIVE_CHUNK_ITEMS = 256` on the read paths costs 4x the hops the stack limit allows.

The guidance is chunk at 256-1000; the hard wall is Lua stack overflow, measured at **8163 `unpack`ed
fields OK, 8164 overflow** `[lab Q9][S1]`. At 8192 old grant fields, chunk 256 means 32 hops where chunk
1000 means 9 — ~620 µs, repeated across `chunked_call` at 339, 354, 403, 410, 421, 422, 513 and
`mget_dynamic` at 564. Raise the *read* chunk to 1000; keep the *write/plan* chunk separate and
conservative, because paired commands pack 2 args per row (1000 rows = 2000 args) and because the chunk
size determines the shape of the stored plan that `resume_mutable_page.lua` replays. Two constants, not
one.

### 7. Shard-CPU redundancy in the validation helpers (lines 57-100, 293-312, 440-466, 591-610).

Not hops, but real single-threaded shard time at 8192 grants, and it compounds with finding 1 because it
lives in the same loops:

- **`grant_workspace` (79-89) rebuilds its pattern per call**: `'^(-?%d+):' .. mailbox_id .. ':'` allocates
  and recompiles a ~70-char pattern for every field. Hoist one pattern per record (the mailbox_id is
  constant across the record's grants).
- **It is called twice per new grant**: once at line 308 during ARGV validation, once again inside
  `scope_entry` (line 93) from line 605. Pass the already-validated workspace in.
- **`scope_entry` (92-100) runs `pcall(cjson.decode, payload)` per grant** — at 8192 grants x ~2 KB that
  is ~16 MiB of JSON parsed on the shard thread, once for old payloads (456) and once for new (605).
  The new-grant decode re-parses a payload the caller just sent and that lines 304-309 already validated
  structurally; whether the `workspace_id` / `legacy_grant_id` / `mailbox_address` cross-check can move
  into the single pass at 299-317 is a straight de-duplication, not a weakening.
- **`decode_array` (57-77) fully parses `grant_fields_json` and then walks it with `pairs`** to prove it is
  a dense array — after which line 305 compares every element to an `ARGV` value the caller also sent.
  The JSON blob is stored verbatim into `KEYS[11]` (594-597), so it must be *received*; only the decode is
  redundant-with-ARGV. Removing it weakens a protocol check, so it is the owner's decision — but it is
  worth pricing before spending elsewhere.

### 8. Micro, listed for completeness — do not spend a measurement cycle on these.

- `while first <= #values` (135, 154, 169, 183, 198) re-evaluates the length operator each iteration.
- `request_bytes()` (102-110) walks all of `ARGV` and `KEYS` (up to 65536 entries) on every call including
  rejected ones. It is the budget gate; it must precede work. Keep it.
- Line 463's `MAX_OLD_GRANTS` check sits *after* the `HGET` at 453, so the script issues one hop past the
  budget before rejecting. Irrelevant once finding 1 lands.

---

## What I would **not** change — recovery contract, not waste

These read like redundancy and are not. Each one is load-bearing for `resume_mutable_page.lua` or for the
documented crash/replay protocol (header comment, lines 18-30).

1. **The receipt write/execute/commit/delete sequence (692-702).** `HSET` header+plan, then
   `execute_commands(commands)`, then `execute_commands(commit)`, then `HDEL`. The plan is deliberately
   serialised *before* it is executed so that a resume can replay it. It is the single most expensive
   thing on the success path and it is the whole point of the script. Tune its *size* (finding 5), never
   its order.
2. **`scope_commands` running before the receipt becomes visible (679-687), on keys `22+n .. 24+n`.** The
   comment states the invariant: those key indices are outside the replayable layout that
   `resume_mutable_page` binds (keys `1 .. 21+n`), so their commands must be idempotent and must complete
   before any receipt exists. Moving them into `commands` would put un-bindable key indices in the stored
   plan.
3. **`SET ... NX` per cursor key instead of `MSETNX` (220).** `MSETNX` is all-or-nothing across the whole
   chunk; per-key `NX` is what makes the plan replay-safe when some cursors were written between the
   original run and the resume. Make these calls async (finding 2), never collapse them into one
   all-or-nothing command.
4. **The `mget_dynamic` pre-read of cursors (564-572) even though the `SET` is `NX`.** It is what makes the
   stored plan describe only the keys that were actually missing at plan time.
5. **The whole-window conflict checks at 403-415** (`record_conflict` over every affected record and every
   new grant field) and **`current < removals` at 525-527 (labels) / 555-557 (workspaces).** These validate the window, not just
   the rows being written. Narrowing them to the rows the script touches changes behaviour for inputs where
   the invariant does not hold, and the isolated speed value of that narrowing is only 1.1-1.8x
   `[lab Q3, Q10][S1]`. Batch every read; do not drop any.
6. **`redis.call('TIME')` at 638.** One hop for a server clock that must not come from the client, and it
   is correctly issued once and reused for all obsolete rows.
7. **`ZADD_NX` vs plain `ZADD` on key 14 (381, 630, 635) and the `migration_*` / `delta` branching.** These
   encode due-time semantics (do not reset an existing due time on addition, do reset on update). Not
   redundancy.
8. **The `MAX_*` budgets themselves (1-9) and the `over_budget` return.** With no script timeout and no
   `SCRIPT KILL` `[df-doc issue #8269][S10]`, an ARGV-supplied bound plus an explicit marker is the only
   escape hatch that exists. Lower `MAX_PLAN_BYTES`; do not remove any of them.
9. **Every key taken from `KEYS`, with `cursor_key()` used only to *verify* `KEYS[20+n]` (line 285), never
   to address.** Key names built by concatenation are a hard error by default and a server-wide GLOBAL
   transaction if `allow-undeclared-keys` is enabled `[df-src DetermineMultiMode][S2][S7]`. This script
   gets it right; the arity check at 240-244 pins the layout.
10. **Counts returned as strings (704-705).** A Lua array truncates at the first `nil` and truncates floats;
    returning `tostring(...)` in a flat array with a leading status code is the correct reply shape
    `[semantics][S21][S26]`.

---

## What I would measure, in this order

Never ship any of this on reasoning alone: the same three workloads measured twice on default flags gave
1.3-2.2x different absolutes depending on co-tenancy `[lab Q10][S1]`.

1. **Regime, first.** `bench_script.py` reports the
   `eval_shardlocal_coordination_total` / `eval_io_coordination_total` delta per invocation. Expect
   `eval_io_coordination_total +1`. If it is shard-local, findings 1-4 shrink by ~27x and the ranking
   inverts toward findings 5 and 7 (`cjson`, payload bytes, loop CPU).
2. **A seeded spec that hits the real shape**: records x grants/record x updates-vs-additions, `delta` and
   `migration` modes separately (migration adds the `KEYS[18]` read at 339 and changes the due-set
   branches). Include the `#affected == 0` no-op page as its own arm — finding 3 is measured only there.
3. **Variant comparison with a reply-equality gate**:
   `bench_script.py --spec <spec.json> --seed <seed.py> --reseed --compare apply_new_mutable_mailbox_page.lua <variant>.lua`.
   `--compare` asserts byte-identical replies outside `ignore_reply_indices` before reporting and exits 2
   otherwise. **`--reseed` is mandatory here**: this script is not idempotent — a second call against the
   same state finds `active_versions` already equal, takes the `#affected == 0` branch at 373-384 and
   measures the wrong path entirely. Put the `TIME`-derived field (638) in `ignore_reply_indices` if it
   reaches the reply.
4. **Order the arms: finding 1 alone, then +2, then +3.** Finding 1 should reproduce the Q7 shape (p50
   ~5.3x, p99 ~3.0x `[lab Q7][S1]`) if the old-grant count per page is in the same order as Q7's 1024
   candidates. If it does not, the page shape is smaller than assumed and findings 3 and 5 move up.
5. **Report p99, not just p50.** A change that improves p50 and worsens p99 is common in this engine.
6. **Server-side confirmation**: `script_latency.py --sha <sha> --watch` for the sha under real
   concurrency. Histograms are cumulative since load and only `SCRIPT FLUSH` resets them; percentiles come
   off 8-16 bucket upper bounds, so quote them as bounds.
7. **For finding 2 specifically**, watch `eval_squashed_flushes` to confirm the `acall` buffer is actually
   batching rather than being flushed by an interleaved synchronous call.
8. **Check `lua_blocked_total`** at the real applier concurrency: only `--interpreter_per_thread` (10)
   scripts run per thread and the rest block on the pool `[df-src interpreter.cc][S4]`. A 50-200 ms script
   (today's worst case, finding 1) makes that queue visible.
9. **`--lock_on_hashtags` as a two-arm experiment, not a fix.** Run the real concurrency with unrelated
   `{email-stats-inbound}` traffic present. Expect the script to get much faster and the neighbours to
   queue; the one-tag layout means the precondition (distinct tags >= shard count) fails, so the only way
   it wins is if total script CPU for the whole tag fits one core.
10. **Keep the arms honest**: never mix back-to-back ratios with standalone absolutes, and re-measure both
    arms on the same node in the same session.

---

**Bottom line.** Findings 1, 2 and 3 are ~10,000 avoidable round trips on the worst-case page and ~7 on
every page including no-ops, at ~27 µs each, with no contract change and a directly comparable measured
precedent (p50 41183 to 7814 µs `[lab Q7][S1]`). Finding 4 is larger in hop count but entangled with a
protocol check and belongs to the data owner. Finding 5 is a latent availability bug (`MAX_PLAN_BYTES` is
set at the size measured to OOM the server) more than a throughput item. Everything in the "not to change"
list is the recovery contract and must survive any rewrite unchanged.
