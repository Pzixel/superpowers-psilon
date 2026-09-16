local unpack = unpack or table.unpack
local HMGET_CHUNK = 256
local WRITE_CHUNK = 128

-- Chunked HMGET over `count` field names taken from `fields`.
-- Returns a sparse array: values[i] is nil when the field is absent,
-- exactly like the per-field HGET it replaces.
local function hmget_all(key, fields, count)
  local values = {}
  local index = 1
  while index <= count do
    local last = index + HMGET_CHUNK - 1
    if last > count then
      last = count
    end
    local batch = redis.call('HMGET', key, unpack(fields, index, last))
    for offset = 1, last - index + 1 do
      local value = batch[offset]
      if value and value ~= false then
        values[index + offset - 1] = value
      end
    end
    index = last + 1
  end
  return values
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

local function delete_matching_poll_start(mailbox_id, token)
  local poll_start = redis.call('HGET', KEYS[10], mailbox_id)
  if poll_start and string.sub(poll_start, 1, string.len(token) + 1) == token .. ':' then
    redis.call('HDEL', KEYS[10], mailbox_id)
  end
end

local function delete_capture(token)
  redis.call('HDEL', KEYS[14], token)
end

local function earliest_due()
  local earliest = redis.call('ZRANGE', KEYS[6], 0, 0, 'WITHSCORES')
  return earliest[2] or ''
end

local function resolved_response(now, batch_size, results)
  local response = {'RESOLVED', tostring(now), earliest_due(), tostring(batch_size)}
  for index = 1, batch_size do
    local item = results[index]
    if not item then
      item = {'UNUSED', ARGV[8 + index], '', '', ''}
    end
    for field = 1, 5 do
      table.insert(response, item[field])
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
  local request_token = ARGV[8 + index]
  if request_token == '' then
    return {'PROTOCOL', 'arguments'}
  end
  request_tokens[index] = request_token
end

local now = server_now_millis()
local recovered = {}
local has_receipt = false
local raw_receipts = hmget_all(KEYS[8], request_tokens, batch_size)
for index = 1, batch_size do
  local request_token = request_tokens[index]
  local receipt = parse_receipt(raw_receipts[index])
  if receipt == false then
    return {'PROTOCOL', 'receipt'}
  end
  if receipt then
    has_receipt = true
    if receipt.token ~= request_token then
      return {'PROTOCOL', 'receipt_token'}
    end
    local lease = parse_lease(redis.call('HGET', KEYS[7], receipt.mailbox_id))
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
      local captured = redis.call('HGET', KEYS[14], request_token)
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
  return resolved_response(now, batch_size, recovered)
end

local active_generation = redis.call('GET', KEYS[1])
if active_generation ~= expected_generation then
  return {'FENCED', 'active_generation_changed'}
end
if redis.call('GET', KEYS[2]) ~= active_generation then
  return {'FENCED', 'cursor_coverage_mismatch'}
end
if redis.call('GET', KEYS[3]) ~= actual_run_id then
  return {'FENCED', 'server_run_reconciliation_required'}
end
local last_reconciliation = tonumber(redis.call('GET', KEYS[4]) or '')
if not last_reconciliation or last_reconciliation > now
  or now - last_reconciliation > freshness_limit then
  return {'FENCED', 'catalog_not_fresh'}
end

local descriptor = redis.call('HMGET', KEYS[11], 'storage_format', 'state', 'generation')
local storage_format = descriptor[1]
local state = descriptor[2]
local descriptor_generation = descriptor[3]
if storage_format == false then storage_format = nil end
if state == false then state = nil end
if descriptor_generation == false then descriptor_generation = nil end
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
  if descriptor_generation ~= active_generation then
    return {'FENCED', 'active_generation_changed'}
  end
  versions_key = KEYS[12]
elseif state then
  return {'PROTOCOL', 'catalog_descriptor'}
end

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
local versions = hmget_all(versions_key, candidates, candidate_count)
local raw_leases = hmget_all(KEYS[7], candidates, candidate_count)

-- Pre-pass: decide which secondary lookups the main loop will need, so they can be
-- issued as a handful of batched HMGETs instead of one redis.call per candidate.
-- Every lookup below is a pure read, and collection stops at the first malformed
-- lease, which is exactly where the main loop can no longer advance.
local leases = {}
local record_fields = {}
local record_slot = {}
local record_count = 0
local lease_tokens = {}
local token_slot = {}
local token_count = 0
for slot = 1, candidate_count do
  local lease = parse_lease(raw_leases[slot])
  leases[slot] = lease
  if lease == false then
    break
  end
  if lease then
    token_count = token_count + 1
    lease_tokens[token_count] = lease.token
    token_slot[slot] = token_count
  end
  local version = versions[slot]
  if version and (not lease or lease.deadline <= now) then
    record_count = record_count + 1
    record_fields[record_count] = candidates[slot] .. ':' .. version
    record_slot[slot] = record_count
  end
end
local prefetched_records = {}
if record_count > 0 then
  prefetched_records = hmget_all(KEYS[13], record_fields, record_count)
end
local prefetched_receipts = {}
if token_count > 0 then
  prefetched_receipts = hmget_all(KEYS[8], lease_tokens, token_count)
end

local saw_active = false
local removals = {}
local removal_count = 0
local rescore_members = {}
local rescore_count = 0
local claimable = {}
local claimable_count = 0
local any_old_lease = false
for slot = 1, candidate_count do
  local mailbox_id = candidates[slot]
  local version = versions[slot]
  local lease = leases[slot]
  if lease == false then
    return {'PROTOCOL', 'lease'}
  end
  if not version then
    if not lease then
      removal_count = removal_count + 1
      removals[removal_count] = mailbox_id
    elseif lease.deadline <= now then
      local stale_receipt = parse_receipt(prefetched_receipts[token_slot[slot]])
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
      rescore_members[rescore_count * 2 + 1] = lease.deadline
      rescore_members[rescore_count * 2 + 2] = mailbox_id
      rescore_count = rescore_count + 1
    end
  else
    saw_active = true
    if not lease or lease.deadline <= now then
      local record = prefetched_records[record_slot[slot]]
      if not record then
        return {'PROTOCOL', 'record_missing'}
      end
      local old_receipt = nil
      if lease then
        old_receipt = parse_receipt(prefetched_receipts[token_slot[slot]])
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
      if claimable_count < batch_size then
        claimable_count = claimable_count + 1
        if lease then
          any_old_lease = true
        end
        claimable[claimable_count] = {
          mailbox_id = mailbox_id,
          old_lease = lease,
          old_receipt = old_receipt,
          record = record
        }
      end
    else
      rescore_members[rescore_count * 2 + 1] = lease.deadline
      rescore_members[rescore_count * 2 + 2] = mailbox_id
      rescore_count = rescore_count + 1
    end
  end
end

local index = 1
while index <= removal_count do
  local last = index + WRITE_CHUNK - 1
  if last > removal_count then
    last = removal_count
  end
  redis.call('ZREM', KEYS[6], unpack(removals, index, last))
  redis.call('HDEL', KEYS[9], unpack(removals, index, last))
  index = last + 1
end
index = 1
while index <= rescore_count * 2 do
  local last = index + WRITE_CHUNK * 2 - 1
  if last > rescore_count * 2 then
    last = rescore_count * 2
  end
  redis.call('ZADD', KEYS[6], unpack(rescore_members, index, last))
  index = last + 1
end

local results = {}
local deadline = now + lease_ttl
local deadline_text = tostring(deadline)
if any_old_lease then
  for slot, candidate in ipairs(claimable) do
    local request_token = request_tokens[slot]
    local mailbox_id = candidate.mailbox_id
    local old_lease = candidate.old_lease
    if old_lease then
      delete_matching_poll_start(mailbox_id, old_lease.token)
      if candidate.old_receipt then
        redis.call('HDEL', KEYS[8], old_lease.token)
      end
      delete_capture(old_lease.token)
    end
    local lease_value = request_token .. ':' .. deadline_text
    local receipt_value = mailbox_id .. ':' .. request_token .. ':' .. deadline_text
    redis.call('HSET', KEYS[7], mailbox_id, lease_value)
    redis.call('HSET', KEYS[8], request_token, receipt_value)
    redis.call('HSET', KEYS[9], mailbox_id, request_token .. ':' .. process_id)
    redis.call('HSET', KEYS[10], mailbox_id, request_token .. ':' .. tostring(now))
    redis.call('HSET', KEYS[14], request_token, candidate.record)
    redis.call('ZADD', KEYS[6], deadline, mailbox_id)
    results[slot] = {
      'CLAIMED',
      request_token,
      mailbox_id,
      deadline_text,
      candidate.record
    }
  end
elseif claimable_count > 0 then
  local now_text = tostring(now)
  local leases_args = {}
  local receipts_args = {}
  local owners_args = {}
  local polls_args = {}
  local records_args = {}
  local due_args = {}
  for slot = 1, claimable_count do
    local candidate = claimable[slot]
    local request_token = request_tokens[slot]
    local mailbox_id = candidate.mailbox_id
    local pair = slot * 2
    leases_args[pair - 1] = mailbox_id
    leases_args[pair] = request_token .. ':' .. deadline_text
    receipts_args[pair - 1] = request_token
    receipts_args[pair] = mailbox_id .. ':' .. request_token .. ':' .. deadline_text
    owners_args[pair - 1] = mailbox_id
    owners_args[pair] = request_token .. ':' .. process_id
    polls_args[pair - 1] = mailbox_id
    polls_args[pair] = request_token .. ':' .. now_text
    records_args[pair - 1] = request_token
    records_args[pair] = candidate.record
    due_args[pair - 1] = deadline
    due_args[pair] = mailbox_id
    results[slot] = {
      'CLAIMED',
      request_token,
      mailbox_id,
      deadline_text,
      candidate.record
    }
  end
  local pair_count = claimable_count * 2
  redis.call('HSET', KEYS[7], unpack(leases_args, 1, pair_count))
  redis.call('HSET', KEYS[8], unpack(receipts_args, 1, pair_count))
  redis.call('HSET', KEYS[9], unpack(owners_args, 1, pair_count))
  redis.call('HSET', KEYS[10], unpack(polls_args, 1, pair_count))
  redis.call('HSET', KEYS[14], unpack(records_args, 1, pair_count))
  redis.call('ZADD', KEYS[6], unpack(due_args, 1, pair_count))
end

if claimable_count > 0 then
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
