local tGConfig = require("GConfig")

NiuNiuMath = {
    PaiNumber = 14
}


-- 判断牛几的算法(只需牌的点数table = {1,2,3,4,5} )
function NiuNiuMath.getNiubyCards(cards)  
    local lave = 0     --余数  
    local ZuHePai = {}
    ZuHePai.NiuWhat = 0 -- 没牛
    ZuHePai.i =  1
    ZuHePai.j =  1
    -- for k ,v in pairs(cards) do
    --     base.Log(v)
    -- end
    if (NiuNiuMath.WuXiaoNiu(cards)) then
        ZuHePai.NiuWhat = tGConfig.GetPlayValue("五小")
    elseif (NiuNiuMath.IsSiZha(cards)) then
        ZuHePai.NiuWhat = tGConfig.GetPlayValue("四炸")
    elseif (NiuNiuMath.IsWuHuaNiu(cards)) then
        ZuHePai.NiuWhat = tGConfig.GetPlayValue("五花牛")
    else
        for i = 1,#cards do
            if  cards[i] >= 10 then
                lave = lave + 10  
            else
                lave = lave + cards[i]  
            end
            
        end  
        print(lave) 
        lave = lave % 10 
        print(lave) 
        for i = 1,#cards - 1 do  
            for j = i + 1,#cards do  
                if(NiuNiuMath.NumberToCount3(cards[i]) + NiuNiuMath.NumberToCount3(cards[j]) ) % 10 == lave then
                    ZuHePai.i =  i
                    ZuHePai.j =  j
                    if lave == 0 then  
                        ZuHePai.NiuWhat = 10 -- 牛牛
                    else  
                        ZuHePai.NiuWhat = lave -- 牛几
                    end  
                end  
            end  
        end  
    end

    return  ZuHePai
end  

--判断四张牌是否有牛{排数} 四张牌判断是否有牛
function NiuNiuMath.GetNiuCard(tCards)
    local lave = 0
    local ZuHePai = {}
    ZuHePai.NiuWhat = 0 -- 没牛
    ZuHePai.i =  1
    ZuHePai.j =  1

    for i = 1,#tCards do
      
        if  tCards[i] >= 10 then
            lave = lave + 10  
        else
            lave = lave + tCards[i]  
        end
        
    end  

    lave = lave % 10 
    base.Log(lave)
    for i = 1,#tCards do  
       local  nTemp = tCards[i]
       if nTemp >= 10 then
           nTemp = 10 
       end
       base.Log(i)
       base.Log(nTemp)
        if ( nTemp % 10  )== lave then
            base.Log(nTemp)
            ZuHePai.i = i
            if lave == 0 then  
                ZuHePai.NiuWhat = 10 -- 牛牛
            else  
                ZuHePai.NiuWhat = lave -- 牛几
            end  
            break
        end  
        
    end  

    return ZuHePai
end

-- 检查牌是否是大于等于牛牛的牌
function NiuNiuMath.CheckPai(cards)
    local a = NiuNiuMath.getNiubyCards(cards)
    
    if (a.NiuWhat == 10  or  a.NiuWhat ==101) then
        return true;
    elseif ( NiuNiuMath.IsWuHuaNiu(cards)) then
        return true;
    elseif (NiuNiuMath.IsSiZha(cards)) then
        return true;
    elseif (NiuNiuMath.WuXiaoNiu(cards)) then
        return true;
    else
        return false;
    end
end

-- 是不是五花牛
function NiuNiuMath.IsWuHuaNiu(cards)
    for i = 1,#cards do  
       if (cards[i] <= 10) then
            return false
       end
    end  
    return true;
end

-- 是不是四炸（排好序）
function NiuNiuMath.IsSiZha(cards)
   --table.sort(, )
   function NiuNiuMath.QuickSort_partition(t,l,h)
        local x = t[h]
        local i = l - 1
        for j=l,h do
            if t[j] < x then
                i = i+1
                t[j], t[i] = t[i], t[j]
            end
        end
        t[h], t[i+1] = t[i+1], t[h]
        return i+1
    end

    function NiuNiuMath.QuickSort(t,l,h)
        if l >= h then return end
        local p = NiuNiuMath.QuickSort_partition(t,l,h)
        NiuNiuMath.QuickSort(t,l,p-1)
        NiuNiuMath.QuickSort(t,p+1,h)
    end
   local temp = {}
    for k,v in pairs (cards) do
        table.insert(temp,v )
    end
    NiuNiuMath.QuickSort(temp, 1, #temp)
    for k,v in pairs (temp) do
       print(v)
    end
    if(temp[1] == temp[#temp - 1 ] or temp[2] == temp[#temp]) then -- 排好序只需判断第一次和第四张是否相同即可
        return true
    else
        return false;
    end
end

--是不是五小
function NiuNiuMath.WuXiaoNiu(cards)
    local nSum = 0;
    for i = 1,#cards  do  
        if (cards[i] >=5) then
             return false
        end
        nSum = nSum + cards[i]
     end  

     if (nSum <= 10) then
        return true
     else
        return false
     end
end

--从牌堆生成五小牌的key
function NiuNiuMath.MakeWuXiaoNiu(tArrPai)
    local tVal = {}
    for k, v in pairs(tArrPai) do
        if v % tGConfig.BaseNumber < 3 then
            table.insert(tVal, v )
            if #tVal >=5 then
                break;
            end
        end
    end
    return tVal
end

-- 从牌堆生成四炸的key 
function NiuNiuMath.MakeSiZha(tArrPai)
    local tVal = {}
    local tTotalKey = {}
    --初始化
    for i = 1, 13 do
        tTotalKey[i] = 0
    end
    --统计当前牌
    for k, v in pairs(tArrPai) do
         tTotalKey[v % tGConfig.BaseNumber] = tTotalKey[v % tGConfig.BaseNumber] + 1
    end
    local  value = 0
    --满足四炸的牌
    for k, v in pairs (tTotalKey) do
        if v >= 4 then
            value = k
        end
    end
    --索引key
    for k, v in pairs(tArrPai) do
        if v % tGConfig.BaseNumber == value  then
            table.insert(tVal, v)
        end
   end
    return tVal
end
-- 生成五花牛的key
function NiuNiuMath.MakeWuHuaNiu(tArrPai)
    local tVal = {}
    for k, v in pairs(tArrPai) do
        if v % 0x10 > 10 then
            table.insert(tVal,v)
            if #tVal >=5 then
                break
            end
          
        end
    end
    return tVal
end

--生成好牌
function NiuNiuMath.MakeGoodPai(tArrPai, tPlay)
    local nRondom  = math.Rondom(7, #tPlay)
    local nVal = tPlay[nRondom]
    local tPai = {}
    local nVal1 = 0
    local nVal2 =0
    if  nVal <= 10  then
        for i = 1,#tArrPai - 1 do  
            for j = i + 1,#tArrPai do  
                if(NiuNiuMath.NumberToCount3(tArrPai[i]) + NiuNiuMath.NumberToCount3(tArrPai[j]) ) % 10 == nVal then
                    nVal1 = tArrPai[i]
                    nVal2 =  tArrPai[j]
                    table.insert(tPai,tArrPai[i] )
                    table.insert(tPai,tArrPai[j] )
                   break
                end  
            end  
        end  
    end

    --抽出3张和10
    for k, nPai in pairs(tPai) do
        if nPai ~= nVal1 or  nVal2 ~= nPai then
            if NiuNiuMath.NumberToCount3(nPai) >= 10 then
                table.insert(tPai,nPai )
            end
        end
    end

    return tPai
end

-- 生成有牛的牌
function NiuNiuMath.MakeHaveNiu(tArrPai)
      --抽出3张有牛牌
      for i = 1, #tArrPai do
          
      end
   
end
-- 好牌排序 
function NiuNiuMath.PaiXu(tShouPaiArr)
    for k, tShouPai in pairs(tShouPaiArr) do
        tShouPai.nNiuWhat = NiuNiuMath.getNiubyCards(tShouPai.tShouPai)
    end

    local Max = 0
    for i = 1, #tShouPaiArr do
        Max = i
        for j = i + 1, #tShouPaiArr do
            if tShouPaiArr[i].nNiuWhat > tShouPaiArr[j].nNiuWhat then
                Max = j
                local  tTemp = {}
                tTemp = tShouPaiArr[j]
                tShouPaiArr[j] =  tShouPaiArr[i]
                tShouPaiArr[i] = tTemp
            end
        end
    end
end



--数字转化牌
function NiuNiuMath.NumberToCard(Number)
    local PuKeCard = {}
    PuKeCard.Card_Number = Number; -- 保存原始数据
    PuKeCard.Card_Type = math.floor(Number / tGConfig.BaseNumber); --取整为花色（1，方块 ... 4黑桃）
    PuKeCard.Card_Count = NiuNiuMath.NumberToCount(Number) -- 取余为点数
    PuKeCard.Card_String = NiuNiuMath.NumberToString(Number) --转成字符串
    return PuKeCard
end

-- 把数字数转化为点数
function NiuNiuMath.NumberToCount(Number)
    -- if (Number % tGConfig.BaseNumber >= 10) then 
    --     return 10
    -- else
    --     return (Number % tGConfig.BaseNumber)
    -- end
    return (Number % tGConfig.BaseNumber)
end  

-- 把数字数转化为点数（数组）
function NiuNiuMath.NumberToCount2(tNumber)
    local tCount = {}
    for i = 1, #tNumber do
        table.insert(tCount,NiuNiuMath.NumberToCount(tNumber[i]))
    end
    return tCount
end

function NiuNiuMath.NumberToCount3(Number)
    if (Number % tGConfig.BaseNumber >= 10) then 
        return 10
    else
        return (Number % tGConfig.BaseNumber)
    end
end
-- 牌转字符串
function NiuNiuMath.NumberToString(Number)
   
    local nType = math.floor(Number / tGConfig.BaseNumber) -- 取整为花色
    local nCount = Number % tGConfig.BaseNumber            -- 取余为牌
    --print(nCount,nType)
    local sType = ""
    local sCount = ""
    if (nType == 1) then
        sType = "◆"
    elseif (nType == 2) then
        sType = "♣"
    elseif (nType == 3) then
        sType = "♥"
    elseif (nType == 4) then
        sType = "♡"
    end
    if (nCount == 1) then
        sCount =  "A"
    elseif (nCount == 2) then
        sCount = "2"
    elseif (nCount == 3) then
        sCount = "3"
    elseif (nCount == 4) then
        sCount = "4"
    elseif (nCount == 5) then
        sCount = "5"
    elseif (nCount == 6) then
        sCount = "6"
    elseif (nCount == 7) then
        sCount = "7"
    elseif (nCount == 8) then
        sCount = "8"
    elseif (nCount == 9) then
        sCount = "9"
    elseif (nCount == 10) then
        sCount = "10"
    elseif (nCount == 11) then
        sCount = "J"
    elseif (nCount == 12) then
        sCount = "Q"
    elseif (nCount == 13) then
        sCount = "K"
    end
    return sType..sCount
end



function NiuNiuMath.zuhe(atable, n)
    if n > #atable then
        return {}
    end

    local len = #atable
    local meta = {}
    -- init meta data
    for i=1, len do
        if i <= n then
            table.insert(meta, 1)
        else
            table.insert(meta, 0)
        end
    end

    local result = {}

    -- 记录一次组合
    local tmp = {}
    for i=1, len do
        if meta[i] == 1 then
            table.insert(tmp, atable[i])
        end
    end
  
    -- 判断有牛牌返回（用于三张手牌判断）
    local lave = 0
    for k, v in pairs(tmp) do
        lave = lave +  NiuNiuMath.NumberToCount3(v)
    end
    if lave % 10 == 0 then
        return tmp
    end

    table.insert(result, tmp)
    while true do
        -- 前面连续的0
        local zero_count = 0
        for i=1, len-n do
            if meta[i] == 0 then
                zero_count = zero_count + 1
            else
                break
            end
        end
        -- 前m-n位都是0，说明处理结束
        if zero_count == len-n then
            break
        end

        local idx
        for j=1, len-1 do
            -- 10 交换为 01
            if meta[j]==1 and meta[j+1] == 0 then
                meta[j], meta[j+1] = meta[j+1], meta[j]
                idx = j
                break
            end
        end
        -- 将idx左边所有的1移到最左边
        local k = idx-1
        local count = 0
        while count <= k do
            for i=k, 2, -1 do
                if meta[i] == 1 then
                    meta[i], meta[i-1] = meta[i-1], meta[i]
                end
            end
            count = count + 1
        end

        -- 记录一次组合
        local tmp = {}
        for i=1, len do
            if meta[i] == 1 then
                table.insert(tmp, atable[i])
            end
        end
        -- 判断有牛牌返回（用于三张手牌判断）
        local lave = 0
        for k, v in pairs(tmp) do
            lave = lave +  NiuNiuMath.NumberToCount3(v)
        end
        if lave % 10 == 0 then
            return tmp
        end
        table.insert(result, tmp)
    end

    return {}
end

return NiuNiuMath