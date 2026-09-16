# Handoff — phase 1 claim corrections to lab/RESULTS.md

Input: `lab/REVIEW-RESULTS.md` (verdict SOUND WITH CAVEATS). Scope: claim text,
qualifiers and cross-references only. **No measured number was changed** and no
benchmark was re-run.

## Route taken

Direct edit of `lab/RESULTS.md` **plus** the identical edit in the emitting
`lab/bench/q*.py` string, so `lab/run_all.sh` cannot resurrect the wrong text.
Regeneration via `run_all.sh` was rejected: it re-measures, which would change
measured numbers (forbidden). The rendered wording in `RESULTS.md` matches what
the patched emitters would produce, with the one intentional exception noted
under item 8.

## Done (one commit on `main`)

1. Q1 key shape — `bench/q1_call_overhead.py:118-126` (summary row) and `:113-117`
   (body); `RESULTS.md:13,27,31`. 0.67us/call is now labelled "against ONE key
   (shard-local)", quotes 5.1us at N=32, and cross-references Q5's 26.95us/call.
2. Q4 conclusion — `bench/q4_big_json.py:208-211`; `RESULTS.md:16,90`. No longer
   claims millisecond blocking; states sub-millisecond p99 and points to Q8 (B).
3. Q4 unsourced figure — `bench/q4_big_json.py:195-201`; `RESULTS.md:117`. The
   13875/30503/43 figures are deleted; the text says the earlier observation was
   not retained in a raw log.
4. Q5 1-key claim — `bench/q5_key_placement.py:213-218` (new per-node vars) and
   `:252-261`; `RESULTS.md:184`. Shard-local only when atomic; per-node figures
   1.01 / 1.46 / 1.54us/call; `disable-atomicity` moves the 1-key script onto
   io-coordination on all three nodes (1.23 / 1.40 / 1.49us/call).
5. Q2/Q3/Q7 vs Q10 — reconciliation paragraph in `bench/q10_lock_on_hashtags.py:270`
   (`RESULTS.md:397`), referenced from the Q2/Q3/Q7 summary rows
   (`bench/q2_write_batching.py:110`, `q3_read_after_full.py:136`,
   `q7_real_script.py:266`). Ratios from Q10 (back-to-back arms), absolutes from
   the standalone runs.
6. Q11 counter scope — `bench/q11_redis_advice.py:452-458`; `RESULTS.md:398`.
   (d)'s deltas are server-wide incl. loader traffic.
7. Q11(d) loader load — `bench/q11_redis_advice.py:438,489-496`; `RESULTS.md:462`.
   States 1320us (default) vs 2034us (lock_on_hashtags), ~1.5x, not equal-load.
8. Q11 traceability — `bench/q11_redis_advice.py:378,397-405,429` now writes the
   full per-variant tables into `results/q11.txt`; the current `RESULTS.md:400`
   carries a "this run is not raw-log-backed for p95/min/max/mean/total" note
   that a regeneration correctly drops (the log will then contain the data).
   This is the one place where `RESULTS.md` text is deliberately not emitted by
   the source.
9. Head-of-line under the flag — `bench/q11_redis_advice.py:447,510-522`;
   `RESULTS.md:481`, plus a pointer in the Q10 summary row. `EVALSHA` of a
   trivial 1-key script: 7712.4us (lock_on_hashtags) vs 81.2us (default) under
   4 loaders.

## Out of scope

Re-measurement of anything; the Q6 "beyond run-to-run variation" strength note
and the Q8 0.52 vs 31.9us/call observation from the review's Notes section (not
blocking, not requested); `lab/REVIEW-RESULTS.md` itself is left as the audit
record.

## Verification

```
python3 - <<'PY'   # (run from the repo root, HEAD~1 = pre-fix revision)
# all 219 non-summary table rows byte-identical; summary rows gain only
# 5.1 / 26.95 / N labels / "Q10"/"Q11" references
PY
```
Executed: every measurement table row in `RESULTS.md` is byte-identical to the
previous revision, no numeric token was removed from any summary row, the
summary table still lists Q1..Q11 in the first 40 lines, and the appendix still
has 11 `<!--BEGIN q*-->`/`<!--END q*-->` blocks. All eight touched benchmarks
byte-compile.

## Open decisions

- Whether the skill should quote Q10's ratios or the standalone absolutes is now
  stated in the report; the skill phase must follow it.
- `--lock_on_hashtags` is still the report's recommendation; item 9 is the
  counter-evidence the skill must carry with it.
