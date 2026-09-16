# handoff-4 — refine, optimize triggering, install, final report

**Phase 4 INCOMPLETE.** Step 1 done and committed (`944d4d2`). Steps 2–5 are in flight or not started; the
phase-lead hit its tool-call budget while four eval runs and the description loop were still executing.
Everything needed to finish is below, with exact commands.

## Done

### Step 1 — skill refined, iteration-2 metadata written (commit `944d4d2` on `main`, not pushed)
All four ANALYSIS.md changes applied as narrow edits. SKILL.md 163 → **180 lines** (≤250).
`quick_validate.py dragonfly-scripting` → `Skill is valid!`. `description:` frontmatter untouched
(the trigger loop owns it). Name, folder and `agents/openai.yaml` unchanged.

**SCRIPT FLUSH verified once on the lab** (`dfskill-primary`, `dragonfly_version:df-v1.34.0`, lab torn down after):
- `SCRIPT LOAD "return 1"` → sha `e0e1f9fabfc9d4800c877a703b823ac0578ff8db`; 5× `EVALSHA` →
  `SCRIPT LATENCY`: `Count: 5 Average: 16.6000 StdDev: 2.50 Min: 12 Median: 17 Max: 19`.
- `SCRIPT FLUSH` → `OK`; `SCRIPT LATENCY` immediately after is **byte-identical, still `Count: 5`**.
- Reload identical text (same sha), 1× `EVALSHA` → `Count: 6 Average: 18.0000 ... Max: 25`.
So the histogram is **cumulative for the server's lifetime**; the old claim was wrong. Raw transcript is
recorded verbatim at `dragonfly-scripting/references/measurements.md:86-129`.

| change | file:line |
|---|---|
| 1 SCRIPT FLUSH correction | `dragonfly-scripting/references/measurements.md:79-84` (lead-in) + `:86-129` (new dated entry); `dragonfly-scripting/SKILL.md:157-162` (§4.4) |
| 2 hashtag does not co-locate without `--lock_on_hashtags`, promoted to intro | `dragonfly-scripting/SKILL.md:12-14`, tagged `[lab Q5][S1]` |
| 3 redundant-write-elimination rule (checklist item 11) | `dragonfly-scripting/SKILL.md:95-99`, tagged `[lab Q6][S1]` |
| 4 `--compare --reseed` as the rule for any before/after claim | `dragonfly-scripting/SKILL.md:16-18` |

**Deviation on change 3:** the rule carries `[lab Q6][S1]` but **not** `[df-doc]`. `lab/RESULTS.md` Q6
(replica attached vs standalone, Q2 write script: per-call 4679 vs 4484 µs = +4.3%; batched 569 vs 402 µs
= +41.6%) does support write/journal cost, but `references/sources.md` has no row covering write
journaling/replication — the only journal mention (`[df-doc PR #8300][S11]`) is about `SCRIPT LOAD`
borrowing an interpreter. The implementer declined to invent a source row. See open decision 1.

### Iteration-2 eval metadata (written, committed in `944d4d2`)
- `dragonfly-scripting-workspace/iteration-2/eval-1-optimize-claim-batch/eval_metadata.json` — **8 assertions**.
  `payload-reads-bounded-by-batch-size` deleted as unsound (bounding the record read changes replies: the
  original returns `PROTOCOL record_missing` for eligible candidates past the 32nd). Added
  `states-execution-regime-with-evidence` (io-coordinated on default flags because a shared hashtag does not
  co-locate, backed by `eval_io_coordination_total` / `eval_shardlocal_coordination_total` deltas) and
  `before-after-on-identical-seeded-state` (identical seeded state, reply-equality check, p50 **and** p99 per arm).
  `no-unverified-redis-only-advice` rephrased positively (must cite a Dragonfly counter, a v1.34.0
  SCRIPT LATENCY/bench measurement, or a v1.34.0 doc/source) — assertion id kept so it stays comparable.
- `dragonfly-scripting-workspace/iteration-2/eval-2-review-apply-page/eval_metadata.json` — 8 kept + 9th
  `flags-redundant-writes` (delete-and-reinsert of unchanged grants at
  `apply_new_mutable_mailbox_page.lua:612-616`, rewrite of records already proven identical at `:403-415`,
  and that both still cost shard mutations, journal bytes and replica bytes). Both line ranges were
  verified against the eval input.
- Per phase-4 decision 2, eval 1 stays **reply-only** (no post-state dump); `--compare` is the contract.
  Record that limitation in `iteration-2/ANALYSIS.md`.

### Step 2 partial — iteration-2 layout
`dragonfly-scripting-workspace/iteration-2/eval-3-design-new-op/` is eval 3's iteration-1 directory copied
unchanged (phase-4 decision 4) so the aggregate covers three evals. **Not yet committed** (untracked).

## In flight when the budget ran out

Four `implementer`/Opus runs, all spawned in one turn, prompts verbatim from the iteration-1
`eval_metadata.json` `prompt` fields, with-skill arms opening
"Use the skill at /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting (read its SKILL.md first
and follow it)." and without-skill arms opening "Work from your own knowledge plus the files named in the
task." plus an explicit ban on reading anything under `dragonfly-scripting/`, `.claude/skills` or
`.codex/skills`. Eval-1 arms use disjoint container prefixes `eval2-ws-` / `eval2-ns-` and `-p 0:6379`.
All four were told to write `transcript.md`, the with-skill arms also `usage.json`, and never to run `git`.

Output roots: `dragonfly-scripting-workspace/iteration-2/eval-<N>-<name>/{with_skill,without_skill}/run-1/outputs/`.

Last observed state: both eval-1 arms were mid-benchmark (containers `eval2-ws-df`, `eval2-ns-df` up,
`outputs/bench/{orig.lua,seed.py,spec.json}` and `outputs/bench_{seed,reset}.lua` written); both eval-2 arms
had produced no output file yet.

The description loop is running in background, log
`dragonfly-scripting-workspace/trigger-loop.log`, last line `Iteration 1/5`, split `12 train, 8 test
(holdout=0.4)`. **Starting description** (this is the "before" baseline, record its held-out score from the
log): `Design, review, optimize and measure server-side Lua on Dragonfly - EVAL/EVALSHA scripts, redis.call
loops, hashtags and key layout, SCRIPT LATENCY, the eval coordination counters, the --!df flags directive,
--lock_on_hashtags, and porting Redis Lua to Dragonfly. ...` (full text in the log, line 5).

## To finish — exact steps

1. **Collect the four runs.** Wait for the four `implementer` agents. Write
   `run-1/timing.json` per run as `{"total_tokens": N, "duration_ms": N, "tool_uses": N}` from each
   completion notification's `<usage>` block (that is how iteration-1 did it). Copy each
   `eval_metadata.json` into every `run-1/` — `eval-viewer/generate_review.py:91` only looks in `run_dir`
   and `run_dir.parent`. Mirror the deliverables into `<config>/artifacts/` as iteration-1 did.
2. **Tear down** every `eval2-*` container (`docker rm -f $(docker ps -aq --filter name=eval2-)`).
   Do not touch `dfskill-*`.
3. **Grade**: one `reviewer`/Opus per eval, both arms, reading
   `/Users/pzixel/.claude/plugins/cache/claude-plugins-official/skill-creator/b5439c41ae98/skills/skill-creator/agents/grader.md`,
   writing `grading.json` per run. For eval 1 the grader re-measures original / with / without on **one**
   container via `dragonfly-scripting/scripts/bench_script.py --compare --reseed` with
   `dragonfly-scripting/assets/examples/claim_mailbox_batch_{spec.json,seed.py}`, using `lab/.venv/bin/python`.
4. **Aggregate + viewer**, from the skill-creator plugin dir:
   `python3 -m scripts.aggregate_benchmark <ws>/iteration-2 --skill-name dragonfly-scripting`
   then `python3 eval-viewer/generate_review.py <ws>/iteration-2 --skill-name dragonfly-scripting
   --benchmark <ws>/iteration-2/benchmark.json --previous-workspace <ws>/iteration-1
   --static <ws>/iteration-2/review.html`.
5. **`iteration-2/ANALYSIS.md`** (≤40 lines): pass rates per eval per arm vs iteration-1, whether the new
   eval-1 assertions discriminate, the reply-only limitation, latency table. Copy deliverables to
   `artifacts/`. Commit.
6. **Trigger loop**: `tail -20 trigger-loop.log`. Apply `best_description` to the SKILL.md frontmatter
   **only if its held-out score ≥ the starting one**; record before/after in the report. Commit.
7. **Install (do this only after every eval run has finished** — a symlink under `~/.claude/skills/` would
   let the without-skill baseline arms auto-discover the skill and contaminate the comparison):
   `ln -s /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting ~/.claude/skills/dragonfly-scripting`
   and the same under `~/.codex/skills/`. Both targets were checked with `ls -la` and **neither contains a
   `dragonfly-scripting` entry**, so no collision and nothing to preserve. Re-run `quick_validate.py` after.
8. **`REPORT.md`** at the repo root, `implementer`/Opus ≤20 turns, Russian, ≤120 lines, every number
   traceable to `lab/RESULTS.md`, `iteration-*/benchmark.md` or `ANALYSIS.md`. Commit.

## Out of scope
No push, no merge. `/Users/pzixel/Documents/Repos/email-stats` was read-only and untouched. Eval 3 was not
rerun (phase-4 decision 4). The skill name, folder and `agents/openai.yaml` were not changed.

## Open decisions for the owner
1. **`[df-doc]` tag for checklist item 11.** The redundant-write rule cites only `[lab Q6][S1]`. Either add
   an S-row to `references/sources.md` for a Dragonfly replication/journal doc and restore the `[df-doc]`
   half, or accept the lab-only citation. Per the Evidence rule a lab measurement alone is sufficient, so
   this is cosmetic consistency, not a gate.
2. **Skill edited mid-run.** The four eval runs were started from the working tree immediately after the
   step-1 edits and just before commit `944d4d2`, and the trigger loop rewrites the `description:`
   frontmatter while the with-skill arms may still be reading SKILL.md. The with-skill arms were pointed at
   the skill explicitly, so the description does not affect their behaviour, but disclose this in ANALYSIS.
3. **`timing.json` provenance.** Captured from completion notifications, not measured by the runs
   themselves — same method as iteration-1, so the arms stay comparable, but it is not wall-clock isolated.

## Verification step that proves the done part
```
cd /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench
git show --stat 944d4d2
python3 /Users/pzixel/.codex/skills/.system/skill-creator/scripts/quick_validate.py dragonfly-scripting
grep -n "lock_on_hashtags" dragonfly-scripting/SKILL.md | head -3
sed -n '86,100p' dragonfly-scripting/references/measurements.md
python3 -c "import json;d=json.load(open('dragonfly-scripting-workspace/iteration-2/eval-1-optimize-claim-batch/eval_metadata.json'));print(len(d['assertions']))"
```
Expect: `Skill is valid!`, the hashtag rule inside the first 20 lines of SKILL.md, the dated
`SCRIPT FLUSH does not reset SCRIPT LATENCY` entry with `Count: 5` before and after the flush, and `8`.

## Trigger score — BEFORE (starting description, loop iteration 1/5)
Measured by `run_loop` on `trigger-eval.json`, 20 queries, 3 samples each, split 12 train / 8 held-out test:

| split | correct | precision | recall | accuracy |
|---|---|---|---|---|
| train | 19/36 | 100% | 6% | 53% |
| **held-out test** | **12/24** | **50%** | **8%** | **50%** |

The failure mode is **under-triggering, not over-triggering**: every should-not-trigger query passes
(ClickHouse, Postgres, k8s operator, replication, dashtable memory, redis-py, valkey/keydb, cache_mode)
while almost every should-trigger query fails (`rate=0/3` on SCRIPT LATENCY p99, the Lua rate limiter,
pipeline-vs-Lua, the EVALSHA claim script, the 8000-field HGET review, the cjson plan blob, renew_leases_batch,
the BullMQ redis→dragonfly port). Precision 100% on train with recall 6% means the current description is far
too narrow. **Apply `best_description` only if its held-out accuracy ≥ 50%** — that is the bar to beat.
Loop was at iteration 2/5 when this handoff was written; read the final `best_description` and its held-out
score from the tail of `trigger-loop.log`.

## Runs collected after the handoff was first written
**eval-2 / without_skill / run-1 — COMPLETE and collected.** `timing.json` written from the completion
notification (`{"total_tokens": 43684, "duration_ms": 289285, "tool_uses": 9}`), `eval_metadata.json` copied
into `run-1/`, `outputs/REVIEW.md` mirrored to `without_skill/artifacts/REVIEW.md`.
Arm cleanliness: `grep -n "dragonfly-scripting/" transcript.md` returns exactly one hit, at `transcript.md:4`,
and it is the agent restating the prohibition it was given ("`dragonfly-scripting/`, `.claude/skills`,
`.codex/skills`, or `email-stats`"), **not** a skill read. The arm is clean; use this line-level check rather
than a bare count when verifying the other baseline arm.

Note for grading: this unskilled arm **did** flag the redundant writes (its finding 3 covers both
`:403-414` and `:612-618`), so the new eval-2 assertion `flags-redundant-writes` may again fail to
discriminate — the same way it was the unskilled arm that found them in iteration 1. Expect eval 2's delta to
come from the execution-regime and measurement-method assertions instead. Grade it as written; do not
rewrite the assertion after seeing the output.

The other three runs (eval-1 both arms, eval-2 with_skill) were still executing; collect their `timing.json`
from their completion notifications the same way.

## Update — eval 2 fully collected, grading spawned
**eval-2 / with_skill / run-1 — COMPLETE and collected.** `timing.json` =
`{"total_tokens": 54975, "duration_ms": 319925, "tool_uses": 15}`; `eval_metadata.json` copied into `run-1/`;
`outputs/REVIEW.md` mirrored to `with_skill/artifacts/REVIEW.md`.
`usage.json` confirms the skill was used: read `dragonfly-scripting/SKILL.md` and ran
`dragonfly-scripting/scripts/lua_call_audit.py` against the eval input; 0 server interactions (static review,
as in iteration 1).

**A `reviewer`/Opus grader for eval 2 (both arms, 9 assertions) is running** and will write
`grading.json` into both `run-1/` directories. It was told to grade blind, to treat a non-discriminating
assertion as a real result, and not to reinterpret an assertion after seeing the outputs. Collect its report;
if it did not finish, its `grading.json` files are the deliverable to check for.

**Qualitative read (not a grade — the grader decides).** The with-skill arm opens with the execution regime
("24+n declared keys under one hashtag on default flags is io-coordinated, not shard-local — a shared hashtag
does not co-locate without `--lock_on_hashtags`"), prices a hop at ~26.95 µs from the lab, ties the 32 MiB
plan to the Q4 OOM cell, and prescribes `bench_script.py --reseed --compare` with p50+p99 and a replica
attached — i.e. exactly the three edits made in step 1. The without-skill arm never states the regime and
reaches the same top-two findings (`:453` HGET loop, `:553` ZCOUNT loop) by call counting. Both arms flag the
redundant writes, so assertion 9 likely does not discriminate.

**Still outstanding:** eval-1 both arms (containers `eval2-ws-df` / `eval2-ns-df` were still up and
benchmarking), the eval-1 grader with the `--compare --reseed` re-measurement, aggregate + viewer,
`ANALYSIS.md`, the trigger-loop result, install, `REPORT.md`, and the commit of everything under
`iteration-2/`.

## Trigger loop — per-iteration held-out scores (log lines 20, 50, 80)
| iteration | train | held-out test | precision | recall |
|---|---|---|---|---|
| 1 (starting description) | 19/36 = 53% | **12/24 = 50%** | 50% | 8% |
| 2 | 21/36 = 58% | **14/24 = 58%** | 100% | 17% |
| 3 | 20/36 = 56% | 12/24 = 50% | 50% | 8% |
| 4, 5 | (was still running) | | | |

Iteration 2's description is the first candidate to **beat** the 50% starting baseline (58%, precision 100%,
recall 17%). Recall is the binding constraint throughout — the skill under-triggers; it never over-triggers.
Read the final `best_description` from the tail of `trigger-loop.log`, confirm its held-out score is ≥ 50%,
then write it into the `description:` frontmatter of `dragonfly-scripting/SKILL.md` and commit. If the loop
picked a description whose held-out score is below 50%, keep the current one and record that.

## Eval 1 — both arms still running at last check
Both arms have produced an optimized `claim_mailbox_batch.lua` and their own bench harness; neither had
written `NOTES.md` or `transcript.md` yet, and containers `eval2-ws-df` / `eval2-ns-df` were still up.
The with-skill arm reused the shipped `assets/examples` spec/seed (`outputs/bench/{spec.json,seed.py,orig.lua}`
plus a `compare_100.txt` and a `spec100.json`); the baseline arm built its own RESP client (`resp.py`,
`bench.py`, `snapshot.lua`, `bench_seed.lua`, `bench_reset.lua`). Collect both, then run the eval-1 grader.
