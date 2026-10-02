
package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path
package.path = "../lua/base/socket/?.lua;./lua/base/socket/?.lua;" .. package.path
package.path = "../lua/Logon_s/?.lua;./lua/Logon_s/?.lua;" .. package.path
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

--发送错误信息
local tBase 	= require("base")         -- 基础功能接口
local tApi  	= require("publicApi")    -- 共用功能接口
local tRdf  	= require("redisdefine")  -- redis用到的kdy
local tname     = require("typename")     -- 类弄定义接口

BaseSink = {}

-- 使用例子
-- function BaseSink.test()  
--         local data = "a\193\207="  
--         local abc = BaseSink.encode(data)  
--         print(abc)  
      
--         def = BaseSink.decode(abc)  
--         if def == data then  
--             print("yes")  
--        end  
-- end  
      
-- BaseSink.test()  

local string = string  
  
BaseSink.__code = {  
            'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',  
            'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',  
            'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v',  
            'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/',  
        };  
BaseSink.__decode = {}  
for k,v in pairs(BaseSink.__code) do  
    BaseSink.__decode[string.byte(v,1)] = k - 1  
end  
  
function BaseSink.encode(text)  
    text = text or ""
    local len = string.len(text)  
    local left = len % 3  
    len = len - left  
    local res = {}  
    local index  = 1  
    for i = 1, len, 3 do  
        local a = string.byte(text, i )  
        local b = string.byte(text, i + 1)  
        local c = string.byte(text, i + 2)  
        -- num = a<<16 + b<<8 + c  
        local num = a * 65536 + b * 256 + c   
        for j = 1, 4 do  
            --tmp = num >> ((4 -j) * 6)  
            local tmp = math.floor(num / (2 ^ ((4-j) * 6)))  
            --curPos = tmp&0x3f  
            local curPos = tmp % 64 + 1  
            res[index] = BaseSink.__code[curPos]  
            index = index + 1  
        end  
    end  
  
    if left == 1 then  
        BaseSink.__left1(res, index, text, len)  
    elseif left == 2 then  
        BaseSink.__left2(res, index, text, len)          
    end  
    return table.concat(res)  
end  
  
function BaseSink.__left2(res, index, text, len)  
    local num1 = string.byte(text, len + 1)  
    num1 = num1 * 1024 --lshift 10   
    local num2 = string.byte(text, len + 2)  
    num2 = num2 * 4 --lshift 2   
    local num = num1 + num2  
     
    local tmp1 = math.floor(num / 4096) --rShift 12  
    local curPos = tmp1 % 64 + 1  
    res[index] = BaseSink.__code[curPos]  
      
    local tmp2 = math.floor(num / 64)  
    curPos = tmp2 % 64 + 1  
    res[index + 1] = BaseSink.__code[curPos]  
  
    curPos = num % 64 + 1  
    res[index + 2] = BaseSink.__code[curPos]  
      
    res[index + 3] = "="   
end  
  
function BaseSink.__left1(res, index,text, len)  
    local num = string.byte(text, len + 1)  
    num = num * 16   
      
    tmp = math.floor(num / 64)  
    local curPos = tmp % 64 + 1  
    res[index ] = BaseSink.__code[curPos]  
      
    curPos = num % 64 + 1  
    res[index + 1] = BaseSink.__code[curPos]  
      
    res[index + 2] = "="   
    res[index + 3] = "="   
end

function BaseSink.decode(text)
    -- 去掉空白（有些来源会带换行/空格）
    text = (text:gsub("%s+", ""))

    local len = #text
    local mod = len % 4

    -- Base64 长度必须是 4 的倍数，不足补 '='
    if mod == 2 then
        text = text .. "=="
    elseif mod == 3 then
        text = text .. "="
    elseif mod == 1 then
        error("Base64 decode: invalid length (" .. len .. ")")
    end

    -- 确保 '=' 可解码（否则 decode['='] 会是 nil）
    BaseSink.__decode[string.byte("=", 1)] = 0

    local decode = BaseSink.__decode
    local res = {}
    local index = 1
    len = #text

    for i = 1, len, 4 do
        local a = decode[string.byte(text, i    )]
        local b = decode[string.byte(text, i + 1)]
        local c = decode[string.byte(text, i + 2)]
        local d = decode[string.byte(text, i + 3)]

        if a == nil or b == nil or c == nil or d == nil then
            error("Base64 decode: invalid character at pos " .. i)
        end

        local num = a * 262144 + b * 4096 + c * 64 + d

        local e = string.char(num % 256)
        num = math.floor(num / 256)
        local f = string.char(num % 256)
        num = math.floor(num / 256)

        res[index]     = string.char(num % 256)
        res[index + 1] = f
        res[index + 2] = e
        index = index + 3
    end

    -- 根据 '=' 去掉尾部补齐产生的 0 字节
    if string.sub(text, -2) == "==" then
        res[#res] = nil
        res[#res] = nil
    elseif string.sub(text, -1) == "=" then
        res[#res] = nil
    end

    return table.concat(res)
end
  
function BaseSink.decode_old(text)  
    local len = string.len(text)  
    local left = 0   
    if string.sub(text, len - 1) == "==" then  
        left = 2   
        len = len - 4  
    elseif string.sub(text, len) == "=" then  
        left = 1  
        len = len - 4  
    end  
  
    local res = {}  
    local index = 1  
    local decode = BaseSink.__decode  
    for i =1, len, 4 do  
        local a = decode[string.byte(text,i    )]   
        local b = decode[string.byte(text,i + 1)]   
        local c = decode[string.byte(text,i + 2)]   
        local d = decode[string.byte(text,i + 3)]  
  
        --num = a<<18 + b<<12 + c<<6 + d  
        local num = a * 262144 + b * 4096 + c * 64 + d  
          
        local e = string.char(num % 256)  
        num = math.floor(num / 256)  
        local f = string.char(num % 256)  
        num = math.floor(num / 256)  
        res[index ] = string.char(num % 256)  
        res[index + 1] = f  
        res[index + 2] = e  
        index = index + 3  
    end  
  
    if left == 1 then  
        BaseSink.__decodeLeft1(res, index, text, len)  
    elseif left == 2 then  
        BaseSink.__decodeLeft2(res, index, text, len)  
    end  
    return table.concat(res)  
end  
  
function BaseSink.__decodeLeft1(res, index, text, len)  
    local decode = BaseSink.__decode  
    local a = decode[string.byte(text, len + 1)]   
    local b = decode[string.byte(text, len + 2)]   
    local c = decode[string.byte(text, len + 3)]   
    local num = a * 4096 + b * 64 + c  
      
    local num1 = math.floor(num / 1024) % 256  
    local num2 = math.floor(num / 4) % 256  
    res[index] = string.char(num1)  
    res[index + 1] = string.char(num2)  
end  
  
function BaseSink.__decodeLeft2(res, index, text, len)  
    local decode = BaseSink.__decode  
    local a = decode[string.byte(text, len + 1)]   
    local b = decode[string.byte(text, len + 2)]  
    local num = a * 64 + b  
    num = math.floor(num / 16)  
    res[index] = string.char(num)  
end  
  



-- -- 编码
-- function BaseSink.EncodeBase64(source_str)  
--     local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'  
--     -- local b64chars = 'quanyu+/'  
--     local s64 = ''  
--     local str = source_str  
  
--     while #str > 0 do  
--         local bytes_num = 0  
--         local buf = 0  
  
--         for byte_cnt=1,3 do  
--             buf = (buf * 256)  
--             if #str > 0 then  
--                 buf = buf + string.byte(str, 1, 1)  
--                 str = string.sub(str, 2)  
--                 bytes_num = bytes_num + 1  
--             end  
--         end  
  
--         for group_cnt=1,(bytes_num+1) do  
--             local b64char = math.fmod(math.floor(buf/262144), 64) + 1  
--             s64 = s64 .. string.sub(b64chars, b64char, b64char)  
--             buf = buf * 64  
--         end  
  
--         for fill_cnt=1,(3-bytes_num) do  
--             s64 = s64 .. '='  
--         end  
--     end  
  
--     return s64  
-- end  
      
-- -- 解码     
-- function BaseSink.DecodeBase64(str64)  
--     local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' 
--     -- local b64chars = 'quanyu+/'   
--     local temp={}  
--     for i=1,64 do  
--         temp[string.sub(b64chars,i,i)] = i  
--     end  
--     temp['=']=0  
--     local str=""  
--     for i=1,#str64,4 do  
--         if i>#str64 then  
--             break  
--         end  
--         local data = 0  
--         local str_count=0  
--         for j=0,3 do  
--             local str1=string.sub(str64,i+j,i+j)  
--             if not temp[str1] then  
--                 return  
--             end  
--             if temp[str1] < 1 then  
--                 data = data * 64  
--             else  
--                 data = data * 64 + temp[str1]-1  
--                 str_count = str_count + 1  
--             end  
--         end  
--         for j=16,0,-8 do  
--             if str_count > 0 then  
--                tBase.Log(" 1111111111111111  j=   "..j ) 
--                tBase.Log(" 1111111111111111  data=   "..data ) 
--                tBase.Log(" 1111111111111111  math.pow(2,j)=   "..math.pow(2,j)) 
--                tBase.Log(" 1111111111111111  math.floor(data/math.pow(2,j))=   "..math.floor(data/math.pow(2,j)))

--                 -- str=str..string.char(math.floor(data/math.pow(2,j)))  
--                 str=str..string.char(math.floor(data/262144))  

--                tBase.Log(" 2222222222222 =   "..str ) 
--                 data= math.modf(data,math.pow(2,j))  
--                 str_count = str_count - 1  
--             end  
--         end  
--     end  
  
--     local last = tonumber(string.byte(str, string.len(str), string.len(str)))  
--     if last == 0 then  
--         str = string.sub(str, 1, string.len(str) - 1)  
--     end  
--     return str  
-- end  


return BaseSink

