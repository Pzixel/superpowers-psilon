## Files read

(none — no repository files were read; both deliverables were written from scratch and the only
inputs were the live Dragonfly container's replies)
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting-workspace/iteration-1/eval-3-design-new-op/without_skill/run-1/outputs/renew_leases_batch.lua (own output, re-read via grep/head while editing)

## Commands run

mkdir -p .../outputs && docker run -d --name eval-3-ns-a -p 0:6379 docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f415c22983dc1c4a1d575fa2d9c22b9a3998a9934bf1cc6d16c17695db && sleep 3 && docker port eval-3-ns-a 6379
which redis-cli || ls /opt/homebrew/bin/redis-cli
redis-cli -p 32816 INFO server | head -4
redis-cli -p 32816 EVAL "local t=redis.call('TIME'); return t" 0
redis-cli -p 32816 EVAL "return redis.call('HMGET', KEYS[1], 'a','b')" 1 '{t}:leases'
cat > .../outputs/renew_leases_batch.lua <<'LUA' ... LUA
sed -i '' '1d' renew_leases_batch.lua && head -3 renew_leases_batch.lua
bash /tmp/eval3_test.sh   # SCRIPT LOAD; FLUSHALL; TIME; HSET {t}:leases m1..m4; ZADD {t}:due; EVALSHA with 5 items; HGETALL; ZRANGE WITHSCORES
bash /tmp/eval3_test2.sh  # 65-item rejection; 64-item batch; odd arity; ttl=0; corrupt value; numkeys=0 undeclared-key error; SCRIPT KILL; INFO commandstats; SLOWLOG GET; LATENCY RESET
python3 (in-place edit of renew_leases_batch.lua: math.floor on n, string.format("%d") in the cap error)
grep -n 'math.floor((nargv\|exceeds max' renew_leases_batch.lua
bash /tmp/eval3_bench.sh  # seed 100k leases via redis-cli --pipe; redis-benchmark -n 50000 -c 32 -r 100000 --csv for N=1,16,64; INFO commandstats; INFO latencystats
bash /tmp/eval3_bench2.sh # redis-benchmark -n 20000 -c 1 -r 100000 for N=1,16,64; INFO commandstats delta around a fixed 20000-call N=64 run
bash /tmp/eval3_test.sh   # re-verify after the edit
redis-cli -p 32816 SLOWLOG LEN; redis-cli -p 32816 CONFIG GET slowlog_log_slower_than; redis-cli -p 32816 CONFIG GET maxmemory
cat > .../outputs/DESIGN.md <<'MD2' ... MD2
docker rm -f eval-3-ns-a

## Final answer

Delivered `renew_leases_batch.lua` (90 lines) and `DESIGN.md`, both validated against a live
`df-v1.34.0` container.

Shape of the script: read -> decide -> write. `TIME` plus one `HMGET` acquire every fact; a pure
loop turns `(stored value, caller token, now_ms, ttl_ms)` into a per-item status and accumulates
two write-argument lists; then at most one variadic `HSET` and one variadic `ZADD` apply the
accumulated decisions. So the command count is **4 regardless of batch size**, not `2N`.

Contract: `EVALSHA <sha> 2 {t}:leases {t}:due <ttl_ms> <mailbox_id> <token> ...`, 1..64 pairs.
Reply is a flat array of `1 + 2N`: `now_ms`, then `(status, new_deadline_or_0)` per item in
request order, status in `renewed | token_mismatch | expired | missing`.

Three decisions worth flagging:
- No clock argument. `now_ms` comes from server `TIME` (legal in Dragonfly because it replicates
  effects, verified), so a skewed client cannot extend or kill a lease. The new deadline is
  `now + ttl_ms`, not `old + ttl_ms`.
- The stored value is split on the *last* colon, so tokens may contain colons; a value that does
  not match `^(.*):(%d+)$` aborts the whole call with an error rather than being reported as
  `missing`, because that is writer corruption, not a lease state.
- Renew never reaps. `expired`/`missing` leave `{t}:due` untouched; deleting state there belongs
  to the reassignment path, which holds the authority renew does not.

Boundedness, and why it is the load-bearing property: Dragonfly `v1.34.0` has no `SCRIPT KILL`
(verified: `ERR Unknown subcommand ... for 'KILL'`), so a slow script cannot be rescued — it has
to be impossible to write. The cap of 64 is enforced inside the script before any I/O; there are
no unbounded primitives (no KEYS/SCAN/HGETALL/ZRANGE, no data-driven loop bound); allocation is
proportional to the request, never to stored data; and the `{t}` tag keeps the transaction on one
shard so other shards keep serving.

Measured on the container (Docker/macOS, loopback, 100k leases — method output, not an SLO):
- `-c 1`: avg 0.282 ms at N=1, 0.413 ms at N=64 => fixed ~0.28 ms (mostly RTT), **marginal 2.1 us
  per item**. Affine in N is the ship criterion; a curve means an accidental O(N^2).
- `INFO commandstats` delta, N=64, c=1: 5824726 us / 20000 calls = **291 us of server time per
  call**, ~4.5 us per renewed lease.
- `-c 32`: 7338 rps (N=1) -> 3890 rps (N=64), p99 12.5 ms, `SLOWLOG LEN` 320. Per-call `evalsha`
  time rose 291 us -> 5.9 ms; that gap is queueing on the single `{t}` shard, not script cost.

The last point is the real finding for shipping: because every lease sits under one hash tag,
this operation does not scale by adding shards or cores. It scales by fatter batches or by
splitting tenants across `{t}` values, and that choice should be made before launch, not after.

DESIGN.md §7 gives the full pre-ship measurement plan as runnable commands: correctness fixture
first (it gates the benchmark), uncontended per-call sweep, `commandstats` CPU delta, saturation
sweep for the hot shard, a no-script pipelined baseline for comparison, a worst-legal-call tail
run (64/64 renewing, read `max` and `SLOWLOG`, gate the release on it), and a replica digest
comparison to prove the `TIME`/effects-replication assumption on the actual build.
