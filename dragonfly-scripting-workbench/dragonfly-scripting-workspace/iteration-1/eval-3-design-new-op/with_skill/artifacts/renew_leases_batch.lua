-- renew_leases_batch-2.lua  (numkeys is pinned to 2 and is part of the script identity)
--
-- Renew up to 64 leases in one atomic multi-transaction.
--
-- KEYS (fixed order, both must carry the same {tag}):
--   KEYS[1] {t}:leases  hash, field = mailbox_id, value = '<token>:<deadline_ms>'
--   KEYS[2] {t}:due     zset, member = mailbox_id, score = deadline_ms
--
-- ARGV:
--   ARGV[1]           ttl_ms, positive integer; new deadline = server_now_ms + ttl_ms
--   ARGV[2i], ARGV[2i+1]  mailbox_id, token   for i = 1..n, n <= 64  (n may be 0)
--
-- Reply: flat array, arity exactly 1 + 2n, positional (item i is the i-th ARGV pair):
--   [1]        server_now_ms as a decimal string
--   [2i], [2i+1]  status (integer), deadline_ms as a decimal string
--     status 1 renewed        deadline = now + ttl_ms (also written to hash and zset)
--     status 2 token_mismatch deadline = stored deadline (unchanged); checked before expiry
--     status 3 expired        deadline = stored deadline (unchanged); stored <= now
--     status 0 missing        deadline = '0'; no hash field for that mailbox_id
--   Milliseconds are returned as strings: a Lua array reply truncates floats, so anything
--   that must keep precision leaves as a string.
--
-- Errors (protocol violations of the caller or of a lease writer; raised before any write,
-- so the batch is a clean no-op): bad ttl_ms, odd ARGV tail, n > 64, lease value that does
-- not match '<token>:<digits>'.
--
-- Cost: exactly 2 (n = 0 or nothing renewable) to 4 redis.call, independent of n.

local rcall = redis.call
local acall = redis.acall

local LEASES = KEYS[1]
local DUE    = KEYS[2]

local MAX_ITEMS = 64
local S_MISSING, S_RENEWED, S_TOKEN_MISMATCH, S_EXPIRED = 0, 1, 2, 3

local ttl_ms = tonumber(ARGV[1])
if ttl_ms == nil or ttl_ms <= 0 or ttl_ms ~= math.floor(ttl_ms) then
  return redis.error_reply('ERR renew_leases_batch: ARGV[1] ttl_ms must be a positive integer')
end

local tail = #ARGV - 1
if tail % 2 ~= 0 then
  return redis.error_reply('ERR renew_leases_batch: ARGV tail must be (mailbox_id, token) pairs')
end
local n = tail // 2
if n > MAX_ITEMS then
  return redis.error_reply('ERR renew_leases_batch: at most ' .. MAX_ITEMS .. ' items, got ' .. n)
end

local ids = {}
for i = 1, n do ids[i] = ARGV[2 * i] end

local t = rcall('TIME')
local now_ms = tonumber(t[1]) * 1000 + tonumber(t[2]) // 1000
local new_deadline = string.format('%d', now_ms + ttl_ms)

local reply = { string.format('%d', now_ms) }
local rn = 1
if n == 0 then return reply end

local stored = rcall('HMGET', LEASES, table.unpack(ids, 1, n))

local hset, hn = {}, 0
local zadd, zn = {}, 0

for i = 1, n do
  local v = stored[i]
  local status, deadline_out
  if v == false then
    status, deadline_out = S_MISSING, '0'
  else
    -- greedy '.*' splits on the last colon, so a token may itself contain ':'
    local tok, dl = string.match(v, '^(.*):(%d+)$')
    if tok == nil then
      return redis.error_reply('ERR renew_leases_batch: malformed lease value for ' .. ids[i])
    elseif tok ~= ARGV[2 * i + 1] then
      status, deadline_out = S_TOKEN_MISMATCH, dl
    elseif tonumber(dl) <= now_ms then
      status, deadline_out = S_EXPIRED, dl
    else
      status, deadline_out = S_RENEWED, new_deadline
      hn = hn + 1; hset[hn] = ids[i]
      hn = hn + 1; hset[hn] = tok .. ':' .. new_deadline
      zn = zn + 1; zadd[zn] = new_deadline
      zn = zn + 1; zadd[zn] = ids[i]
    end
  end
  rn = rn + 1; reply[rn] = status
  rn = rn + 1; reply[rn] = deadline_out
end

if hn > 0 then
  -- replies are discarded, so buffer both writes instead of paying a hop each
  acall('HSET', LEASES, table.unpack(hset, 1, hn))
  acall('ZADD', DUE, table.unpack(zadd, 1, zn))
end

return reply
