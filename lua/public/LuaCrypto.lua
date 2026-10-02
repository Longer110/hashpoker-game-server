
-- LuaCrypto.lua - 轻量级加密库实现
-- 主要提供HMAC-SHA256功能用于Telegram验证

local LuaCrypto = {}

-- SHA-256算法常量
local k = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

-- 位操作函数
local function rshift(a, b) return math.floor(a / 2^b) end
local function lshift(a, b) return a * 2^b % 2^32 end
-- 兼容 Lua 5.1/5.3 的按位与
local function band(a, b)
    -- if bit32 and bit32.band then
    --     return bit32.band(a, b)
    -- elseif _VERSION == "Lua 5.3" or _VERSION == "Lua 5.4" then
    --     return a & b
    -- else
        -- 纯 Lua 实现
        local res, p = 0, 1
        while a > 0 or b > 0 do
            local aa, bb = a % 2, b % 2
            if aa == 1 and bb == 1 then res = res + p end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            p = p * 2
        end
        return res
    -- end
end
local function bor(a, b)
    local result = 0
    local bit = 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then
            result = result + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end
-- 兼容 Lua 5.1/5.3 的按位异或
local function bxor(a, b)
    -- if bit32 and bit32.bxor then
    --     return bit32.bxor(a, b)
    -- elseif _VERSION == "Lua 5.3" or _VERSION == "Lua 5.4" then
    --     return a ~ b
    -- else
        -- 兼容 LuaJIT 或无 bit32 的 Lua 5.1
        local res, p = 0, 1
        while a > 0 or b > 0 do
            local aa, bb = a % 2, b % 2
            if aa ~= bb then res = res + p end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            p = p * 2
        end
        return res
    -- end
end
-- 兼容 Lua 5.1/5.3 的按位非
local function bnot(a)
    -- if bit32 and bit32.bnot then
    --     return bit32.bnot(a)
    -- elseif _VERSION == "Lua 5.3" or _VERSION == "Lua 5.4" then
    --     return (~a) & 0xFFFFFFFF
    -- else
        return 0xFFFFFFFF - a
    -- end
end
local function rotr(a, b) return bor(rshift(a, b), lshift(a, 32-b)) end

-- 辅助函数
local function ch(x, y, z) return bxor(band(x, y), band(bnot(x), z)) end
local function maj(x, y, z) return bxor(bxor(band(x, y), band(x, z)), band(y, z)) end
local function sigma0(x) return bxor(bxor(rotr(x, 2), rotr(x, 13)), rotr(x, 22)) end
local function sigma1(x) return bxor(bxor(rotr(x, 6), rotr(x, 11)), rotr(x, 25)) end
local function gamma0(x) return bxor(bxor(rotr(x, 7), rotr(x, 18)), rshift(x, 3)) end
local function gamma1(x) return bxor(bxor(rotr(x, 17), rotr(x, 19)), rshift(x, 10)) end

-- 将字符串转换为字节数组
local function str_to_bytes(str)
    local bytes = {}
    for i = 1, #str do
        bytes[i] = string.byte(str, i)
    end
    return bytes
end

-- 将字节数组转换为字符串
local function bytes_to_str(bytes)
    local str = {}
    for i = 1, #bytes do
        str[i] = string.char(bytes[i])
    end
    return table.concat(str)
end

-- 将32位整数转换为4个字节
local function int_to_bytes(num)
    local bytes = {}
    bytes[1] = band(rshift(num, 24), 0xFF)
    bytes[2] = band(rshift(num, 16), 0xFF)
    bytes[3] = band(rshift(num, 8), 0xFF)
    bytes[4] = band(num, 0xFF)
    return bytes
end

-- 将4个字节转换为32位整数
local function bytes_to_int(b, offset)
    offset = offset or 1
    return lshift(b[offset], 24) + lshift(b[offset+1], 16) + lshift(b[offset+2], 8) + b[offset+3]
end

-- SHA-256核心算法
local function sha256(message)
    -- 初始哈希值
    local h = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }
    
    -- 预处理消息
    local bytes = str_to_bytes(message)
    local length = #bytes
    local bits_length = length * 8
    
    -- 添加填充
    bytes[#bytes + 1] = 0x80  -- 添加1后跟0
    
    -- 填充0直到长度满足 (length + 1 + 8) % 64 = 0
    while (#bytes + 8) % 64 ~= 0 do
        bytes[#bytes + 1] = 0
    end
    
    -- 添加消息长度（以位为单位）作为64位整数
    for i = 1, 8 do
        bytes[#bytes + 1] = band(rshift(bits_length, (8-i)*8), 0xFF)
    end
    
    -- 处理消息块
    for i = 1, #bytes, 64 do
        local w = {}
        
        -- 准备消息调度
        for j = 0, 15 do
            w[j+1] = bytes_to_int(bytes, i + j*4)
        end
        
        -- 扩展消息调度
        for j = 17, 64 do
            local s0 = gamma0(w[j-15])
            local s1 = gamma1(w[j-2])
            w[j] = (w[j-16] + s0 + w[j-7] + s1) % 2^32
        end
        
        -- 初始化工作变量
        local a, b, c, d, e, f, g, h_val = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        
        -- 主循环
        for j = 1, 64 do
            local S1 = sigma1(e)
            local ch_val = ch(e, f, g)
            local temp1 = (h_val + S1 + ch_val + k[j] + w[j]) % 2^32
            local S0 = sigma0(a)
            local maj_val = maj(a, b, c)
            local temp2 = (S0 + maj_val) % 2^32
            
            h_val = g
            g = f
            f = e
            e = (d + temp1) % 2^32
            d = c
            c = b
            b = a
            a = (temp1 + temp2) % 2^32
        end
        
        -- 更新哈希值
        h[1] = (h[1] + a) % 2^32
        h[2] = (h[2] + b) % 2^32
        h[3] = (h[3] + c) % 2^32
        h[4] = (h[4] + d) % 2^32
        h[5] = (h[5] + e) % 2^32
        h[6] = (h[6] + f) % 2^32
        h[7] = (h[7] + g) % 2^32
        h[8] = (h[8] + h_val) % 2^32
    end
    
    -- 生成最终哈希
    local result = {}
    for i = 1, 8 do
        local bytes = int_to_bytes(h[i])
        for j = 1, 4 do
            result[#result + 1] = bytes[j]
        end
    end
    
    return bytes_to_str(result)
end

-- HMAC-SHA256实现
function LuaCrypto.hmac_sha256(key, message)
    local blocksize = 64
    if #key > blocksize then
        key = sha256(key)
    end
    if #key < blocksize then
        key = key .. string.rep("\0", blocksize - #key)
    end

    local key_bytes = { string.byte(key, 1, #key) }
    local o_key_pad = {}
    local i_key_pad = {}
    for i = 1, blocksize do
        o_key_pad[i] = string.char(bxor(key_bytes[i], 0x5c))
        i_key_pad[i] = string.char(bxor(key_bytes[i], 0x36))
    end

    local inner = sha256(table.concat(i_key_pad) .. message)
    -- ⚠️ inner 是二进制字符串（32字节）
    local hmac = sha256(table.concat(o_key_pad) .. inner)
    return hmac
end


LuaCrypto.sha256 = sha256

-- 将二进制数据转换为十六进制字符串
function LuaCrypto.bin2hex(bin)
    local hex = {}
    for i = 1, #bin do
        hex[i] = string.format("%02x", string.byte(bin, i))
    end
    return table.concat(hex)
end

-- 将十六进制字符串转换为二进制数据
function LuaCrypto.hex2bin(hex)
    local bin = {}
    for i = 1, #hex, 2 do
        local byte = tonumber(hex:sub(i, i+1), 16)
        bin[#bin+1] = string.char(byte)
    end
    return table.concat(bin)
end

-- Base64编码表
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- Base64编码
function LuaCrypto.base64_encode(data)
    local result = {}
    local i = 1
    while i <= #data do
        local b1, b2, b3 = string.byte(data, i, i+2)
        local c1 = rshift(b1, 2)
        local c2 = lshift(band(b1, 0x3), 4)
        if b2 then
            c2 = c2 + rshift(b2, 4)
            local c3 = lshift(band(b2, 0xF), 2)
            if b3 then
                c3 = c3 + rshift(b3, 6)
                local c4 = band(b3, 0x3F)
                table.insert(result, b64chars:sub(c1+1, c1+1) .. b64chars:sub(c2+1, c2+1) ..
                                     b64chars:sub(c3+1, c3+1) .. b64chars:sub(c4+1, c4+1))
            else
                table.insert(result, b64chars:sub(c1+1, c1+1) .. b64chars:sub(c2+1, c2+1) ..
                                     b64chars:sub(c3+1, c3+1) .. '=')
            end
        else
            table.insert(result, b64chars:sub(c1+1, c1+1) .. b64chars:sub(c2+1, c2+1) .. '==')
        end
        i = i + 3
    end
    return table.concat(result)
end

-- Base64解码
function LuaCrypto.base64_decode(data)
    local b64chars_inv = {}
    for i = 1, #b64chars do
        b64chars_inv[b64chars:sub(i, i)] = i-1
    end
    local result = {}
    local i = 1
    while i <= #data do
        local c1, c2, c3, c4 = data:sub(i, i), data:sub(i+1, i+1), data:sub(i+2, i+2), data:sub(i+3, i+3)
        local b1 = lshift(b64chars_inv[c1], 2) + rshift(b64chars_inv[c2], 4)
        table.insert(result, string.char(b1))
        if c3 ~= '=' then
            local b2 = lshift(band(b64chars_inv[c2], 0xF), 4) + rshift(b64chars_inv[c3], 2)
            table.insert(result, string.char(b2))
            if c4 ~= '=' then
                local b3 = lshift(band(b64chars_inv[c3], 0x3), 6) + b64chars_inv[c4]
                table.insert(result, string.char(b3))
            end
        end
        i = i + 4
    end
    return table.concat(result)
end

-- 用密钥加密用户密码，返回十六进制字符串
function LuaCrypto.encrypt_password(password, secret)
    -- password: 明文密码
    -- secret: 加密密钥
    -- 返回: HMAC-SHA256
    local hmac = LuaCrypto.hmac_sha256(secret, password)
    return LuaCrypto.bin2hex(hmac)
end

return LuaCrypto