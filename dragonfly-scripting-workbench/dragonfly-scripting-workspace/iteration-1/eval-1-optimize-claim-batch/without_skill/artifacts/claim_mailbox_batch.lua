-- claim_mailbox_batch.lua (optimized)
-- Same KEYS/ARGV contract, same replies, same final state as the original.
-- Optimization strategy: identical decision logic, but every per-candidate
-- HGET/HSET/ZADD/ZREM/HDEL is replaced by a batched multi-field command, so the
-- number of redis.call round trips drops from O(candidate_window) to O(1).

local unpack = unpack or table.unpack
local MAX_ARGS = 400

-- HMGET `fields[1..count]` from `key` in bounded chunks. Missing fields come
-- back as `false`, exactly like a plain HGET miss.
local function hmget_all(key, fields, count)
  local values = {}
  local pos = 1
  while pos <= count do
    local stop = pos + MAX_ARGS - 1
    if stop > count then stop = count end
    local args = {key}
    local n = 1
    for index = pos, stop do
      n = n + 1
      args[n] = fields[index]
    end
    local chunk = redis.call('HMGET', unpack(args))
    for index = 1, n - 1 do
      values[pos + index - 1] = chunk[index]
    end
    pos = stop + 1
  end
  return values
end

-- Run `command key a1 a2 ...` in bounded chunks (HDEL fields, ZREM members).
local function call_chunked(command, key, items, count)
  local pos = 1
  while pos <= count do
    local stop = pos + MAX_ARGS - 1
    if stop > count then stop = count end
    local args = {command, key}
    local n = 2
    for index = pos, stop do
      n = n + 1
      args[n] = items[index]
    end
    redis.call(unpack(args))
    pos = stop + 1
  end
end

-- Run `command key p1 p2 p3 p4 ...` for flat pair lists (HSET, ZADD).
local function call_pairs_chunked(command, key, pairs_list, count)
  local pos = 1
  while pos <= count do
    local stop = pos + MAX_ARGS - 1
    if stop > count then stop = count end
    local args = {command, key}
    local n = 2
    for index = pos, stop do
      n = n + 1
      args[n] = pairs_list[index]
    end
    redis.call(unpack(args))
    pos = stop + 1
  end
end

local function server_now_millis()
  local now = redis.call('TIME')
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
  local earliest = redis.call('ZRANGE', KEYS[6], 0, 0, 'WITHSCORES')
  return earliest[2] or ''
end

local function resolved_response(now, batch_size, results)
  local response = {'RESOLVED', tostring(now), earliest_due(), tostring(batch_size)}
  local at = 4
  for index = 1, batch_size do
    local item = results[index]
    if not item then
      item = {'UNUSED', ARGV[8 + index], '', '', ''}
    end
    for field = 1, 5 do
      at = at + 1
      response[at] = item[field]
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
local request_tokens = {}
for index = 1, batch_size do
  local token = ARGV[8 + index]
  if token == '' then
    return {'PROTOCOL', 'arguments'}
  end
  request_tokens[index] = token
end

local now = server_now_millis()

-- ---------------------------------------------------------------- recovery --
-- One HMGET instead of batch_size HGETs; the per-slot validation below runs in
-- the original order so the first failing slot still decides the reply.
local raw_receipts = hmget_all(KEYS[8], request_tokens, batch_size)
local has_receipt = false
for index = 1, batch_size do
  if raw_receipts[index] then
    has_receipt = true
    break
  end
end

if has_receipt then
  local receipts = {}
  local lease_mailboxes = {}
  local lease_slots = {}
  local lease_count = 0
  for index = 1, batch_size do
    local receipt = parse_receipt(raw_receipts[index])
    receipts[index] = receipt
    if receipt then
      lease_count = lease_count + 1
      lease_mailboxes[lease_count] = receipt.mailbox_id
      lease_slots[index] = lease_count
    end
  end
  local raw_leases = hmget_all(KEYS[7], lease_mailboxes, lease_count)
  local captures = hmget_all(KEYS[14], request_tokens, batch_size)

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
      local lease = parse_lease(raw_leases[lease_slots[index]])
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
        local captured = captures[index]
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
  return resolved_response(now, batch_size, recovered)
end

-- ----------------------------------------------------------------- fences --
local fence = redis.call('MGET', KEYS[1], KEYS[2], KEYS[3], KEYS[4])
local active_generation = fence[1]
if active_generation ~= expected_generation then
  return {'FENCED', 'active_generation_changed'}
end
if fence[2] ~= active_generation then
  return {'FENCED', 'cursor_coverage_mismatch'}
end
if fence[3] ~= actual_run_id then
  return {'FENCED', 'server_run_reconciliation_required'}
end
local last_reconciliation = tonumber(fence[4] or '')
if not last_reconciliation or last_reconciliation > now
  or now - last_reconciliation > freshness_limit then
  return {'FENCED', 'catalog_not_fresh'}
end

local descriptor = redis.call('HMGET', KEYS[11], 'storage_format', 'state', 'generation')
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

-- ------------------------------------------------------------- candidates --
local candidates = redis.call(
  'ZRANGEBYSCORE',
  KEYS[6],
  '-inf',
  tostring(now),
  'LIMIT',
  0,
  candidate_window
)
local candidate_count = #candidates

-- Two batched reads replace 2 * candidate_count HGETs.
local versions = hmget_all(versions_key, candidates, candidate_count)
local raw_leases = hmget_all(KEYS[7], candidates, candidate_count)

-- Prefetch pass: decide (without emitting any reply or effect) which record
-- fields and which stale-receipt tokens the decision pass will need.
local leases = {}
local record_fields = {}
local record_slots = {}
local record_count = 0
local stale_tokens = {}
local stale_slots = {}
local stale_count = 0
for index = 1, candidate_count do
  local lease = parse_lease(raw_leases[index])
  leases[index] = lease
  if lease ~= false then
    local version = versions[index]
    if not version then
      if lease and lease.deadline <= now then
        stale_count = stale_count + 1
        stale_tokens[stale_count] = lease.token
        stale_slots[index] = stale_count
      end
    elseif not lease or lease.deadline <= now then
      record_count = record_count + 1
      record_fields[record_count] = candidates[index] .. ':' .. version
      record_slots[index] = record_count
      if lease then
        stale_count = stale_count + 1
        stale_tokens[stale_count] = lease.token
        stale_slots[index] = stale_count
      end
    end
  end
end
local records = hmget_all(KEYS[13], record_fields, record_count)
local stale_receipts = hmget_all(KEYS[8], stale_tokens, stale_count)

-- Decision pass: identical logic and identical ordering of early returns.
local saw_active = false
local removals = {}
local removal_count = 0
local rescores = {}
local rescore_count = 0
local claimable = {}
local claim_count = 0
for index = 1, candidate_count do
  local mailbox_id = candidates[index]
  local version = versions[index]
  local lease = leases[index]
  if lease == false then
    return {'PROTOCOL', 'lease'}
  end
  if not version then
    if not lease then
      removal_count = removal_count + 1
      removals[removal_count] = mailbox_id
    elseif lease.deadline <= now then
      local stale_receipt = parse_receipt(stale_receipts[stale_slots[index]])
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
      rescore_count = rescore_count + 1
      rescores[rescore_count] = lease.deadline
      rescores[rescore_count + 1] = mailbox_id
      rescore_count = rescore_count + 1
    end
  else
    saw_active = true
    if not lease or lease.deadline <= now then
      local record = records[record_slots[index]]
      if not record then
        return {'PROTOCOL', 'record_missing'}
      end
      local old_receipt = nil
      if lease then
        old_receipt = parse_receipt(stale_receipts[stale_slots[index]])
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
      if claim_count < batch_size then
        claim_count = claim_count + 1
        claimable[claim_count] = {
          mailbox_id = mailbox_id,
          old_lease = lease,
          old_receipt = old_receipt,
          record = record
        }
      end
    else
      rescore_count = rescore_count + 1
      rescores[rescore_count] = lease.deadline
      rescores[rescore_count + 1] = mailbox_id
      rescore_count = rescore_count + 1
    end
  end
end

if removal_count > 0 then
  call_chunked('ZREM', KEYS[6], removals, removal_count)
  call_chunked('HDEL', KEYS[9], removals, removal_count)
end
if rescore_count > 0 then
  call_pairs_chunked('ZADD', KEYS[6], rescores, rescore_count)
end

-- ------------------------------------------------------------------ claims --
local results = {}
if claim_count > 0 then
  -- Slot of each request token that is actually written this round; used to
  -- keep delete-vs-write ordering identical to the sequential original.
  local written_slot = {}
  for index = 1, claim_count do
    local token = request_tokens[index]
    if not written_slot[token] then
      written_slot[token] = index
    end
  end

  local receipt_deletes = {}
  local receipt_delete_count = 0
  local capture_deletes = {}
  local capture_delete_count = 0
  local lease_writes = {}
  local receipt_writes = {}
  local owner_writes = {}
  local poll_writes = {}
  local capture_writes = {}
  local due_writes = {}
  local write_pos = 0
  local deadline = now + lease_ttl
  local deadline_text = tostring(deadline)
  local now_text = tostring(now)

  for index = 1, claim_count do
    local candidate = claimable[index]
    local request_token = request_tokens[index]
    local mailbox_id = candidate.mailbox_id
    local old_lease = candidate.old_lease
    if old_lease then
      local old_token = old_lease.token
      local slot = written_slot[old_token]
      if not slot or slot < index then
        if candidate.old_receipt then
          receipt_delete_count = receipt_delete_count + 1
          receipt_deletes[receipt_delete_count] = old_token
        end
        capture_delete_count = capture_delete_count + 1
        capture_deletes[capture_delete_count] = old_token
      end
    end
    write_pos = write_pos + 1
    local value_pos = write_pos + 1
    lease_writes[write_pos] = mailbox_id
    lease_writes[value_pos] = request_token .. ':' .. deadline_text
    receipt_writes[write_pos] = request_token
    receipt_writes[value_pos] = mailbox_id .. ':' .. request_token .. ':' .. deadline_text
    owner_writes[write_pos] = mailbox_id
    owner_writes[value_pos] = request_token .. ':' .. process_id
    poll_writes[write_pos] = mailbox_id
    poll_writes[value_pos] = request_token .. ':' .. now_text
    capture_writes[write_pos] = request_token
    capture_writes[value_pos] = candidate.record
    due_writes[write_pos] = deadline_text
    due_writes[value_pos] = mailbox_id
    write_pos = write_pos + 1

    results[index] = {
      'CLAIMED',
      request_token,
      mailbox_id,
      deadline_text,
      candidate.record
    }
  end

  if receipt_delete_count > 0 then
    call_chunked('HDEL', KEYS[8], receipt_deletes, receipt_delete_count)
  end
  if capture_delete_count > 0 then
    call_chunked('HDEL', KEYS[14], capture_deletes, capture_delete_count)
  end
  call_pairs_chunked('HSET', KEYS[7], lease_writes, write_pos)
  call_pairs_chunked('HSET', KEYS[8], receipt_writes, write_pos)
  call_pairs_chunked('HSET', KEYS[9], owner_writes, write_pos)
  call_pairs_chunked('HSET', KEYS[10], poll_writes, write_pos)
  call_pairs_chunked('HSET', KEYS[14], capture_writes, write_pos)
  call_pairs_chunked('ZADD', KEYS[6], due_writes, write_pos)

  return resolved_response(now, batch_size, results)
end

if candidate_count > 0 and not saw_active then
  return {'RETRY_IMMEDIATELY', tostring(now)}
end
local earliest = earliest_due()
if earliest ~= '' and tonumber(earliest) <= now then
  return {'RETRY_IMMEDIATELY', tostring(now)}
end
return {'NOT_DUE', tostring(now), earliest}
