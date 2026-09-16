# Q7 — `claim_mailbox_batch.lua` invocation contract (verified 2026-09-16)

Source repo `/Users/pzixel/Documents/Repos/email-stats` is READ-ONLY. Script lives at
`crates/dragonfly-store/assets/claim_mailbox_batch.lua` (296 lines); copy it to
`lab/variants/claim_mailbox_batch.orig.lua`.

All keys carry the single hashtag `{email-stats-inbound}` (`src/keys.rs:5-7`), so
`catalog:` prefix = `catalog:{email-stats-inbound}`, `imap:` prefix = `imap:{email-stats-inbound}`.

## KEYS — exactly N = 14, assembled at `src/coordinator.rs:450-463`

| # | literal key | builder |
|---|---|---|
| 1 | `catalog:{email-stats-inbound}:active_generation` | keys.rs:30-32 |
| 2 | `catalog:{email-stats-inbound}:cursor_coverage_generation` | keys.rs:100-102 |
| 3 | `catalog:{email-stats-inbound}:reconciled_server_run_id` | keys.rs:96-98 |
| 4 | `catalog:{email-stats-inbound}:last_reconciliation_started_ms` | keys.rs:26-28 |
| 5 | `catalog:{email-stats-inbound}:generation:<GEN>:mailbox_versions` | keys.rs:108-112 |
| 6 | `imap:{email-stats-inbound}:due` | keys.rs:184-186 |
| 7 | `imap:{email-stats-inbound}:leases` | keys.rs:204-206 |
| 8 | `imap:{email-stats-inbound}:lease_receipts` | keys.rs:208-210 |
| 9 | `imap:{email-stats-inbound}:diagnostic_owners` | keys.rs:216-218 |
| 10 | `imap:{email-stats-inbound}:poll_starts` | keys.rs:188-190 |
| 11 | `catalog:{email-stats-inbound}:active_grants_descriptor` | keys.rs:34-36 |
| 12 | `catalog:{email-stats-inbound}:active_mailbox_versions` | keys.rs:44-46 |
| 13 | `catalog:{email-stats-inbound}:mailbox_records` | keys.rs:102-104 |
| 14 | `imap:{email-stats-inbound}:lease_records` | keys.rs:212-214 |

`execute_atomic_for_current_run` (`src/client.rs:486-517`) prepends/appends NOTHING to
KEYS or ARGV; it only reads `INFO replication` to get `run_id` and passes it to the builder.

## ARGV — `#ARGV` must be exactly `8 + batch_size` (lua:74)

| # | value | file:line |
|---|---|---|
| 1 | `"1"` schema version | coordinator.rs:464, const :15 |
| 2 | generation string; must equal the value stored at KEYS[1] | :465 |
| 3 | `run_id` = server `master_replid` from `INFO replication` | :466 / client.rs:496-503 |
| 4 | `process_id`, non-empty | :467 |
| 5 | `120000` exactly (`MAILBOX_LEASE_TTL_MS`) — script rejects anything else | :468, const :17 |
| 6 | candidate_window (prod const is `64`; **phase-1 spec says use 1024**) | :469, const :18 |
| 7 | `600000` freshness limit (`CATALOG_FRESHNESS_LIMIT_MS`) | :470, const :20 |
| 8 | `batch_size`, 1..=32 (**spec: 32**) | :471 |
| 9..8+batch | one non-empty UUIDv4 lease token per slot, matched by `^[0-9a-f-]+$` | :472-479, :375 |

## Key types and seeding shapes

| key | type | field/member -> value |
|---|---|---|
| 1,2,3,4 | string | see fences |
| 5 (legacy) / 12 (mutable_v2) | hash | `<mailbox_id>` -> `<version>`; script picks KEYS[5] unless the descriptor says `mutable_v2` (lua:151-168) |
| 6 due | zset | member `<mailbox_id>`, score = due-at ms; must be `<= now` to be a candidate (lua:174-182) |
| 7 leases | hash | `<mailbox_id>` -> `"<token>:<deadline_ms>"`, regex `^([0-9a-f-]+):(%d+)$` (lua:65-73). Leave ABSENT for a free mailbox (spec: no leases) |
| 8 receipts | hash | `<token>` -> `"<mailbox_id>:<token>:<deadline_ms>"` (lua:71-81). Must be ABSENT for the request tokens, else the script short-circuits to RESOLVED (lua:95-118) |
| 9 diagnostic_owners | hash | `<mailbox_id>` -> `"<token>:<process_id>"` (lua:274) |
| 10 poll_starts | hash | `<mailbox_id>` -> `"<token>:<now_ms>"` (lua:275) |
| 11 descriptor | hash | fields `storage_format`, `state`, `generation`. Simplest seeding: DO NOT CREATE IT — all three nil means legacy layout and versions come from KEYS[5] |
| 13 mailbox_records | hash | field `"<mailbox_id>:<version>"` -> JSON record containing a matching `mailbox_id`; this is the ~2 KB payload (lua:213-217, decode coordinator.rs:1220-1227) |
| 14 lease_records | hash | `<token>` -> same record JSON (lua:276) |

`mailbox_id` must be lowercase hex `[0-9a-f]+` (receipt regex; `parse_mailbox_id` coordinator.rs:1218).
The exact `ImmutableMailboxRecord` JSON schema lives in the `mailbox_domain` crate and was
NOT opened; the only verified constraint is "valid JSON whose `mailbox_id` field matches".
Pad it to ~2 KB with a filler field.

## Fences — all must pass for a claim to succeed

| fence | requirement | lua line |
|---|---|---|
| active generation | `GET KEYS[1] == ARGV[2]` | 133-136 |
| cursor coverage | `GET KEYS[2] == GET KEYS[1]` | 137-139 |
| server run | `GET KEYS[3] == ARGV[3]` (current `master_replid`) | 140-142 |
| freshness | `KEYS[4]` numeric ms, `<= now` and `now - it <= ARGV[7]`; `now` from server `TIME` | 60-63, 143-147 |
| descriptor | absent hash = OK; if `storage_format` set it must be `mutable_v2` + `state=committed` + `generation=active_generation`; `state` without `storage_format` -> PROTOCOL | 150-172 |
| receipts | no request token may already exist in KEYS[8] | 95-118 |
| record present | `HGET KEYS[13] "<mailbox_id>:<version>"` must exist for a claimable candidate | 213-216 |

## Reply shape (decode target, coordinator.rs:1168-1174)

Flat array of bulk strings:
`["RESOLVED", now_ms, earliest_due_or_"", batch_size, <batch_size x 5 fields>]` where each
5-tuple is `[status, token, mailbox_id, deadline, record_json]` and status is
`CLAIMED` / `RECEIPT_EXPIRED` / `UNUSED` (lua:278-284, 306-310).
Other terminal forms: `{'NOT_DUE', now, earliest}`, `{'RETRY_IMMEDIATELY', now}`,
`{'CLEANUP_REQUIRED', now, mailbox_id, token, deadline}`, `{'FENCED', reason}`,
`{'PROTOCOL', reason}`.
