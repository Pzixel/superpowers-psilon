# handoff phase 1, part B (Q5-Q8)

Done, on `main`. Full technical handoff: `lab/HANDOFF-B.md` (counter helpers,
findings, gotchas). Results: `lab/RESULTS.md` summary rows Q5-Q8 + appendix, raw
logs `lab/results/q5.txt`..`q8.txt`.

## Files and interfaces
- `lab/bench/common.py:401-470` - new `parse_counters` / `script_counters` /
  `counter_delta` / `format_counters` (INFO execution-path counters). Nothing
  existing was changed, so A's Q1-Q4 are untouched.
- `lab/bench/q5_key_placement.py` - key placement matrix + hop microbenchmark +
  `--lock_on_hashtags` / `--lua_auto_async=true` runs on a throwaway container
  `dfskill-flag` :6382 (created and removed inside the run; the lab keeps its flags).
- `lab/bench/q6_replica.py` - imports A's Q2 scripts verbatim
  (`import q2_write_batching`), ABBA replicates, standalone produced with
  `REPLICAOF NO ONE` on the replica, re-attached at the end.
- `lab/bench/q7_real_script.py` + `lab/variants/claim_mailbox_batch.orig.lua`
  (verbatim copy) and `claim_mailbox_batch.hmget.lua` (header documents the one
  semantic difference: `record_missing` is checked only for claimed candidates).
- `lab/bench/q8_head_of_line.py` - 8 loader PROCESSES (not threads), per-node
  two-point calibration of the ~2ms script, four cells + unloaded baselines.

## Out of scope / not done
- Q1-Q4 were not re-run and not retrofitted with the counters (left for the
  follow-up agent named in the counter request).
- email-stats was not written to; the only touch is a read of the .lua asset.
- The lab is left RUNNING, as instructed; the final `docker compose down -v` is the
  phase lead's step.
- No unit tests: this is measurement code, the benchmark output is the evidence.

## Open decisions
- Q7's HMGET variant checks `record_missing` only for claimed candidates. If the
  skill recommends this rewrite it must carry that caveat, or re-add a full-window
  existence check (an `HMGET` of all candidate record fields would restore it at
  roughly the metadata cost).
- Whether the skill should recommend `--lock_on_hashtags`: it is the only flag that
  made a hashtag mean shard locality here (27.9 -> 1.0 us per `redis.call`), but it
  was measured on a throwaway node, not on the production-shaped primary.

## Verification (one step)
`lab/.venv/bin/python lab/bench/q7_real_script.py` -> `reply arrays identical
(clock fields normalised): True`, both variants fence-checked `RESOLVED, 32/32
CLAIMED`, and p50 67136us -> 6011us.
