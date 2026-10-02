local socket = require("socket")
local io = require("io")
local string = require("string")
local bit = require("bit")-- 位运算 使用luajit自带的
local baseHttp = _G
module("socket.dnsip")
local arIPPool = {}

-- 异步获取DNS地址
getipbyhost = function(host, udpSocket)

    -- 2个8位转16位
    local ByteToInt16 = function(Byte_H, Byte_L)
        Byte_H = bit.lshift(Byte_H, 8)
        return bit.bor(Byte_H, Byte_L)
        -- Byte_H = Byte_H << 8
        -- return Byte_H | Byte_L
    end

    -- 4个8位转32位
    local ByteToInt32 = function(Byte_1, Byte_2, Byte_3, Byte_4)
        local H = ByteToInt16(Byte_1, Byte_2)
        local L = ByteToInt16(Byte_3, Byte_4)
        H = bit.lshift(H, 16)
        return bit.bor(H, L)
        -- H = H << 16
        -- return H | L
    end    

    -- 分割字符串
    local string_split = function(str, split_char)
        if str==nil or #str==0 then return {} end
        local sub_str_tab = {}
        while (true) do
            local pos = baseHttp.string.find(str, split_char)    
            if (not pos) then
                sub_str_tab[#sub_str_tab + 1] = str
                break
            end
            local sub_str = baseHttp.string.sub(str, 1, pos - 1)
            sub_str_tab[#sub_str_tab + 1] = sub_str
            str = baseHttp.string.sub(str, pos + 1, #str)
        end
        return sub_str_tab
    end

    -- 编码器
    local EncodeCode = function(val)
        local sERes = ""
        local tPlit = string_split(val, "%.")
        for _, value in baseHttp.ipairs(tPlit) do
            sERes = sERes..baseHttp.string.char(baseHttp.string.len(value))
            sERes = sERes..value
        end
        return sERes
    end

    -- 解码器
    local function DecodeCode(val, pos)

        if baseHttp.string.len(val) < pos then
            return false
        end

        local sIP = ""
        local nPos = pos
        local nLen = 0
        while baseHttp.string.byte(val, nPos) ~= 0x00 do

            nLen = baseHttp.string.byte(val, nPos)
            if ( bit.band(nLen, 0xc0) == 0 ) then
            -- if ((nLen & 0xc0) == 0) then
                if baseHttp.string.len(val) < nPos + nLen then
                    return false
                end
                for i = 1, nLen do
                    sIP = sIP..baseHttp.string.byte(val, nPos + i)
                end
                sIP = sIP.."."
                nPos = nPos + nLen + 1
            else
                if baseHttp.string.len(val) < nPos + 1 then
                    return false
                end
                -- bit.band(nLen, 0x3f)
                local usJumpPos = bit.band(
                    ByteToInt16(baseHttp.string.byte(val, nPos), baseHttp.string.byte(val, nPos + 1)),
                    0x3fff
                ) + 1
                -- local usJumpPos = (ByteToInt16(baseHttp.string.byte(val, nPos), baseHttp.string.byte(val, nPos + 1)) & 0x3fff) + 1
                local bRes, smyIP, _ = DecodeCode(val, usJumpPos)
                if bRes == false then
                    return false
                end
                sIP = sIP..smyIP
                nPos = nPos + 2
                return true, sIP, nPos
            end

            if baseHttp.string.len(val) < nPos then
                return false
            end
        end

        return true, sIP, nPos + 1
    end

    -- 生成报文
    local GetSendData = function(addr)        

        -- 报表头
        local sData = baseHttp.string.char(baseHttp.math.random(0, 255), baseHttp.math.random(0, 255)) -- 标识符

        local sData = sData..baseHttp.string.char(
        0x01,0x00, -- 各种标志位
        0x00,0x01, -- Question字段个数
        0x00,0x00, -- Answer字段个数
        0x00,0x00, -- Authority字段个数
        0x00,0x00 -- Additional字段个数
            )

        -- 报文内容
        sData = sData ..EncodeCode(addr)
        
        -- 消息类型
        sData = sData ..baseHttp.string.char(
        0x00,
        0x00,0x01, -- TYPE(16bits)：查询类型/回复包RDATA类型，比如TYPE=1表示主机IP地址、TYPE=5表示CNAME，详见RFC1035 3.2.2
        0x00,0x01  -- CLASS(16bits)：类，一般情况下CLASS=1表示Internet，详见RFC1035 3.2.4
            )

        return sData
    end

    local GetRecvData = function(sRecvBuff)

        local arrIP = {}
        if baseHttp.string.len(sRecvBuff) > 12 then
            local usTransID = ByteToInt16(baseHttp.string.byte(sRecvBuff,1), baseHttp.string.byte(sRecvBuff,2)) -- 标识符
            local usFlags = ByteToInt16(baseHttp.string.byte(sRecvBuff,3), baseHttp.string.byte(sRecvBuff,4)) -- 各种标志位
            local usQuestionCount = ByteToInt16(baseHttp.string.byte(sRecvBuff,5), baseHttp.string.byte(sRecvBuff,6)) -- Question字段个数 
            local usAnswerCount = ByteToInt16(baseHttp.string.byte(sRecvBuff,7), baseHttp.string.byte(sRecvBuff,8)) -- Answer字段个数
            local usAuthorityCount = ByteToInt16(baseHttp.string.byte(sRecvBuff,9), baseHttp.string.byte(sRecvBuff,10)) -- Authority字段个数
            local usAdditionalCount = ByteToInt16(baseHttp.string.byte(sRecvBuff,11), baseHttp.string.byte(sRecvBuff,12)) -- Additional字段个数
    
            if (usQuestionCount > 0 and usAnswerCount > 0) then
                
                local bRes = false
                local smyIP = ""
                local nmyPos = 13 -- 报文头大小
    
                for i = 1, usQuestionCount do
                    bRes, smyIP, nmyPos = DecodeCode(sRecvBuff, nmyPos)
                    if bRes == false then
                        return bRes
                    end
                    nmyPos = nmyPos + 2 + 2 -- 跨过usAnswerType和usAnswerClass
                end
    
                for i = 1, usAnswerCount do                
                    bRes, smyIP, nmyPos = DecodeCode(sRecvBuff, nmyPos)
                    if bRes == false then
                        return bRes
                    end
                    local usAnswerType = ByteToInt16(baseHttp.string.byte(sRecvBuff,nmyPos), baseHttp.string.byte(sRecvBuff,nmyPos+1))
                    local usAnswerClass = ByteToInt16(baseHttp.string.byte(sRecvBuff,nmyPos+2), baseHttp.string.byte(sRecvBuff,nmyPos+3))
                    local usAnswerTTL = ByteToInt32(baseHttp.string.byte(sRecvBuff,nmyPos+4), baseHttp.string.byte(sRecvBuff,nmyPos+5),
                                        baseHttp.string.byte(sRecvBuff,nmyPos+6), baseHttp.string.byte(sRecvBuff,nmyPos+7))
                    local usAnswerDataLen = ByteToInt16(baseHttp.string.byte(sRecvBuff,nmyPos+8), baseHttp.string.byte(sRecvBuff,nmyPos+9))
                    nmyPos = nmyPos + 2 + 2 + 4 + 2 -- 跨过上面的字段
    
                    if usAnswerType == 0x0001 then
                        local sResIP = baseHttp.string.format("%d", baseHttp.string.byte(sRecvBuff, nmyPos))
                        sResIP = sResIP..baseHttp.string.format(".%d", baseHttp.string.byte(sRecvBuff, nmyPos + 1))
                        sResIP = sResIP..baseHttp.string.format(".%d", baseHttp.string.byte(sRecvBuff, nmyPos + 2))
                        sResIP = sResIP..baseHttp.string.format(".%d", baseHttp.string.byte(sRecvBuff, nmyPos + 3))
                        baseHttp.table.insert(arrIP, sResIP)
                    end
                    nmyPos = nmyPos + usAnswerDataLen
                end
            end
        else
            return false
        end

        return true, arrIP
    end

    local IsIPFormat = function(ipStr)
        if baseHttp.type(ipStr) ~= "string" then
            return false
        end
        --判断长度
        local len = baseHttp.string.len(ipStr)
        if len < 7 or len > 15 then --长度不对
            return false
        end
        --判断出现的非数字字符
        local point = baseHttp.string.find(ipStr, "%p", 1) --字符"."出现的位置
        local pointNum = 0 --字符"."出现的次数 正常ip有3个"."
        while point ~= nil do
            if baseHttp.string.sub(ipStr, point, point) ~= "." then --得到非数字符号不是字符"."
                return false
            end
            pointNum = pointNum + 1
            point = baseHttp.string.find(ipStr, "%p", point + 1)
            if pointNum > 3 then
                return false
            end
        end
        if pointNum ~= 3 then --不是正确的ip格式
            return false
        end
        --判断数字对不对
        local num = {}
        for w in baseHttp.string.gmatch(ipStr, "%d+") do
            num[#num + 1] = w
            local kk = baseHttp.tonumber(w)
            if kk == nil or kk > 255 then --不是数字或超过ip正常取值范围了
                return false
            end
        end
        if #num ~= 4 then --不是4段数字
            return false
        end
        return true
    end

    ------------------------------------------------------------------------

    local sIPRes = nil

    if IsIPFormat(host) == true then
        sIPRes = host        
    else
        --1：读取缓存
        if arIPPool[host] ~= nil then
            local nIPLen = #arIPPool[host]
            if nIPLen > 0 then
                sIPRes = arIPPool[host][baseHttp.math.random(1, nIPLen)]
                socket.mBase.LogT("wwwwwwwwwwwwww_read_arIPPool__sIPRes1_",sIPRes)
                return sIPRes
            end
        end

        --2：读取系统hosts文件
        --------------------------
        local hostsFile,errInfo = io.open('/etc/hosts',"r")
        if hostsFile then
            for content in hostsFile:lines() do
                local test = string.format("%s",content)
                test = string.gsub(test, "[%(%)%.%%%+%-%*%?%[%]%^%$]", ".")
                newhost = string.gsub(host, "[%(%)%.%%%+%-%*%?%[%]%^%$]", ".")

                local pos = string.find(test,newhost)
                if pos then
                    test = string.gsub(test,newhost,"")
                    test = string.gsub(test,"%s+","")
                    if IsIPFormat(test) == true then
                        sIPRes = test           
                        local arrIP = {}                       
                        baseHttp.table.insert(arrIP,sIPRes)                      
                        arIPPool[host] = arrIP
                        hostsFile:close()
                        socket.mBase.LogT("wwwwwwwwwwwwww_read_hosts_sIPRes2_",sIPRes)
                        return sIPRes
                    else
                        socket.mBase.LogT("wwwwwwwwwwwwww_read_hosts_sIPRes2_failed,this is not IPFormat, host_",test)
                    end
                else
                    socket.mBase.LogT("wwwwwwwwwwwwww_read_hosts_sIPRes2_failed,no this host_",host)
                end
            end
            hostsFile:close()
        else
            socket.mBase.LogT("wwwwwwwwwwwwww_read_hosts_sIPRes2_failed,no hostsFile,host_",host)
        end
        
        --------------------------
   
        --3:使用DNS解析
        local c = udpSocket()

        local sData = GetSendData(host)
    
        c:sendto(sData, "114.114.114.114", 53)
    
        local sRecvData = ""    
        local bRes = false
        repeat
            local sRes, err = c:receive(1024)
    
            if err ~= nil then
                c:close()
                return nil, err
            end
            
            if sRes ~= nil then
                sRecvData = sRecvData..sRes
                local arrIP = {}
                bRes, arrIP = GetRecvData(sRecvData)
                if bRes then
                    arIPPool[host] = arrIP
                --else
                end
            end
        until(bRes)
    
        c:close()
    end
    
    if arIPPool[host] ~= nil then
        local nIPLen = #arIPPool[host]
        if nIPLen >= 1 then
            sIPRes = arIPPool[host][baseHttp.math.random(1, nIPLen)]
        end
    end
    socket.mBase.LogT("wwwwwwwwwwwwww_read_DNS_sIPRes3_",sIPRes)
    return sIPRes
end


-- 清除解释缓存池
ClearIPPool = function()

    arIPPool = {}

end

