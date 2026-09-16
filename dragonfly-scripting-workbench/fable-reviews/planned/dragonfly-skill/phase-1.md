# Phase 1 — local Dragonfly lab + measurements

Goal: a reproducible local lab shaped like production, and measured answers to the questions below. The numbers feed the skill (phase 2); a claim without a measurement or an official source does not enter the skill.

## Done-condition
- `lab/compose.yaml` starts `primary` (port 6379) + `replica` (port 6380, `--replicaof primary 6379`) from the digest in README, args `--cache_mode=false --maxmemory=2048Mi --dbfilename=dump --proactor_threads=4`, container memory limit 3g each; a `single` profile with `--proactor_threads=1`. `lab/run_all.sh` runs every benchmark and regenerates `lab/RESULTS.md`.
- `lab/bench/*.py` (python3.12 venv at `lab/.venv`, `redis` package) — one file per question, prints a table, appends to RESULTS. Each benchmark: warm-up, ≥200 iterations (fewer for Q4), client p50/p95/p99 in µs, and the `SCRIPT LATENCY` histogram for the script SHA. Record server version, flags, and exact command lines.
- `lab/RESULTS.md`: first 40 lines = summary table (question → numbers → one-line conclusion); appendix with raw output.
- Committed on `main` of this repo. Lab torn down (`docker compose down -v`) at the end; images kept.

## Questions (each one experiment)
- Q1 `redis.call` overhead inside Lua: N×`HGET` on one hash vs `HMGET` in chunks of 256, N ∈ {32, 256, 1024, 8192}, field values ~2 KB. Report µs per call and total.
- Q2 Writes: 32 items × (5×`HSET` + 1×`ZADD`) vs 5 multi-field `HSET` + 1 multi-member `ZADD`.
- Q3 Read-after-full: loop over 1024 `ZRANGEBYSCORE` candidates, `HGET` version + lease + ~2 KB payload for each vs stop after 32 payloads (metadata still read for all 1024).
- Q4 Big JSON plan on the success path: `cjson.encode` of a command table of 1, 8, 32 MiB, `HSET` it, later `HDEL`; time in script; and p99 of a plain `GET` from a second client during the run (shard blocking).
- Q5 Key placement: script over 8 keys in one hashtag vs 8 keys in 8 hashtags (proactor_threads=4); with and without `#!lua flags=disable-atomicity`; note whether `--lock_on_hashtags` changes anything (needs restart, keep it a separate run). Also test `--lua_auto_async=true` if the flag exists in v1.34.0 (check `dragonfly --helpfull | grep -i lua`).
- Q6 Replica attached vs standalone: the Q2 write script latency.
- Q7 Real script: `crates/dragonfly-store/assets/claim_mailbox_batch.lua` from email-stats (read-only; copy into `lab/variants/claim_mailbox_batch.orig.lua`). KEYS order and ARGV protocol: find the call site in `crates/dragonfly-store/src/coordinator.rs` (grep `claim_mailbox_batch`) and `src/keys.rs`. Seed 1024 due mailboxes (versions hash, due zset, ~2 KB captured payloads), no leases, candidate_window=1024, batch_size=32, `lease_ttl=120000`. Measure. Then `lab/variants/claim_mailbox_batch.hmget.lua`: same protocol, per-loop `HGET`s replaced by chunked `HMGET` prefetch and payload reads only for chosen candidates; verify identical response on the same seed (assert equality of the reply arrays), measure delta. Do not modify email-stats.
- Q8 Head-of-line: 8 concurrent clients running a ~2 ms script in a loop; p99 of plain `GET` from a 9th client; proactor_threads=1 vs 4; keys in the same vs another hashtag.
- Q9 Inventory of script-related server commands and flags on v1.34.0 by trying them: `SCRIPT LATENCY`, `SCRIPT FLAGS <sha> ...`, `SCRIPT LIST`, `SCRIPT GC`, `SCRIPT EXISTS`, `DEBUG OBJHIST`, `MEMORY USAGE`, `INFO` sections mentioning scripts/tx (`tx_*`, `eval_*`), `dragonfly --helpfull | grep -iE 'lua|script|lock_on|squash|interpreter'`. Record exact output format (needed for a parsing helper in the skill).

## Constraints
- ≤ 8 GiB memory and disk for the lab in total. Never `docker system prune`, never remove images. Container names prefixed `dfskill-`.
- email-stats repo is read-only for this phase.
- Workers: `implementer` (Opus) for lab code + benchmarks; suggested split: A = compose, venv, harness helpers (`lab/bench/common.py`: connect, time, parse `SCRIPT LATENCY`), Q1–Q4, Q9; B = Q5–Q8 starting from A's harness (write handoff between them). `prod-probe` only if a read-only inventory is needed. No `general-purpose`.
- A per-run raw log goes to `lab/results/<question>.txt`; RESULTS.md cites them.

## Decisions already taken
- Python + redis-py for the harness (no Rust); scripts loaded with `SCRIPT LOAD`, invoked with `EVALSHA`.
- Latency measured both client-side and via `SCRIPT LATENCY` when available; if `SCRIPT LATENCY` is absent or empty in this version, say so in RESULTS.
- Timings are reported as-is; no smoothing, no dropping outliers beyond stating p99.
