
local TgVerify = {}

local function bit_and(a, b)
    local result = 0
    local bit = 1
    while a > 0 or b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end

local function bit_or(a, b)
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

local function bit_xor(a, b)
    local result = 0
    local bit = 1
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then
            result = result + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end

local function bit_not(a)
    return 0xFFFFFFFF - a
end

local function bit_rshift(a, n)
    return math.floor(a / (2^n))
end

local function bit_lshift(a, n)
    return (a * (2^n)) % 0x100000000
end

local function bit_ror(x, n)
    local low = x % (2^n)
    local high = math.floor(x / (2^n))
    return bit_or(bit_lshift(low, 32-n), high)
end

local function sha256_pure(message)
    local char, byte, format, rep, sub =
          string.char, string.byte, string.format, string.rep, string.sub
    local bit_or, bit_and, bit_not, bit_xor, bit_rshift, bit_lshift =
           bit_or,bit_and,bit_not,bit_xor,bit_rshift,bit_lshift
    
    -- 初始化常量
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
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    }
    
    local function rrotate(x, n)
        return bit_or(bit_rshift(x, n), bit_lshift(x, 32 - n))
    end
    
    local function preproc(msg, len)
        local extra = 64 - ((len + 9) % 64)
        len = len * 8
        msg = msg .. char(0x80) .. rep(char(0), extra) .. char(
              bit_and(bit_rshift(len, 56), 0xFF),
              bit_and(bit_rshift(len, 48), 0xFF),
              bit_and(bit_rshift(len, 40), 0xFF),
              bit_and(bit_rshift(len, 32), 0xFF),
              bit_and(bit_rshift(len, 24), 0xFF),
              bit_and(bit_rshift(len, 16), 0xFF),
              bit_and(bit_rshift(len, 8), 0xFF),
              bit_and(len, 0xFF))
        return msg
    end
    
    local function hash_block(w, H)
        for j = 16, 63 do
            local v = w[j - 15]
            local s0 = bit_xor(bit_xor(rrotate(v, 7), rrotate(v, 18)), bit_rshift(v, 3))
            v = w[j - 2]
            local s1 = bit_xor(bit_xor(rrotate(v, 17), rrotate(v, 19)), bit_rshift(v, 10))
            w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % 0x100000000
        end
        
        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        
        for j = 0, 63 do
            local S1 = bit_xor(bit_xor(rrotate(e, 6), rrotate(e, 11)), rrotate(e, 25))
            local ch = bit_xor(bit_and(e, f), bit_and(bit_not(e), g))
            local temp1 = (h + S1 + ch + k[j + 1] + w[j]) % 0x100000000
            local S0 = bit_xor(bit_xor(rrotate(a, 2), rrotate(a, 13)), rrotate(a, 22))
            local maj = bit_xor(bit_xor(bit_and(a, b), bit_and(a, c)), bit_and(b, c))
            local temp2 = (S0 + maj) % 0x100000000
            
            h = g
            g = f
            f = e
            e = (d + temp1) % 0x100000000
            d = c
            c = b
            b = a
            a = (temp1 + temp2) % 0x100000000
        end
        
        H[1] = (H[1] + a) % 0x100000000
        H[2] = (H[2] + b) % 0x100000000
        H[3] = (H[3] + c) % 0x100000000
        H[4] = (H[4] + d) % 0x100000000
        H[5] = (H[5] + e) % 0x100000000
        H[6] = (H[6] + f) % 0x100000000
        H[7] = (H[7] + g) % 0x100000000
        H[8] = (H[8] + h) % 0x100000000
    end
    
    -- 主函数
    message = preproc(message, #message)
    
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }
    
    for i = 1, #message, 64 do
        local w = {}
        for j = 0, 15 do
            local base = i + j * 4
            w[j] = bit_or(bit_or(bit_or(
                bit_lshift(byte(message, base), 24),
                bit_lshift(byte(message, base + 1), 16)),
                bit_lshift(byte(message, base + 2), 8)),
                byte(message, base + 3))
        end
        hash_block(w, H)
    end
    
    return format("%08x%08x%08x%08x%08x%08x%08x%08x",
        H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

local function hex2bin(hex_str)
    local bin = ""
    for i = 1, #hex_str, 2 do
        local hex_byte = hex_str:sub(i, i+1)
        bin = bin .. string.char(tonumber(hex_byte, 16))
    end
    return bin
end

-- 二进制转十六进制
local function bin2hex(bin_str)
    local hex = ""
    for i = 1, #bin_str do
        hex = hex .. string.format("%02x", bin_str:byte(i))
    end
    return hex
end

-- HMAC-SHA256 实现
local function hmac_sha256(key, message)
    local block_size = 64  -- SHA-256 块大小（字节）

    -- 如果密钥太长，先进行哈希
    if #key > block_size then
        key = hex2bin(sha256_pure(key))
    end

    -- 如果密钥太短，进行填充
    if #key < block_size then
        key = key .. string.rep('\0', block_size - #key)
    end

    -- 计算 o_key_pad 和 i_key_pad
    local o_key_pad = ""
    local i_key_pad = ""

    for i = 1, block_size do
        local key_byte = key:byte(i) or 0
        o_key_pad = o_key_pad .. string.char(bit_xor(key_byte, 0x5C))
        i_key_pad = i_key_pad .. string.char(bit_xor(key_byte, 0x36))
    end

    -- 计算 HMAC: HMAC = H(o_key_pad || H(i_key_pad || message))
    local inner_hash = hex2bin(sha256_pure(i_key_pad .. message))
    return hex2bin(sha256_pure(o_key_pad .. inner_hash))
end
TgVerify.hmac_sha256 = hmac_sha256
TgVerify.bin2hex = bin2hex

return TgVerify