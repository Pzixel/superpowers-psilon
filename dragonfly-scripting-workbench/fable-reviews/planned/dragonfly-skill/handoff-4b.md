# handoff-4b — finish phase 4 after the rate-limit kill

**Done.** Eval 1 rerun (both arms) and graded, eval 2 graded, benchmark + viewer regenerated,
`iteration-2/ANALYSIS.md` written, `REPORT.md` written. Two commits on `main`, nothing pushed.
Symlink install and the `description:` line were left to the main session, as instructed.

## Commits
| hash | content |
|---|---|
| `dc4b8eb` | iteration-2 eval-1 rerun (both arms), grading for evals 1 and 2, `benchmark.{json,md}`, `review.html`, `ANALYSIS.md` — 19 files, 3473 insertions |
| `c97cfa7` | `REPORT.md` (Russian, 86 lines) |

## Results

| eval | with (it-2) | without (it-2) | with (it-1) | without (it-1) |
|---|---|---|---|---|
| 1 optimize-claim-batch | 8/8 = 1.000 | 6/8 = 0.750 | 6/7 = 0.857 | 6/7 = 0.857 |
| 2 review-apply-page | 9/9 = 1.000 | 6/9 = 0.667 | 8/8 = 1.000 | 6/8 = 0.750 |
| 3 design-new-op (it-1 copy) | 8/8 = 1.000 | 5/8 = 0.625 | 8/8 = 1.000 | 5/8 = 0.625 |
| **total** | **25/25 = 100%** | **17/25 = 68%** | 22/23 = 95.3% | 17/23 = 73.9% |

`benchmark.md`: with 100% ± 0%, without 68% ± 6%, delta +0.32; tokens 59773 ± 8694 vs 48053 ± 12443.

Grader re-measurement, one fresh `eval1g-*` container, df-v1.34.0 `--proactor_threads=4`, 30 iters + 5
warmup, `bench_script.py --reseed --compare`; all three runs printed
`replies identical on this seed (164 fields, ignored [1, 7, 12, …162])`, coordination
`shardlocal=0.00 io=1.00 -> cross-shard` every time:

| run | script | p50 µs | p99 µs | SCRIPT LATENCY avg µs |
|---|---|---|---|---|
| A | original | 99270.6 | 153354.5 | 96029.7 |
| A | with_skill | 7446.3 | 10883.2 | 5794.1 |
| B | original | 68480.6 | 71497.2 | 67381.5 |
| B | without_skill | 6749.9 | 11164.3 | 5360.9 |
| C control | original vs original | 97735.9 / 97756.0 | 119023.8 / 130951.9 | ratio 1.000 |

The original's p50 drifts 68–99 ms between runs, so only each arm's own before/after ratio is meaningful.

## Files and interfaces touched
- `dragonfly-scripting-workspace/iteration-2/eval-1-optimize-claim-batch/{with_skill,without_skill}/run-1/`
  — `outputs/` (gitignored), `transcript.md`, `timing.json`, `eval_metadata.json`, `grading.json`;
  `with_skill/run-1/usage.json`; deliverables mirrored into `<arm>/artifacts/`.
- `.../eval-2-review-apply-page/{with_skill,without_skill}/run-1/grading.json` (new; the runs, timing and
  artifacts were already committed in `237fa1f`).
- `dragonfly-scripting-workspace/iteration-2/{ANALYSIS.md:1-36,benchmark.json,benchmark.md,review.html}`.
- `REPORT.md:1-86` (placeholder line at `REPORT.md:70` — `Итоговая description: см. SKILL.md`).
- Not touched: `dragonfly-scripting/` (skill text and `description:`), `~/.claude/skills`, `~/.codex/skills`,
  `/Users/pzixel/Documents/Repos/email-stats`.

## Evidence files
`iteration-2/ANALYSIS.md`, `iteration-2/benchmark.md`, `iteration-2/review.html`, the four `grading.json`,
the four `transcript.md`, `with_skill/run-1/usage.json` per eval.

## Out of scope / not done
No push, no merge. Symlink install not done (main session owns it) — until it is done, a `~/.claude/skills`
entry would contaminate any future baseline arm, so install only after the last eval run. The
`description:` frontmatter was not touched. Eval 3 was not rerun (phase-4 decision 4). The trigger loop was
not restarted: `trigger-loop.log` ends in `RuntimeError: claude -p exited 1` (rate limit) on iteration 5/5.
`dragonfly-scripting-workspace/trigger-handtuned.log` (193 lines, no result lines yet) is left untracked —
it looks like the main session's in-flight hand-tuned description run.

## Open decisions for the owner
1. **Final `description:`** — the loop's best held-out score was 62% accuracy / 25% recall / 100% precision
   (`trigger-loop.log:110`) vs the starting description's 50% / 8% / 50% (`:20`); the loop crashed before
   finishing, so no `best_description` was applied. `REPORT.md:70` carries the placeholder.
2. **eval-2 `timing.json` provenance** — those two files came from commit `237fa1f` (written by the main
   session from completion notifications of runs the killed lead had started); this lead could not
   re-verify them and did not overwrite them with nulls. Disclosed in `ANALYSIS.md`.
3. **Assertion design** — in eval 1 the two new assertions split the arms on reporting discipline only; the
   baseline script is as fast and as reply-identical as the with-skill one. In eval 2 the baseline review
   rested on a false premise (hashtag co-location on default flags) that only assertion 6 caught, and both
   arms passed the new `flags-redundant-writes`. If a further iteration is wanted, tighten those two.
4. **Checklist item 11 `[df-doc]` tag** — still open from handoff-4 (cosmetic, lab citation suffices).

## Verification step that proves the phase
```
cd /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench
python3 -c "import json;d=json.load(open('dragonfly-scripting-workspace/iteration-2/benchmark.json'));print(d['summary'] if 'summary' in d else list(d)[:5])"
head -13 dragonfly-scripting-workspace/iteration-2/benchmark.md   # with 100% / without 68% / delta +0.32
git show --stat dc4b8eb c97cfa7 | head -30
```
