## Files read

/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/evals/inputs/claim_mailbox_batch.lua
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/evals/inputs/claim_mailbox_batch_CONTRACT.md
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/iteration-1/eval-1-optimize-claim-batch/without_skill/run-1/outputs/claim_mailbox_batch.lua (written by me, re-read via grep)
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/iteration-1/eval-1-optimize-claim-batch/without_skill/run-1/outputs/NOTES.md (written by me, re-read via grep)

## Commands run

mkdir -p .../outputs && python3 -c "import sys; print(sys.version)"; docker ps --format '{{.Names}}' | head -20
docker run -d --name eval-1-ns-df -p 0:6379 docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f415c22983dc1c4a1d575fa2d9c22b9a3998a9934bf1cc6d16c17695db --proactor_threads=4 --cache_mode=false --maxmemory=2048Mi && sleep 2 && docker port eval-1-ns-df 6379 && docker logs eval-1-ns-df 2>&1 | tail -3
cat > outputs/harness.py <<'EOF' ... EOF   (raw RESP client, seeding, dump helpers)
cat > outputs/smoke.py <<'EOF' ... EOF ; DF_PORT=32819 python3 smoke.py       (baseline single call: 113.97 ms)
cat > outputs/claim_mailbox_batch.lua <<'LUA' ... LUA                          (optimized script)
perl -0pi -e 's/    pos = stop \+ 2 - 1\n/    pos = stop + 1\n/' claim_mailbox_batch.lua && grep -n 'pos = stop' claim_mailbox_batch.lua
cat > outputs/smoke2.py <<'EOF' ... EOF ; DF_PORT=32819 python3 smoke2.py      (optimized single call: 3.92 ms)
cat > outputs/difftest.py <<'EOF' ... EOF ; DF_PORT=32819 python3 difftest.py  (27 scenarios, normalizer bug -> 13 false mismatches)
python3 - <<'EOF' (patch difftest.py normalizer: epoch-ms regex + second-granularity) EOF ; DF_PORT=32819 python3 difftest.py
python3 - <<'EOF' (append sc_receipt_token, sc_large_mixed, sc_dup_tokens) EOF ; DF_PORT=32819 python3 difftest.py
DF_PORT=32819 python3 difftest.py | grep -c '^ok' ; DF_PORT=32819 python3 difftest.py | grep -E 'FAILS|sc_large|sc_dup'
cat > outputs/bench.py <<'EOF' ... EOF ; DF_PORT=32819 python3 bench.py
cat > outputs/cmdcount.py <<'EOF' ... EOF ; DF_PORT=32819 python3 cmdcount.py
rm -f smoke.py smoke2.py ; cat > outputs/NOTES.md <<'EOF' ... EOF ; wc -l NOTES.md claim_mailbox_batch.lua ; ls
rm -rf __pycache__ ; grep -n 'local function hmget_all|...' claim_mailbox_batch.lua
perl -0pi -e '<fix line references>' NOTES.md && grep -n 'lines ...' NOTES.md
docker rm -f eval-1-ns-df

## Final answer

The script is ~36x faster at the production call shape, with byte-identical replies and
identical post-state on 30 differential scenarios.

Deliverables (all in
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/iteration-1/eval-1-optimize-claim-batch/without_skill/run-1/outputs/):
- claim_mailbox_batch.lua  — optimized script
- NOTES.md                 — every change and why it is safe, plus the numbers
- bench.py / cmdcount.py / difftest.py / harness.py, bench_results.json, command_counts.json

Numbers (Dragonfly v1.34.0 at the pinned digest, --proactor_threads=4 --cache_mode=false
--maxmemory=2048Mi, 1000 due mailboxes with ~2 KB records, candidate_window=1024, batch_size=32,
30 A/B-interleaved samples with a full reseed before every measured call):

| | original | optimized |
|---|---|---|
| p50 | 64.60 ms | 1.81 ms  (35.7x) |
| mean | 59.57 ms | 1.84 ms |
| min / p90 / max | 32.48 / 67.07 / 82.85 ms | 1.52 / 1.97 / 3.03 ms |
| 30 consecutive claims draining one pool | 1083.25 ms | 43.77 ms (24.7x) |
| server commands per invocation | 3234 | 22 |

Root cause: the script issued ~3200 individual redis.calls per invocation — 32 receipt HGETs,
2000 version/lease HGETs (one pair per candidate), ~1000 HGETs pulling the full ~2 KB record of
every eligible candidate (not just the 32 claimable), and one write command per claimed/rescored/
removed mailbox — all inside the exclusive script transaction.

Changes: batched every read (HMGET for receipts, versions, leases, records, stale receipts; MGET
for the four fence keys; one HMGET for the descriptor) and every write (variadic HSET/ZADD/ZREM/
HDEL), chunked at 400 arguments; dropped the poll_starts HGET+HDEL on the claim path because the
same field is unconditionally overwritten two lines later; replaced table.insert with index writes
and hoisted tostring out of the claim loop. The script is structured as a side-effect-free prefetch
pass followed by a decision pass that walks candidates in the original order, so the first
offending candidate still decides the reply.

Explicitly not done, because they would change recovery semantics: lazy record fetching (only the
32 claimed) and early exit once 32 claimables are found — both would move or drop
PROTOCOL record_missing / CLEANUP_REQUIRED detection.

Verification: difftest.py seeds a scenario, runs the original, dumps reply + all 14 keys, restores
the same seed, runs the optimized script, compares. 30/30 scenarios identical (claims, mixed
removal/rescore/re-claim pools, a 1000-candidate pool that exercises the 400-argument chunking,
receipt recovery, duplicate tokens, CLEANUP_REQUIRED, NOT_DUE, RETRY_IMMEDIATELY, all FENCED
reasons, mutable_v2 descriptor, and every PROTOCOL reason). Container eval-1-ns-df was torn down.
