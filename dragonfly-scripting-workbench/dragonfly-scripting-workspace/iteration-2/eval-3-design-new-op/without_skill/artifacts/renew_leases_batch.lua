-- renew_leases_batch
--
-- KEYS[1] = hash  "{t}:leases"  field=mailbox_id  value="<token>:<deadline_ms>"
-- KEYS[2] = zset  "{t}:due"     member=mailbox_id score=deadline_ms
-- ARGV[1] = ttl_ms          (positive integer, milliseconds)
-- ARGV[2..] = mailbox_id, token, mailbox_id, token, ...   (1..64 pairs)
--
-- Reply (flat array, length 1 + 2*N):
--   [1]        now_ms used for every decision in this call (integer)
--   [2i]       status for item i: "renewed" | "token_mismatch" | "expired" | "missing"
--   [2i+1]     new deadline_ms for item i if renewed, otherwise 0
--
-- Errors (no writes performed): bad arity, bad ttl_ms, batch larger than 64,
-- corrupt stored value.

local MAX_ITEMS = 64

local nargv = #ARGV
if nargv < 3 then
  return redis.error_reply("renew_leases_batch: need ttl_ms and at least one (mailbox_id, token) pair")
end
if (nargv - 1) % 2 ~= 0 then
  return redis.error_reply("renew_leases_batch: ARGV after ttl_ms must be (mailbox_id, token) pairs")
end

local n = math.floor((nargv - 1) / 2)
if n > MAX_ITEMS then
  return redis.error_reply("renew_leases_batch: batch of " .. string.format("%d", n) .. " exceeds max " .. string.format("%d", MAX_ITEMS))
end

local ttl_ms = tonumber(ARGV[1])
if ttl_ms == nil or ttl_ms <= 0 or ttl_ms ~= math.floor(ttl_ms) then
  return redis.error_reply("renew_leases_batch: ttl_ms must be a positive integer")
end

-- Server time is the single clock for the whole batch; the caller sends no time.
local t = redis.call('TIME')
local now_ms = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local new_deadline = now_ms + ttl_ms
local new_deadline_str = string.format("%d", new_deadline)

-- One read for the whole batch.
local fields = {}
for i = 1, n do
  fields[i] = ARGV[2 * i]
end
local stored = redis.call('HMGET', KEYS[1], unpack(fields))

local reply = {}
reply[1] = now_ms

local hset_args = {}   -- field, value, ...
local zadd_args = {}   -- score, member, ...
local nh, nz = 0, 0

for i = 1, n do
  local mailbox_id = ARGV[2 * i]
  local token = ARGV[2 * i + 1]
  local value = stored[i]
  local status, out_deadline = nil, 0

  if value == false or value == nil then
    status = "missing"
  else
    -- Greedy ".*" splits on the LAST colon, so tokens may contain colons.
    local stored_token, stored_deadline_str = string.match(value, "^(.*):(%d+)$")
    if stored_token == nil then
      return redis.error_reply(
        "renew_leases_batch: corrupt lease value for field '" .. mailbox_id .. "'")
    end
    if stored_token ~= token then
      status = "token_mismatch"
    elseif tonumber(stored_deadline_str) <= now_ms then
      status = "expired"
    else
      status = "renewed"
      out_deadline = new_deadline
      hset_args[nh + 1] = mailbox_id
      hset_args[nh + 2] = token .. ":" .. new_deadline_str
      nh = nh + 2
      zadd_args[nz + 1] = new_deadline_str
      zadd_args[nz + 2] = mailbox_id
      nz = nz + 2
    end
  end

  reply[2 * i]     = status
  reply[2 * i + 1] = out_deadline
end

-- At most one write per data structure, regardless of batch size.
if nh > 0 then
  redis.call('HSET', KEYS[1], unpack(hset_args))
  redis.call('ZADD', KEYS[2], unpack(zadd_args))
end

return reply
