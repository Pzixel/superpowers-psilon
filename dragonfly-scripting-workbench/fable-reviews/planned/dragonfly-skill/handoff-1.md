# handoff-1 — phase 1 (local Dragonfly lab + measurements)

Status: **DONE** against every clause of the phase-1 done-condition, plus Q10 and Q11
added mid-phase by the coordinator. Lab torn down, image kept, working tree clean.

## Done per done-condition

| clause | state |
|---|---|
| `lab/compose.yaml`: primary :6379 + replica :6380 (`--replicaof`), digest image, prod args, 3g limits, `single` profile `--proactor_threads=1` | done (`lab/compose.yaml`) |
| `lab/run_all.sh` runs every benchmark and regenerates `lab/RESULTS.md` | done; picks up new `lab/bench/q*.py` automatically |
| `lab/bench/*.py` on python3.12 venv, one file per question, warm-up + >=200 iterations, p50/p95/p99 in µs, `SCRIPT LATENCY` | done (Q4 uses 50, stated in its table) |
| `lab/RESULTS.md` first 40 lines = summary table; appendix with raw output | done, 11 rows at lines 11-24; raw logs `lab/results/q1.txt`..`q11.txt` |
| committed on `main` | done, 8 lab commits, nothing pushed |
| lab torn down (`docker compose down -v`), images kept | done — no `dfskill-*` container remains, dragonfly image still present |

## Commits (branch `main`, no remote)

`fcfd597` compose + `common.py` harness + Q9 · `943baf8` Q1-Q3 · `3a29167` Q4 + extended Q9 +
`run_all.sh` + RESULTS.md · `f0aa6d7` HANDOFF-A · `cf1d808` Q5-Q8 + variants + counter helpers ·
`9b2006e` Q10 + throwaway-node helper + `_FRAG_RE` fix · `285f42f` Q11 · `442b6f3` corrections to
four unsupported claims in RESULTS.md.

## RESULTS.md summary table (verbatim, `lab/RESULTS.md:11-24`)

| Q | experiment | key numbers | conclusion |
|---|---|---|---|
| Q1 | N x HGET vs HMGET/256, 2048B values | N=8192: 5496us vs 4698us p50 (1.2x); 0.67us per redis.call against ONE key | against one key (shard-local) a redis.call costs ~0.67us at N=8192 and 5.1us at N=32; across 8 keys Q5 measures 26.95us/call -- batch with HMGET |
| Q2 | 32x(5 HSET+1 ZADD) vs 5 multi-HSET + 1 multi-ZADD | p50 5846us -> 539us (10.8x); p99 9295us -> 1920us | 192 -> 6 redis.call is a 10.8x win; batch writes (standalone run; see the Q10 reconciliation note) |
| Q3 | 1024 candidates, payload for all vs first 32 | p50 34136us -> 31971us (1.1x); p99 50827us -> 44045us | fetch payloads only for the chosen 32; metadata scan still costs 31971us (standalone run; see the Q10 reconciliation note) |
| Q4 | cjson.encode 1/8/32 MiB command table, HSET then HDEL | script p50 1905us at 1 MiB; worst concurrent GET p99 375us vs 155us idle | concurrent GET degrades but stays sub-millisecond here; this run does NOT show millisecond shard blocking -- see Q8 for the controlled head-of-line measurement |
| Q5 | 256 HGET, 1 key vs 8 keys/1 tag vs 8 keys/8 tags (+disable-atomicity, lock_on_hashtags, lua_auto_async) | us/call 1.01 (1 key) / 26.95 (1 tag) / 27.00 (8 tags); hop 25.26 vs 23.17 | see verdict in the appendix |
| Q6 | Q2 write scripts, primary with replica attached vs detached | mean p50 attached vs standalone: per-call 4679 vs 4484us (+4.3%), batched 569 vs 402us (+41.6%) | difference is beyond the spread between replicates of the same condition |
| Q7 | claim_mailbox_batch.lua, 1024 due, batch 32, ~2048B records: per-candidate HGET vs chunked HMGET | p50 41183us -> 7814us (5.3x); p99 52222us -> 17150us | replies identical; prefetch + deferred payload is a 5.3x win (standalone run; see the Q10 reconciliation note) |
| Q8 | 8 clients x ~2000us script, 9th client GET p99, threads 1 vs 4, probe in same vs different hashtag | p99 t1/same 33219us, t1/diff 33084us, t4/same 169us, t4/diff 191us | see the four cells in the appendix |
| Q9 | inventory of SCRIPT*/DEBUG/INFO/flags | 43 probes, 20 server flags | SCRIPT LATENCY+FLAGS+LIST+GC exist; SCRIPT STATS does not; FLAGS is a setter only; histograms never reset |
| Q10 | Q2/Q3/Q7 workloads re-run on default vs `--lock_on_hashtags`, back to back | batching 9.9x -> 2.0x; payload skip 1.3x -> 1.8x; claim_mailbox_batch hmget 7.6x -> 2.6x | see the 4-cell Q7 table and the counter split in the appendix; the flag's cost under concurrent load is in Q11(d) |
| Q11 | pipeline vs Lua vs MULTI; 100k keys vs 1 hash; Lua limiter vs CL.THROTTLE; SCRIPT LOAD under load | 64 GET: script/pipeline p50 3.9x default, 0.4x lock_on_hashtags; Lua limiter/CL.THROTTLE 0.9x default, 0.8x lock_on_hashtags; 8894B SCRIPT LOAD p50 499us idle -> 478us under 4 loaders (cached sha 149us); 100k x 64B costs 83.7 B/value as strings vs 109.6 in one hash | see the four sub-experiments in the appendix |

## The headline finding phase 2 must build on

A shared hashtag does **not** co-locate keys on default flags. A 1-key script takes the
shard-local path (~1.01 µs/`redis.call`); an 8-key script costs ~26.95 µs/call **whether the
8 keys share one hashtag or use 8 different hashtags** — the INFO counters are decisive
(`eval_shardlocal_coordination_total` vs `eval_io_coordination_total`). Only
`--lock_on_hashtags` moves a one-hashtag multi-key script onto the shard-local path
(26.95 → 1.03 µs/call). The example workload's `claim_mailbox_batch` has 14 keys all sharing
`{email-stats-inbound}` and today pays the io-coordination cost (counters confirm it).

Two corollaries, both measured: `--!df flags=disable-atomicity` and `allow-undeclared-keys`
are **fast-path killers** — they take even a 1-key script off the shard-local counter; and
`--lock_on_hashtags` **reintroduces head-of-line blocking** under concurrent load (Q11(d):
`EVALSHA` of a trivial 1-key script 7712 µs vs 81 µs on the default node under 4 loaders).
So the flag is not a free win, and Q8's reassuring `proactor_threads=4` result was default
flags only.

## Files and interfaces touched

- `lab/compose.yaml`, `lab/run_all.sh`, `lab/requirements.txt`, `lab/.venv` (gitignored).
- Harness `lab/bench/common.py`: counter helpers `script_counters` / `counter_delta` /
  `format_counters` at `lab/bench/common.py:401-470`; fragment merge regex `_FRAG_RE`
  at `lab/bench/common.py:327`; `QUESTION_ORDER` at `:32`; `restart()`; nonce-comment helper
  for fresh SHAs.
- Benchmarks `lab/bench/q1_call_overhead.py`, `q2_write_batching.py`, `q3_read_after_full.py`,
  `q4_big_json.py`, `q5_key_placement.py`, `q6_replica.py`, `q7_real_script.py`,
  `q8_head_of_line.py`, `q9_inventory.py`, `q10_lock_on_hashtags.py`, `q11_redis_advice.py`.
- Q7 variants `lab/variants/claim_mailbox_batch.orig.lua` (copied from the read-only
  email-stats repo) and `lab/variants/claim_mailbox_batch.hmget.lua`.
- Contract/handoff docs: `lab/Q7-CONTRACT.md` (verified KEYS[1..14], ARGV, fences, seeding),
  `lab/HANDOFF-A.md`, `lab/HANDOFF-B.md`, `lab/HANDOFF-C.md`,
  `lab/handoff-phase1-results-fixes.md`, `lab/REVIEW-RESULTS.md`.

## Evidence files

`lab/RESULTS.md` (summary + appendix), raw logs `lab/results/q1.txt` .. `q11.txt`
(each records server version, flags and exact command lines), review
`lab/REVIEW-RESULTS.md` (verdict **SOUND WITH CAVEATS**; its four blocking findings were
fixed in `442b6f3`, the rest are recorded there).

## Verbatim: the one semantic difference in the hmget variant

Phase 2 must judge whether this is contract-neutral. From the header of
`lab/variants/claim_mailbox_batch.hmget.lua:8-13`:

> KNOWN semantic difference: the original returns {'PROTOCOL','record_missing'}
> if ANY eligible candidate in the window lacks a record, including candidates
> past batch_size that it would never claim; this variant only checks the
> claimed ones. On data where every eligible candidate has its record -- the
> seeded state here and the invariant the writer maintains -- the replies are
> identical, which is what the benchmark asserts.

## Out of scope for this phase

No change to `/Users/pzixel/Documents/Repos/email-stats` (read-only throughout). No skill
text (phase 2). No push, no merge.

## Open decisions for the owner

1. **Is the hmget variant's semantic difference acceptable?** It narrows the
   `PROTOCOL record_missing` check to claimed candidates only. It is contract-neutral only
   under the writer's invariant that every eligible candidate has a record. Phase 2 should
   decide before the skill recommends this rewrite.
2. **Does the skill recommend `--lock_on_hashtags`?** It converts the example workload's
   14-key script from io-coordination to shard-local (a 7.6x→2.6x shift in how much the
   Lua-level optimization still buys, Q10) but reintroduces head-of-line blocking under
   concurrent load (Q11(d), 95x on a trivial EVALSHA). This is a genuine trade-off, not a
   default recommendation, and prod currently does **not** set it.
3. **Q2/Q3/Q7 were each measured twice** with unreconciled absolutes (Q3 34136 vs 74627 µs).
   The reconciliation note in the Q10 appendix sets the rule — ratios from Q10 (back-to-back
   arms), absolutes from the standalone runs. Confirm phase 2 quotes them that way.
4. **Non-blocking review notes not addressed** (`lab/REVIEW-RESULTS.md`): Q6's claim-strength
   caveat, and the Q8 0.52-vs-31.9 µs/call observation.
5. **Q11 p95/min/max/mean/total columns are not raw-log-backed for this run** (the log kept
   only p50/p99); `q11_redis_advice.py` now writes full tables, so a re-run backs them.

## One verification step that proves the phase

    cd /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/lab && ./run_all.sh

Brings the lab up from the digest, runs all eleven benchmarks, exits 0, and regenerates
`lab/RESULTS.md` with Q1..Q11 in the summary table (no `pending` rows) and eleven appendix
blocks. Note it **re-measures**: absolute numbers will differ run to run (these workloads are
load-sensitive); the execution-path counter splits and the ratios are what reproduce.
Tear down again with `docker compose --profile single down -v`.
