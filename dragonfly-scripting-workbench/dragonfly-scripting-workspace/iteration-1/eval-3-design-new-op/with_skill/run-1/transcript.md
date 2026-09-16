## Files read

/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/SKILL.md
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/references/lua-patterns.md
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/references/measurements.md (grepped: Q7, --compare, --reseed, ignore_reply_indices, spec)
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/assets/examples/claim_mailbox_batch_spec.json
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/assets/examples/claim_mailbox_batch_seed.py
/Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/scripts/lab.sh

## Commands run

ls -la /Users/pzixel/Documents/Repos/codex-personal-skills/dragonfly-scripting-workbench/dragonfly-scripting/
wc -c references/*.md scripts/* assets/examples/* ; ls -R assets scripts
sed -n '1,200p' references/lua-patterns.md
cat assets/examples/claim_mailbox_batch_spec.json; cat assets/examples/claim_mailbox_batch_seed.py; sed -n '1,80p' scripts/lab.sh
grep -n "Q7\|--compare\|--reseed\|ignore_reply_indices\|spec" references/measurements.md | head -50
docker run -d --name eval-3-ws-df -p 0:6379 docker.dragonflydb.io/dragonflydb/dragonfly@sha256:366e34f415c22983dc1c4a1d575fa2d9c22b9a3998a9934bf1cc6d16c17695db --proactor_threads=4 --cache_mode=false --maxmemory=2048Mi
docker port eval-3-ws-df 6379; docker exec eval-3-ws-df redis-cli PING; docker exec eval-3-ws-df redis-cli INFO server | grep -i version
docker exec eval-3-ws-df redis-cli EVAL "local t=redis.call('TIME') return {t[1],t[2],tostring(math.type(tonumber(t[1])))}" 0
docker exec eval-3-ws-df redis-cli EVAL "redis.acall('HSET',KEYS[1],'f','v') return 'done'" 1 k ; redis-cli HGET k f
docker exec eval-3-ws-df redis-cli EVAL "redis.acall('HSET',KEYS[1],'f2','v2') return redis.error_reply('ERR boom')" 1 k ; redis-cli HGET k f2
docker exec eval-3-ws-df redis-cli SET strkey x
docker exec eval-3-ws-df redis-cli EVAL "redis.acall('HSET',KEYS[1],'f','v') return 'done'" 1 strkey
docker exec eval-3-ws-df redis-cli EVAL "redis.call('HSET',KEYS[1],'f','v') return 'done'" 1 strkey
docker exec eval-3-ws-df redis-cli EVAL "redis.acall('HSET',KEYS[1],'f','v') local x=redis.call('GET',KEYS[1]) return 'done '..x" 1 strkey
cat > outputs/renew_leases_batch.lua <<'LUA' ... LUA   (heredoc write of the script)
docker cp outputs/renew_leases_batch.lua eval-3-ws-df:/tmp/r.lua
docker exec eval-3-ws-df redis-cli DEL '{t}:leases' '{t}:due'
docker exec eval-3-ws-df redis-cli HSET '{t}:leases' m1 "tokA:$FUT" m2 "tokB:$FUT" m3 "tokC:$PAST" m5 "ns:tokE:$FUT"
docker exec eval-3-ws-df redis-cli ZADD '{t}:due' $FUT m1 $FUT m2 $PAST m3 $FUT m5
docker exec eval-3-ws-df redis-cli --eval /tmp/r.lua '{t}:leases' '{t}:due' , 60000 m1 tokA m2 WRONG m3 tokC m4 tokD m5 "ns:tokE"
docker exec eval-3-ws-df redis-cli HGETALL '{t}:leases'; redis-cli ZRANGE '{t}:due' 0 -1 WITHSCORES
docker exec eval-3-ws-df redis-cli --eval /tmp/r.lua '{t}:leases' '{t}:due' , 60000
docker exec eval-3-ws-df redis-cli --eval /tmp/r.lua '{t}:leases' '{t}:due' , 60000 m1
docker exec eval-3-ws-df redis-cli --eval /tmp/r.lua '{t}:leases' '{t}:due' , 0 m1 tokA
docker exec eval-3-ws-df redis-cli --eval /tmp/r.lua '{t}:leases' '{t}:due' , abc m1 tokA
python3 -c 'print(" ".join(f"m{i} tok{i}" for i in range(65)))' > /tmp/args65.txt
docker exec eval-3-ws-df sh -c "redis-cli --eval /tmp/r.lua '{t}:leases' '{t}:due' , 60000 $(cat /tmp/args65.txt)"
docker exec eval-3-ws-df redis-cli HSET '{t}:leases' m6 'nodeadline'
docker exec eval-3-ws-df redis-cli --eval /tmp/r.lua '{t}:leases' '{t}:due' , 60000 m1 tokA m6 tokF ; redis-cli HGET '{t}:leases' m1
docker exec eval-3-ws-df redis-cli INFO ALL | grep -E 'eval_io_coordination_total|eval_shardlocal_coordination_total'   (before/after one invocation, and around a 1-key EVAL)
docker exec eval-3-ws-df redis-cli SCRIPT LOAD "$(docker exec eval-3-ws-df cat /tmp/r.lua)"
docker exec eval-3-ws-df redis-cli SCRIPT LATENCY | head -20
python3 -c 'import redis' (absent on host)
python3 heredoc -> /tmp/seed64.txt (DEL/HSET/ZADD for 64 leases); docker cp; docker exec sh -c 'redis-cli < /tmp/seed64.txt'
docker exec eval-3-ws-df redis-cli SCRIPT FLUSH
docker exec eval-3-ws-df sh -c "redis-cli -x SCRIPT LOAD < /tmp/r.lua"
python3 heredoc -> /tmp/bench.txt (220x EVALSHA, 64 pairs); docker cp; docker exec sh -c 'redis-cli < /tmp/bench.txt > /dev/null'
docker exec eval-3-ws-df redis-cli SCRIPT LATENCY | head -22
cat > /tmp/naive.lua <<'LUA' ... LUA  (per-item HGET/HSET/ZADD control variant)
docker cp /tmp/naive.lua eval-3-ws-df:/tmp/naive.lua ; docker exec sh -c "redis-cli -x SCRIPT LOAD < /tmp/naive.lua"
python3 heredoc -> /tmp/bench2.txt (220x EVALSHA naive); docker cp; docker exec sh -c 'redis-cli < /tmp/bench2.txt > /dev/null'
docker exec eval-3-ws-df redis-cli SCRIPT LATENCY | grep -A4 <naive sha>
docker exec eval-3-ws-df redis-cli INFO ALL | grep -E 'eval_io_coordination_total|eval_shardlocal_coordination_total'
cat > outputs/DESIGN.md <<'MD' ... MD
docker rm -f eval-3-ws-df ; docker ps -a --filter name=eval-3-ws-

## Final answer

Delivered `outputs/renew_leases_batch.lua` and `outputs/DESIGN.md`. Both were exercised against a
throwaway df-v1.34.0 container (removed afterwards).

**Contract.** `EVALSHA <sha> 2 {t}:leases {t}:due <ttl_ms> <mailbox_id> <token> ...`, n <= 64 pairs.
Reply is a flat array of arity exactly `1 + 2n`: `[1]` = server `now_ms` as a decimal string, then
per item `status` (integer) and `deadline_ms` (decimal string). Status 1 renewed / 2 token_mismatch
/ 3 expired / 0 missing; token is checked before expiry, the expiry boundary is inclusive
(`stored <= now` is dead), and `deadline_ms` carries the stored deadline for 2 and 3, `'0'` for 0.
Milliseconds leave as strings because a Lua array reply truncates floats; status codes are integers
rather than error replies. `redis.error_reply` is reserved for protocol violations (bad ttl, odd
ARGV tail, n > 64, a lease value not matching `'<token>:<digits>'`), all raised before the first
write so a rejected batch is a clean no-op.

**Bounding.** `MAX_ITEMS = 64` is a constant in the script and an over-sized batch is rejected, not
truncated. The script issues **2 to 4 `redis.call` regardless of n** — `TIME`, one `HMGET` for the
whole window, then one multi-field `HSET` and one multi-member `ZADD` only if something renewed —
against 1 + 3n = 193 for the per-item shape. No loop's trip count comes from the keyspace, the
largest `unpack` is 128 arguments (ceiling is 8163), there is no `cjson`, and the reply is at most
129 short elements. This matters because Dragonfly has no script timeout, no `SCRIPT KILL` and no
BUSY reply. The two writes use `redis.acall` since their replies are discarded; I verified on
v1.34.0 that `acall` errors still abort the script and reach the client, and that buffered writes
flush even when the script returns an `error_reply` (hence validation-before-write).

**Regime, measured not guessed.** Two keys under one hashtag on default flags is io-coordinated:
one invocation moved `eval_io_coordination_total` +1 with `eval_shardlocal_coordination_total`
unchanged, while a single-key EVAL on the same server moved the shardlocal counter. So the unit of
cost is the call count, which is what the design minimises. `--lock_on_hashtags` is discussed as a
deployment-wide trade-off with its rule (distinct tags >= shard count, or total script CPU fits one
core, then measure both arms), not as a default.

**Verification performed.** Mixed batch returned renewed / token_mismatch / expired / missing in
input order with correct deadlines; only the renewed fields changed in the hash and the zset; a
token containing `:` round-trips (greedy split on the last colon); n = 0, odd tail, ttl = 0,
non-numeric ttl and n = 65 all rejected; a malformed stored value aborted the batch with no write.
Smoke cost, server-side `SCRIPT LATENCY`, 220 invocations, 64 renewable leases, single sequential
client: ~201 µs median (max 618) for the batched script vs ~6482 µs (max 9724) for a per-item
control, both io-coordinated — a shape check, not a shipping number.

**Pre-ship measurement plan** (DESIGN.md §4): lab up with the pinned digest; seed + spec with a
realistic tenant and an adversarial status mix including a zero-renewal batch;
`bench_script.py --spec --seed --reseed --compare naive.lua renew_leases_batch.lua` with
`ignore_reply_indices = [1] + [2i+1 for renewable i]` and the derived invariant
`deadline - now == ttl_ms` asserted instead; read the coordination-counter delta per invocation from
the same run; sweep batch size 1/8/32/64 and hit ratio 0/50/100% (near-flat cost in batch size is
the falsifiable claim); `script_latency.py --sha --watch` under real concurrency with percentiles
quoted as bucket bounds; a `--lock_on_hashtags` arm back-to-back in one session if the flag is on
the table. `--reseed` is mandatory here because renewal is not idempotent across the expiry
boundary. Ship gate: expected regime counter, byte-identical replies under `--compare`, p50 **and**
p99 reported and flat in batch size, no co-tenant regression.

**Caveat found:** on df-v1.34.0, `SCRIPT FLUSH` did not reset an existing sha's `SCRIPT LATENCY`
histogram (a sha's sample count carried over), so arms need before/after differencing or a node
restart. The skill's `references/measurements.md` states SCRIPT FLUSH resets them.

No git operations were run, per the mechanics.
