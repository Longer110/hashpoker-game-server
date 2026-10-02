
local  tHotFix = require("HotFix")
local TB_shield_words = require("TB_shield_words")
publicApi = {}
 

--计算零点时间差
function publicApi.GetLeroLeadTime()  
   local now_date = os.date("*t",now)      -- 获取当前时间 
   local nEnd_Time = os.time{year=now_date.year, month=now_date.month, day=now_date.day, hour=23,min=59,sec=59}     -- 当天的最后时间
   local nLero_Time = (nEnd_Time - os.time()) +1       -- 当前时间与零点的时间差
   return nLero_Time
end

--获取当月天数
function publicApi.GetMonthDayCount()  
    local year,month = os.date("%Y", os.time()), os.date("%m", os.time())+1 -- 正常是获取服务器给的时间来算
    local dayAmount = os.date("%d", os.time({year=year, month=month, day=0})) -- 获取当月天数
    return dayAmount 
end


-- 检查开始时间和 过期时间"2018-11-01 11:47:36" ： 0 正常， 1 没到开始时间， 2 过期 
function publicApi.CheakStarTimeEndTiem(sStartTime,sEndTime)
    local nStartTime = 0
    local nEndTime = 0
    nStartTime = publicApi.string2time(sStartTime)                
    nEndTime = publicApi.string2time(sEndTime) 
    local nStart = os.time() - nStartTime    -- 开始日期   小于 0  还没开始， 大于 0  开始了
    local nIndate =  nEndTime - os.time()   -- 有效期    大于 0  没过期， 小于 0  过期了 
    if  nStart >= 0  and nIndate >=  0 then 
        return 0   -- 正常
    else                
        if nStart < 0 then 
            return 1
        elseif  nIndate < 0 then 
            return 2 
        else 
            return -1
        end 
    end
    return 
end

-- os.time() -- 转为 日期
function publicApi.OsTimetoDataTime(nTime)  
    return  os.date("%Y-%m-%d %H:%M:%S",nTime)
end  

-- 数据库时间转换为   秒数 :   格式必须是这样  "2018-11-01 11:47:36"
function publicApi.string2time(timeString)  
    local Y = string.sub(timeString , 1, 4)  
    local M = string.sub(timeString , 6, 7)  
    local D = string.sub(timeString , 9, 10)  
    local h = string.sub(timeString , 12,13)  
    local m = string.sub(timeString , 15,16)  
    local s = string.sub(timeString , 18,19) 
    local tRet = {year=Y, month=M, day=D, hour=h,min=m,sec=s} 
    return os.time(tRet), tRet   
end  
 
-- 关于特殊字符变 处理
function publicApi.Special_String(sString)
    sString = publicApi.filter_emoji_chars(sString)
    sString = publicApi.Check_String_Special(sString)
    return sString
end

--获取可用字符
function publicApi.CodeChar(str)
    local str2 = ""
    for k=1,#str do 
        local s = string.sub(str,k,k)
        local n = s:byte()
        if (48<=n and n<=57) or (65<=n and n<=90) or (97<=n and n<=122) or (n==45) then
            str2 = str2..s
        else
            str2 = str2.."*"
        end
    end
    return str2
end

-- 微信昵称中的特殊字符处理：   emoji 表情变*    utf8    
function publicApi.filter_emoji_chars(s)
    local ss = {}
    local k = 1
    while true do
        if k > #s then break end
        local c = string.byte(s,k)
        if not c then break end
        if c<192 then
            table.insert(ss, string.char(c))
            k = k + 1
            -- tBase.Log(" 微信昵称中的特殊字符处理： 11111  ")
        elseif c<224 then
            local c1 = string.byte(s,k+1)
            table.insert(ss, string.char(c,c1))
            k = k + 2
            -- tBase.Log(" 微信昵称中的特殊字符处理： 22222  ")
        elseif c<240 then
            if c>=228 and c<=233 then
                local c1 = string.byte(s,k+1)
                local c2 = string.byte(s,k+2)
                if c1 and c2 then
                    local a1,a2,a3,a4 = 128,191,128,191
                    if c == 228 then a1 = 184
                    elseif c == 233 then a2,a4 = 190,c1 ~= 190 and 191 or 165
                    end
                    if c1>=a1 and c1<=a2 and c2>=a3 and c2<=a4 then
                        table.insert(ss, string.char(c,c1,c2))
                        print(c)
                    else
                        local str = string.char(c,c1,c2)
                        if string.find(str, "[\226][\132-\173]") or string.find(str, "[\227][\138]") or string.find(str, "[\227][\128][\189]") then
                            table.insert(ss,"*")
                            -- tBase.Log(" 微信昵称中的特殊字符处理： 33333   44444  ")
                        else
                            table.insert(ss, string.char(c,c1,c2))
                        end
                    end
                end
            else
                local c1 = string.byte(s,k+1)
                local c2 = string.byte(s,k+2)
                local str = string.char(c,c1,c2)
                if string.find(str, "[\226][\132-\173]") or string.find(str, "[\227][\138]") or string.find(str, "[\227][\128][\189]") then
                    table.insert(ss,"*")
                    -- tBase.Log(" 微信昵称中的特殊字符处理： 33333   55555  ")
                    print(c)
                else
                    table.insert(ss, string.char(c,c1,c2))
                end
            end
            -- tBase.Log(" 微信昵称中的特殊字符处理： 33333333 ")
            k = k + 3
        elseif c<248 then
            k = k + 4
            -- tBase.Log(" 微信昵称中的特殊字符处理： 44444444 ")
            table.insert(ss,"*")
        elseif c<252 then
            k = k + 5
            table.insert(ss,"*")
            -- tBase.Log(" 微信昵称中的特殊字符处理： 555555555 ")
        elseif c<254 then
            k = k + 6
            table.insert(ss,"*")
            -- tBase.Log(" 微信昵称中的特殊字符处理： 666666666 ")
        end
    end
    --特殊转化字符床%为*
    local sss = string.gsub(table.concat(ss), "%%", "*")
    return sss
end

-- 处理 特殊字符变  * 号 
function publicApi.Check_String_Special(str)
    -- str = string.format(" %q", str) -- 转换可被lua编译的字符
    -- str =  string.gsub(str, "/[(\\)]+/","*")    -- 处理 ’

    str =  string.gsub(str, "\\","*")    -- 处理 ’
    str =  string.gsub(str, "'", "*")    -- 处理 ’
    str =  string.gsub(str, "%%", "*")   -- 处理 % 
    str =  string.gsub(str, "/", "*")    -- 处理 /
    str =  string.gsub(str, "“", "*")    -- 处理 “
    str =  string.gsub(str, "”", "*")    -- 处理 ”
    str =  string.gsub(str, "%b“”", "*")   -- 处理 “” 
    str =  string.gsub(str, " ", "*")   -- 处理 “” 
    return str
end

--检查是否有特殊字符
function publicApi.CheckSpecailWords(str)
    local s,s1 = publicApi.filter_spec_chars(str)
    if #s1>0 then
        Base.Log("CheckSpecailWords %s",s1)
        return true
    end
    return false
end

--过滤特殊字符
function publicApi.filter_spec_chars(s)
    local ss = {} --正常字符
    local sss = {} --特殊字符
    local k = 1
    while true do
        if k > #s then break end
        local c = string.byte(s,k)
        if not c then break end
        if c<192 then
            if (c>=48 and c<=57) or (c>= 65 and c<=90) or (c>=97 and c<=122) then
                table.insert(ss, string.char(c))
            else
                if c ~= 32 then 
                    table.insert(sss, string.char(c))
                end 
            end
            k = k + 1
        elseif c<224 then
            k = k + 2
            table.insert(sss, string.char(c))
        elseif c<240 then
            if c>=228 and c<=233 then
                local c1 = string.byte(s,k+1)
                local c2 = string.byte(s,k+2)
                if c1 and c2 then
                    local a1,a2,a3,a4 = 128,191,128,191
                    if c == 228 then 
                        a1 = 184
                    elseif c == 233 then 
                        a2 = 190
                        a4 = (c1 ~= 190 and 191) or 165
                    end
                    if c1>=a1 and c1<=a2 and c2>=a3 and c2<=a4 then
                        table.insert(ss, string.char(c,c1,c2))
                    else
                        table.insert(sss, string.char(c))
                    end
                end
            else
                table.insert(sss, string.char(c))
            end
            k = k + 3
        elseif c<248 then
            k = k + 4
            table.insert(sss, string.char(c))
        elseif c<252 then
            k = k + 5
            table.insert(sss, string.char(c))
        elseif c<254 then
            k = k + 6
            table.insert(sss, string.char(c))
        end
    end
    return table.concat(ss),table.concat(sss)
end

--检查是否有特殊字符,部分标点符号除外
function publicApi.CheckSpecailWords2(str)
    local s,s1 = publicApi.filter_spec_chars2(str)
    if #s1>0 then
        Base.Log("CheckSpecailWords2 %s",s1)
        return true
    end
    return false
end

--过滤特殊字符，保留部分标点符号
function publicApi.filter_spec_chars2(s)
    local ss = {} --正常字符
    local sss = {} --特殊字符
    local k = 1
    while true do
        if k > #s then break end
        local c = string.byte(s,k)
        if not c then break end
        if c<192 then
            if (c>=48 and c<=57) or (c>= 65 and c<=90) or (c>=97 and c<=122) then
                table.insert(ss, string.char(c))
            elseif c==33 or c==35 or c==36 or (c>=38 and c<=47) or (c>=58 and c<=64) or (c>=94 and c<=96) or (c>=123 and c<=126) then
                table.insert(ss, string.char(c))
            else
                table.insert(sss, string.char(c))
            end
            k = k + 1
        elseif c<224 then
            k = k + 2
            if c==194 then
                table.insert(ss, string.char(c))
            else
                table.insert(sss, string.char(c))
            end
        elseif c<240 then
            if c>=228 and c<=233 then
                local c1 = string.byte(s,k+1)
                local c2 = string.byte(s,k+2)
                if c1 and c2 then
                    local a1,a2,a3,a4 = 128,191,128,191
                    if c == 228 then 
                        a1 = 184
                    elseif c == 233 then 
                        a2 = 190
                        a4 = (c1 ~= 190 and 191) or 165
                    end
                    if c1>=a1 and c1<=a2 and c2>=a3 and c2<=a4 then
                        table.insert(ss, string.char(c,c1,c2))
                    else
                        table.insert(sss, string.char(c))
                    end
                end
            elseif c==226 or c==227 or c==239 then 
                table.insert(ss, string.char(c))
            else
                table.insert(sss, string.char(c))
            end
            k = k + 3
        elseif c<248 then
            k = k + 4
            table.insert(sss, string.char(c))
        elseif c<252 then
            k = k + 5
            table.insert(sss, string.char(c))
        elseif c<254 then
            k = k + 6
            table.insert(sss, string.char(c))
        end
    end
    return table.concat(ss),table.concat(sss)
end

--检查是否有敏感词
function publicApi.CheckSensitiveWords(str)
    for _,v in pairs(TB_shield_words) do
        local sWords = string.gsub(v.word, "^%s*(.-)%s*$", "%1")
        local isSuccee,sFind = pcall(string.match,str,sWords)
        if isSuccee then
            if sFind then
                Base.Log("CheckSensitiveWords %d %s",v.id,sWords)
                return true
            end
        else
            Base.Log("CheckSensitiveWords Error %d %s",v.id,sWords)
        end
    end
    return false
end

-- 检查账号 是否英文字母 与数字 或者下划线
function publicApi.Check_AccountString(string)
   for i=1,string.len(string) do
       local char = string.sub(string,i,i)
       if string.find(char,"[%w_]") then 
           -- m.Log("检查账号 是否英文字母与数字或者下划线   true")  
       else
           -- m.Log("检查账号 是否英文字母与数字或者下划线   false")  
           return false
       end         
   end 
   return true 
end

-- 检查字符串 是否只包含英文和字母
function publicApi.Check_StringIsNormal(str)
    for i=1,string.len(str) do
        local temp = string.sub(str,i,i)
        if string.find(temp,"[%w]") then 
            -- m.Log("检查账号 是否英文字母与数字或者下划线   true")  
        else
            -- m.Log("检查账号 是否英文字母与数字或者下划线   false")  
            return false
        end         
    end 
    return true 
 end


-- 返回本机IP列表dd
function publicApi.GetLocalIPs()
    local Papi = PAPI_A178350C2F44461DB18C9DAD18D78121.new()
    local Res = Papi:GetIP()
    Papi = nil
    return Res
end

-- 返回本机IP
function publicApi.GetLocalIP()
    local localIP = ""
    local ipformat1 = "%d+%.%d+%.%d+%.%d+"
    local ipformat2 = "%.1$"
    local ips = publicApi.GetLocalIPs()
    for i = 1, #ips do  
        local nI1, nI2 = string.find(ips[i], ipformat1)
        if (nI1 ~= nil) then
            local tmpV = string.sub(ips[i], string.find(ips[i], ipformat1))
            local nnI1, nnI2 = string.find(tmpV, ipformat2)
            if nnI1 == nil then
                localIP = tmpV
            end
        end       
    end 

    return localIP
end

-- double转int型
function publicApi.Double2Int(d)
    if not d then
        return 0
    end
    local Papi = PAPI_A178350C2F44461DB18C9DAD18D78121.new()
    local Res = Papi:Double2Int(d)
    Papi = nil
    return Res
end
-- Dword转strin型
function publicApi.Dword2String(d)
    if not d then
        return ""
    end
    local Papi = PAPI_A178350C2F44461DB18C9DAD18D78121.new()
    local Res = Papi:Dword2String(d)
    Papi = nil
    return Res
end


-- 分割字符串
function publicApi.Split(szFullString, szSeparator)  
    local nFindStartIndex = 1  
    local nSplitIndex = 1  
    local nSplitArray = {}  
    while true do  
    local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex)  
    if not nFindLastIndex then  
        nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, string.len(szFullString))  
        break  
    end  
    nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1)  
    nFindStartIndex = nFindLastIndex + string.len(szSeparator)  
    nSplitIndex = nSplitIndex + 1  
    end  
    return nSplitArray  
end


-- 将数据块转换成字符串
function publicApi.udataToStr(Data, Len)
    local Papi = PAPI_A178350C2F44461DB18C9DAD18D78121.new()
    local Res = Papi.udataToStr(Data, Len)
    Papi = nil
    return Res
end

-- 将字符串转换成数据块
function publicApi.StrToudata(str)
    local Papi = PAPI_A178350C2F44461DB18C9DAD18D78121.new()
    local Data, Len = Papi.StrToudata(str)
    Papi = nil
    return Data, Len
end

-- 将obj转化为字符串
function publicApi.objToBase64(Buff, nSize)
    local Papi = PAPI_A178350C2F44461DB18C9DAD18D78121.new()
    local Res = Papi.objToBase64(Buff, nSize)
    Papi = nil
    return Res
end

-- 返回自系统开机以来的毫秒数
function publicApi.GetTickCount()
    local Papi = PAPI_A178350C2F44461DB18C9DAD18D78121.new()
    local Res = Papi.LuaGetTickCount()
    Papi = nil
    return Res
end

-- 将字符串切割成特定长度
function publicApi.CutString(str, nPerLen)
    local nT = string.len(str)
    local nI = 1
    
    local arrRet = {}
    while(nI <= nT)
    do
        local s = string.sub(str, nI, nI+nPerLen-1)
        table.insert(arrRet, s)
        nI = nI + nPerLen
    end
    
    return arrRet
end

-- 将sClientID字符串转成ClientId数字
function publicApi.GetServerKey(sClientId)
    local arr = publicApi.Split(sClientId, ":")  
    return arr[1]
end

-- 将sClientID字符串转成ClientId数字
function publicApi.SClientIdtoNumber(sClientId)
    local arr = publicApi.Split(sClientId, ":")  
    return tonumber(arr[2])
end



--  分割字符串    输入参数：  源字符串，分割服，输出参数：  分割后table
function publicApi.string_split(str, split_char)
    if str==nil or #str==0 then return {} end
    local sub_str_tab = {}
    while (true) do
        local pos = string.find(str, split_char)    
        if (not pos) then
            sub_str_tab[#sub_str_tab + 1] = str
            break
        end
        local sub_str = string.sub(str, 1, pos - 1)
        sub_str_tab[#sub_str_tab + 1] = sub_str
        str = string.sub(str, pos + 1, #str)
    end
    return sub_str_tab
end

-- 获取  某字符串 出现次数   例如 （"he#llo#world#aaa#","#" )  = 4 
function publicApi.Get_String_Arise_Count(sString,split_char)
   local String,nCount = string.gsub(sString,split_char,split_char ) 
   return nCount
end
 
-- 对象复制函数
function publicApi.Clone(object)
    local lookup_table = {}--复制元素查找表，为了防止递归无限复制元素
    local function _copy(object)
        if type(object) ~= "table" then --不是table元素就直接返回
            return object
        elseif lookup_table[object] then --是table但是已经在表里了，代表该table已经复制过了；即该table内如果有元素指向本身时候，复制该元素时就会查到表中有本身的记录，则直接把本体的table引用返回。
            return lookup_table[object] 
        end --如果是table并且没有复制过的table，则深度复制table中的数据，并把此table记录在表中，防止再次复制
        local new_table = {}
        lookup_table[object] = new_table --记录时如果Object是元素或函数，则下标是元素名字，如果是table，则下标是table的地址，所以不同层同名table也不会判定重复复制。
        for key, value in pairs(object) do
            new_table[_copy(key)] = _copy(value)
        end
        return new_table
    end
    return _copy(object)
end

-- 文件复制
function publicApi.copyfile(source, destination)
    sourcefile = io.open(source, "r")
    destinationfile = io.open(destination, "w")

    destinationfile:write(sourcefile:read("*all"))

    sourcefile:close()
    destinationfile:close()
end

function publicApi.TableEqual(a, b)
	if #a ~= #b then
		return false
	end
	table.sort(a,function(n,m) return n>m end)
	table.sort(b,function(n,m) return n>m end)
	for i=1,#a do
		if a[i]~=b[i] then
			return false
		end
	end
	return true
end

function publicApi.ShuffleArr(t)
    if type(t)~="table" then
        return
    end
    local tab={}
    local index=1
    while #t~=0 do
        local n=math.random(0,#t)
        if t[n]~=nil then
            tab[index]=t[n]
            table.remove(t,n)
            index=index+1
        end
    end
    return tab
end

function publicApi.FindKeyByVal(tTable, nval)
    if (type(tTable) ~= "table" or tTable == nil) then
        return nil
    end
    for key ,val in pairs(tTable) do
        if (val == nval) then
            return key         
        end
    end
    return nil
end

function publicApi.FindValByKey(tTable, nkey)
    if (type(tTable) ~= "table" or tTable == nil) then
        return nil
    end
    for key ,val in pairs(tTable) do
        if (key == nkey) then
            return val         
        end
    end
    return nil
end

-- 获取 UUID  唯一标识
function publicApi.CreateUUID() 
    local template ="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" 
    d = io.open("/dev/urandom", "r"):read(4) math.randomseed(os.time() + d:byte(1) + (d:byte(2) * 256) + (d:byte(3) * 65536) + (d:byte(4) * 4294967296)) 
    return string.gsub(template, "x", function (c) 
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb) 
        return string.format("%x", v) end) 
end

--创建一个唯一种子
function publicApi.CreateUniqueSeed()
    d = io.open("/dev/urandom", "r"):read(4) 
    local nRet = tostring(os.time()):reverse():sub(1, 7) + d:byte(1) + (d:byte(2) * 256) + (d:byte(3) * 65536) + (d:byte(4) * 4294967296)
    return nRet
end

--混乱数组元素 arrOld:数组, nBegin:混乱的起始坐标, nEnd:混乱的结束坐标
function publicApi.RandomArr(arrOld, nBegin, nEnd)
    local nTotalCnt = nEnd or #arrOld
    local _nBegin = nBegin or 1

    local nIdx = 0
    while(nIdx < nTotalCnt)
    do
        local nPos = math.random(_nBegin, nTotalCnt-nIdx)
        local tmp = arrOld[nPos]
        arrOld[nPos] = arrOld[nTotalCnt - nIdx]
        arrOld[nTotalCnt - nIdx] = tmp
        nIdx = nIdx + 1
    end
end

-- 当天最晚的时间
function publicApi.GetNextDayTime(timeString)  
    local Y = string.sub(timeString , 1, 4)  
    local M = string.sub(timeString , 6, 7)  
    local D = string.sub(timeString , 9, 10)  
    local h = string.sub(timeString , 12,13)  
    local m = string.sub(timeString , 15,16)  
    local s = string.sub(timeString , 18,19) 
    local tRet = {year=Y, month=M, day=D, hour=23,min=59,sec=59} 
    return os.time(tRet)  
end

-- 仅保留n位有效小数
function publicApi.Floor_n_old(nNumber,n)
    local  function IsEqual(a, b )
		local eps_0 = 1.0e-6
		local isEqualFlag = false;
         if  math.abs(a-b) <= eps_0  then
             isEqualFlag = true;
		end
		return isEqualFlag
	end

    nNumber = nNumber * math.pow(10,n)
    if nNumber > 0 then
		if  IsEqual( nNumber, math.ceil( nNumber )) then -- 两者接近
			nNumber = math.ceil( nNumber )
		else
			nNumber=math.floor(nNumber)
		end
    elseif nNumber < 0 then
        if IsEqual( nNumber, math.floor( nNumber ))  then -- 两者接近
			nNumber=math.floor(nNumber)
		else
			nNumber=math.ceil(nNumber)
		end
    end
    return  nNumber * math.pow(10,-n)
end

function publicApi.Floor_n(x, n)
    if x == 0 then
        return 0
    end
    local factor = math.pow(10, n)
    local eps = 1e-12
    if x >= 0 then
        return math.floor((x + eps) * factor) / factor
    else
        return math.ceil((x - eps) * factor) / factor
    end
end

function publicApi.Ceil_n(nNumber, n)
    local factor = math.pow(10, n)
    local eps = 1e-12
    -- 真正的向上取整：只要有小数就进位
    return math.ceil(nNumber * factor - eps) / factor
end

-- 仅保留1位有效小数
function publicApi.Floor_1(nNumber)
    local factor = 10
    if nNumber >= 0 then
        return math.floor(nNumber * factor) / factor
    else
        return math.floor(tonumber(string.format("%.1f", nNumber * factor))) / factor
    end
end

-- 仅保留2位有效小数
function publicApi.Floor_2_old(nNumber)
    local  function IsEqual(a, b )
		local eps_0 = 1.0e-6
		local isEqualFlag = false;
         if  math.abs(a-b) <= eps_0  then
             isEqualFlag = true;
		end
		return isEqualFlag
	end

    nNumber = nNumber * 100
    if nNumber > 0 then
		if  IsEqual( nNumber, math.ceil( nNumber )) then -- 两者接近
			nNumber = math.ceil( nNumber )
		else
			nNumber=math.floor(nNumber)
		end
    elseif nNumber < 0 then
        if IsEqual( nNumber, math.floor( nNumber ))  then -- 两者接近
			nNumber=math.floor(nNumber)
		else
			nNumber=math.ceil(nNumber)
		end
    end
    return nNumber / 100
end

function publicApi.Floor_2(nNumber)
    if not nNumber then
        return 0
    end
    local sign = nNumber >= 0 and 1 or -1
    nNumber = math.abs(nNumber) * 100
    nNumber = math.floor(nNumber + 0.5)  -- 四舍五入
    return sign * nNumber / 100
end

function publicApi.Round_n(value, decimals)
    local multiplier = 10 ^ decimals
    return math.floor(value * multiplier + 0.5) / multiplier
end

--保留3位数向下取整
function publicApi.Floor_3(nNumber)
    nNumber = nNumber * 1000
    nNumber=math.floor(nNumber)
    return  nNumber / 1000
end

function publicApi.DealFloat(nNumber)
    local goldStr = string.format("%.2f", nNumber)
	local gold = tonumber(goldStr) or 0
    return gold
end


-- tZJ = {}
-- tZJ.dScore = 2468.0

-- tData = {}
-- tData[1] = {}
-- tData[1].nUserID = 1
-- tData[1].dScore = 3402.0
-- tData[1].dWinLoss = -1000.00

-- tData[2] = {}
-- tData[2].nUserID = 2
-- tData[2].dScore = 2600.0
-- tData[2].dWinLoss = 5000.00

-- tData[3] = {}
-- tData[3].nUserID = 3
-- tData[3].dScore = 3328.65
-- tData[3].dWinLoss = -5000.00

-- tData[4] = {}
-- tData[4].nUserID = 4
-- tData[4].dScore = 2120.0
-- tData[4].dWinLoss = 5000.00


-- 有庄游戏的算分
function QZCalculateItem(dSrcVal, tData, nWin)
    local dZjval = 0.00

    local nCount = 0
    while (dSrcVal > 0.0)
    do
        local dWin = 0.00
        dZJSum = 0.00

        for idx ,tObj in ipairs(tData) do
            if tObj.nWin == nWin and tObj.dMin > 0 then
                dZJSum = dZJSum + math.abs(tObj.dWinLoss)
            end
        end

        if dZJSum == 0.00 then
            break
        end

        for idx ,tObj in ipairs(tData) do
            if tObj.nWin == nWin and tObj.dMin > 0 then
                local dValTmp = dSrcVal * math.abs(tObj.dWinLoss) / dZJSum -- 玩家实际获得的金币
                if tObj.dMin < dValTmp then -- 以小博大情况
                    dValTmp = tObj.dMin -- 只能赢取身上的金币值
                end

                tObj.dRes = tObj.dRes + dValTmp
                tObj.dMin = tObj.dMin - dValTmp
                dWin = dWin + dValTmp
            end
        end

        dZjval = dZjval + dWin
        dSrcVal = dSrcVal - dWin -- 可赔付的钱 - 第一次分配的钱

        if math.abs(publicApi.Floor_3(dSrcVal)) < 0.001 then
            -- logger:debug("min :"..dSrcVal)
            break
        end

        -- logger:debug("dSrcVal:"..dSrcVal)
        nCount = nCount + 1
        assert(nCount < 10)
    end

    return dZjval
end

function publicApi.QiangZhuangCalculate(tZJ, tData)

    local dZJWinSum = 0.00    -- 庄家总赢理论值
    local dZJLossSum = 0.00   -- 庄家总输理论值

    logger:debug('ZJ Score :'..tZJ.dScore)

    for idx ,tObj in ipairs(tData) do

        tObj.dRes = 0.00
        tObj.nWin = 0

        if tObj.dWinLoss > 0.00 then
            dZJLossSum = dZJLossSum + tObj.dWinLoss
            tObj.nWin = 1
            -- 获取庄家真正要赔付的钱
            if tObj.dWinLoss > tObj.dScore then
                tObj.dMin = tObj.dScore
            else
                tObj.dMin = tObj.dWinLoss
            end
        elseif tObj.dWinLoss < 0.00 then
            dZJWinSum = dZJWinSum + math.abs(tObj.dWinLoss)
            tObj.nWin = 2
            -- 获取庄家真正获得的钱
            if math.abs(tObj.dWinLoss) > tObj.dScore then
                tObj.dMin = tObj.dScore
            else
                tObj.dMin = math.abs(tObj.dWinLoss)
            end
        end

        logger:debug('UserID:'..tObj.nUserID..', Score:'..tObj.dScore..', Win:'..tObj.dWinLoss)
    end

    -------------------------------------------------------
    -- 计算庄家获得的钱，还有输家真正输的钱
    -------------------------------------------------------

    -- logger:debug('-------c win')

    local dSrcWin = dZJWinSum       -- 分配给庄家的那个总金币
    if tZJ.dScore < dSrcWin then    -- 以小博大情况
        dSrcWin = tZJ.dScore        -- 只能赢本金
    end

    local dZjWin = QZCalculateItem(dSrcWin, tData, 2)
    for idx ,tObj in ipairs(tData) do
        if tObj.nWin == 2 then
            tObj.dRes = tObj.dRes * -1  -- 输钱玩家，变负数
        end
    end

    -------------------------------------------------------
    -- 计算庄家赔付的钱，还有赢家真正赢的钱
    -------------------------------------------------------

    -- logger:debug('-------c loss')

    local dSrcLoss = dZJLossSum -- 庄家赔付给赢家的总金币(理论值)
    if dZjWin + tZJ.dScore < dSrcLoss then -- 庄家不够赔付 
        dSrcLoss = dZjWin + tZJ.dScore   -- 只能赔付庄家身上的钱
    end

    local dZjLoss = QZCalculateItem(dSrcLoss, tData, 1) -- 庄家给赢家的赔付

    -- 庄家的输赢
    tZJ.dRes = dZjWin - dZjLoss

    logger:debug('------------------------------------------')
    logger:debug('ZJ Res :'..tZJ.dRes)
    for idx ,tObj in ipairs(tData) do
        logger:debug('UserID:'..tObj.nUserID..', Res:'..tObj.dRes)
    end
end



--时间 =路程(nCap)/速度(理论值占比)
local function GetSortFunction(nFormulaSum)
	local _ForSort=function(a,b)
		local nCap=math.min(a.nFormulaValue,a.nTakeIn)
		local nV =a.nFormulaValue/nFormulaSum
		local nCapB=math.min(b.nFormulaValue,b.nTakeIn)
		local nVB =b.nFormulaValue/nFormulaSum
		local nA =nCap/nV
		local nB =nCapB/nVB
		return nA<nB
	end
	return _ForSort
end
--arrInfo ={{nSitId=,nTakeIn=,nFormulaValue=},{nSitId=,nTakeIn=,nFormulaValue=}}
--将nGoldForDistribute按比例分给arrInfo中的各玩家,为了确保一次刚好分完，会对arrInfo排序
local function DistributeGold(nGoldForDistribute,nFormulaSum,arrInfo)
	table.sort(arrInfo,GetSortFunction(nFormulaSum))
	local arrGoldGet ={}
	for _,v in ipairs(arrInfo) do
		local nCapGold =math.min(v.nFormulaValue,v.nTakeIn)
		local lv =0
		if nFormulaSum~= 0 then
			lv =v.nFormulaValue/nFormulaSum
		end
		local nGoldChange =math.min( lv*nGoldForDistribute,nCapGold)
		nFormulaSum =nFormulaSum -v.nFormulaValue
		nGoldForDistribute=nGoldForDistribute-nGoldChange
		table.insert(arrGoldGet,{nGoldChange=nGoldChange,nSitId=v.nSitId,nTakeIn=v.nTakeIn,nFormulaValue=v.nFormulaValue})
	end
	return arrGoldGet
end
--local arrLostXianJia ={{nSitId=,nTakeIn=,nFormulaValue=},{nSitId=,nTakeIn=,nFormulaValue=}}
local function _AuxCal(nZhuangTakeIn,arrUsers)
	local nSumWeigh =0									
	local nWinLostCan =0								
	for _,item in ipairs(arrUsers) do
		nWinLostCan =nWinLostCan +math.min(item.nFormulaValue,item.nTakeIn)
		nSumWeigh =nSumWeigh+item.nFormulaValue
	end
	local nWinLostCan =math.min(nZhuangTakeIn,nWinLostCan) 
	return nSumWeigh,nWinLostCan
end
local function _CalWinLost(nZhuangTakeIn,arrUsersOfLost,arrUsersOfWin)
	--先计算庄赢
	local nSumWeighOfLost,nZhuangGoldWin =_AuxCal(nZhuangTakeIn,arrUsersOfLost)		--nZhuangGoldWin表示庄家赢得的分数
	local arrGoldLost =DistributeGold(nZhuangGoldWin,nSumWeighOfLost,arrUsersOfLost)  --arrGoldLost表示闲家输掉的分数
	--后计算庄输
	local nSumWeighOfWin,nZhuangGoldLost =_AuxCal(nZhuangTakeIn+nZhuangGoldWin,arrUsersOfWin)	 --nZhuangGoldLost表示庄家输掉的分数
	local arrGoldWin =DistributeGold(nZhuangGoldLost,nSumWeighOfWin,arrUsersOfWin) --arrGoldWin表示闲家赢得的分数
	--输了的玩家，将其符号由正改为负，表示输
	for _,item in ipairs(arrGoldLost) do
		item.nGoldChange= -item.nGoldChange
	end
	return arrGoldLost,arrGoldWin,(nZhuangGoldWin-nZhuangGoldLost)
end

-- QiangZhuangCalculate替代品
publicApi._CalWinLost=_CalWinLost
--[[
    --运行
    local nZhuangTakeIn =1000
    local arrUsersOfLost ={{nSitId=1,nTakeIn=500,nFormulaValue=200},{nSitId=2,nTakeIn=500,nFormulaValue=1000}}
    local arrUsersOfWin ={{nSitId=3,nTakeIn=500,nFormulaValue=100},{nSitId=4,nTakeIn=100,nFormulaValue=50}}
    local arrL,arrW,Z =_CalWinLost(nZhuangTakeIn,arrUsersOfLost,arrUsersOfWin)
    Print(arrL)
    Print(arrW)
    print(Z)

    --输出
    nFormulaValue:1000 nSitId:2 nTakeIn:500 nGoldChange:-500
    nFormulaValue:200 nSitId:1 nTakeIn:500 nGoldChange:-200.0
    ------------
    nFormulaValue:100 nSitId:3 nTakeIn:500 nGoldChange:100.0
    nFormulaValue:50 nSitId:4 nTakeIn:100 nGoldChange:50.0
    ------------
    550
]]


--接口适配
local function _WrapCal(tZJ, tData)
	local nZhuangTakeIn =tZJ.dScore
	local arrXianJia_Lost ={}
	local arrXianJia_Win ={}
	for nSitId,v in ipairs(tData) do
		if v.dWinLoss<0 then
			table.insert(arrXianJia_Lost,{nSitId=nSitId,nTakeIn=v.dScore,nFormulaValue=math.abs(v.dWinLoss)})
		else
			table.insert(arrXianJia_Win,{nSitId=nSitId,nTakeIn=v.dScore,nFormulaValue=v.dWinLoss})
		end
	end
	local  arrXiaGoldChange_Lost,arrXiaGoldChange_Win,nZhuangGoldChange =_CalWinLost(nZhuangTakeIn,arrXianJia_Lost,arrXianJia_Win)
	tZJ.dRes=nZhuangGoldChange
	for _,v in ipairs(arrXiaGoldChange_Lost) do
		tData[v.nSitId].dRes =v.nGoldChange
	end
	for _,v in ipairs(arrXiaGoldChange_Win) do
		tData[v.nSitId].dRes =v.nGoldChange
	end
end
--publicApi.QiangZhuangCalculate =_WrapCal


--通比游戏算分
function publicApi.TongBiCalculate(tWin, tData)
    local dZJWinSum = 0.00    -- 通比总赢理论值

    logger:debug('tWin Score :'..tWin.dScore)
    tWin.dRes = 0.00
    for nIndex , tObj in pairs(tData) do
        tObj.dRes = 0.00
        tObj.dRes = tObj.dWinLoss
        if tObj.dScore < math.abs( tObj.dRes ) then
            tObj.dRes = 0 - tObj.dScore
        end

        if math.abs( tObj.dRes ) > tWin.dScore then
            tObj.dRes = 0 - tWin.dScore
        end
        logger:debug('UserID:'..tObj.nUserID..', Score:'..tObj.dScore..', Win:'..tObj.dWinLoss)
        tWin.dRes = tWin.dRes + math.abs(tObj.dRes)
    end
    logger:debug('------------------------------------------')
    logger:debug('tWin Res :'..tWin.dRes)
    for idx ,tObj in ipairs(tData) do
        logger:debug('UserID:'..tObj.nUserID..', Res:'..tObj.dRes)
    end
end


-- 热更新
-- nTimeID 热更的定时器ID，使用定时器检查
-- tPrivateModule = {[Table]=  "Table",[XXX] = "User"} -- 值是文件名 key,旧的模块，val 新的的模块
function publicApi.PublicModuleUpdate(nTimeID,tPrivateModule)
    -- local nTime = base.GetTime()
    local sFileName = ""
    for sOldModuleName, sNewModuleName in pairs(tPrivateModule) do
        -- base.Log("tTemp Name: %s ", sNewModuleName)
        -- require(sOldModuleName)
        -- local tTemp = require(sNewModuleName)
        -- base.Log("tTemp GoldOfFreeRoom: %d ", tTemp.GoldOfFreeRoom)
        -- --base.Log("tTemp GoldOfFreeRoom: %d ", Define.GoldOfFreeRoom)
        -- base.Log(" tTemp ddsdf : %s ", tostring(tTemp ))
        -- base.Log(" tostring(require(sOldModuleName) : %s ", tostring(require(sOldModuleName) ))
        tHotFix.HotUpdate(sOldModuleName,sNewModuleName)
        sFileName = sFileName.." "..sNewModuleName
    end
    base.TokenCallTimeID(nTimeID,1000 * 6, 1,publicApi.PublicModuleUpdate,nTimeID,tPrivateModule )
    -- base.Log("PublicModuleUpdateFile  热更新文件 %d毫秒 ", base.GetTime()-nTime)
end

-- 热更新文件
function publicApi.PublicModuleUpdateFile(nTimeID,sUpdataFile)
         
    -- publicApi.PublicModuleUpdate(nTimeID,{[sUpdataFile] = sUpdataFile}) -- 热更配置
end 


--根据ServerKey获得游戏名称和服务器id
--@params ServerKey 服务器key 如1F7B948C50EC47BB9D87C397C1BB6565_BaiRenZhaJinHua162884731479687933493_322
--@return sGameName：服务器名字，如BaiRenZhaJinHua， sServerId：服务器id，如322
function publicApi.GetGameNameByServerKey(ServerKey)
    if not ServerKey then
        return ""
    end
    ServerKey = publicApi.GetServerKey(ServerKey)
    local arr = publicApi.Split(ServerKey, '_')
    local sServerId = (arr and arr[3]) or "0"
    local sTwo = (arr and arr[2]) or ""
    local sGameName = string.match(sTwo,"%a+") or ""
    return sGameName,sServerId
end

-- 是否读取缓存还是获取最新数据
local tCache ={}
function publicApi.DoCache(spacetime, func,...)  
	local parameter ={...}
	local sparameter =table.concat(parameter,"_")
	tCache[func]=tCache[func] or {}
	local tCacheRlt =tCache[func][sparameter]
	if tCacheRlt and (os.time()-tCacheRlt.nTime) < spacetime then
		return table.unpack(tCacheRlt.arrRlt)
	end
	local arrRlt ={func(...)}
	tCache[func][sparameter] ={arrRlt=arrRlt,nTime=os.time()}
	return table.unpack(arrRlt)
end


--根据时区获取当前时间(以东八区为标准转换)
--@param sTimeZone 时区 如东八区="+8:00"  西八区="-8:00" 中时区="+0:00" 东西十二区="+12:00"
--return nTime=时间戳  tDate = 等同os.date("*t")的结构
function publicApi.GetTimeByTimeZone(sTimeZone)
	sTimeZone = sTimeZone or "+8:00"
    local arr = publicApi.Split(sTimeZone,":")
    local nTimeZone = tonumber(arr[1]) or 8
    local nDiffHour = nTimeZone - 8 --时区与东八区之间的小时差

    local nTime = os.time()
    nTime = nTime + nDiffHour*3600
    
    local tDate = os.date("*t",nTime)

    return nTime,tDate
end

--获取本日0点时间戳
function publicApi.GetTodayZero()
    local tDate = os.date("*t")
    tDate.hour=0
    tDate.min=0
    tDate.sec=0
    return os.time(tDate)
end

--获取本周0点时间戳
function publicApi.GetWeekZero()
    local nZeroTime = publicApi.GetTodayZero()
    local tDate = os.date("*t")
    if tDate.wday==1 then
        --周日
        return nZeroTime - 6*60*60*24
    elseif tDate.wday==2 then
        --周一
        return nZeroTime
    else
        --周二~周六
        return nZeroTime - (tDate.wday-2)*60*60*24
    end
end

-- 暂时处理浮点数据随机
function publicApi.RandDouble(v1, v2)

    local dRes = 0
    local ff =  function()
        v1 = tonumber(v1)
        v2 = tonumber(v2)

        dRes = v1

        local f = 100

        assert(v1 <= v2)
        if v1 == v2 then
            return v1
        end

        local item = 0.0
        local c = v2 - v1
        if c >= f then
            item = c / f
            dRes = tonumber(math.random(1, f)) * item + v1
        end
    end

    local isSuccee, sErr = pcall(ff)  
    if not isSuccee then
        logger:error(sErr)
    end

    return dRes
end

--是否是德州类的游戏(德州，短牌，奥马哈)
function publicApi.IsTexasClassGame(nGameId)
    local arrGameList = {}
    arrGameList.nTexas = 125
    arrGameList.nTexasOmaha = 126
    arrGameList.nTexasShortCard = 175

    for _,v in pairs(arrGameList) do
        if nGameId==v then
            return true
        end
    end
    return false
end

--是否是牛牛类的游戏(抢庄牛)
function publicApi.IsNiuNiuClassGame(nGameId)
    local arrGameList = {}
    arrGameList.nClubQiangZhuangNiu = 178

    for _,v in pairs(arrGameList) do
        if nGameId==v then
            return true
        end
    end
    return false
end

-- 服务器是否 维护
function publicApi._IsServerIdMainTain(nServerId)    
    local nStatus = RedisCahche.GetServerState(nServerId) 
    if nStatus > 1 then  -- 服务器状态 0:未启用 1:正常 2:维护 3:测试 4:进程没开 (默认1)   
        return true 
    else
        return false
    end 
end

-- 获取不维护的 key 
function publicApi._GetNotMaintianServerKey(arrServerKey)
    local arrKey = {}
    for _,sKey in pairs(arrServerKey) do
        local nServerId =tonumber(string.match(sKey,"_(%d+)")) 
        if not publicApi._IsServerIdMainTain(nServerId) then 
            table.insert(arrKey,sKey)
        end 
    end     
    return arrKey
end


-- 通知Web 服公共接口
function publicApi.PublicPushWebHttp(sHttp)    
    local arrWKey = base.GetSrcAllKey(tname.web) or {}
    if #arrWKey < 1 then return end
    NoticeMess.NoticeMess(arrWKey[1],sHttp) 
end



return publicApi
