# Handoff A -> B (Dragonfly lab, phase 1)

Part A delivered: `compose.yaml`, `.venv`, `bench/common.py`, Q1/Q2/Q3/Q4/Q9, `run_all.sh`,
`RESULTS.md`. The lab is LEFT RUNNING (all three nodes). Q5-Q8 are yours.

## Running things
- One benchmark: `lab/.venv/bin/python lab/bench/q5_key_placement.py` (cwd-independent).
- All: `lab/run_all.sh` — compose up, every `bench/q*.py` in version order, then prints the
  first 40 lines of `RESULTS.md`. Re-runnable; never tears the lab down.
- Ports: 6379 `dfskill-primary`, 6380 `dfskill-replica`, 6381 `dfskill-single`
  (proactor_threads=1, `single` profile — `docker compose --profile single up -d --wait
  single`; `run_all.sh` starts it once any `bench/*.py` mentions `SINGLE_PORT`/`6381`).

## `common.py` interface
```python
connect(port=6379, decode=False) -> redis.Redis;  primary()/replica()/single()
server_version(r) -> str   # "df-v1.34.0 (redis_version 7.4.0), threads=4"
server_flags(r) -> str     # exact argv via `docker inspect`
info_text(r, section="ALL") -> str    # raw INFO text (redis-py would give a dict)
unique_body(body) -> str   # pure; appends "-- run:<uuid>"
load_script(r, body, unique=True) -> sha;  evalsha(r, sha, keys, args=None)
script_flush(r); script_latency_text(r) -> str; flushall(*clients)
restart(container="dfskill-primary", port=6379, timeout_s=60) -> None
time_calls(fn, iters=200, warmup=20) -> list[float]   # MICROSECOND samples, as-is
payload(nbytes, seed="x") -> bytes
percentiles(samples_us) -> {n,min,p50,p95,p99,max,mean,total}   # pure, nearest-rank
format_table(headers, rows) -> str                              # pure
stat_row(label, st, extra=None) -> list ; STAT_HEADERS
parse_script_latency(text, sha=None) -> dict  # pure; count/average_us/stddev/min_us/
                                              # median_us/max_us/buckets/raw
format_script_latency(entry) -> str           # pure one-liner
RawLog(question, r=None, note="")  -> .w(s) .cmd(s) .section(t) .save()
emit(question, title, summary_row, body) -> None   # merges into RESULTS.md
```
Pattern: `log = RawLog("q5", r, note=...)` -> `log.cmd(...)` per command issued -> tables via
`format_table(STAT_HEADERS + [...], rows)` -> `log.save()` ->
`emit("q5", title, ["Q5", experiment, key_numbers, conclusion], body)`.

## Raw logs and RESULTS.md
Raw log `lab/results/<question>.txt` (via `RawLog.save()`) must carry server version, server
flags and every command line (`log.cmd`). `emit()` wraps your body in
`<!--BEGIN q5-->...<!--END q5-->` with a `<!--SUMMARY| ... |-->` line, replaces any existing
block for that question and rebuilds the leading summary table from all blocks (missing ones
show `pending (part B)`). Never edit RESULTS.md by hand; you cannot clobber A's rows.

## Gotchas hit in part A (all verbatim evidence in `lab/results/q9.txt`)
1. **`SCRIPT LATENCY` histograms are cumulative for the server lifetime; `SCRIPT FLUSH` does
   NOT reset them.** Hence `load_script(..., unique=True)` (default) appends a run nonce so a
   fresh sha gives a this-run-only histogram. It still includes warm-up — say so when quoting.
   Reply is a *nested* array of `[sha, blob]` pairs; `script_latency_text()` flattens it.
   Units are microseconds.
2. `SCRIPT FLAGS <sha>` with no flag argument **errors** — setter only, no getter.
   `SCRIPT STATS`, `SCRIPT KILL`, `FUNCTION`, `FCALL`, `MEMORY DOCTOR`, `LATENCY HISTORY`
   do not exist on v1.34.0. `EVAL_RO`/`EVALSHA_RO` do.
3. **`#!lua flags=...` is a Lua SYNTAX ERROR on Dragonfly** (`unexpected symbol near '#'`),
   not a silently-ignored shebang. The real directive is `--!df flags=disable-atomicity` /
   `--!df flags=allow-undeclared-keys`, first line — both probed working. Use that in Q5.
4. Lua is **5.4** (Redis 5.1). `unpack`, `table.unpack`, `bit`, `cjson`, `cmsgpack`, `struct`,
   `redis.sha1hex` present; `redis.setresp` is `nil`. `redis.call('HMGET', k, unpack(t))`:
   **8163 fields OK, 8164 -> `stack overflow`** (16000 -> `too many results to unpack`).
5. **Dragonfly's OOM check is against RSS.** After a 32 MiB `cjson.encode` RSS sits at
   ~2.5 GiB against `--maxmemory=2048Mi` and every later write returns `-ERR Out of memory`.
   `FLUSHALL` does not help; use `common.restart(...)`. Q4 restarts the primary on entry and
   flushes — do not assume keys seeded by an earlier benchmark survive.
6. `redis.call` cost is dominated by key placement: ~0.6 us in a 1-key (shard-local) script
   vs ~29 us in a 4–6 key script on `--proactor_threads=4`. That is Q5's whole subject.
7. `--lua_auto_async` **exists** on v1.34.0, as do `--lock_on_hashtags`, `--default_lua_flags`,
   `--lua_force_atomicity_shas`, `--multi_exec_squash`, `--interpreter_per_thread`.
8. Q4's concurrent-`GET` blocking is **run-to-run unstable** (p99 130 us vs 34 ms for the same
   8 MiB script) depending on whether the probe key lands on the script's proactor. Q8 is the
   controlled version — pin the probe key deliberately.

9. Part B added execution-path counters to `common.py` (`script_counters`/
   `counter_delta`/`format_counters`) and found that a hashtag does NOT pin keys to
   one shard without `--lock_on_hashtags`. See `lab/HANDOFF-B.md` before reusing
   any of A's numbers as a shard-locality claim.
