local tGConfig = require("GConfig")
local mlogger = require("logger")
local tJson = require("cjson")
PublicMath = {}

--简单复制表
function  PublicMath.CopyTable(tNew, tOld)
    for i, v in pairs(tOld) do
        tNew[i] = v
    end
end

-- 复制牌堆
function PublicMath.MakeCard(tCard)
    for _, v in pairs(tGConfig.Card) do
        table.insert(tCard,v)
    end
end

--随机数组
function PublicMath.Random(arr)
    local tmp, index
    for i=1, #arr-1 do
        index = math.random(i, #arr)
        if i ~= index then
            tmp = arr[index]
            arr[index] = arr[i]
            arr[i] = tmp
        end
    end
end

-- 随机牌堆
function PublicMath.RandCard()
    local tNew = {}
	PublicMath.MakeCard(tNew)
    PublicMath.Random(tNew)
    mlogger:info(string.format("随机牌堆的数据：%s", tJson.encode(tNew)))
    return tNew
end

--查找牌堆 
function PublicMath.FinCard(tCard,nCard)
    for k, v in pairs(tCard) do
        if v == nCard then
            return k
        end
    end

    return nil
end

-- 牌堆移动一些牌到一个数组
function PublicMath.MoveToCard(tOldCard,tObjectCard,tNewCard)

    for k, v in pairs (tOldCard) do
        for k1, v1 in pairs(tObjectCard) do
            if (v == v1) then
                table.insert(tNewCard, v)
                table.remove(tObjectCard, k1)
                break
            end
        end
    end

    -- 移除数组
    while #tObjectCard do
        for k, v in pairs (tOldCard) do
            
            if (v == tObjectCard[1]) then
                 table.remove(tObjectCard, 1)
                 table.remove(tOldCard, k)
                break
            end
           
        end
    end
    
end
--从新组合牌
function PublicMath.ChongZu(tCards,i,j)
   
   local tCard ={}
    local temp = {}
    for k,v in pairs(tCards) do
        if k == i then
            tCard [v] = v
        elseif k == j then
            tCard [v] = v
        else
            table.insert(temp,v)
        end
    end
   
    for k, v in pairs(tCard) do
        table.insert(temp, v )
    end
    return temp
end

-- 乱序数组算法
function PublicMath.Shuffle(t)
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
-- 通过玩法查找 对应的key(对比谁大)
function PublicMath.FindKeyByID(tPlayFanc, nID)
    for i = 1, #tPlayFanc do
        if (tPlayFanc[i] == nID) then
            return i
        end
    end
end

--通过key查找对应的倍数
function PublicMath.FindFanByKey(tPlayFan, nKey)
    for i = 1, #tPlayFan do
        if (i == nKey) then
            return tPlayFan[i]
        end
    end
end
--查找牌点数
function PublicMath.FindPosByNumber(tPlayFanc, nID)
    for i = 1, #tPlayFanc do
        if (tPlayFanc[i] == nID) then
            return i
        end
    end
end

-- 比牌
function PublicMath.Compare(tTableObj,tCard1,tCard2)
	if (PublicMath.FindKeyByID(tTableObj.tPlayFan,tCard1.NiuWhat) > PublicMath.FindKeyByID(tCard1.NiuWhat)) then
		return 1

	elseif PublicMath.FindKeyByID(tTableObj.tPlayFan,tCard1.NiuWhat) < PublicMath.FindKeyByID(tCard1.NiuWhat) then
		return 2
	elseif PublicMath.FindKeyByID(tTableObj.tPlayFan,tCard1.NiuWhat) == PublicMath.FindKeyByID(tCard1.NiuWhat) then -- 相等比点数和花色
		if ( (PublicMath.MaxCard(tCard1.HandCard).Card_Number > PublicMath.MaxCard(tCard2.HandCard).Card_Number) or --最大的牌
			 (PublicMath.MaxCard(tCard1.HandCard).Card_Number == PublicMath.MaxCard(tCard2.HandCard).Card_Number and  PublicMath.MaxCard(tCard1.HandCard).Card_Type == self.MaxCard(tCard2.HandCard).Card_Type ) ) then
			return 1
		else
			return 2
		end

	end
end

-- 查找最大的那张牌
function PublicMath.MaxCard(tCards)
	local Max_Card = {}
	Max_Card = tCards[1]
	for _, v in pairs(tCards) do
		if  (v.Card_Number > Max_Card.Card_Number) or (v.Card_Number == Max_Card.Card_Number and v.Card_Type > Max_Card.Card_Type)  then
			Max_Card = v
		end
	
	end
	return Max_Card
end

--查找牌里面最大的那张牌
function PublicMath.GetMaxCard(tCards)
    local Max_Card = {}
    Max_Card = tCards[1]
    for _, v in pairs(tCards) do
        if (v % tGConfig.BaseNumber > Max_Card % tGConfig.BaseNumber) then
            Max_Card = v --点数大则大
        elseif( v % tGConfig.BaseNumber) == (Max_Card % tGConfig.BaseNumber) then
            if ( math.floor(v / tGConfig.BaseNumber) >  math.floor(Max_Card / tGConfig.BaseNumber)) then --一样点数比花色
                Max_Card = v
            end
        end
    end

    return Max_Card
end

--比牌
function PublicMath.ComepareCard(tTableObj,tCards1, tCards2)
    if (PublicMath.FindKeyByID(tTableObj.tPlayFan,tCards1.NiuWhat) > PublicMath.FindKeyByID(tTableObj.tPlayFan,tCards2.NiuWhat)) then
        return 1
    elseif PublicMath.FindKeyByID(tTableObj.tPlayFan,tCards1.NiuWhat) < PublicMath.FindKeyByID(tTableObj.tPlayFan,tCards2.NiuWhat) then
        return 2
    elseif PublicMath.FindKeyByID(tTableObj.tPlayFan,tCards1.NiuWhat) == PublicMath.FindKeyByID(tTableObj.tPlayFan,tCards2.NiuWhat) then -- 相等比点数和花色
        local nCard1 =  PublicMath.GetMaxCard(tCards1.HandCard)
        local nCard2 =  PublicMath.GetMaxCard(tCards2.HandCard)
        if ( nCard1 % tGConfig.BaseNumber >  nCard2 % tGConfig.BaseNumber )  then
            return 1 
        elseif ( nCard1 % tGConfig.BaseNumber <  nCard2 % tGConfig.BaseNumber )  then
            return 2
        elseif ( nCard1 % tGConfig.BaseNumber ==  nCard2 % tGConfig.BaseNumber ) then --点数一样比花色
            if ( math.floor(nCard1 / tGConfig.BaseNumber ) >   math.floor (nCard2 / tGConfig.BaseNumber ) ) then
                return  1
            else  
                return  2
            end
        
        end
    end
end


-- 把升序
function PublicMath.PaiXu(tTabelObje, tShouPaiArr)

    local tMaxCard = table.remove(tShouPaiArr, 1) 
    for i = 1, #tShouPaiArr - 1  do
        local  tMaxCard = tShouPaiArr[i]
        for j = i + 1 , #tShouPaiArr do
            local ShouPai1 = {}
            local ShouPai2 = {}
            ShouPai1.NiuWhat = NiuNiuMath.getNiubyCards(NiuNiuMath.NumberToCount2(tMaxCard)).NiuWhat
            ShouPai1.HandCard = tMaxCard
    
            ShouPai2.NiuWhat = NiuNiuMath.getNiubyCards(NiuNiuMath.NumberToCount2(tShouPaiArr[j])).NiuWhat
            ShouPai2.HandCard = tShouPaiArr[i]
    
            if PublicMath.ComepareCard(ShouPai1, ShouPai2) == 2 then
                local  temp = tShouPaiArr[j]
                tShouPaiArr[j] = tMaxCard
                tMaxCard = temp
            end
        end

    end
    
    table.insert(tShouPaiArr, tMaxCard )
   
end


-- 把最大牌放最后面
function PublicMath.PaiXu2(tTabelObje, tShouPaiArr)

    local tMaxCard = table.remove(tShouPaiArr, 1) 
    for i = 1, #tShouPaiArr  do
        local ShouPai1 = {}
        local ShouPai2 = {}
        ShouPai1.NiuWhat = NiuNiuMath.getNiubyCards(NiuNiuMath.NumberToCount2(tMaxCard)).NiuWhat
        ShouPai1.HandCard = tMaxCard

        ShouPai2.NiuWhat = NiuNiuMath.getNiubyCards(NiuNiuMath.NumberToCount2(tShouPaiArr[i])).NiuWhat
        ShouPai2.HandCard = tShouPaiArr[i]
        mlogger:info(tJson.encode(NiuNiuMath.NumberToCount2(tMaxCard)))
        mlogger:info(tJson.encode(NiuNiuMath.NumberToCount2(tShouPaiArr[i])))

        mlogger:info(tJson.encode(ShouPai1))
        mlogger:info(tJson.encode(ShouPai2))
        if PublicMath.ComepareCard(tTabelObje,ShouPai1, ShouPai2) == 2 then
            local  temp = tShouPaiArr[i]
            tShouPaiArr[i] = tMaxCard
            tMaxCard = temp
        end

    end
    
    table.insert(tShouPaiArr, tMaxCard )
   
end

-- -- 牌大小排序
-- function PublicMath.ComepareCard2(tTableObj,tCardArr)
--     local tMaxCard = tCardArr[1]
--     for i = 1, #tCardArr do
--         local tCards1 = {}
--         tCards1.HandCard = tMaxCard 
--         tCards1.NiuWhat = NiuNiuMath.getNiubyCards()
--     end
-- end
-- 
return PublicMath