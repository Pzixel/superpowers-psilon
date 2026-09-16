# Transcript — optimize `claim_mailbox_batch.lua` (with skill)

## 1. Files read

1. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/SKILL.md`
2. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/evals/inputs/claim_mailbox_batch.lua`
3. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/evals/inputs/claim_mailbox_batch_CONTRACT.md`
4. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/references/measurements.md`
5. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/references/lua-patterns.md` (grep: acall, chunk idiom)
6. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/scripts/bench_script.py` (docstring + CLI args)
7. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/assets/examples/claim_mailbox_batch_spec.json`
8. `/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/assets/examples/claim_mailbox_batch_seed.py`

Key facts taken from the skill: (a) determine the regime first from the
`eval_io_coordination_total` / `eval_shardlocal_coordination_total` delta, and a shared hashtag does *not*
co-locate keys without `--lock_on_hashtags`; (b) in the io-coordinated regime the win is cutting the
*number* of `redis.call` (~27 µs/hop); (c) batch with chunked `HMGET`/`HSET` at 256–1000 fields (`unpack`
ceiling 8163); (d) `redis.acall` for discarded replies; (e) **contract before speed** — batch every read the
original performs, do not narrow the whole-window `record_missing` check; (f) any before/after claim must
come from `bench_script.py --compare --reseed` on identical seeded state, p50 *and* p99.

## 2. Commands and key output

```
$ mkdir -p .../outputs ; cp skill example seed+spec and the eval input .lua into outputs/
$ docker run -d --name eval3-ws-df -p 0:6379 \
    docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f4...95db \
    --proactor_threads=4 --cache_mode=false --maxmemory=2048Mi
$ docker port eval3-ws-df 6379      ->  0.0.0.0:32825
```

Wrote `outputs/claim_mailbox_batch.lua` (the batched rewrite; design in NOTES.md).

Smoke compare (30 iters, 5 warm-up, `--reseed`):

```
$ .venv/bin/python dragonfly-scripting/scripts/bench_script.py \
    --spec outputs/claim_mailbox_batch_spec.json --seed outputs/claim_mailbox_batch_seed.py --reseed \
    --host 127.0.0.1 --port 32825 \
    --compare outputs/claim_mailbox_batch.orig.lua outputs/claim_mailbox_batch.lua

127.0.0.1:32825 df-v1.34.0 (redis_version 7.4.0), threads=4
replies identical on this seed (164 fields, ignored [1, 7, 12, ...])
| claim_mailbox_batch.orig.lua | 30 | 100724.0 | 109191.0 | 154053.1 | ...
| claim_mailbox_batch.lua      | 30 |   4079.7 |   7771.8 |   8634.1 | ...
orig: coordination per invocation: shardlocal=0.00 io=1.00 -> cross-shard
new : coordination per invocation: shardlocal=0.00 io=1.00 -> cross-shard
```

Regime confirmed: **io-coordinated** (1.00 io per invocation) for both variants — the 14 keys share one
hashtag but the server runs without `--lock_on_hashtags`, so each `redis.call` pays a hop. That is the term
the rewrite attacks.

Differential check over every reply path (`outputs/differential_paths.py`, one-off verification tool;
seeds a scenario, runs the original, dumps all 14 keys, re-seeds, runs the rewrite, dumps again, compares
reply **and** state with clock-derived values normalised):

```
$ .venv/bin/python outputs/differential_paths.py 127.0.0.1 32825 \
    outputs/claim_mailbox_batch.orig.lua outputs/claim_mailbox_batch.lua
OK   happy                    RESOLVED
OK   recovery_active          RESOLVED
OK   recovery_expired         RESOLVED
OK   expired_lease_reclaim    RESOLVED
OK   expired_lease_no_receipt RESOLVED
OK   poll_start_mismatch      RESOLVED
OK   removals_and_rescores    RESOLVED
OK   cleanup_required         CLEANUP_REQUIRED
OK   record_missing           PROTOCOL
OK   not_due                  NOT_DUE
OK   retry_immediately        RETRY_IMMEDIATELY
OK   fenced_generation        FENCED
OK   bad_lease_format         PROTOCOL
OK   mutable_v2               RESOLVED
FAILURES: none
```

Headline measurement on a **fresh** container (100 timed iterations, 10 warm-up, `--reseed`, port 32826):

```
| script                       | n   | p50_us   | p95_us   | p99_us   | min_us  | max_us   | mean_us  |
| claim_mailbox_batch.orig.lua | 100 | 101223.9 | 120421.0 | 170109.2 | 48963.5 | 170109.2 | 100034.3 |
| claim_mailbox_batch.lua      | 100 |   3289.4 |   6318.1 |   8644.8 |  2473.0 |   8644.8 |   3621.0 |
orig: SCRIPT LATENCY n=110 avg=99455.236us   p50<=120000us max=180000us
new : SCRIPT LATENCY n=110 avg= 2965.864us   p50<=3000us   max=8000us
p50 ratio new/orig = 0.032
```

Saved verbatim to `outputs/bench_result.txt`.

```
$ docker rm -f eval3-ws-df        # teardown, both containers reused the same name
```

Note on absolutes: this host is slower than the skill's lab cell for Q7 (41183 -> 7814 µs); the *ratio*
(30.8x p50 here vs 5.3x recorded there) is larger mainly because this rewrite also batches the writes and
the receipt/poll-start reads, and because the host's per-hop cost is higher. Do not mix these absolutes with
the skill's recorded Q7 cell.

## 3. Final answer

Batched every per-item `redis.call`: candidate versions, leases, records and receipts become chunked
`HMGET` (256/chunk); the 32 x (5 `HSET` + 1 `ZADD`) claim writes plus the removal/rescore writes become
about ten multi-field `HSET`/`HDEL`/`ZADD`/`ZREM` calls emitted from a pending last-write-wins state table;
fences collapse to one `MGET` + one `HMGET`; discarded-reply hash writes use `redis.acall`. ~3300 calls per
invocation -> ~35. The reply protocol, the fence order and reasons, the whole-window `record_missing`
check, the recovery/`RESOLVED` path and the pre-write `CLEANUP_REQUIRED` return are unchanged, verified by
`--compare` and by a 14-scenario reply+state differential.

**p50 101224 -> 3289 µs (30.8x), p99 170109 -> 8645 µs (19.7x)**, df-v1.34.0,
`--proactor_threads=4 --cache_mode=false --maxmemory=2048Mi`, 1024 due mailboxes, window 1024, batch 32,
~2 KB records, 100 iterations with re-seed before every call, replies byte-identical.

Deliverables: `outputs/claim_mailbox_batch.lua`, `outputs/NOTES.md`, `outputs/bench_result.txt`,
`outputs/differential_paths.py`, `outputs/claim_mailbox_batch_spec.json`,
`outputs/claim_mailbox_batch_seed.py`, `outputs/claim_mailbox_batch.orig.lua`.
