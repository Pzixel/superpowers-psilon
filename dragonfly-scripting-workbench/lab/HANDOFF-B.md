# Handoff B (Dragonfly lab, phase 1, Q5-Q8)

Part B delivered Q5-Q8 (`lab/bench/q5_key_placement.py`, `q6_replica.py`,
`q7_real_script.py`, `q8_head_of_line.py`), the two Q7 script variants under
`lab/variants/`, and the execution-path counter helpers in `lab/bench/common.py`.
The lab is LEFT RUNNING in its default state (primary :6379 + replica attached,
single :6381; no throwaway containers).

## New in `common.py` (retrofit these onto Q1-Q4)
```python
parse_counters(info_text) -> dict          # pure
script_counters(r) -> dict                 # I/O snapshot from INFO ALL
counter_delta(before, after, include_zero=False) -> dict   # pure
format_counters(delta, keys=(...)) -> str  # pure one-liner
```
Covers every `eval_*`, `lua_*`, `tx_*`, `squash*`, `multi_*` field plus
`blocked_on_interpreter`, `commands_squashing_replies_bytes`, `used_memory_lua`.
`tx_with_freq` / `squash_with_freq` are comma-separated vectors, not scalars, and
are skipped by the numeric parser. Pattern: snapshot before the timed loop,
snapshot after, `format_counters(counter_delta(a, b))` into the raw log, and
divide by the invocation count to get the per-invocation path.

The two decisive fields are `eval_shardlocal_coordination_total` (script ran on
the shard-local fast path) and `eval_io_coordination_total` (script needed
cross-shard hops). They are what turns Q5 from a latency story into a mechanism.

## Findings that change how the other benchmarks should be read
1. **A hashtag does NOT co-locate keys on one shard on default flags.** 8 keys in
   one hashtag are io-coordinated and cost the same per `redis.call` as 8 keys in
   8 hashtags (~27us/call). Only `--lock_on_hashtags` makes the one-hashtag script
   shard-local (~1.0us/call). The 1-key script is always shard-local (~1.1us/call).
   That, not "multi-key", is the 0.6us vs 29us split part A saw.
2. `--!df flags=disable-atomicity` and `--!df flags=allow-undeclared-keys` both move
   a script from `eval_shardlocal_coordination_total` to `eval_io_coordination_total`,
   i.e. they COST the fast path. Visible as latency only where there was a fast path
   to lose (under `--lock_on_hashtags`).
3. `--lua_auto_async=true` only helps `redis.call` whose result is discarded.
4. Q6: the attached replica is inside run-to-run variation for the 192-call script;
   a single A-then-B comparison flipped sign between pilot runs, so Q6 runs ABBA
   with two replicates per condition. Any future A/B on this lab needs the same.
5. Q7's fixtures must not derive seed values from the wall clock: the reply carries
   `earliest_due`, which is the seeded zset score, so a clock-derived score makes two
   variants' replies differ for a reason unrelated to the scripts.
6. Benchmarks leave large keys behind (Q7 seeds ~2 MB of records). Absolute numbers
   for a benchmark that runs after Q7 shift by tens of percent; compare within a run.

## Verification
`lab/.venv/bin/python lab/bench/q7_real_script.py` prints
`reply arrays identical (clock fields normalised): True` plus the fence check
`RESOLVED, 32/32 CLAIMED` for both variants - that is the phase's strongest single
check (real production script, real protocol, variant proven equivalent).
