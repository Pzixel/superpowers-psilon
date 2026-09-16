# handoff-2 — phase 2 (`dragonfly-scripting` skill)

Status: **NOT DONE — incomplete at the phase lead's turn limit.** Two `implementer`
workers were still running when this handoff was written; their commits, if any, land on
`main` after this file. **The main session must re-check `git log --oneline` and
`find dragonfly-scripting -type f` before acting on this handoff.**

## Blocker index

| blocker | status | impact | clearance |
|---|---|---|---|
| phase-lead turn budget exhausted while both implementers still running | open | SKILL.md + references not verified as written; reviewer pass never spawned | main session re-checks the tree, then spawns the `reviewer` (model `fable`) pass described below |
| `reviewer` design-review pass (done-condition clause 5) | not started | done-condition clause unmet | spawn it once SKILL.md + `references/` exist |
| `generate_openai_yaml.py` + `quick_validate.py` (done-condition clause 4) | not run | done-condition clause unmet | run after both halves land (see verification step) |

No other blocker found. Nothing was pushed; no merge, no release.

## Done per done-condition

| clause | state at write time |
|---|---|
| `dragonfly-scripting/SKILL.md` ≤250 lines with the required sections | **not met** — only the 8-line `init_skill.py` placeholder exists |
| `dragonfly-scripting/references/` (7 files) | **not met** — directory empty |
| `dragonfly-scripting/scripts/` (4 tools) | **not met** — directory empty |
| `dragonfly-scripting/assets/compose.yaml` | **met** — written by implementer 2b, uncommitted |
| `agents/openai.yaml` via `generate_openai_yaml.py`, `quick_validate.py` passes | **not met** — only the `init_skill.py` stub exists; the generator was deliberately deferred to after both halves land |
| one `reviewer` (model `fable`) design-review pass, findings fixed or recorded | **not met** — not spawned |
| committed on `main` | **not met** — no phase-2 commit; `git log` head is `6e73591` (a main-session commit) |

## What was actually done in this phase

1. Verified every phase-2 input exists and is readable: `lab/RESULTS.md` (488 lines,
   summary table at `:11-24`, appendix blocks delimited `<!--BEGIN qN-->`/`<!--END qN-->`),
   the four `research/*.md` reports (300/347/300/277 lines), `SOURCES.md` (106 lines,
   93 rows, next free number **94**), `lab/Q7-CONTRACT.md` (86 lines),
   `lab/bench/common.py` (506 lines), `lab/compose.yaml`, `lab/variants/claim_mailbox_batch.{orig,hmget}.lua`,
   and the skill-creator tooling at `/Users/pzixel/.codex/skills/.system/skill-creator/scripts/`
   (`init_skill.py`, `generate_openai_yaml.py`, `quick_validate.py` all present).
2. **Confirmed the four required audit-script hit sites by direct inspection** of the
   read-only corpus `/Users/pzixel/Documents/Repos/email-stats/crates/dragonfly-store/assets/`
   (52 `.lua` files). The line numbers in the phase-2 spec are exact:
   - `apply_new_mutable_mailbox_page.lua:453` — `local old_payload = redis.call('HGET', KEYS[7], field)` in a per-grant loop.
   - `remove_mutable_mailbox.lua:314` — `local payload = redis.call('HGET', KEYS[7], field)` in a per-grant loop.
   - `apply_new_mutable_mailbox_page.lua:673-674` — `cjson.encode(header)` / `cjson.encode(plan)`.
   - `claim_mailbox_batch.lua:176-182` — candidate window read, payload fetched before the batch-size check.
3. Read the Q5 appendix block in full and carried its verdict/mechanism/fast-path-killer
   paragraphs verbatim into both worker briefs (the two-regime decision, the counter
   split, `disable-atomicity`/`allow-undeclared-keys` as fast-path killers).
4. Spawned two `implementer` (Opus) workers on **disjoint file sets** so they could run
   concurrently without a git index race:
   - **2a — skill text.** Writes `SKILL.md` + the seven `references/*.md`. Brief carries:
     the binding evidence rule, the `[lab Qn]`/`[df-src]`/`[df-doc]` + `[S<n>]` tagging
     scheme, the ≤30-row `references/sources.md` requirement, all six decisions D1–D6
     from the spec (two regimes; recommendation order for the example workload; the
     contract-preserving `claim_mailbox_batch` rewrite and the separate "bound payload
     reads" contract decision; `--lock_on_hashtags` as a measured trade-off never a
     default; Q10 ratios vs standalone absolutes; conditions quoted with every number),
     the required contents of each reference file including the minimum
     `redis-advice-audit.md` rows, and the skill-creator style constraints.
     Instructed **not** to run the yaml generator or validator.
   - **2b — scripts + assets.** Writes `scripts/{lua_call_audit.py,script_latency.py,bench_script.py,lab.sh}`
     and `assets/compose.yaml`, vendoring what it needs from `lab/bench/common.py`
     (`parse_script_latency` `:211`, `format_script_latency` `:243`, `percentiles` `:136`,
     `time_calls` `:256`, counter helpers `:401-470`) rather than importing it, so the
     skill is self-contained when copied. `lua_call_audit.py` must be pure stdlib, exit 0,
     hit the four sites above, and keep the whole 52-file finding list **≤150 lines**.
     Brief requires live evidence: bring the lab up, run `script_latency.py` and
     `bench_script.py --compare orig vs hmget` (reply-equality asserted, not loosened),
     then tear down.

## Files and interfaces touched

- `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/SKILL.md` — 8-line placeholder from `init_skill.py`.
- `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/agents/openai.yaml` — `init_skill.py` stub, **must be regenerated**.
- `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/assets/compose.yaml` — copy of `lab/compose.yaml` (primary :6379, replica :6380, `single` profile :6381 at `--proactor_threads=1`, image pinned by digest).
- `dragonfly-scripting/{references,scripts}/` — created, empty at write time.
- Nothing under `lab/`, `research/`, `SOURCES.md` was modified by this phase lead.
- `/Users/pzixel/Documents/Repos/email-stats` was read only.

## Evidence files

- `lab/RESULTS.md` — the only admissible source of numbers (summary `:11-24`; per-question
  blocks by `<!--BEGIN qN-->`). Raw logs `lab/results/qN.txt`.
- No new evidence file was produced by this phase.
- `fable-reviews/planned/dragonfly-skill/review-2.md` — **does not exist yet**; it is the
  output path for the reviewer pass below.

## Out of scope

Phase 3 (evals with-skill vs baseline, benchmark, viewer) and phase 4 (refinement,
description optimization, final report). No push, no merge, no release — those stay with
the main session and the user.

## Open decisions for the owner

1. **Reviewer pass not run.** Spawn `reviewer` with `model: fable`, findings file
   `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/fable-reviews/planned/dragonfly-skill/review-2.md`,
   against the four criteria in `phase-2.md:10`: (1) every numeric claim traceable to
   `lab/RESULTS.md`, every behavioral claim to a URL in `research/`; (2) no Redis-origin
   advice without Dragonfly evidence, and no generic advice a capable model already knows;
   (3) the `description` triggers on the listed intents and **not** on generic Redis
   caching questions; (4) skill-creator principles at
   `/Users/pzixel/.codex/skills/.system/skill-creator/SKILL.md:10-30`.
   Then one short `implementer` fix round if findings block.
2. **`agents/openai.yaml` still a stub.** Run
   `python3 /Users/pzixel/.codex/skills/.system/skill-creator/scripts/generate_openai_yaml.py`
   and `quick_validate.py` (same folder) after both halves land, before the reviewer pass
   if convenient.
3. **Audit false-positive count not yet measured.** The handoff was to report findings per
   file over the 52-file corpus; implementer 2b was told the budget is ≤150 lines total.
   Unreported — take it from 2b's own reply or re-run
   `python3 dragonfly-scripting/scripts/lua_call_audit.py /Users/pzixel/Documents/Repos/email-stats/crates/dragonfly-store/assets/ | wc -l`.
4. **Nothing is committed.** Both workers were told to commit their own halves on `main`
   with explicit `git add <path>` (never `git add -A`). If they died before committing,
   the working tree holds the work — check `git status` before any destructive operation.

## One verification step that proves the phase

```
cd /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench && \
  wc -l dragonfly-scripting/SKILL.md dragonfly-scripting/references/*.md && \
  python3 /Users/pzixel/.codex/skills/.system/skill-creator/scripts/quick_validate.py dragonfly-scripting && \
  python3 dragonfly-scripting/scripts/lua_call_audit.py \
    /Users/pzixel/Documents/Repos/email-stats/crates/dragonfly-store/assets/ \
  | tee /tmp/audit.txt | grep -E 'apply_new_mutable_mailbox_page\.lua:(453|673|674)|remove_mutable_mailbox\.lua:314|claim_mailbox_batch\.lua:1[78][0-9]' ; \
  wc -l /tmp/audit.txt
```
Passes when: `SKILL.md` ≤250 lines, all seven references non-empty, `quick_validate.py`
exits 0, all four required sites appear, and `/tmp/audit.txt` is ≤150 lines.

## Late update (phase lead's last turn)

Implementer 2b was still producing files as this phase lead ended. Tree at that moment,
still **uncommitted**:

```
dragonfly-scripting/SKILL.md                  (8-line placeholder — 2a had not written yet)
dragonfly-scripting/agents/openai.yaml        (init_skill stub)
dragonfly-scripting/assets/compose.yaml       (done)
dragonfly-scripting/scripts/lua_call_audit.py (in progress)
dragonfly-scripting/scripts/test_lua_call_audit.py
dragonfly-scripting/references/               (empty — 2a had not written yet)
```

Both implementers keep running after this handoff and commit their own halves on `main`.
Re-run the verification step above before concluding anything about the phase state.
Note `scripts/test_lua_call_audit.py`: 2b was told at most one focused test for a
non-trivial pure rule is acceptable and nothing ceremonial — audit it against the Tests
gates before keeping it.

## Update 2 — implementer 2b landed

`1e61ac1  dragonfly-scripting: executable tools (audit, latency, bench, lab)` is on `main`.
2b had hit its 40-turn limit with everything written but nothing committed; it was resumed
**once** (its one permitted resumption) with a commit-first instruction and committed.

Committed files (line counts at commit time):

| file | lines |
|---|---|
| `dragonfly-scripting/scripts/lua_call_audit.py` | 323 |
| `dragonfly-scripting/scripts/_common.py` | 253 |
| `dragonfly-scripting/scripts/bench_script.py` | 202 |
| `dragonfly-scripting/scripts/script_latency.py` | 92 |
| `dragonfly-scripting/scripts/lab.sh` | — |
| `dragonfly-scripting/scripts/test_lua_call_audit.py` | 41 |
| `dragonfly-scripting/assets/compose.yaml` | — |

**Implementer 2a (SKILL.md + the seven `references/*.md`) never wrote a single file** in
roughly five hours. `SKILL.md` is still the 8-line `init_skill.py` placeholder and
`references/` is still empty. This is the phase's central gap: the skill has tools but no
text, so the done-condition's first two clauses and the reviewer pass all remain unmet.
Re-spawn a fresh `implementer` for the skill text rather than resuming 2a (it is far past
the 15-turn staleness bound for new scope).

Evidence still NOT obtained, and not to be assumed: the `lua_call_audit.py` self-test
counts over the 52-file corpus (the <=150-line false-positive budget), and the live run of
`script_latency.py` / `bench_script.py --compare`. Take these from 2b's own reply if it
reports them, or re-run the verification step above. Do not record a number nobody observed.

## Update 3 — audit self-test evidence (run by the phase lead, not reported by a worker)

`python3 dragonfly-scripting/scripts/lua_call_audit.py /Users/pzixel/Documents/Repos/email-stats/crates/dragonfly-store/assets/`
at commit `1e61ac1`: **exit 0, 66 findings in 18 of the 52 files** — inside the <=150-line
false-positive budget, with room to spare. All four required sites are flagged:

- `apply_new_mutable_mailbox_page.lua:453` — `batchable-hash`: per-item HGET in the loop opened at line 440.
- `apply_new_mutable_mailbox_page.lua:673` and `:674` — `cjson-hot`: `cjson.encode(header)` / `cjson.encode(plan)`.
- `remove_mutable_mailbox.lua:314` — `batchable-hash`: per-item HGET in the loop opened at line 303.
- `claim_mailbox_batch.lua:184` — flagged twice, by `batchable-hash` **and** by `read-past-bound`
  ("HGET is issued for every candidate, but the loop's own bound check at line 233 discards
  most of them"). That is exactly the payload-read-before-the-batch-size-check pattern the
  spec asked for; note the spec pointed at `:178+` and the finding lands at `:184`, the
  `redis.call` line inside the loop opened at `:183`.

Findings per file, top offenders: `claim_mailbox_batch.lua` 9, `apply_new_mutable_mailbox_page.lua` 9,
`write_catalog_page.lua` 8, `import_cursor_page.lua` 5, `claim_mailbox.lua` 5,
`write_catalog_grant_page.lua` 4.

Still NOT obtained: the live run (`script_latency.py`, `bench_script.py --compare`). The
reply-equality assertion between `lab/variants/claim_mailbox_batch.{orig,hmget}.lua` has
NOT been re-checked in this phase; `lab/RESULTS.md` Q7 recorded the replies as identical on
the lab seed, but per the handoff-1 decision the hmget variant's narrowed `record_missing`
check is not contract-neutral in general, so treat that as unverified here.

## Update 4 — CORRECTION to Update 3: the live run WAS done

Update 3's closing paragraph is wrong and is retracted. Implementer 2b had already
collected the live evidence before it committed; my resumption message was based on stale
state. 2b's own handoff: `fable-reviews/planned/dragonfly-skill/handoff-2b.md`.

Live run, all values observed by 2b (lab up -> down clean, df v1.34.0, `--proactor_threads=4`,
primary+replica healthy):
- `script_latency.py` rendered the cumulative table for both shas; `--watch 1` produced a
  true delta window (60 injected calls, n=60, p50 18 us; empty windows reported as such).
- `bench_script.py --compare` on `lab/variants/claim_mailbox_batch.{orig,hmget}.lua` with a
  Q7-contract seed: **replies identical** (164 flattened fields, ignoring the 33
  spec-declared clock positions: `now` + 32 `deadline`s). 30 iterations: orig p50 42.8 ms vs
  hmget 8.7 ms (ratio 0.203, i.e. ~4.9x). An earlier 200-iter run on a noisier machine:
  101.9 vs 9.4 ms (ratio 0.092). **The two runs agree on direction, not magnitude** — quote
  neither as a headline number without its conditions; `lab/RESULTS.md` Q7 (5.3x standalone)
  remains the citable figure.
- Coordination split for both variants: `eval_io_coordination_total` 1.00/invocation,
  shardlocal 0.00 — the example workload is in regime (a), as phase 1 found.

The audit self-test numbers in Update 3 were produced independently by me and by 2b and
**agree exactly at 66 findings**. 2b adds the by-rule split: batchable-hash 37,
call-in-loop 24, cjson-hot 4, read-past-bound 1, undeclared-key 0.

Three open items 2b raised for whoever writes the skill text:
1. The bench seed used for this evidence lives at `/tmp/dfscratch/q7_seed.py` and was
   deliberately not shipped. If a worked example is wanted it belongs in `references/`.
   **It is in /tmp and will not survive a reboot** — regenerate from `lab/bench/q7.py` if needed.
2. Whether the `undeclared-key` rule earns a line in SKILL.md given zero corpus hits (2b
   kept the rule because it catches the failure that breaks Dragonfly scheduling outright).
3. Delta histograms have no server median, so `format_script_latency` degrades to
   `p50 <= <bucket upper bound>`. Do not quote those as precise percentiles in prose.

`scripts/test_lua_call_audit.py` (2 cases): 2b's verdict is **keep** — it pins the audit's
one non-trivial pure decision (Lua block nesting: `repeat`/`until`, non-loop `do`,
`elseif ... then`, `for` inside a string literal) and the zero-corpus-coverage
`undeclared-key` rule, with expectations derived from Lua semantics rather than the
implementation. I did not independently re-audit that judgement against the Tests gates.

## Update 5 — FINAL. Implementer 2a is dead, not pending.

2a was **killed** (stopped externally), not merely slow. Its last recorded step was
"Now I have all inputs. Writing `sources.md` first." — it had finished reading and had
written nothing. Confirmed terminal state of its scope:
`dragonfly-scripting/SKILL.md` = the 8-line `init_skill.py` placeholder,
`dragonfly-scripting/references/` = empty.

This supersedes the "both implementers keep running" sentence in the Late update and
Update 2: **no worker from phase 2 is still running.** The phase is over at
`7f8327e`, with the tools landed and the skill text absent.

Do **not** resume 2a: it is both dead and far past the 15-turn staleness bound for new
scope. Spawn a fresh `implementer` (Opus) with the brief summarised in item 4 of "What was
actually done" above — the binding evidence rule, the `[lab Qn]`/`[df-src]`/`[df-doc]` plus
`[S<n>]` tagging scheme, the <=30-row `references/sources.md`, decisions D1-D6, the required
contents of each of the seven reference files, and the skill-creator style constraints.
Feed it the three open items from Update 4 (the /tmp bench seed, the zero-hit
`undeclared-key` rule, the degraded delta-histogram percentiles) and the caution from
Update 4 that the compare's two ratios agree on direction but not magnitude.
Then the `reviewer` (model `fable`) pass, then `generate_openai_yaml.py` + `quick_validate.py`.
