# dragonfly-skill — plan README

Goal: a skill `dragonfly-scripting` (folder `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/`) that makes an agent design, review and optimize Lua/EVALSHA operations and key layouts on Dragonfly well, and measure them. Grounded in official sources and in measurements from a local lab. Then prove (a) an agent given the skill actually uses it and (b) its output is measurably better than without it.

## Fixed facts (verified 2026-09-16)
- Target server: Dragonfly v1.34.0, image `docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f415c22983dc1c4a1d575fa2d9c22b9a3998a9934bf1cc6d16c17695db` (already pulled, arm64). Prod: operator, 3 replicas (1 primary + 2 replicas), `--cache_mode=false --maxmemory=2048Mi`. Staging: single pod, 3Gi. No `--lock_on_hashtags`, no cluster mode.
- Example workload: `/Users/pzixel/Documents/Repos/email-stats/crates/dragonfly-store/assets/*.lua` (52 scripts, 5266 lines, 794 `redis.call` sites). Every key carries the single hashtag `{email-stats-inbound}` (`src/keys.rs:5-7`), so all scripts touch one shard. Client: `EVALSHA` with one `EVAL` retry on `NOSCRIPT` (`src/client.rs:668-690, 923-927`). Keys are always declared in KEYS.
- Existing integration tests start Dragonfly via `docker run --rm -d -p 0:6379 <IMAGE> --proactor_threads=1` (`tests/mutable_page_replay.rs:35-60`).
- Prior static analysis (initial.txt) named four candidates: claim_mailbox_batch reads payloads after batch is full (`assets/claim_mailbox_batch.lua:178+`); per-grant `HGET` loops in apply_new_mutable_mailbox_page (`:453`) and remove_mutable_mailbox (`:314`) instead of `HMGET`; per-claim 5×HSET+1×ZADD; 32 MiB JSON replay plan encode/store on the success path.
- Host: docker 29.4, 16 CPU, 16 GiB. Lab budget: ≤16 GiB memory and disk total for the experiment; use far less (2 GiB maxmemory per node).
- Trusted sources: dragonflydb.io docs and blog, github.com/dragonflydb/dragonfly (source, docs/, .claude/skills/benchmark*), redis.io docs, GitHub repos ≥500 stars (bullmq, redis clients). Not trusted: reddit, medium, SO.
- Tools present: redis-cli, redis-benchmark, python3.12, claude CLI 2.1.273. memtier_benchmark absent (docker image `redislabs/memtier_benchmark` acceptable).
- Skill-creator tooling: `/Users/pzixel/.claude/plugins/cache/claude-plugins-official/skill-creator/b5439c41ae98/skills/skill-creator/` (scripts/aggregate_benchmark.py, eval-viewer/generate_review.py, scripts/run_loop.py, agents/grader.md, references/schemas.md) and `/Users/pzixel/.codex/skills/.system/skill-creator/scripts/{init_skill,quick_validate}.py`.

## Sources gate (user requirement, 2026-09-16)
`SOURCES.md` at the repo root lists every source consulted (append-only, tiered). Phase 2 (skill text) starts only when it holds ≥20 distinct high-quality articles/pages and a second, broad research round (R2) has finished. Every agent that reads a source appends it.

## Evidence rule (user requirement, 2026-09-16)
The subject is Dragonfly only. Redis-origin advice can harm Dragonfly performance. A rule enters the skill only with Dragonfly evidence: a lab measurement (`lab/RESULTS.md Qn`) or a Dragonfly v1.34.0 doc/source citation. Redis-only sources may explain Lua API semantics, never justify a performance rule. The skill carries an audit table of Redis advice with a Dragonfly verdict (helps / neutral / harms) and evidence; unverified Redis advice in an eval output counts as a failure.

## Phases
| # | Spec | Output | Status |
|---|---|---|---|
| R | (main session, 2 web-research agents) | `research/dragonfly-sources.md`, `research/redis-lua-sources.md` | done |
| R2 | (main session, 2 broad-search agents) | `research/dragonfly-ecosystem.md`, `research/lua-patterns-in-the-wild.md`, SOURCES.md 93 rows (A30/B39/C23/D1, 6 rejected) | done |
| 1 | phase-1.md | `lab/` (compose, harness, benchmarks), `lab/RESULTS.md` Q1–Q11 | done (handoff-1.md) |
| 2 | phase-2.md | `dragonfly-scripting/` skill (SKILL.md 163 lines, 7 references, 4 tools), fable review REJECT→fixed | done (handoff-2c-lead.md) |
| 3 | phase-3.md | iteration-1: with-skill 95.3% vs without 74.7% (evals 2,3 discriminate; eval 1 tie), usage evidence, viewer | done (handoff-3.md) |
| 4 | phase-4.md, handoff-4.md, handoff-4b.md | skill refined (944d4d2), iteration-2 100% vs 68%, description from loop iteration 4 (62% held-out), REPORT.md, symlinks installed | done |

Handoffs: `fable-reviews/planned/dragonfly-skill/handoff-<n>.md`. Branch: `main` (fresh repo, no remote).
