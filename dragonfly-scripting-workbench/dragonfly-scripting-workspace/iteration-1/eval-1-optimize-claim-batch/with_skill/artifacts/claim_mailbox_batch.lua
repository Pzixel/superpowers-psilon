-- claim_mailbox_batch (14 keys) -- Dragonfly v1.34.0, default flags.
--
-- KEYS (fixed arity 14, all sharing one {hashtag}):
--   1 active_generation      2 cursor_coverage_generation  3 reconciled_server_run_id
--   4 last_reconciliation_started_ms                       5 generation:<GEN>:mailbox_versions
--   6 due (zset)             7 leases                      8 lease_receipts
--   9 diagnostic_owners     10 poll_starts                11 active_grants_descriptor
--  12 active_mailbox_versions 13 mailbox_records           14 lease_records
-- ARGV: 1 schema_version, 2 expected_generation, 3 run_id, 4 process_id,
--       5 lease_ttl(=120000), 6 candidate_window, 7 freshness_limit,
--       8 batch_size(1..32), 9..8+batch_size request tokens.
--
-- Reply protocol and recovery semantics are identical to the per-item version;
-- only the number of redis.call round trips changed (see NOTES.md).

local rcall = redis.call
local racall = redis.acall
local unpack = unpack or table.unpack
local CHUNK = 512

-- Read `fields` from hash `key` in chunked HMGETs. Missing fields come back as
-- false, exactly like the HGET they replace.
local function hmget_many(key, fields)
  local out = {}
  local n = #fields
  local i = 1
  while i <= n do
    local hi = i + CHUNK - 1
    if hi > n then hi = n end
    local vals = rcall('HMGET', key, unpack(fields, i, hi))
    for j = 1, hi - i + 1 do
      out[i + j - 1] = vals[j]
    end
    i = hi + 1
  end
  return out
end

-- Fire `cmd key <args...>` in chunked redis.acall (reply is discarded).
local function acall_many(cmd, key, args)
  local n = #args
  local i = 1
  while i <= n do
    local hi = i + CHUNK - 1
    if hi > n then hi = n end
    racall(cmd, key, unpack(args, i, hi))
    i = hi + 1
  end
end

local function server_now_millis()
  local now = rcall('TIME')
  return tonumber(now[1]) * 1000 + math.floor(tonumber(now[2]) / 1000)
end

local function parse_lease(raw)
  if not raw then
    return nil
  end
  local token, deadline = string.match(raw, '^([0-9a-f%-]+):(%d+)$')
  if not token then
    return false
  end
  return {token = token, deadline = tonumber(deadline)}
end

local function parse_receipt(raw)
  if not raw then
    return nil
  end
  local mailbox_id, token, deadline =
    string.match(raw, '^([0-9a-f]+):([0-9a-f%-]+):(%d+)$')
  if not mailbox_id then
    return false
  end
  return {mailbox_id = mailbox_id, token = token, deadline = tonumber(deadline)}
end

local function earliest_due()
  local earliest = rcall('ZRANGE', KEYS[6], 0, 0, 'WITHSCORES')
  return earliest[2] or ''
end

local function resolved_response(now, batch_size, results, earliest)
  local response = {'RESOLVED', tostring(now), earliest, tostring(batch_size)}
  local n = 4
  for index = 1, batch_size do
    local item = results[index]
    if not item then
      item = {'UNUSED', ARGV[8 + index], '', '', ''}
    end
    for field = 1, 5 do
      n = n + 1
      response[n] = item[field]
    end
  end
  return response
end

if ARGV[1] ~= '1' then
  return {'PROTOCOL', 'schema_version'}
end

local expected_generation = ARGV[2]
local actual_run_id = ARGV[3]
local process_id = ARGV[4]
local lease_ttl = tonumber(ARGV[5])
local candidate_window = tonumber(ARGV[6])
local freshness_limit = tonumber(ARGV[7])
local batch_size = tonumber(ARGV[8])
if expected_generation == '' or actual_run_id == '' or process_id == ''
  or lease_ttl ~= 120000
  or not candidate_window or candidate_window < 1
  or not freshness_limit or freshness_limit < 1
  or not batch_size or batch_size < 1 or batch_size > 32
  or #ARGV ~= 8 + batch_size then
  return {'PROTOCOL', 'arguments'}
end
for index = 1, batch_size do
  if ARGV[8 + index] == '' then
    return {'PROTOCOL', 'arguments'}
  end
end

local now = server_now_millis()

-- ---------------------------------------------------------------- recovery --
-- Prefetch every receipt/lease/capture the recovery scan can need (all pure
-- reads), then take the decisions in the original slot order so the first
-- PROTOCOL reason is unchanged.
local request_tokens = {}
for index = 1, batch_size do
  request_tokens[index] = ARGV[8 + index]
end
local raw_receipts = hmget_many(KEYS[8], request_tokens)

local receipts = {}
local has_receipt = false
local bad_receipt = false
local lease_ids, lease_slot = {}, {}
local capture_tokens, capture_slot = {}, {}
for index = 1, batch_size do
  local receipt = parse_receipt(raw_receipts[index])
  receipts[index] = receipt
  if receipt == false then
    bad_receipt = true
  elseif receipt then
    has_receipt = true
    lease_ids[#lease_ids + 1] = receipt.mailbox_id
    lease_slot[index] = #lease_ids
    if receipt.deadline > now then
      capture_tokens[#capture_tokens + 1] = request_tokens[index]
      capture_slot[index] = #capture_tokens
    end
  end
end

if has_receipt or bad_receipt then
  local raw_leases = hmget_many(KEYS[7], lease_ids)
  local captures = hmget_many(KEYS[14], capture_tokens)
  local recovered = {}
  for index = 1, batch_size do
    local request_token = request_tokens[index]
    local receipt = receipts[index]
    if receipt == false then
      return {'PROTOCOL', 'receipt'}
    end
    if receipt then
      if receipt.token ~= request_token then
        return {'PROTOCOL', 'receipt_token'}
      end
      local lease = parse_lease(raw_leases[lease_slot[index]])
      if lease == false then
        return {'PROTOCOL', 'lease'}
      end
      if not lease or lease.token ~= receipt.token or lease.deadline ~= receipt.deadline then
        return {'PROTOCOL', 'receipt_lease_mismatch'}
      end
      if receipt.deadline <= now then
        recovered[index] = {
          'RECEIPT_EXPIRED',
          request_token,
          receipt.mailbox_id,
          tostring(receipt.deadline),
          ''
        }
      else
        local captured = captures[capture_slot[index]]
        if not captured then
          return {'PROTOCOL', 'record_missing'}
        end
        recovered[index] = {
          'CLAIMED',
          request_token,
          receipt.mailbox_id,
          tostring(receipt.deadline),
          captured
        }
      end
    end
  end
  if has_receipt then
    return resolved_response(now, batch_size, recovered, earliest_due())
  end
end

-- ------------------------------------------------------------------ fences --
local fences = rcall('MGET', KEYS[1], KEYS[2], KEYS[3], KEYS[4])
local active_generation = fences[1]
if active_generation ~= expected_generation then
  return {'FENCED', 'active_generation_changed'}
end
if fences[2] ~= active_generation then
  return {'FENCED', 'cursor_coverage_mismatch'}
end
if fences[3] ~= actual_run_id then
  return {'FENCED', 'server_run_reconciliation_required'}
end
local last_reconciliation = tonumber(fences[4] or '')
if not last_reconciliation or last_reconciliation > now
  or now - last_reconciliation > freshness_limit then
  return {'FENCED', 'catalog_not_fresh'}
end

local descriptor = rcall('HMGET', KEYS[11], 'storage_format', 'state', 'generation')
local storage_format = descriptor[1]
local state = descriptor[2]
local versions_key = KEYS[5]
if storage_format then
  if storage_format == 'mutable_v2' then
    if state == 'applying' then
      return {'FENCED', 'catalog_mutation_in_progress'}
    end
    if state ~= 'committed' then
      return {'PROTOCOL', 'catalog_descriptor'}
    end
  else
    return {'PROTOCOL', 'catalog_descriptor'}
  end
  if descriptor[3] ~= active_generation then
    return {'FENCED', 'active_generation_changed'}
  end
  versions_key = KEYS[12]
elseif state then
  return {'PROTOCOL', 'catalog_descriptor'}
end

-- -------------------------------------------------------------- candidates --
local candidates = rcall(
  'ZRANGEBYSCORE',
  KEYS[6],
  '-inf',
  tostring(now),
  'LIMIT',
  0,
  candidate_window
)
local n_candidates = #candidates

-- Pass 1: pure classification over prefetched versions/leases; it never
-- returns, it only records which records/receipts the decision pass can need.
local versions = hmget_many(versions_key, candidates)
local raw_leases = hmget_many(KEYS[7], candidates)

local leases = {}
local record_fields, record_slot = {}, {}
local receipt_tokens, receipt_slot = {}, {}
for index = 1, n_candidates do
  local lease = parse_lease(raw_leases[index])
  leases[index] = lease
  if lease ~= false then
    local version = versions[index]
    if not version then
      if lease and lease.deadline <= now then
        receipt_tokens[#receipt_tokens + 1] = lease.token
        receipt_slot[index] = #receipt_tokens
      end
    elseif not lease or lease.deadline <= now then
      record_fields[#record_fields + 1] = candidates[index] .. ':' .. version
      record_slot[index] = #record_fields
      if lease then
        receipt_tokens[#receipt_tokens + 1] = lease.token
        receipt_slot[index] = #receipt_tokens
      end
    end
  end
end
local records = hmget_many(KEYS[13], record_fields)
local stale_receipts = hmget_many(KEYS[8], receipt_tokens)

-- Pass 2: the original decision loop, unchanged, over prefetched values.
local saw_active = false
local removals = {}
local rescore_args = {}
local claimable = {}
for index = 1, n_candidates do
  local mailbox_id = candidates[index]
  local version = versions[index]
  local lease = leases[index]
  if lease == false then
    return {'PROTOCOL', 'lease'}
  end
  if not version then
    if not lease then
      removals[#removals + 1] = mailbox_id
    elseif lease.deadline <= now then
      local stale_receipt = parse_receipt(stale_receipts[receipt_slot[index]])
      if stale_receipt == false then
        return {'PROTOCOL', 'receipt'}
      end
      if not stale_receipt or stale_receipt.mailbox_id ~= mailbox_id
        or stale_receipt.token ~= lease.token
        or stale_receipt.deadline ~= lease.deadline then
        return {'PROTOCOL', 'receipt_lease_mismatch'}
      end
      return {
        'CLEANUP_REQUIRED',
        tostring(now),
        mailbox_id,
        lease.token,
        tostring(lease.deadline)
      }
    else
      rescore_args[#rescore_args + 1] = lease.deadline
      rescore_args[#rescore_args + 1] = mailbox_id
    end
  else
    saw_active = true
    if not lease or lease.deadline <= now then
      local record = records[record_slot[index]]
      if not record then
        return {'PROTOCOL', 'record_missing'}
      end
      local old_receipt = nil
      if lease then
        old_receipt = parse_receipt(stale_receipts[receipt_slot[index]])
        if old_receipt == false then
          return {'PROTOCOL', 'receipt'}
        end
        if old_receipt and (
          old_receipt.mailbox_id ~= mailbox_id
          or old_receipt.token ~= lease.token
          or old_receipt.deadline ~= lease.deadline
        ) then
          return {'PROTOCOL', 'receipt_lease_mismatch'}
        end
      end
      if #claimable < batch_size then
        claimable[#claimable + 1] = {
          mailbox_id = mailbox_id,
          old_lease = lease,
          old_receipt = old_receipt,
          record = record
        }
      end
    else
      rescore_args[#rescore_args + 1] = lease.deadline
      rescore_args[#rescore_args + 1] = mailbox_id
    end
  end
end

-- ------------------------------------------------------------------ writes --
acall_many('ZREM', KEYS[6], removals)
acall_many('HDEL', KEYS[9], removals)
acall_many('ZADD', KEYS[6], rescore_args)

local results = {}
local drop_receipts, drop_captures = {}, {}
local set_leases, set_receipts, set_owners, set_polls, set_captures, due_args =
  {}, {}, {}, {}, {}, {}
for index = 1, #claimable do
  local candidate = claimable[index]
  local request_token = ARGV[8 + index]
  local mailbox_id = candidate.mailbox_id
  local old_lease = candidate.old_lease
  if old_lease then
    if candidate.old_receipt then
      drop_receipts[#drop_receipts + 1] = old_lease.token
    end
    drop_captures[#drop_captures + 1] = old_lease.token
  end
  local deadline = now + lease_ttl
  local deadline_str = tostring(deadline)
  set_leases[#set_leases + 1] = mailbox_id
  set_leases[#set_leases + 1] = request_token .. ':' .. deadline_str
  set_receipts[#set_receipts + 1] = request_token
  set_receipts[#set_receipts + 1] = mailbox_id .. ':' .. request_token .. ':' .. deadline_str
  set_owners[#set_owners + 1] = mailbox_id
  set_owners[#set_owners + 1] = request_token .. ':' .. process_id
  set_polls[#set_polls + 1] = mailbox_id
  set_polls[#set_polls + 1] = request_token .. ':' .. tostring(now)
  set_captures[#set_captures + 1] = request_token
  set_captures[#set_captures + 1] = candidate.record
  due_args[#due_args + 1] = deadline
  due_args[#due_args + 1] = mailbox_id
  results[index] = {
    'CLAIMED',
    request_token,
    mailbox_id,
    deadline_str,
    candidate.record
  }
end

acall_many('HDEL', KEYS[8], drop_receipts)
acall_many('HDEL', KEYS[14], drop_captures)
acall_many('HSET', KEYS[7], set_leases)
acall_many('HSET', KEYS[8], set_receipts)
acall_many('HSET', KEYS[9], set_owners)
acall_many('HSET', KEYS[10], set_polls)
acall_many('HSET', KEYS[14], set_captures)
acall_many('ZADD', KEYS[6], due_args)

-- Sync read: it is the reply value in two of the three exits and it flushes the
-- buffered writes above before the script returns.
local earliest = earliest_due()

if #claimable > 0 then
  return resolved_response(now, batch_size, results, earliest)
end
if n_candidates > 0 and not saw_active then
  return {'RETRY_IMMEDIATELY', tostring(now)}
end
if earliest ~= '' and tonumber(earliest) <= now then
  return {'RETRY_IMMEDIATELY', tostring(now)}
end
return {'NOT_DUE', tostring(now), earliest}
