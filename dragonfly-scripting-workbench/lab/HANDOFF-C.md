# Handoff C (Dragonfly lab, phase 1, Q10 commit + Q11)

Phase C committed part B's unfinished Q10 work and added Q11 (does Redis
performance advice hold on Dragonfly?). The lab is LEFT RUNNING in its default
state: primary :6379 + replica attached, single :6381, no throwaway container.

## Commits
- `9b2006e` lab: add Q10 (lock_on_hashtags), lift throwaway-node helper, fix
  fragment regex
- Q11: `lab/bench/q11_redis_advice.py`, `lab/results/q11.txt`, RESULTS.md row.

## Bug found and fixed in `common.merge_results`
`_FRAG_RE` (`lab/bench/common.py:327`) matched `<!--BEGIN (q\d)-->`, one digit.
`merge_results` only carries over the fragments that regex finds, so emitting any
q1-q9 block **silently deleted the q10 block and its summary row** from
RESULTS.md. It bit immediately: the verification run of q5 dropped part B's
uncommitted Q10 fragment, so Q10 had to be re-run to regenerate it (the Q10
numbers in RESULTS.md are therefore from phase C, not part B; the mechanism and
conclusions are unchanged). Regex is now `q\d+` and `QUESTION_ORDER`
(`common.py:32`) lists `q11`. Any question past q9 depends on this.

## Q11 layout (`lab/bench/q11_redis_advice.py`)
One file, four sections, each run on the default primary :6379 AND on a
throwaway `--lock_on_hashtags` node :6382 (`common.start_flag_node`, same helper
as q5/q10), 200 iterations after 20 warm-up, every cell with its INFO
execution-path counter delta:
- `section_a` :127 - 64 GET / 64 HSET in one hashtag as client pipeline vs one
  atomic script vs MULTI/EXEC.
- `section_b` :210 - 100k x 64B as 100k strings (`DEBUG POPULATE`, which names
  keys `<prefix>:<i>`) vs one 100k-field hash vs 1000x100 hashes; `used_memory`
  delta on a freshly restarted server plus `DEBUG OBJHIST` (works on v1.34.0)
  and single-value read latency.
- `section_c` :253 - sliding-window ZSET limiter in Lua vs `CL.THROTTLE`
  (**exists** on v1.34.0; reply `[0, limit+1, remaining, -1, retry]`).
- `section_d` :296 - 200 sequential `SCRIPT LOAD` of the 8894B
  `claim_mailbox_batch.orig.lua`, idle and under 4 q8-style loader PROCESSES
  running a calibrated ~2 ms script, against `EVALSHA` of a trivial 1-key script
  under the same load. Two load rows: same text (cached sha) and fresh text
  (nonce comment appended, so it really compiles).

## Gotchas for the next agent
1. `timed()`'s `iters=ITERS` default binds at def time, so monkeypatching
   `q11.ITERS` from outside does not shrink the timed loops - only `N_B` etc.
2. `section_b` restarts the node it measures (`common.restart`) because
   `used_memory` deltas need a clean baseline and RSS never comes back from
   `FLUSHALL`. That restarts `dfskill-primary` mid-run and briefly breaks the
   replica link; the replica reconnects on its own.
3. Section d's loaders are terminated (`Process.terminate`) rather than joined on
   a deadline, so the loaded window is exactly the measured window.

## Out of scope
No unit tests (measurement code). Q1-Q4 still do not report counter deltas.
Nothing was pushed; no PR.

## Verification
`lab/.venv/bin/python lab/bench/q11_redis_advice.py` exits 0, prints all four
sections for both nodes, ends with `throwaway node removed; lab is back to its
default flags` and `[q11] RESULTS.md updated`, and leaves
`docker ps --format '{{.Names}}' | grep dfskill` showing exactly
`dfskill-primary`, `dfskill-replica`, `dfskill-single`.
