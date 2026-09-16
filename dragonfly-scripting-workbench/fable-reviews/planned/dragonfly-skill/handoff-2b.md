# Handoff — phase 2b (dragonfly-scripting executables)

Commit `1e61ac1` on `main` (not pushed). 7 files, 1033 insertions. Only
`dragonfly-scripting/scripts/` and `dragonfly-scripting/assets/` were staged;
SKILL.md and `references/` were left untouched for the concurrent implementer.

## Files

| file | lines | role |
|---|---|---|
| `dragonfly-scripting/scripts/lua_call_audit.py` | 323 | stdlib-only static Lua audit, always exit 0 |
| `dragonfly-scripting/scripts/_common.py` | 253 | vendored redis helpers (only third-party dep: `redis`) |
| `dragonfly-scripting/scripts/script_latency.py` | 92 | SCRIPT LATENCY p50/p95/p99, cumulative or `--watch` delta |
| `dragonfly-scripting/scripts/bench_script.py` | 202 | seeded EVALSHA bench, `--compare` with reply-equality assert |
| `dragonfly-scripting/scripts/lab.sh` | 61 | up/down/status over `../assets/compose.yaml` |
| `dragonfly-scripting/scripts/test_lua_call_audit.py` | 41 | one focused test of loop detection + undeclared-key |
| `dragonfly-scripting/assets/compose.yaml` | 61 | copy of `lab/compose.yaml`, digest-pinned |

Interfaces a reviewer/SKILL.md author needs:
- `lua_call_audit.py:14` `RULES` — the five rule ids; `--rules/--rule/--exclude/--count`.
- `lua_call_audit.py:196` `audit_source(path, src) -> [(line, rule, problem, fix)]` (pure).
- `_common.py:97` `parse_script_latency`, `:137` `bucket_percentiles`, `:152` `subtract_entry`
  (the "histograms never reset" workaround), `:205` `COUNTERS` / `:210` `parse_counters`.
- `bench_script.py:7-31` — the JSON spec shape, also printed by `--help`.
- `script_latency.py:28` `rows()`, `:39` `deltas()` (pure).

## Verification (all observed, this machine, 2026-09-16)

1. Audit over `/Users/pzixel/Documents/Repos/email-stats/crates/dragonfly-store/assets/`
   (52 files): **66 finding lines** (budget 150). By rule: batchable-hash 37,
   call-in-loop 24, cjson-hot 4, read-past-bound 1, undeclared-key 0.
   Top files: apply_new_mutable_mailbox_page 9, claim_mailbox_batch 9,
   write_catalog_page 8, claim_mailbox 5, import_cursor_page 5.
   Required hits all present: `apply_new_mutable_mailbox_page.lua:453`,
   `remove_mutable_mailbox.lua:314`, `apply_new_mutable_mailbox_page.lua:673` and
   `:674`, `claim_mailbox_batch.lua:184` (both `batchable-hash` and
   `read-past-bound`, the latter naming the bound check at line 233).
2. Live on the lab (`lab.sh up` -> df-v1.34.0, threads=4, primary+replica healthy):
   `script_latency.py` cumulative table and `--watch 1` delta window (60 calls,
   p50 18us); `bench_script.py --compare orig.lua hmget.lua` with a Q7-contract
   seed and `--reseed`: **replies identical** over 164 flattened fields, ignoring
   the 33 declared clock positions. orig p50 ~42.8ms vs hmget p50 ~8.7ms,
   ratio 0.203 (a 200-iter run earlier the same session gave 101.9ms vs 9.4ms,
   ratio 0.092 — the machine was noisier then; both runs agree on the direction,
   not on the magnitude). Coordination split: io=1.00/invocation for both
   variants, shardlocal=0.00. `lab.sh down` clean.
3. `--help` clean on system python3 3.12 for all three python tools (the `redis`
   import is deferred so `--help` works without the client installed); `lab.sh`
   with no args prints usage and exits 2.

Repro of the phase in one step:
`python3 dragonfly-scripting/scripts/lua_call_audit.py <email-stats>/crates/dragonfly-store/assets/ | wc -l` -> 66,
and that output contains the four required sites above.

## Out of scope / open

- SKILL.md, `references/`, `generate_openai_yaml.py`, `quick_validate.py` — phase lead.
- The bench seed used for the live evidence is scratch (`/tmp/dfscratch/q7_seed.py`),
  deliberately not shipped: the skill's contract is the JSON spec + a user seed.
  If the lead wants a worked example in the skill, it belongs in `references/`.
- `undeclared-key` fires zero times on the production corpus (that code always
  passes keys through KEYS). It is covered by the unit test instead. Decide
  whether a zero-hit rule earns its place in the SKILL.md rule list.
- `subtract_entry` deltas have no server-reported median, so `format_script_latency`
  degrades to `p50<=<bucket upper bound>`. Bucket resolution is coarse (8-16
  buckets); do not quote those as precise percentiles in prose.
