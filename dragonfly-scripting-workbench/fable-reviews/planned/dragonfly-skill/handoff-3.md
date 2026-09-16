# handoff-3 — prove the skill is used and has an effect

**Phase 3 done.** Commit `5d48645` on `main`, no push.

## Done
6 runs = 3 evals x {with_skill, without_skill}, all `implementer`/Opus (same tools, same model), each pair spawned in
one turn. Prompts verbatim from `dragonfly-scripting-workspace/evals/evals.json`. The with-skill prompt opens with
"Use the skill at .../dragonfly-scripting (read its SKILL.md first and follow it)."; the without-skill prompt names no
skill and only adds "work from your own knowledge plus the files named in the task". Neither arm was told the expected
answer. Eval-1 arms got disjoint container prefixes (`eval-1-ws-`, `eval-1-ns-`) and `-p 0:6379` so they ran
concurrently on separate keyspaces. Nothing touched `dfskill-*` or `/Users/pzixel/Documents/Repos/email-stats`.

`eval_metadata.json` written per eval **before** grading (7/8/8 objective assertions from phase-3 spec line 12), and
copied into each `run-1/` because `eval-viewer/generate_review.py:91` only looks in `run_dir` and `run_dir.parent`.
Graded by one `reviewer`/Opus per eval covering both arms. All `eval-*` containers torn down.

### Pass rates (`benchmark.json`, `benchmark.md`, `review.html`)
| eval | with_skill | without_skill |
|---|---|---|
| 1 optimize-claim-batch | 6/7 = 0.86 | 6/7 = 0.86 |
| 2 review-apply-page | 8/8 = 1.00 | 6/8 = 0.75 |
| 3 design-new-op | 8/8 = 1.00 | 5/8 = 0.63 |
| aggregate | **95.3%** | **74.7%** (delta +0.21) |

### Measured latency, eval 1 (grader ran it, one container, shipped spec+seed, `--reseed`, 30 iters)
original 100 114 us (paired with A) / 41 852 us (paired with B); with_skill 6 424 us; without_skill 6 046 us.
`bench_script.py --compare` exit 0 for both arms vs original and for A vs B. The two optimized scripts are
indistinguishable — eval 1 does not discriminate on speed.

### Usage evidence (`usage.json` per run)
All three with-skill runs read SKILL.md. eval 1 also ran `scripts/bench_script.py` + `scripts/lab.sh` and reused
`assets/examples/claim_mailbox_batch_{seed.py,spec.json}`; eval 2 read execution-model + lua-patterns (static only);
eval 3 read lua-patterns + measurements and ran `scripts/lab.sh` (33 server interactions). No baseline transcript
contains any path under `dragonfly-scripting/` (grep count 0).

## Files and interfaces touched
- `dragonfly-scripting-workspace/iteration-1/` (new, 49 files committed): per run `eval_metadata.json`, `grading.json`,
  `timing.json`, `transcript.md`, `usage.json`; per config `artifacts/` holding the two optimized
  `claim_mailbox_batch.lua`, the two `renew_leases_batch.lua`, both `REVIEW.md`, both `DESIGN.md`, both `NOTES.md`;
  top level `ANALYSIS.md`, `benchmark.json`, `benchmark.md`, `review.html`.
- `outputs/` stays gitignored by `.gitignore:3` (`*-workspace/iteration-*/**/outputs/`), which is why `artifacts/` exists.
- No source file outside the workspace was modified.

## Open decisions for the owner
1. **Eval 1 assertion 4 (`payload-reads-bounded-by-batch-size`) is unsound and must be dropped or restated.** Bounding
   the record read changes replies: the original returns `PROTOCOL record_missing` for eligible candidates past the
   32nd. It contradicts assertion 6 and the prompt. Both arms failed it identically, so the A/B comparison holds, but
   eval 1 currently measures nothing.
2. Eval 1 assertion 7 passes by omission; a positive phrasing ("must cite a Dragonfly execution-path counter") would
   separate the arms. No eval-1 assertion checks post-state, only replies.
3. Whether to add an assertion for redundant writes (`:612-616`, `:403-415`) — the one place the **unskilled** arm
   found more than the skilled one.

## Skill defect found on a live v1.34.0 node (for phase 4)
`SCRIPT FLUSH` did **not** reset an existing sha's `SCRIPT LATENCY` histogram (sample count carried over). This
contradicts `dragonfly-scripting/references/measurements.md` and SKILL.md 4.4. Fix: difference before/after or restart.

## Out of scope
No push, no merge, no production writes, no release. Phase 4 not started.

## One verification step that proves the phase
```
cd /Users/pzixel/.claude/plugins/cache/claude-plugins-official/skill-creator/b5439c41ae98/skills/skill-creator
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/lab/.venv/bin/python -m scripts.aggregate_benchmark \
  /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/iteration-1 \
  --skill-name dragonfly-scripting
```
prints `With Skill: 95.3% / Without Skill: 74.7% / Delta: +0.21` over 6 graded runs.
