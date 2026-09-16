-- claim_mailbox_batch.lua -- batched rewrite. Reply protocol and recovery
-- semantics are byte-identical to the original; only the number of redis.call
-- hops changed (per-item HGET/HSET/ZADD -> chunked HMGET/HSET/ZADD/HDEL).
--
-- KEYS (fixed arity 14, all under one hashtag):
--   1 active_generation          2 cursor_coverage_generation
--   3 reconciled_server_run_id   4 last_reconciliation_started_ms
--   5 generation:<GEN>:mailbox_versions (legacy)
--   6 due (zset)                 7 leases        8 lease_receipts
--   9 diagnostic_owners         10 poll_starts  11 active_grants_descriptor
--  12 active_mailbox_versions   13 mailbox_records
--  14 lease_records
-- ARGV: 1 schema, 2 generation, 3 run_id, 4 process_id, 5 lease_ttl,
--       6 candidate_window, 7 freshness_limit, 8 batch_size, 9.. tokens.

local rcall = redis.call
local racall = redis.acall
local CHUNK = 256

-- ---------------------------------------------------------------- pure bits
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

-- pending hash/zset mutations: last write wins per field, exactly as the
-- sequential per-item writes of the original would have left them.
local function new_pending()
  return {set = {}, del = {}}
end
local function pend_set(p, field, value)
  p.del[field] = nil
  p.set[field] = value
end
local function pend_del(p, field)
  p.set[field] = nil
  p.del[field] = true
end

-- ------------------------------------------------------------- batched I/O
local function hmget_many(key, fields, n)
  local out = {}
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

local function flush_hash(key, pending)
  local dels, dn = {}, 0
  for field in pairs(pending.del) do
    dn = dn + 1
    dels[dn] = field
  end
  local i = 1
  while i <= dn do
    local hi = i + CHUNK - 1
    if hi > dn then hi = dn end
    racall('HDEL', key, unpack(dels, i, hi))
    i = hi + 1
  end
  local args, an = {}, 0
  for field, value in pairs(pending.set) do
    args[an + 1] = field
    args[an + 2] = value
    an = an + 2
  end
  i = 1
  while i <= an do
    local hi = i + 2 * CHUNK - 1
    if hi > an then hi = an end
    racall('HSET', key, unpack(args, i, hi))
    i = hi + 1
  end
end

local function server_now_millis()
  local now = rcall('TIME')
  return tonumber(now[1]) * 1000 + math.floor(tonumber(now[2]) / 1000)
end

local function earliest_due()
  local earliest = rcall('ZRANGE', KEYS[6], 0, 0, 'WITHSCORES')
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

-- ------------------------------------------------------------- arguments
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
  if ARGV[8 + index] == '' then
    return {'PROTOCOL', 'arguments'}
  end
  request_tokens[index] = ARGV[8 + index]
end

local now = server_now_millis()

-- ---------------------------------------------------- receipt recovery path
-- All reads for the recovery path are issued up front (reads have no side
-- effects); the per-index checks below then run in the original index order,
-- so the first PROTOCOL failure reported is the same one.
local receipt_raws = hmget_many(KEYS[8], request_tokens, batch_size)
local receipts = {}
local mb_fields, mb_index, mbn = {}, {}, 0
local cap_fields, cap_index, capn = {}, {}, 0
for index = 1, batch_size do
  local receipt = parse_receipt(receipt_raws[index])
  receipts[index] = receipt
  if receipt then
    mbn = mbn + 1
    mb_fields[mbn] = receipt.mailbox_id
    mb_index[mbn] = index
    if receipt.deadline > now then
      capn = capn + 1
      cap_fields[capn] = request_tokens[index]
      cap_index[capn] = index
    end
  end
end

do
  local recovery_lease = {}
  if mbn > 0 then
    local vals = hmget_many(KEYS[7], mb_fields, mbn)
    for i = 1, mbn do
      recovery_lease[mb_index[i]] = vals[i]
    end
  end
  local recovery_capture = {}
  if capn > 0 then
    local vals = hmget_many(KEYS[14], cap_fields, capn)
    for i = 1, capn do
      recovery_capture[cap_index[i]] = vals[i]
    end
  end

  local recovered = {}
  local has_receipt = false
  for index = 1, batch_size do
    local request_token = request_tokens[index]
    local receipt = receipts[index]
    if receipt == false then
      return {'PROTOCOL', 'receipt'}
    end
    if receipt then
      has_receipt = true
      if receipt.token ~= request_token then
        return {'PROTOCOL', 'receipt_token'}
      end
      local lease = parse_lease(recovery_lease[index])
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
        local captured = recovery_capture[index]
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
end

-- ------------------------------------------------------------------- fences
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

-- --------------------------------------------------------- candidate scan
local candidates = rcall(
  'ZRANGEBYSCORE',
  KEYS[6],
  '-inf',
  tostring(now),
  'LIMIT',
  0,
  candidate_window
)
local ncand = #candidates
local versions = hmget_many(versions_key, candidates, ncand)
local lease_raws = hmget_many(KEYS[7], candidates, ncand)

-- Pass 1 decides, per candidate, which further reads the original would have
-- issued (record for the whole window, receipt for every lease token seen);
-- it never returns, so pass 2 can still report the first failure in order.
local leases = {}
local rec_fields, rec_index, recn = {}, {}, 0
local tok_fields, tok_index, tokn = {}, {}, 0
for i = 1, ncand do
  local lease = parse_lease(lease_raws[i])
  leases[i] = lease
  local version = versions[i]
  if lease ~= false then
    if not version then
      if lease and lease.deadline <= now then
        tokn = tokn + 1
        tok_fields[tokn] = lease.token
        tok_index[tokn] = i
      end
    elseif not lease or lease.deadline <= now then
      recn = recn + 1
      rec_fields[recn] = candidates[i] .. ':' .. version
      rec_index[recn] = i
      if lease then
        tokn = tokn + 1
        tok_fields[tokn] = lease.token
        tok_index[tokn] = i
      end
    end
  end
end
local records = {}
if recn > 0 then
  local vals = hmget_many(KEYS[13], rec_fields, recn)
  for i = 1, recn do
    records[rec_index[i]] = vals[i]
  end
end
local token_receipts = {}
if tokn > 0 then
  local vals = hmget_many(KEYS[8], tok_fields, tokn)
  for i = 1, tokn do
    token_receipts[tok_index[i]] = vals[i]
  end
end

local saw_active = false
local removals, remn = {}, 0
local rescores, resn = {}, 0
local claimable, cln = {}, 0
for i = 1, ncand do
  local mailbox_id = candidates[i]
  local version = versions[i]
  local lease = leases[i]
  if lease == false then
    return {'PROTOCOL', 'lease'}
  end
  if not version then
    if not lease then
      remn = remn + 1
      removals[remn] = mailbox_id
    elseif lease.deadline <= now then
      local stale_receipt = parse_receipt(token_receipts[i])
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
      resn = resn + 1
      rescores[resn] = {mailbox_id, lease.deadline}
    end
  else
    saw_active = true
    if not lease or lease.deadline <= now then
      local record = records[i]
      if not record then
        return {'PROTOCOL', 'record_missing'}
      end
      local old_receipt = nil
      if lease then
        old_receipt = parse_receipt(token_receipts[i])
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
      if cln < batch_size then
        cln = cln + 1
        claimable[cln] = {
          mailbox_id = mailbox_id,
          old_lease = lease,
          old_receipt = old_receipt,
          record = record
        }
      end
    else
      resn = resn + 1
      rescores[resn] = {mailbox_id, lease.deadline}
    end
  end
end

-- ------------------------------------------------------------ mutations
-- The poll_start values are read before any write. Every claimed mailbox_id is
-- distinct (zset members), and the original only ever wrote poll_starts for the
-- mailbox it was processing, so no write of the original could have changed a
-- value a later iteration read.
local poll_fields, poll_index, polln = {}, {}, 0
for index = 1, cln do
  if claimable[index].old_lease then
    polln = polln + 1
    poll_fields[polln] = claimable[index].mailbox_id
    poll_index[polln] = index
  end
end
local poll_starts = {}
if polln > 0 then
  local vals = hmget_many(KEYS[10], poll_fields, polln)
  for i = 1, polln do
    poll_starts[poll_index[i]] = vals[i]
  end
end

local p_leases = new_pending()       -- KEYS[7]
local p_receipts = new_pending()     -- KEYS[8]
local p_owners = new_pending()       -- KEYS[9]
local p_polls = new_pending()        -- KEYS[10]
local p_captures = new_pending()     -- KEYS[14]
local due_add, due_del = {}, {}

for i = 1, remn do
  local mailbox_id = removals[i]
  due_add[mailbox_id] = nil
  due_del[mailbox_id] = true
  pend_del(p_owners, mailbox_id)
end
for i = 1, resn do
  local rescore = rescores[i]
  due_del[rescore[1]] = nil
  due_add[rescore[1]] = rescore[2]
end

local results = {}
for index = 1, cln do
  local candidate = claimable[index]
  local request_token = request_tokens[index]
  local mailbox_id = candidate.mailbox_id
  local old_lease = candidate.old_lease
  if old_lease then
    local poll_start = poll_starts[index]
    if poll_start and string.sub(poll_start, 1, string.len(old_lease.token) + 1)
      == old_lease.token .. ':' then
      pend_del(p_polls, mailbox_id)
    end
    if candidate.old_receipt then
      pend_del(p_receipts, old_lease.token)
    end
    pend_del(p_captures, old_lease.token)
  end
  local deadline = now + lease_ttl
  pend_set(p_leases, mailbox_id, request_token .. ':' .. tostring(deadline))
  pend_set(p_receipts, request_token, mailbox_id .. ':' .. request_token .. ':' .. tostring(deadline))
  pend_set(p_owners, mailbox_id, request_token .. ':' .. process_id)
  pend_set(p_polls, mailbox_id, request_token .. ':' .. tostring(now))
  pend_set(p_captures, request_token, candidate.record)
  due_del[mailbox_id] = nil
  due_add[mailbox_id] = deadline
  results[index] = {
    'CLAIMED',
    request_token,
    mailbox_id,
    tostring(deadline),
    candidate.record
  }
end

local zrem_args, zn = {}, 0
for member in pairs(due_del) do
  zn = zn + 1
  zrem_args[zn] = member
end
local i = 1
while i <= zn do
  local hi = i + CHUNK - 1
  if hi > zn then hi = zn end
  rcall('ZREM', KEYS[6], unpack(zrem_args, i, hi))
  i = hi + 1
end
local zadd_args, zan = {}, 0
for member, score in pairs(due_add) do
  zadd_args[zan + 1] = score
  zadd_args[zan + 2] = member
  zan = zan + 2
end
i = 1
while i <= zan do
  local hi = i + 2 * CHUNK - 1
  if hi > zan then hi = zan end
  rcall('ZADD', KEYS[6], unpack(zadd_args, i, hi))
  i = hi + 1
end
flush_hash(KEYS[7], p_leases)
flush_hash(KEYS[8], p_receipts)
flush_hash(KEYS[9], p_owners)
flush_hash(KEYS[10], p_polls)
flush_hash(KEYS[14], p_captures)

if cln > 0 then
  return resolved_response(now, batch_size, results)
end
if ncand > 0 and not saw_active then
  return {'RETRY_IMMEDIATELY', tostring(now)}
end
local earliest = earliest_due()
if earliest ~= '' and tonumber(earliest) <= now then
  return {'RETRY_IMMEDIATELY', tostring(now)}
end
return {'NOT_DUE', tostring(now), earliest}
