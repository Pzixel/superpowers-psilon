# Phase 4 — refine, optimize triggering, install, final report

Goal: apply what phase 3 measured, make the skill trigger reliably, install it where both agents (Claude Code, Codex) discover it, and leave a report the user can read cold.

## Done-condition
- Skill revised per `dragonfly-scripting-workspace/iteration-1/ANALYSIS.md` ("what the skill should change"); each change traced to an observed failure or a non-discriminating assertion, no new universal MUSTs. If the with-skill arm lost on any assertion, iteration-2 reruns that eval (both arms) and the ANALYSIS is updated.
- Description optimization: 20 trigger queries (8–10 should-trigger, 8–10 tricky should-not: Redis-only questions, ClickHouse/Postgres, generic caching, Dragonfly operator/k8s ops, BullMQ config without Lua) in `dragonfly-scripting-workspace/trigger-eval.json`; run `python -m scripts.run_loop --eval-set <json> --skill-path <skill> --model claude-fable-5-1 --max-iterations 5 --verbose` from the skill-creator plugin dir; apply `best_description` if its held-out score ≥ current; record before/after scores.
- Install: symlinks `~/.claude/skills/dragonfly-scripting` and `~/.codex/skills/dragonfly-scripting` → the repo folder (check for name collisions first; do not overwrite an existing directory). `quick_validate.py` passes on the final folder.
- `REPORT.md` at the repo root, ≤120 lines, in Russian: what the skill is, the two execution regimes with numbers, the four measured findings on the example workload (claim batching, apply/remove per-grant HGET, plan blob, lock_on_hashtags trade-off), evidence that agents use the skill (usage.json summary) and that it helps (pass rates, latency delta, tokens/time), the sources count by tier, how to run the lab and the evals again, and what was not done.
- Committed on `main`.

## Decisions taken on handoff-3 open items
1. Eval 1 assertion 4 (`payload-reads-bounded-by-batch-size`) is deleted as unsound. Replace with two discriminating assertions: (a) "states the execution regime with evidence" — the notes say the script is io-coordinated on default flags because a shared hashtag does not co-locate keys, backed by the `eval_*` counters or an equivalent measurement; (b) "before/after measured on identical seeded state with a reply-equality check and p50+p99 reported". Keep the reply-protocol/recovery assertion.
2. Eval 1 keeps reply-only checking (no post-state dump) — the `--compare` gate is the contract; note the limitation in ANALYSIS.
3. Eval 2 gains an assertion "flags redundant writes: delete-and-reinsert of unchanged grants (`:612-616`) and rewrite of records already proven identical (`:403-415`)".
4. Iteration 2 reruns evals 1 and 2 only (both arms, fresh implementers, same prompts); eval 3's iteration-1 result stands. Grade with the revised assertions; regenerate benchmark + viewer with `--previous-workspace`.
5. Skill changes 1–4 from ANALYSIS.md are all applied (SCRIPT FLUSH correction after a one-shot lab verification; hashtag/co-location rule promoted into the intro; redundant-write-elimination rule added to the checklist with `[df-doc]`/`[lab Q6]` evidence for journal/replica cost; `--compare --reseed` named in §0 or the intro as the rule for any before/after claim). Each change is a narrow edit; SKILL.md stays ≤250 lines.

## Known corrections to apply (from handoff-3)
- The eval-3 with-skill run observed on a live v1.34.0 node that `SCRIPT FLUSH` does NOT reset an existing sha's `SCRIPT LATENCY` histogram (sample count carried over). `references/measurements.md` and SKILL.md §4.4 claim it does. Verify once on the lab (load script, run, `SCRIPT FLUSH`, reload same text, `SCRIPT LATENCY`), then correct both places: the histogram is cumulative for the server's lifetime; difference before/after (`script_latency.py --watch`) or restart the node.

## Constraints
- Workers: `implementer` (Opus) for revisions/report; the trigger loop is run by the phase-lead itself via Bash (it takes minutes; run in background and poll the log). No `general-purpose`.
- Do not change the skill's name or folder. Preserve `agents/openai.yaml` policy.
