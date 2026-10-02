local hmac  = require("openssl.hmac")
local cjson = require("cjson")

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64enc(bin)
  local t, len, i = {}, #bin, 1
  while i <= len do
    local a = bin:byte(i) or 0
    local b = bin:byte(i+1) or 0
    local c = bin:byte(i+2) or 0
    local n = a*65536 + b*256 + c
    local c1 = math.floor(n/262144)%64
    local c2 = math.floor(n/4096)%64
    local c3 = math.floor(n/64)%64
    local c4 = n%64
    t[#t+1] = b64chars:sub(c1+1,c1+1)
    t[#t+1] = b64chars:sub(c2+1,c2+1)
    t[#t+1] = (i+1<=len) and b64chars:sub(c3+1,c3+1) or "="
    t[#t+1] = (i+2<=len) and b64chars:sub(c4+1,c4+1) or "="
    i = i + 3
  end
  return table.concat(t)
end

local function b64url_enc(bin)
  return (b64enc(bin):gsub("%+", "-"):gsub("/", "_"):gsub("=+$", ""))
end

local function hmac_sha256(secret, msg)
  local ctx = hmac.new(secret, "sha256")
  return ctx:final(msg)
end

local M = {}

function M.sign(secret, payload, expired)
  assert(type(secret) == "string", "secret must be string")
  assert(type(payload) == "table", "payload must be table")
  expired = expired or 3600*24*30
  local header_json = '{"typ":"JWT","alg":"HS256"}'
  local now = os.time()
  payload.iss = payload.iss or "dz-game"
  if payload.iat == nil then
      payload.iat = now
  end
  if  payload.exp == nil then
      payload.exp = now + expired
  end
  local h = b64url_enc(header_json)
  local p = b64url_enc(cjson.encode(payload))
  local input = h .. "." .. p
  local sig = b64url_enc(hmac_sha256(secret, input))
  return input .. "." .. sig
end

return M