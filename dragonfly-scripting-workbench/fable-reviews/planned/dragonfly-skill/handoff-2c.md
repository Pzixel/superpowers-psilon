# Handoff 2c — `dragonfly-scripting` skill text + references

Commit: `0f666ea` on `main` ("dragonfly-scripting: skill text + references", 10 files, +761).
Predecessor: `1e61ac1` (executable tools; untouched here).

## Done

| file | lines | spec clause satisfied |
|---|---|---|
| `dragonfly-scripting/SKILL.md` | 162 (cap 250) | line 6 in full: frontmatter `name: dragonfly-scripting` + pushy description hitting every listed intent; §0 regime detection; §1 execution model (14 bullet lines); §2 review checklist, 10 anti-patterns each with a measured cost and its lab conditions; §3 design procedure (declare, colocate, batch, bound, reply shape, "should it be Lua"); §4 measurement procedure (lab, `SCRIPT LATENCY`, client p99, identical seed + reply-equality, worked example); §5 routing |
| `references/sources.md` | 43 | line 15: 30 rows, each with title/URL/tier/one phrase **and** its `SOURCES.md` row number; S1 = the lab itself |
| `references/execution-model.md` | 125 | threads/shards/hops, three multi-modes, fast path, why a sync `redis.call` hops, squashing, interpreter pool, counters |
| `references/lua-patterns.md` | 115 | chunked HMGET/HSET/ZADD with the measured `unpack` ceiling, batching vs bounding split, cjson costs, reply shape, error protocol, NOSCRIPT/EVAL-in-pipeline |
| `references/measurements.md` | 92 | lab conditions, Q1-Q11 summary table, the ratios-vs-absolutes rule, how to redo it with the shipped tools, `SCRIPT LATENCY` bucket caveat, audit-corpus numbers |
| `references/server-flags.md` | 97 | directives + placement/interpreter/squash/runtime flags with v1.34.0 source defaults, the `--lock_on_hashtags` trade-off and decision rule, six docs-vs-source conflicts |
| `references/redis-advice-audit.md` | 22 | all 12 mandated rows plus MGET-in-Lua and pipeline-depth; verdict column helps/neutral/harms/absent/unverified with `[lab Qn]`/`[df-src]`/`[df-doc]` |
| `references/redis-differences.md` | 57 | `--!df` vs `#!lua`, Lua 5.4, absent FUNCTION/SCRIPT KILL/setresp, `acall`, `CL.THROTTLE`, expiry rounding, cluster slot rule, hashtag inversion |

Also staged: `dragonfly-scripting/assets/examples/{claim_mailbox_batch_seed.py,claim_mailbox_batch_spec.json}`
(copied in by 2b; referenced as the worked example in SKILL.md §4 and `measurements.md`).

## Interfaces referenced (file:line)

- `dragonfly-scripting/scripts/lua_call_audit.py:14` — the five rule ids, cited by name in SKILL.md §2 and `measurements.md`.
- `dragonfly-scripting/scripts/bench_script.py:7-31` — spec shape, `--seed` stdout merge, `--reseed`, `--compare` exit 2.
- `dragonfly-scripting/scripts/script_latency.py:1-13` — cumulative histograms, `--sha`, `--watch`, bucket-bound percentiles.
- `dragonfly-scripting/scripts/lab.sh:11-20` — `up|down|status`, `--single`.

## Decisions carried through as written

Regime (a)/(b) split with counter-based detection; recommendation order 1-5 for a one-hashtag workload;
`--lock_on_hashtags` as a measured trade-off with the tag-cardinality decision rule and the Q11d
head-of-line number; the contract-preserving rewrite for `claim_mailbox_batch` (batch every read, keep
whole-window protocol checks, treat the payload bound as a separate owner decision) stated in SKILL.md §4
and `lua-patterns.md` §2; Q10 ratios and standalone absolutes never mixed; conditions in every numeric clause.

## Deviation to review

**`--lock_on_hashtags` one-tag figure quoted as 26.95 -> 1.54 µs/call, not 26.95 -> 1.03.** `lab/RESULTS.md`
Q5 has no 1.03: the `--lock_on_hashtags` 8-keys/1-tag atomic row is p50 393.0 µs / 256 calls = 1.54 µs, and
the Q5 verdict text says "1.54us/call (26.95us/call without it)". 1.01 µs is the *1-key, default-node*
figure. Traceability to RESULTS.md won over the decision's transcription.

## Out of scope / not done

- `dragonfly-scripting/scripts/`, `assets/compose.yaml`, `agents/openai.yaml` (untracked, phase 2d).
- No new web sources read, so `SOURCES.md` is unchanged (still 93 rows).
- Rules dropped for lack of Dragonfly evidence: "route read-only scripts to a replica" (kept only as
  **unverified** in the audit, with Q6's primary-side cost as the adjacent measured fact) and "raise
  pipeline depth" (**unverified**, no lab cell). No Redis-only performance rule survives anywhere.

## Verification

`python3 /Users/pzixel/.codex/skills/.system/skill-creator/scripts/quick_validate.py dragonfly-scripting`
-> `Skill is valid!`, and `wc -l dragonfly-scripting/SKILL.md` -> 162 (cap 250). Frontmatter uses only
`name` + `description`; the description contains no angle brackets.

## Open decisions for the reviewer pass

1. The 1.54-vs-1.03 correction above — confirm or supply the run that produced 1.03.
2. `references/redis-advice-audit.md` is 22 lines of very wide table rows; if the reviewer prefers, split
   the evidence column into a second table.
