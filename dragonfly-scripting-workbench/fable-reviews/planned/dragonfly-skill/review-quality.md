# dragonfly-scripting skill — quality audit against the two skill-authoring guides

Audited: `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/` (2026-09-16). Read-only.
Guides: codex `skill-creator/SKILL.md` (G1) and claude-plugins `skill-creator/SKILL.md` (G2).

Verdict: **PASS WITH FIXES**. One factual contradiction between a script's `--help` and the skill body (blocking), one self-containment break (blocking), and heavy intra-skill duplication that bloats SKILL.md and three references (should-fix).

## Rule-by-rule

| Rule | Result | Evidence |
|---|---|---|
| G1 Assume reader is capable; no generic advice | PARTIAL | Generic Redis-Lua semantics in `SKILL.md:116-118`, `references/lua-patterns.md:89-100` (nil-truncation, `false` for missing key, `pcall` vs `call`, globals), `lua-patterns.md:110-113` (NOSCRIPT reload-once, EVAL in pipelines). Tagged `[semantics]` so they are at least labelled, but they do not change a strong model's decisions. |
| G1 No repeated instructions | FAIL | See Duplication section: hashtag fact 3x inside SKILL.md, bench `--compare --reseed` 2x inside SKILL.md, Q7/Q3 contract-narrowing 4x in SKILL.md + 2 references. |
| G1 No speculative edge cases | PASS | Every rule cites a lab cell or source. |
| G1 Preserve scope; no personal preference as universal rule | PARTIAL | `SKILL.md:16-18` mandates the bundled `bench_script.py` for *any* latency claim; the real requirement (identical seeded state, reply equality, p50+p99) is tool-independent. |
| G1 Specificity matched to risk; absolute language justified | PASS | Each absolute carries its consequence: `SKILL.md:16-18` (second-call path), `:28-35` (helpfull lies), `:138-139` (Q10 co-tenancy), `:128` (Q11d serialisation), `measurements.md:42-44`, `lua-patterns.md:44`. No bare MUST/NEVER. |
| G1 Discovery cheap and precise; no exhaustive lists | PARTIAL | `SKILL.md:3` lists ~15 trigger phrases (`writing, reviewing, porting or optimizing … ; redis.call loops; SCRIPT LOAD, SCRIPT LATENCY or SCRIPT FLAGS; eval_* … ; hashtags, shard placement, --lock_on_hashtags, --!df flags; … rate limiting, leases, claims, queues`). G2 asks for pushiness so a list is defensible, but the clause "because Dragonfly's execution model, flag syntax and metrics differ and Redis advice often inverts here" is body rationale, not routing. Exclusions present and correct. No history narration. |
| G1 Self-contained | FAIL | `references/measurements.md:3,69-70`, `references/lua-patterns.md:66`, `references/sources.md:14`, `assets/examples/claim_mailbox_batch_seed.py:1` reference `lab/RESULTS.md`, `lab/results/`, `lab/Q7-CONTRACT.md`, `lab/variants/claim_mailbox_batch.hmget.lua`; none ships in the skill folder (they live in the parent repo). `sources.md:8` adds a `SOURCES row` column keyed to the parent repo's `SOURCES.md`. |
| G1 Progressive disclosure; SKILL.md short; no duplication entrypoint↔references | FAIL | SKILL.md is 180 lines but ~40 of them restate reference content verbatim (lab conditions `SKILL.md:62-64` = `measurements.md:5-17`; CONFIG GET note `SKILL.md:33-35` = `measurements.md:11-13`; SCRIPT FLUSH `SKILL.md:157-163` = `measurements.md:77-137`; worked example `SKILL.md:152-156` = `measurements.md:67-75`; Q7/Q3 `SKILL.md:166-170` = `lua-patterns.md:49-67`). |
| G1/G2 Each reference linked with "read when" | PARTIAL | `SKILL.md:174-180` lists every reference with a *contents* summary, not a condition. Inline conditional links exist only for `measurements.md` (`:64,:103,:153`) and `server-flags.md` (`:130`). `execution-model.md`, `lua-patterns.md`, `redis-advice-audit.md`, `redis-differences.md` have no "read when". |
| G1 No README/changelog/install guide | PASS | None present. |
| G1 No copied manuals / process logs in references | PARTIAL | `measurements.md:86-131` is a 46-line raw `redis-cli` transcript whose conclusion is two sentences (`:128-131`). `measurements.md:46-48` (Q11 traceability of `results/q11.txt`) and `:139-146` (email-stats corpus counts, "150-line looseness budget") are project-specific process log. `redis-advice-audit.md` is decision material, not a manual — PASS for that file. |
| G1 Scripts verified to run | PARTIAL | `--help` exit 0 for `bench_script.py`, `lua_call_audit.py`, `script_latency.py`; `lab.sh --help` prints usage but exits 2 (treats `--help` as bad arg). Audit on corpus: 66 findings / 18 files / 52 scripts, per-rule 37/24/4/1/0 — matches `measurements.md:143-144`; 0 `undeclared-key` verified correct (all `..` concatenations in the corpus are value comparisons, not key positions). Tests pass (run directly; `pytest` not installed on host). |
| G1 Description does not narrate history | PASS | `SKILL.md:3` has no history. |
| G2 Description = when to trigger + what it does, pushy | PASS | Trigger contexts and "read it even when…" clause; see PARTIAL above only for the rationale tail. |
| G2 <500 lines, TOC for refs >300 | PASS | SKILL.md 180; refs 22-146 lines. No TOC needed. |
| G2 Imperative form | PASS | Body is imperative throughout. |
| G2 Explain why instead of MUSTs | PASS | Consequences accompany every rule. |
| G2 Bundle repeated work as scripts | PASS | bench/latency/audit/lab scripts cover the repeated mechanics. |
| G1 openai.yaml consistent | PASS | `agents/openai.yaml:2-3` display/short description match the skill scope. `quick_validate.py`: "Skill is valid!". |

## Findings, ranked

### Blocking

- **Script help contradicts the skill's measured fact.** `scripts/script_latency.py:4-5`: "nothing but SCRIPT FLUSH resets them" vs `SKILL.md:158`, `references/measurements.md:80,86-131`, `references/redis-differences.md:26`: `SCRIPT FLUSH` does **not** reset the histogram. Failure: a user reads `--help`, flushes to "reset", and reports a before/after that is a cumulative delta. Fix: change the docstring to "nothing short of restarting the node resets them (SCRIPT FLUSH does not)".
- **Not self-contained; the "worked example ships with the skill" claim is false.** `SKILL.md:152` says the worked `--compare` invocation ships in `assets/examples/`, but the two Lua variants it compares (`claim_mailbox_batch.lua`, `lab/variants/claim_mailbox_batch.hmget.lua`) are outside the skill (`measurements.md:69-70`, `lua-patterns.md:66`). Also `measurements.md:3`, `sources.md:14` (`lab/RESULTS.md`, `lab/results/`), `sources.md:8` (`SOURCES row` column tied to parent repo), `assets/examples/claim_mailbox_batch_seed.py:1` (`lab/Q7-CONTRACT.md`). Failure: a copied skill instructs the reader to run a comparison whose inputs do not exist. Fix: either ship both `.lua` variants under `assets/examples/` or reword `SKILL.md:152-156` and `measurements.md:67-75` to "spec + seed ship; supply your own two variants"; drop the `SOURCES row` column and the `lab/` path mentions (keep `[S1]` as "lab measurements, df-v1.34.0").

### Should-fix

- **Hashtag fact stated three times in 30 lines of SKILL.md.** `SKILL.md:12-14`, `:24` ("including keys that share a `{hashtag}`"), `:37-40`; again in `execution-model.md:50-59`, `redis-differences.md:40`, `redis-advice-audit.md:13`, `server-flags.md:32,37-42`. Fix: keep `:22-26` table row + `:37-40` once; delete `:12-14`.
- **`bench_script.py --compare --reseed` rule duplicated inside SKILL.md** (`:16-18` and `:146-151`), again in `measurements.md:55-65`, and in the script's own `--help`. Fix: drop `:16-18`; keep §4 step 3; measurements.md keeps only what `--help` does not say.
- **Q7/Q3 "contract before speed" point in four places in SKILL.md** (`:70-73`, `:76-78`, `:152-156`, `:166-170`) plus `lua-patterns.md:49-67` and `measurements.md:67-75`. Fix: one paragraph in SKILL.md §4 (or §2 rule 4), pointer to `lua-patterns.md §2`.
- **Lab-conditions and provenance narration in SKILL.md.** `SKILL.md:62-64` (Docker, 4-core, 200 after 20 warm-up) duplicates `measurements.md:5-17`; `:33-35` "(observed 2026-09-16, lab primary)" duplicates `measurements.md:11-13`; `:157-163` "(5 runs, flush, reload, 1 run = `Count: 6`, observed 2026-09-16…)" narrates how the number was obtained. Fix: state the fact, cite `[lab Q9]`/`[S1]`, move conditions/dates to measurements.md only.
- **`SKILL.md:132-134` restates §0–§3 as a five-step order** ("(1) measure the counters, (2) evaluate --lock_on_hashtags…"). Fix: delete; §0 already says "do this first".
- **References listed without "read when".** `SKILL.md:174-180`. Fix: e.g. "`execution-model.md` — read when a counter or hop count needs explaining or you are citing source"; "`lua-patterns.md` — read when rewriting a script body"; "`redis-differences.md` — read when porting from Redis or the user quotes a Redis command that fails"; "`redis-advice-audit.md` — read when the user proposes standard Redis tuning advice".
- **`redis-differences.md` and `redis-advice-audit.md` overlap.** `redis-differences.md:47-57` ("Advice that inverts") restates `redis-advice-audit.md:9,14,19` with the same numbers; `redis-differences.md:10-13` restates `server-flags.md:10-21`. Fix: delete `redis-differences.md:47-56` (line 57 already points to the audit); replace `:10-13` rows with one row pointing at `server-flags.md`.
- **Process-log material in measurements.md.** `:86-131` 46-line redis-cli transcript; `:46-48` raw-file traceability caveat; `:139-146` email-stats corpus counts and "150-line looseness budget" (repo-specific, also `lua-patterns.md:81-82` "4 hits in the 52-script corpus", `SKILL.md:102-103`). Fix: keep `:128-137` conclusion, drop the transcript; drop corpus counts entirely (they say nothing about the reader's corpus).
- **Evidence-tag inconsistencies.** `sources.md:4-5` defines `[df-src path:symbol]` / `[df-doc URL]`, but bare `[df-doc]`/`[df-src]` appear 28 times (`SKILL.md:110,111`; `execution-model.md:44,85,112`; `redis-advice-audit.md` x8; `redis-differences.md` x6; `server-flags.md` x8); `[df-src:2019]` at `execution-model.md:68`; non-standard `[lab 2026-09-16]` at `SKILL.md:160`. `[S2]` (defined as `main_service.cc` only) is used for `transaction.cc` (`execution-model.md:18`), `multi_command_squasher.cc` (`:83`, `server-flags.md:66`), `server_family.cc` (`SKILL.md:30`, `execution-model.md:111`), `facade/error.h` (`redis-differences.md:13`); `[S8]` (docs flags page) is used with `[df-src common.cc]`/`[df-src dragonfly_connection.cc]` (`server-flags.md:33,85,92`, `redis-advice-audit.md:22`). All `[S1]`–`[S30]` resolve. Fix: widen S2's title to "Dragonfly v1.34.0 `src/` tree" or add rows; either drop the URL/path requirement from the legend or fill the bare tags; retag `:160` as `[lab Q9]` or add a Q12 row.
- **`[semantics]` legend duplicated**: `SKILL.md:123-124` and `lua-patterns.md:86-87`. Fix: define once in `sources.md`.
- **`SKILL.md:16-18` over-specifies the tool.** Fix: "must come from identical seeded state with a reply-equality check and p50+p99 — `scripts/bench_script.py --compare --reseed` does exactly that".
- **Generic Redis-Lua content**: `SKILL.md:116-118` and `lua-patterns.md:89-100,110-113`. Fix: cut to the Dragonfly-specific deltas (`redis.setresp` absent, `EVAL_RO` exists, declared-key set decides path); drop nil-truncation/pcall/globals/NOSCRIPT text.

### Cosmetic

- `scripts/lab.sh --help` exits 2; make `--help`/`-h` exit 0.
- `scripts/test_lua_call_audit.py:1-3` says loop detection is "the only non-trivial pure decision" yet `:39-41` tests `undeclared-key`; either drop that sentence or the second test. The tests themselves are justified (pure rule engine, plausible false-positive defects: `do` blocks, `elseif`, string literal containing `for … do`); not ceremonial.
- `SKILL.md:42` "(the 15 lines that matter)" — the section is 15 bullets of 1–3 lines; drop the parenthetical.
- `SKILL.md:3` is one 120-word line; trim the "because …" rationale tail.
- `SKILL.md:62-64` says "Numbers are client p50 … unless stated" while several items quote per-call µs (not p50 of an invocation); clarify in measurements.md, not in SKILL.md.
- `references/sources.md:8` "kept so the mapping stays auditable after the skill is copied elsewhere" — the parent `SOURCES.md` is not copied with it, so the column serves nothing.

## Checks requested by the orchestrator

- (a) Description: no history, no body content except the "because…" rationale clause — PARTIAL.
- (b) Sentences that narrate provenance rather than direct action: `SKILL.md:33-35` (date), `:62-64`, `:97-99` ("Q6 measured a Q2 write script"), `:152-156`, `:157-163`, `:132-134`.
- (c) Duplication: quoted above with both locations.
- (d) Read-when: PARTIAL, 4 of 7 references lack a condition.
- (e) Absolute language: all justified; the problem is repetition, not justification.
- (f) Tags: every `[S<n>]` resolves (S1–S30 defined, S1–S30 all cited). Inconsistencies listed under should-fix.
- (g) measurements.md contains a raw transcript and repo-specific corpus counts (process log); redis-advice-audit.md is decision material.
- (h) Scripts: 3/4 `--help` exit 0, `lab.sh` exit 2. Audit: 66 findings, sane, matches documented split. Tests: justified, pass.
- (i) openai.yaml consistent.
- (j) SKILL.md 180; refs 125/121/146/22/57/97/43; no TOC needed.
