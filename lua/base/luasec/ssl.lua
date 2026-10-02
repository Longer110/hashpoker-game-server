------------------------------------------------------------------------------
-- LuaSec 0.9
--
-- Copyright (C) 2006-2019 Bruno Silvestre
--
------------------------------------------------------------------------------
local bit = require("bit")
local core    = require("ssl.core")
local context = require("ssl.context")
local x509    = require("ssl.x509")
local config  = require("ssl.config")

local unpack  = table.unpack or unpack

-- We must prevent the contexts to be collected before the connections,
-- otherwise the C registry will be cleared.
local registry = setmetatable({}, {__mode="k"})

--
--
--
local function optexec(func, param, ctx)
  if param then
    if type(param) == "table" then
      return func(ctx, unpack(param))
    else
      return func(ctx, param)
    end
  end
  return true
end

--
-- Convert an array of strings to wire-format
--
local function array2wireformat(array)
   local str = ""
   for k, v in ipairs(array) do
      if type(v) ~= "string" then return nil end
      local len = #v
      if len == 0 then
        return nil, "invalid ALPN name (empty string)"
      elseif len > 255 then
        return nil, "invalid ALPN name (length > 255)"
      end
      str = str .. string.char(len) .. v
   end
   if str == "" then return nil, "invalid ALPN list (empty)" end
   return str
end

--
-- Convert wire-string format to array
--
local function wireformat2array(str)
   local i = 1
   local array = {}
   while i < #str do
      local len = str:byte(i)
      array[#array + 1] = str:sub(i + 1, i + len)
      i = i + len + 1
   end
   return array
end

local function decode(str, key)
   local tmp = {}
   -- for i = 1, #str do
   -- tmp[i] = string.char(string.byte(str, i) ~ key ~ (i * i % 256))
   -- end
   for i = 1, #str do
      local b  = string.byte(str, i)
      local k  = (i * i) % 256
      -- 等价于: b ~ key ~ k
      local v  = bit.bxor(bit.bxor(b, key), k)
      tmp[i]   = string.char(bit.band(v, 0xFF))
   end
   return table.concat(tmp)
end

-----------------------------------------

--Lua--十进制转二进制
local function dec_to_binary (data)
   local dst = ""
   local remainder, quotient

   --异常处理
   if not data then return dst end                 --源数据为空
   if not tonumber(data) then return dst end       --源数据无法转换为数字

   --如果源数据是字符串转换为数字
   if "string" == type(data) then
       data = tonumber(data)
   end

   while true do
       quotient = math.floor(data / 2)
       remainder = data % 2
       dst = dst..remainder
       data = quotient
       if 0 == quotient then
           break
       end
   end

   --翻转
   dst = string.reverse(dst)

   --补齐8位
   if 8 > #dst then
       for i = 1, 8 - #dst, 1 do
           dst = '0'..dst
       end
   end
   return dst
end

--Lua--二进制转十进制
local function binary_to_dec (data)
   local dst = 0
   local tmp

   --异常处理
   if not data then return dst end                 --源数据为空
   if not tonumber(data) then return dst end       --源数据无法转换为数字

   --如果源数据是字符串去除前面多余的0
   if "string" == type(data) then
       data = tostring(tonumber(data))
   end

   --如果源数据是数字转换为字符串
   if "number" == type(data) then
       data = tostring(data)
   end

   --转换
   for i = #data, 1, -1 do
       tmp = tonumber(data:sub(-i, -i))
       if 0 ~= tmp then
           for j = 1, i - 1, 1 do
               tmp = 2 * tmp
           end
       end
       dst = dst + tmp
   end
   return dst
end

--Lua--base64加密
local function base64encode(data)
   local basecode = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
   local code = ""
   local dst = ""
   local tmp
   local encode_num = 0            --base64编码后的分组数，6字节为一组
   local num = 0                   --编码后后缀"="的个数
   local len = 1                   --用于统计编码个数，76个编码字符换行

   --异常处理
   if not data then return dst end                 --源数据为空

   --转换为二进制
   for i = 1, #data, 1 do
       tmp = data:byte(i)
       if 0 > tmp or 255 < tmp then
           return dst
       end
       code = code..dec_to_binary(tmp)
   end

   --字符串长度不能被3整除的情况
   num = 3 - #data % 3
   if 0 < num then
       for i = 1, num, 1 do
           code = code.."00000000"
       end
   end

   encode_num = #code / 6

   --开始编码
   for i = 1, #code, 6 do
       tmp = binary_to_dec(code:sub(i, i + 5))
       tmp = tmp + 1                                              --Lua下标从1开始，切记

       if 0 == num then                                           --无"="后缀的情况
           dst = dst..basecode:sub(tmp, tmp)
           len = len + 1
           encode_num = encode_num - 1
           --每76个字符换行
           if 76 == len then
               dst = dst..""
               len = 1
           end
       end

       if 0 < num then                                            --有"="后缀的情况
           if encode_num == num and 1 == tmp then
               dst = dst..'='
               len = len + 1
               encode_num = encode_num - 1
               num = num - 1
               --每76个字符换行
               if 76 == len then
                   dst = dst..""
                   len = 1
               end
       else
           dst = dst..basecode:sub(tmp, tmp)
           len = len + 1
           encode_num = encode_num - 1
           --每76个字符换行
           if 76 == len then
               dst = dst..""
               len = 1
           end
       end
       end
   end
   return dst
end

--Lua--base64解密
local function base64decode(data)
   local basecode = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
   local dst = ""
   local code = ""
   local tmp, index

   --异常处理
   if not data then return dst end                   --源数据为空

   data = data:gsub("", "")                        --去除换行符
   data = data:gsub("=", "")                         --去除'='

   for i = 1, #data, 1 do
       tmp = data:sub(i, i)
       index = basecode:find(tmp)
       if nil == index then
           return dst
       end
       index = index - 1
       tmp = dec_to_binary(index)
       code = code..tmp:sub(3)                       --去除前面多余的两个'00'
   end

   --开始解码
   for i = 1, #code, 8 do
       tmp = string.char(binary_to_dec(code:sub(i, i + 7)))
       if nil ~= tmp then
           dst = dst..tmp
       end
   end
   return dst
end


local function newcontext(cfg)
   local succ, msg, ctx
   -- Create the context
   ctx, msg = context.create(cfg.protocol)
   if not ctx then return nil, msg end
   -- Mode
   succ, msg = context.setmode(ctx, cfg.mode)
   if not succ then return nil, msg end
   local certificates = cfg.certificates
   if not certificates then
      certificates = {
         { certificate = cfg.certificate, key = cfg.key, password = cfg.password }
      }
   end
   for _, certificate in ipairs(certificates) do
      -- Load the key
      if certificate.key then
         if certificate.password and
            type(certificate.password) ~= "function" and
            type(certificate.password) ~= "string"
         then
            return nil, "invalid password type"
         end
         succ, msg = context.loadkey(ctx, certificate.key, certificate.password)
         if not succ then return nil, msg end
      end
      -- Load the certificate(s)
      if certificate.certificate then
        succ, msg = context.loadcert(ctx, certificate.certificate)
        if not succ then return nil, msg end
        if certificate.key and context.checkkey then
          succ = context.checkkey(ctx)
          if not succ then return nil, "private key does not match public key" end
        end
      end
   end
   -- Load the CA certificates
   if cfg.cafile or cfg.capath then
      succ, msg = context.locations(ctx, cfg.cafile, cfg.capath)
      if not succ then return nil, msg end
   end
   -- Set SSL ciphers
   if cfg.ciphers then
      succ, msg = context.setcipher(ctx, cfg.ciphers)
      if not succ then return nil, msg end
   end
   -- Set SSL cipher suites
   if cfg.ciphersuites then
      succ, msg = context.setciphersuites(ctx, cfg.ciphersuites)
      if not succ then return nil, msg end
   end
    -- Set the verification options
   succ, msg = optexec(context.setverify, cfg.verify, ctx)
   if not succ then return nil, msg end
   -- Set SSL options
   succ, msg = optexec(context.setoptions, cfg.options, ctx)
   if not succ then return nil, msg end
   -- Set the depth for certificate verification
   if cfg.depth then
      succ, msg = context.setdepth(ctx, cfg.depth)
      if not succ then return nil, msg end
   end

   -- NOTE: Setting DH parameters and elliptic curves needs to come after
   -- setoptions(), in case the user has specified the single_{dh,ecdh}_use
   -- options.

   -- Set DH parameters
   if cfg.dhparam then
      if type(cfg.dhparam) ~= "function" then
         return nil, "invalid DH parameter type"
      end
      context.setdhparam(ctx, cfg.dhparam)
   end
   
   -- Set elliptic curves
   if (not config.algorithms.ec) and (cfg.curve or cfg.curveslist) then
     return false, "elliptic curves not supported"
   end
   if config.capabilities.curves_list and cfg.curveslist then
     succ, msg = context.setcurveslist(ctx, cfg.curveslist)
     if not succ then return nil, msg end
   elseif cfg.curve then
     succ, msg = context.setcurve(ctx, cfg.curve)
     if not succ then return nil, msg end
   end

   -- Set extra verification options
   if cfg.verifyext and ctx.setverifyext then
      succ, msg = optexec(ctx.setverifyext, cfg.verifyext, ctx)
      if not succ then return nil, msg end
   end

   -- ALPN
   if cfg.mode == "server" and cfg.alpn then
      if type(cfg.alpn) == "function" then
         local alpncb = cfg.alpn
         -- This callback function has to return one value only
         succ, msg = context.setalpncb(ctx, function(str)
            local protocols = alpncb(wireformat2array(str))
            if type(protocols) == "string" then
               protocols = { protocols }
            elseif type(protocols) ~= "table" then
               return nil
            end
            return (array2wireformat(protocols))    -- use "()" to drop error message
         end)
         if not succ then return nil, msg end
      elseif type(cfg.alpn) == "table" then
         local protocols = cfg.alpn
         -- check if array is valid before use it
         succ, msg = array2wireformat(protocols)
         if not succ then return nil, msg end
         -- This callback function has to return one value only
         succ, msg = context.setalpncb(ctx, function()
            return (array2wireformat(protocols))    -- use "()" to drop error message
         end)
         if not succ then return nil, msg end
      else
         return nil, "invalid ALPN parameter"
      end
   elseif cfg.mode == "client" and cfg.alpn then
      local alpn
      if type(cfg.alpn) == "string" then
         alpn, msg = array2wireformat({ cfg.alpn })
      elseif type(cfg.alpn) == "table" then
         alpn, msg = array2wireformat(cfg.alpn)
      else
         return nil, "invalid ALPN parameter"
      end
      if not alpn then return nil, msg end
      succ, msg = context.setalpn(ctx, alpn)
      if not succ then return nil, msg end
   end

   if config.capabilities.dane and cfg.dane then
      context.setdane(ctx)
   end

   return ctx
end

--
--
--
local function wrap(sock, cfg)
   local ctx, msg
   if type(cfg) == "table" then
      ctx, msg = newcontext(cfg)
      if not ctx then return nil, msg end
   else
      ctx = cfg
   end
   local s, msg = core.create(ctx)
   if s then
      core.setfd(s, sock:getfd())
      sock:setfd(core.SOCKET_INVALID)
      registry[s] = ctx
      return s
   end
   return nil, msg 
end

--
-- Extract connection information.
--
local function info(ssl, field)
  local str, comp, err, protocol
  comp, err = core.compression(ssl)
  if err then
    return comp, err
  end
  -- Avoid parser
  if field == "compression" then
    return comp
  end
  local info = {compression = comp}
  str, info.bits, info.algbits, protocol = core.info(ssl)
  if str then
    info.cipher, info.protocol, info.key,
    info.authentication, info.encryption, info.mac =
        string.match(str, 
          "^(%S+)%s+(%S+)%s+Kx=(%S+)%s+Au=(%S+)%s+Enc=(%S+)%s+Mac=(%S+)")
    info.export = (string.match(str, "%sexport%s*$") ~= nil)
  end
  if protocol then
    info.protocol = protocol
  end
  if field then
    return info[field]
  end
  -- Empty?
  return ( (next(info)) and info )
end

--
-- Set method for SSL connections.
--
core.setmethod("info", info)

--------------------------------------------------------------------------------
-- Export module
--

local _M = {
  _VERSION        = "0.9",
  _COPYRIGHT      = core.copyright(),
  config          = config,
  loadcertificate = x509.load,
  newcontext      = newcontext,
  wrap            = wrap,
  decode          = decode,
  array2wireformat = array2wireformat,
  encodeBase64 = encodeBase64,
  decodeBase64 = decodeBase64,

  base64encode = base64encode,
  base64decode = base64decode,

}

return _M
