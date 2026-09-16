# handoff-2c (phase lead) — `dragonfly-scripting` skill text

Status: **phase 2 done** against every done-condition clause of `phase-2.md`. Nothing pushed, no merge,
no release. Branch `main`, three commits added by this phase.

## Blocker index

| blocker | status | impact | clearance |
|---|---|---|---|
| reviewer REJECT (4 numeric-traceability findings, B1-B4) | **cleared** | skill quoted numbers absent from `lab/RESULTS.md` and one mixed-condition pair | fixed in `969b034`, each number re-verified against a RESULTS.md line |
| `phase-2.md:25` quotes `--lock_on_hashtags` as 26.95 → **1.03** µs/call | **open (spec defect, not a skill defect)** | none in the skill — it quotes 1.54 | owner corrects phase-2.md line 25; see "Open decisions" #1 |

No other blocker. The two non-blocking reviewer findings deliberately left for phase 4 are listed below.

## Commits

| commit | content |
|---|---|
| `0f666ea` | `dragonfly-scripting: skill text + references` — SKILL.md + 7 references + 2 example assets, 10 files, +761 |
| `800ad8e` | `dragonfly-scripting: regenerate agents/openai.yaml from the written SKILL.md` (the tracked file had been generated from the 8-line stub) |
| `969b034` | `dragonfly-scripting: fix reviewer findings (numeric traceability)` — B1-B4 plus six should-fixes |

Predecessor `1e61ac1` (executable tools) untouched. `fable-reviews/` never staged.

## Done, clause by clause (`phase-2.md:5-11`)

| clause | state | evidence |
|---|---|---|
| 6 — SKILL.md ≤250 lines, frontmatter, pushy description, execution model ≤15 lines, review checklist with measured costs, design procedure, measurement procedure, routing | **done** | `dragonfly-scripting/SKILL.md` **163 lines**. §0 regime detection (`:12-28`), §1 execution model 14 bullet lines (`:30-46`), §2 checklist of 10 anti-patterns each with a measured cost and its conditions (`:48-85`), §3 design procedure (`:87-115`), §4 measurement procedure incl. the worked example (`:117-152`), §5 routing (`:154-163`) |
| 7 — seven references | **done** | `references/`: `sources.md` 43, `execution-model.md` 125, `lua-patterns.md` ~115, `measurements.md` ~92, `server-flags.md` 97, `redis-advice-audit.md` ~22 (wide table rows), `redis-differences.md` 57. `redis-advice-audit.md` carries all eleven mandated rows plus MGET-in-Lua and pipeline-depth; every verdict cell leads with **helps/neutral/harms/absent/unverified** |
| 8 — `scripts/` | **done in phase 2b** (`1e61ac1`), unchanged here; SKILL.md §2/§4 were checked against the real interfaces by the reviewer, no findings |
| 9 — `agents/openai.yaml` generated, `quick_validate.py` passes | **done** | regenerated in `800ad8e`; `quick_validate.py dragonfly-scripting` → `Skill is valid!` re-run after `969b034`. The generator templates `short_description` from the display name by design (`generate_openai_yaml.py:74-92`), so "Help with Dragonfly Scripting tasks" is the tool's output, not a stub left behind |
| 10 — one `reviewer` pass (model fable) on the four criteria, findings fixed or recorded | **done** | `fable-reviews/planned/dragonfly-skill/review-2.md`, verdict **REJECT**; all four blocking findings fixed, the non-blocking ones recorded below |
| 11 — committed on `main` | **done** | `969b034` |

Added lead criteria (both met): SKILL.md tells the reader how to detect the execution regime **before**
optimizing — the regime table plus the counter diff is section 0, the first thing after the title
(`SKILL.md:12-28`), reviewer criterion 5 "passes"; and the audit table holds the spec's minimum rows,
reviewer criterion 6 "no findings".

## Evidence rule compliance

Every performance rule carries a `[lab Qn]` / `[df-src …]` / `[df-doc …]` tag **and** an `[Sn]` tag into
`references/sources.md` (30 rows, each naming its `SOURCES.md` row). Reviewer criterion 2: "no performance
rule rests on a Redis-only source; all `[Sn]` tags (S1-S30) resolve." Redis-Lua semantics (array truncation
at the first `nil`, RESP2 null → `false`, globals protection) carry a `[semantics]` marker instead of a
performance tag. Two rules kept but marked **unverified** for lack of a Dragonfly measurement: "send
read-only scripts to a replica" (EVAL_RO exists per Q9, but no lab cell ran a script on the replica) and
"raise pipeline depth" (no lab cell varied it). `SOURCES.md` stays at 93 rows — no worker read a web page.

## Files and interfaces touched

- `dragonfly-scripting/SKILL.md` (new, 163) — frontmatter `description` at `:3` is the trigger string phase 4 optimizes.
- `dragonfly-scripting/references/{sources,execution-model,lua-patterns,measurements,server-flags,redis-advice-audit,redis-differences}.md` (new).
- `dragonfly-scripting/assets/examples/claim_mailbox_batch_seed.py`, `…_spec.json` (new) — 2b's live `--compare` seed, rescued from `/tmp/dfscratch` before reboot; referenced from `SKILL.md` §4 and `measurements.md`.
- `dragonfly-scripting/agents/openai.yaml` (regenerated).

## Evidence files

- `fable-reviews/planned/dragonfly-skill/review-2.md` — fable review, 36 lines, blocker index + criteria.
- `fable-reviews/planned/dragonfly-skill/handoff-2c.md` — the text implementer's own handoff (per-file spec-clause mapping).
- New lab observation recorded in `references/measurements.md:12-14`: `CONFIG GET lock_on_hashtags` returns an **empty reply** on df-v1.34.0 (lab primary, 2026-09-16), which is why the skill routes regime detection to the counters and the process args.

## Out of scope / not done

- `dragonfly-scripting/scripts/` and `assets/compose.yaml` — phase 2b, untouched.
- No push, no merge, no release. Phase 3 (evals) not started.
- The unrecorded re-run behind the worked example (orig ~42.8 ms vs hmget ~8.7 ms, 30 iterations) was
  **deleted from the skill** rather than back-filled into `lab/RESULTS.md`: it is a real observation from
  2b but has no logged conditions, and fabricating a RESULTS entry would break the Evidence rule. The
  worked example now points at the recorded Q7 cell for magnitudes.

## Open decisions for the owner

1. **`phase-2.md:25` is wrong.** It states `--lock_on_hashtags` moves a one-hashtag multi-key script
   26.95 → **1.03** µs/call. `lab/RESULTS.md:184` says **1.54** µs/call for that shape; 1.01 is the
   *1-key, default-primary* figure and 1.03 appears nowhere. The skill quotes 1.54. Correct the spec line
   so phase 3/4 do not reintroduce 1.03.
2. **Description length (reviewer, non-blocking).** ~110 words after trimming. Phase 4 optimizes triggers;
   decide there whether to shorten further, keeping the generic-caching exclusion that criterion 3 needs.
3. **Residual duplication (reviewer, non-blocking).** The Q5 regime numbers appear in `SKILL.md:14-28`,
   `execution-model.md:50-59` and `redis-differences.md:40` with different mechanism detail. Left as is:
   §0 must stand alone for the decision it drives. Revisit only if phase 3 shows agents skipping references.
4. **Zero-hit audit rule (from 2b).** `undeclared-key` fires 0 times on the 52-script corpus; it is kept in
   the SKILL.md checklist as item 7 because the failure mode is a server-wide GLOBAL transaction, not
   because the corpus exercises it. Confirm or drop in phase 4.

## One verification step that proves the phase

```
cd /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench && \
python3 /Users/pzixel/.codex/skills/.system/skill-creator/scripts/quick_validate.py dragonfly-scripting && \
wc -l dragonfly-scripting/SKILL.md && \
grep -c '^|' dragonfly-scripting/references/redis-advice-audit.md
```
Expect `Skill is valid!`, `163`, and ≥13 table lines (11 mandated advice rows + header + separator).
