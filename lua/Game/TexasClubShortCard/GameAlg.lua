local Alg ={}
local bit = require("bit")
local arrPackOfCards={
    0x11,0x16,0x17,0x18,0x19,0x1a,0x1b,0x1c,0x1d,	--方块 A~K
    0x21,0x26,0x27,0x28,0x29,0x2a,0x2b,0x2c,0x2d,	--梅花 A~K
    0x31,0x36,0x37,0x38,0x39,0x3a,0x3b,0x3c,0x3d,	--红桃 A~K
    0x41,0x46,0x47,0x48,0x49,0x4a,0x4b,0x4c,0x4d,   --黑桃 A~K
}

--0没牌或不可见 1高牌 2对子 3两对 4三条 5顺子 6葫芦 7同花 8四条(金刚) 9同花顺 10皇家同花顺

--将0x11 0x21 0x31 0x41 转换成 0x1E 0x2E 0x3E 0x4E,其它不变
local function TurnCard(nCard)
	if (nCard %16)==1 then
		return nCard+13
	end
	return nCard
end
local function TurnCardBack(nCard)
	if (nCard %16)==14 then
		return nCard-13
	end
	return nCard
end

local function DianShu(nCard)
	if nCard==nil then return 0 end
	local nP = (nCard %16)
	return nP
end
local function HuaSe(nCard)
    -- return (nCard //16)
	return bit.rshift(nCard,4)
end
local function _CopyArr(arr)
	local arrCopy ={}
	for _,v in ipairs(arr) do
		table.insert(arrCopy,v)
	end
	return arrCopy
end
local function random_array(arr)
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
local function _removeItem( list,item,isRemoveAll)
    local rmCount = 0
    for i = 1,#list do
        if list[i - rmCount] == item then
            table.remove(list,i - rmCount)
            if isRemoveAll then
                rmCount = rmCount + 1
            else
                return 1
            end
        end
    end
	return rmCount
end

local function FC2(arr)
	local tem ={}
	if #arr>=2 then
		for i=1,#arr-1 do
			for j=i+1,#arr do
				table.insert(tem,{arr[i],arr[j]})
			end
		end
	end
	return tem
end

local function FC3(arr)
	local tem ={}
	if #arr>=3 then
		for i=1,#arr-2 do
			for j=i+1,#arr-1 do
				for k=j+1,#arr do
					table.insert(tem,{arr[i],arr[j],arr[k]})
				end
			end
		end
	end
	return tem
end

--按点数和花色由大到小排序 (A为最大的牌,到K)
local function _SortByDesc(a,b)
	local nPa,nPb =(a %16),(b %16)
	if nPa==1 then nPa=0x0E end
	if nPb==1 then nPb=0x0E end
	if nPa>nPb then
		return true
	elseif nPa<nPb then
		return false
	end
	return bit.rshift(a,4) > bit.rshift(b,4)
	-- return ((a//16) >(b//16))
end


local function CardsPointAnaly(arrCard)
	local tPointToCnt ={}
	for _,nCard in ipairs(arrCard) do
		local nP =DianShu(nCard)
		tPointToCnt[nP] =tPointToCnt[nP] or 0
		tPointToCnt[nP] =tPointToCnt[nP] +1
	end
	local arr4={}
	local arr3={}
	local arr2={}
	local arr1={}
	local arrNoRepeat={}
	for nPoint,nCnt in pairs(tPointToCnt) do
		if nCnt>=4 then
			table.insert(arr4,nPoint)
		elseif nCnt==3 then
			table.insert(arr3,nPoint)
		elseif nCnt==2 then
			table.insert(arr2,nPoint)
		elseif nCnt==1 then
			table.insert(arr1,nPoint)
		end
		table.insert(arrNoRepeat,nPoint)
	end
	table.sort(arr4,_SortByDesc)
	table.sort(arr3,_SortByDesc)
	table.sort(arr2,_SortByDesc)
	table.sort(arr1,_SortByDesc)
	table.sort(arrNoRepeat,_SortByDesc)
	return arr4,arr3,arr2,arr1,arrNoRepeat
end


local function _GetCardsTo(arrCard,arrRec,nGetCnt,nPoint)
	local arrRemain ={}
	local nCurGetCnt =0
	for _,nCard in ipairs(arrCard) do
		if nCurGetCnt< nGetCnt and (nPoint==nil or DianShu(nCard)==nPoint) then
			table.insert(arrRec,nCard)
			nCurGetCnt =nCurGetCnt+1
		else
			table.insert(arrRemain,nCard)
		end
	end
	return arrRemain
end

local function _BigPointValue(nBigCard) --1点最大(A)
	local nBigPoint =(nBigCard%16)
	if nBigPoint ==1 then
		return 0x0E
	end
	return nBigPoint
end

--arrCard 应按点数由大到小
local function _CardsWeigh(arrCard)
	local nWeigh =0
	local nPower =#arrCard -1
	for _,nCard in ipairs(arrCard) do
		nWeigh =nWeigh + _BigPointValue(nCard)*16^nPower
		nPower =nPower -1
	end
	return nWeigh
end

--返回下一个同花色的牌(服务于同花顺查找)
local function NextCardForTongHua(nCard,nDex) --A->K->Q->J->10...
	if (nCard%16) ==1 then
		if nDex==1 then
			return (nCard+12)
		else
			return 0xFF		--0xFF表示不存在的牌
		end
	end
	return (nCard -1)
end
--返回下一4个不同花色的牌(服务于顺子查找)
local function NextCardForShunZi(nCard,nDex) --A->K->Q->J->10...
	local nNextPoint =(nCard %16) -1
	if nNextPoint ==0 then
		if nDex==1 then
			nNextPoint =13
		else
			return {0xFF}		--0xFF表示不存在的牌
		end
	end
	return {nNextPoint+64,nNextPoint+48,nNextPoint+32,nNextPoint+16}
end
--返回其中最大的同花顺,假设arrCard已按由大到小排序(A最大,K次之)
local function _FindTongHuaShun(arrCard,tCard)
	for i=1,(#arrCard-3) do
		local nHighestCard =arrCard[i]
		local arr ={nHighestCard}
		for j=1,4 do
			nHighestCard =NextCardForTongHua(nHighestCard,#arr)
			if not tCard[nHighestCard] then
				break
			end
			table.insert(arr,nHighestCard)
		end
		if #arr==5 then
			return arr
		end
	end
end
--返回其中最大的同花牌,假设arrCard已按由大到小排序(A最大,K次之)
local function _FindTongHua(arrCard)
	for nHighestCardDex=1,(#arrCard-4) do
		local nHighestCard =arrCard[nHighestCardDex]
		-- local nHuaSe =(nHighestCard//16)
		local nHuaSe = bit.rshift(nHighestCard,4)
		local arr ={nHighestCard}
		for i=nHighestCardDex+1,#arrCard do
			if bit.rshift(arrCard[i],4)==nHuaSe then
			-- if (arrCard[i]//16)==nHuaSe then
				table.insert(arr,arrCard[i])
			end
			if #arr==5 then
				return arr
			end
		end
	end
end
--返回其中最大的顺子,假设arrCard已按由大到小排序(A最大,K次之)
local function _FindShunZi(arrCard,tCard)
	for i=1,(#arrCard-3) do
		local nHighestCard =arrCard[i]
		local arr ={nHighestCard}
		for j=1,4 do
			local arrNextCards =NextCardForShunZi(arr[#arr],#arr)
			for _,v in ipairs(arrNextCards) do
				if tCard[v] then
					table.insert(arr,v)
					break
				end
			end
			if #arr ~= (j+1) then
				break
			end
		end
		if #arr==5 then
			return arr
		end
	end
end

--0没牌或不可见 1高牌 2对子 3两对 4三条 5顺子 6葫芦 7同花  8四条(金刚) 9同花顺 10皇家同花顺
--假设使用一副牌,且其中没有重复数值的牌
local function CardsAnaly(arrCard)
	-- 短牌，增加最小 
	local arr = {}
	local arrCard1 = {}
	for _, nCard in pairs(arrCard) do
		if (nCard%16) == 1 then 
			table.insert(arrCard1,nCard+4)  
			table.insert(arr,(nCard+4)%16)
		end 
		table.insert(arrCard1,nCard)
		table.insert(arr,nCard%16)
	end   

	--按点数和花色由大到小排序(A最大)
	table.sort(arrCard,_SortByDesc)
	table.sort(arrCard1,_SortByDesc)
	local tCard ={}
	for _,v in ipairs(arrCard) do
		tCard[v]=true
	end	
	local tCard1 ={}
	for _,v in ipairs(arrCard1) do
		tCard1[v]=true
	end
	--皇家同花顺 和 同花顺
	local arrFive =_FindTongHuaShun(arrCard1,tCard1)
	if arrFive then
		local nBigPoint =_BigPointValue(arrFive[1])
		if nBigPoint==0x0E then 
			return 10,nBigPoint,arrFive
		end
		if (arrFive[5]%16) == 5 then -- 转回  A
			arrFive[5] = arrFive[5] - 4 
		end
		return 9,nBigPoint,arrFive
	end	
	--把牌按4条、3条、2条、单个划分
	local arr4,arr3,arr2,arr1,arrNoRepeat =CardsPointAnaly(arrCard)
	--金刚.
	if #arr4>0 then
		local arrFive ={}
		local arrRemain =_GetCardsTo(arrCard,arrFive,4,arr4[1])
		_GetCardsTo(arrRemain,arrFive,1)
		assert(#arrFive >=4)
		local nCmpValue =_CardsWeigh({arr4[1],arrFive[5]}) --牌型相同时，用此值比较大小
		return 8,nCmpValue,arrFive
	end
	--同花. 
	local arrFive =_FindTongHua(arrCard)
	if arrFive then
		assert(#arrFive ==5)
		local nCmpValue =_CardsWeigh(arrFive) --牌型相同时，用此值比较大小
		return 7,nCmpValue,arrFive
	end
	--葫芦.
	if (#arr3>0 and #arr2>0) or #arr3>1 then
		local arrFive ={}
		local arrRemain =_GetCardsTo(arrCard,arrFive,3,arr3[1])
		local nPairPoint =math.max((arr3[2] or 0),(arr2[1] or 0))
		_GetCardsTo(arrRemain,arrFive,2,nPairPoint)
		assert(#arrFive ==5)
		local nCmpValue =_CardsWeigh({arr3[1],arrFive[5]}) --牌型相同时，用此值比较大小
		return 6,nCmpValue,arrFive
	end

	--顺子.
	local arrFive =_FindShunZi(arrCard1,tCard1)
	if arrFive then
		assert(#arrFive ==5)
		local nBigPoint =_BigPointValue(arrFive[1])		
		if (arrFive[5]%16) == 5 then -- 转回  A
			arrFive[5] = arrFive[5] - 4 
		end
		return 5,nBigPoint,arrFive
	end
	--三条.
	if #arr3 >0 then
		local arrFive ={}
		local arrRemain =_GetCardsTo(arrCard,arrFive,3,arr3[1])
		_GetCardsTo(arrRemain,arrFive,2)
		assert(#arrFive >=3)
		local nCmpValue =_CardsWeigh({arr3[1],arrFive[4],arrFive[5]}) --牌型相同时，用此值比较大小
		return 4,nCmpValue,arrFive
	end
	--两对. (大小判断:大对 -> 小对 ->单牌)
	if #arr2>1 then
		local arrFive ={}
		local arrRemain =_GetCardsTo(arrCard,arrFive,2,arr2[1])
		arrRemain =_GetCardsTo(arrRemain,arrFive,2,arr2[2])
		arrRemain =_GetCardsTo(arrRemain,arrFive,1)
		assert(#arrFive >=4)
		local nCmpValue =_CardsWeigh({arr2[1],arr2[2],arrFive[5]}) --牌型相同时，用此值比较大小
		return 3,nCmpValue,arrFive
	end
	--对子.
	if #arr2>0 then
		local arrFive ={}
		local arrRemain =_GetCardsTo(arrCard,arrFive,2,arr2[1])
		arrRemain =_GetCardsTo(arrRemain,arrFive,3)
		assert(#arrFive >=2)
		local nCmpValue =_CardsWeigh({arr2[1],arrFive[3],arrFive[4],arrFive[5]}) --牌型相同时，用此值比较大小
		return 2,nCmpValue,arrFive
	end

	--高牌
	local arrFive ={}
	for i=1,5 do
		if arrCard[i] then
		table.insert(arrFive,arrCard[i])
		end
	end
	local nCmpValue =_CardsWeigh(arrFive) --牌型相同时，用此值比较大小
	return 1,nCmpValue,arrFive
end


--0没牌或不可见 1高牌 2对子 3两对 4三条 5顺子 6葫芦 7同花 8四条(金刚) 9同花顺 10皇家同花顺
function Alg.DeZhouCardType(arrHoleCard,arrCommunityCards)
    if arrHoleCard==nil or #arrHoleCard ~=2 then
       return {nCardType=0},0
	end
	local arrCard ={table.unpack(arrHoleCard)}
	for _,v in ipairs(arrCommunityCards) do
		table.insert(arrCard,v)
	end
	local nCardType,nComValue,arrFive =CardsAnaly(arrCard)
	return {nCardType=nCardType,nComValue=nComValue,arrFiveBack=arrFive},nCardType
end

--按牌型由大到小排序
local function _ForSortCardType(v1,v2)
	if v1.nCardType>v2.nCardType then
		return true
	end
	if v1.nCardType<v2.nCardType then
		return false
	end
	if v1.nComValue>v2.nComValue then
		return true
	end
	if v1.nComValue<v2.nComValue then
		return false
	end
	return false
end

function Alg.TheWinCardType(arrUsersCardType)
	table.sort(arrUsersCardType,_ForSortCardType)
	local tBigItem =arrUsersCardType[1]
	local arrRlt ={}
	for _,v in ipairs(arrUsersCardType) do
		if v.nCardType==tBigItem.nCardType and v.nComValue==tBigItem.nComValue then
			table.insert(arrRlt,v)
		end
	end
	return arrRlt
end

local deepcopy = function(object)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end


local Pile ={}
function Pile:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
    t.arrCards={}
	t.resCards={}
	t.nCutIndex=0
	return t
end
function Pile:GetCnt()
	return #self.arrCards
end

--nPackCnt:意指使用多少副牌
function Pile:Shuffle(nPackCnt)
    nPackCnt =nPackCnt or 1
    assert(nPackCnt>0)
    local arrCards={}
    for i=1,nPackCnt do
        for _,nCard in ipairs(arrPackOfCards) do
            table.insert(arrCards,nCard)
        end
    end
    random_array(arrCards)  --混乱数组
    self.arrCards=arrCards
	self.resCards=deepcopy(arrCards)
end
function Pile:GetACard()
    assert(#self.arrCards>=0)
    return table.remove(self.arrCards, 1)
end
function Pile:GetCards(nCnt,arrPrivToGet,noDel)
	arrPrivToGet =arrPrivToGet or {}
	local arr={}
	for i=1,nCnt do
		local nCard =table.remove(arrPrivToGet)
		if nCard ==nil then
			break
		end
		table.insert(arr,nCard)
		if not noDel then
			_removeItem( self.arrCards,nCard,false)
		end
	end

    for i=1,nCnt-#arr do
        table.insert(arr,self:GetACard())
    end
    return arr
end
function Pile:IsHaveCard(nCard)
	for _,v in ipairs(self.arrCards) do
		if v ==nCard then
			return true
		end
	end
	return false
end
function Pile:BackCard(nCard)
	table.insert(self.arrCards,nCard)
end
function  Pile:DelCard(nCard)
	_removeItem( self.arrCards,nCard,false)
end

function Pile:GetAllCards()
	return self.resCards
end

function Pile:GetAllCardsStr()
	return table.concat(self.resCards, ",")
end

-- 切牌位置
function Pile:GetCutIndex()
	return self.nCutIndex
end


function Alg.NewPile(arrCards)
    local tPile = Pile:New()
    tPile:Shuffle(1)
	if arrCards then
		tPile.arrCards = deepcopy(arrCards)
		tPile.resCards = deepcopy(arrCards)
	end
    return tPile
end

-- arrPreSetCommCard ={1,2,3,4,5}
-- arrHoleCard ={{arrHoleCard={1,2},nRank=1,nCardType=1,nComValue=11},{arrHoleCard={1,2},nRank=2,nCardType=1,nComValue=11}}
function Alg.PreSetCards_old(nCnt, tPile, nCutIndex)
	tPile = tPile or Alg.NewPile()
	nCutIndex = nCutIndex or 0
	if nCutIndex > 0 and nCutIndex < #tPile.arrCards then
        local left = {}
        local right = {}
        for i = 1, nCutIndex do
            table.insert(left, tPile.arrCards[i])
        end
        for i = nCutIndex + 1, #tPile.arrCards do
            table.insert(right, tPile.arrCards[i])
        end
        -- 切牌后新的发牌顺序 = right + left
        tPile.arrCards = right
        for _, v in ipairs(left) do
            table.insert(tPile.arrCards, v)
        end
		tPile.nCutIndex = nCutIndex
    end
	local arrCommunityCards =tPile:GetCards(5)
	local arrUsersHoleCard ={}
	for i=1,nCnt do
		local arrHoleCard =tPile:GetCards(2)
		local tCardType =Alg.DeZhouCardType(arrHoleCard,arrCommunityCards)
		local item ={}
		item.arrHoleCard =arrHoleCard
		item.nCardType =tCardType.nCardType
		item.nComValue =tCardType.nComValue
		table.insert(arrUsersHoleCard,item)
	end
	--按牌型由大到小排序
	table.sort(arrUsersHoleCard,_ForSortCardType)
	for dex,v in ipairs(arrUsersHoleCard) do
		v.nRank =dex
	end
	random_array(arrUsersHoleCard)
	return arrCommunityCards,arrUsersHoleCard
end

function Alg.PreSetCards(nCnt, tPile, nCutIndex)
	tPile = tPile or Alg.NewPile()
	nCutIndex = nCutIndex or 0
	if nCutIndex > 0 and nCutIndex < #tPile.arrCards then
        local left = {}
        local right = {}
        for i = 1, nCutIndex do
            table.insert(left, tPile.arrCards[i])
        end
        for i = nCutIndex + 1, #tPile.arrCards do
            table.insert(right, tPile.arrCards[i])
        end
        -- 切牌后新的发牌顺序 = right + left
        tPile.arrCards = right
        for _, v in ipairs(left) do
            table.insert(tPile.arrCards, v)
        end
		tPile.nCutIndex = nCutIndex
    end
	local arrUsersHoleCard = {}
	for i=1,nCnt do
		local arrHoleCard = tPile:GetCards(2)
		local tCardType = Alg.DeZhouCardType(arrHoleCard, {})
		local item ={}
		item.arrHoleCard = arrHoleCard
		item.nCardType = tCardType.nCardType
		item.nComValue = tCardType.nComValue
		table.insert(arrUsersHoleCard, item)
	end
	local arrCommunityCards =tPile:GetCards(3)
	random_array(arrUsersHoleCard)
	return arrCommunityCards, arrUsersHoleCard
end

--arr ={{nCardType=?,nComValue=?},{nCardType=?,nComValue=?}}
function Alg.SortByCardType(arr)
	table.sort(arr,_ForSortCardType)
end
 
local TestPile ={}
function TestPile:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
    t.arrCards={}
	t.nNowDex=1
	return t
end
function TestPile:Init(tKickCards)
    local arrCards={}
	for _,nCard in ipairs(arrPackOfCards) do
		if not tKickCards[nCard] then
			table.insert(arrCards,nCard)
		end
	end
    self.arrCards=arrCards
end
function TestPile:Shuffle()
	random_array(self.arrCards)
	self.nNowDex =1
end

function TestPile:GetCards(nCnt)
	local arr={}
	for i=self.nNowDex,self.nNowDex+nCnt-1 do
		table.insert(arr,self.arrCards[i])
	end
	self.nNowDex =self.nNowDex +#arr
	return arr
end


local function Play(nPlayerCnt,arrTestHoleCard,arrCommunityCards,tTestPile)
	tTestPile:Shuffle()
	local arrPulicCard =tTestPile:GetCards(5-#arrCommunityCards)
	for _,v in ipairs(arrCommunityCards) do
		table.insert(arrPulicCard,v)
	end
	local arrCardType ={}
	local tCardType =Alg.DeZhouCardType(arrTestHoleCard,arrPulicCard)
	tCardType.dex =1
	table.insert(arrCardType,tCardType)
	for i=2,nPlayerCnt do
		local arrHoleCard =tTestPile:GetCards(2)
		local tCardType =Alg.DeZhouCardType(arrHoleCard,arrPulicCard)
		tCardType.dex =i
		table.insert(arrCardType,tCardType)
	end
	local arrRlt =Alg.TheWinCardType(arrCardType)
	for _,v in ipairs(arrRlt) do
		if v.dex==1 then
			return true
		end
	end
	return false
end

--计算outs 用于低水保险
function Alg.CalUsersOuts(arrUsersHoleCard,arrCommunityCards)
	local tKickCard ={}
	for _,v in ipairs(arrCommunityCards) do
		tKickCard[v]=true
	end
	for _,arrHoleCard in ipairs(arrUsersHoleCard) do
		for _,nCard in ipairs(arrHoleCard) do
			tKickCard[nCard]=true
		end
	end
	local tDexToOuts ={}
	local nTailDex =#arrCommunityCards +1
	local tDexToWinRate={}
	local nCnt =0
	for _,nPileCard in ipairs(arrPackOfCards) do
		if not tKickCard[nPileCard] then
			arrCommunityCards[nTailDex] =nPileCard
			local arrCardType ={}
			for dex,arrHoleCard in ipairs(arrUsersHoleCard) do
				local tCardType =Alg.DeZhouCardType(arrHoleCard,arrCommunityCards)
				tCardType.dex=dex
				table.insert(arrCardType,tCardType)
			end
			local arrRlt =Alg.TheWinCardType(arrCardType)
			for _,v in ipairs(arrRlt) do
				local outs =tDexToOuts[v.dex] or {}
				table.insert(outs,nPileCard)
				tDexToOuts[v.dex]=outs
			end

			if #arrRlt ~=#arrUsersHoleCard then
				for _,v in ipairs(arrRlt) do
					tDexToWinRate[v.dex] =tDexToWinRate[v.dex] or 0
					tDexToWinRate[v.dex]=tDexToWinRate[v.dex]+1
				end
			end
			nCnt =nCnt+1
		end
	end
	for dex,_ in ipairs(arrUsersHoleCard) do
		tDexToWinRate[dex] =tDexToWinRate[dex] or 0
		tDexToWinRate[dex] =tDexToWinRate[dex] /nCnt
	end

	arrCommunityCards[nTailDex]=nil
	return tDexToOuts,tDexToWinRate
end
 
local function _TheRestCard(arrUsersHoleCard,arrCommunityCards)
	local tValueToBool ={}
	for _,nCard in ipairs(arrCommunityCards) do
		tValueToBool[nCard]=true
	end
	for _,arrHoleCard in ipairs(arrUsersHoleCard) do
		for _,nCard in ipairs(arrHoleCard) do
			tValueToBool[nCard]=true
		end
	end
	local arrRest ={}
	for _,nCard in ipairs(arrPackOfCards) do
		if not tValueToBool[nCard] then
			table.insert(arrRest,nCard)
		end
	end
	return arrRest
end
local function _IsHaveInsurDex(arr,nInsurDex)
	for _,v in ipairs(arr) do
		if v.dex ==nInsurDex then
			return true
		end
	end
	return false
end
--是否存在平分的可能 (公共牌3个时用,比较耗费性能, 不能用,待优化)
local function _IsHaveMoreOneWin(arrUsersHoleCard,arrCommunityCards,nInsurDex)
	assert(#arrCommunityCards==3)
	local arrRest =_TheRestCard(arrUsersHoleCard,arrCommunityCards)
	local arrPair =FC2(arrRest)
	local nLen =#arrCommunityCards
	local isFind =false
	for _,arr in ipairs(arrPair) do
		arrCommunityCards[nLen+1]=arr[1]
		arrCommunityCards[nLen+2]=arr[2]
		local arrCardType ={}
		for dex,arrHoleCard in ipairs(arrUsersHoleCard) do
			local tCardType =Alg.DeZhouCardType(arrHoleCard,arrCommunityCards)
			tCardType.dex=dex
			table.insert(arrCardType,tCardType)
		end
		local arrRlt =Alg.TheWinCardType(arrCardType)
		if #arrRlt>1 and _IsHaveInsurDex(arrRlt,nInsurDex) then
			isFind=true
			break
		end
	end
	arrCommunityCards[nLen+1]=nil
	arrCommunityCards[nLen+2]=nil
	return isFind
end

--计算outs(常规保险)
function Alg.CalUsersOutsNormal(arrUsersHoleCard,arrCommunityCards,nInsurDex,isAv)
	local arrRest =_TheRestCard(arrUsersHoleCard,arrCommunityCards)
	local tDexToOuts ={}
	local nTailDex =#arrCommunityCards +1
	local isHaveWinEqual =false			--是否存在平分outs
	local tDexToWinRate={}
	local nCnt =0

	for _,nPileCard in ipairs(arrRest) do
		arrCommunityCards[nTailDex] =nPileCard
		local arrCardType ={}
		for dex,arrHoleCard in ipairs(arrUsersHoleCard) do
			local tCardType =Alg.DeZhouCardType(arrHoleCard,arrCommunityCards)
			tCardType.dex=dex
			table.insert(arrCardType,tCardType)
		end
		local arrRlt =Alg.TheWinCardType(arrCardType)
		local isHaveInsurDex =_IsHaveInsurDex(arrRlt,nInsurDex)
		isHaveWinEqual =isHaveWinEqual or (isHaveInsurDex and #arrRlt>1)
		if not isHaveInsurDex then
			for _,v in ipairs(arrRlt) do
				local outs =tDexToOuts[v.dex] or {}
				table.insert(outs,nPileCard)
				tDexToOuts[v.dex]=outs
			end
		elseif isAv and #arrRlt>1 then  --平分的牌也算做outs
			for _,v in ipairs(arrRlt) do
				if v.dex~=nInsurDex then
					local outs =tDexToOuts[v.dex] or {}
					table.insert(outs,nPileCard)
					tDexToOuts[v.dex]=outs
				end
			end
		end
		
		if #arrRlt ~=#arrUsersHoleCard then
			for _,v in ipairs(arrRlt) do
				tDexToWinRate[v.dex] =tDexToWinRate[v.dex] or 0
				tDexToWinRate[v.dex]=tDexToWinRate[v.dex]+1
			end
		end
		nCnt =nCnt+1
	end
	arrCommunityCards[nTailDex]=nil
	if #arrCommunityCards==3 then
		isHaveWinEqual =false   --_IsHaveMoreOneWin(arrUsersHoleCard,arrCommunityCards,nInsurDex)
	end

	for dex,_ in ipairs(arrUsersHoleCard) do
		tDexToWinRate[dex] =tDexToWinRate[dex] or 0
		tDexToWinRate[dex] =tDexToWinRate[dex] /nCnt
	end
	isHaveWinEqual =false
	return tDexToOuts,isHaveWinEqual,tDexToWinRate
end


--根据 当前人数、手牌、公共牌计算胜率. [0,1]
function Alg.WinRate(nPlayerCnt,arrHoleCard,arrCommunityCards)
	if nPlayerCnt<=1 then return 1 end
	local tTestPile =TestPile:New()
	local tKickCards ={}
	for _,v in ipairs(arrHoleCard) do
		tKickCards[v]=true
	end
	for _,v in ipairs(arrCommunityCards) do
		tKickCards[v]=true
	end
	tTestPile:Init(tKickCards)
	local nWinCnt =0
	local nCnt =25		--这个值越大胜率越准,同时越消耗性能
	for i=1,nCnt do
		local isWin =Play(nPlayerCnt,arrHoleCard,arrCommunityCards,tTestPile)
		if isWin then
			nWinCnt =nWinCnt +1
		end
	end
	local nRate =nWinCnt/nCnt
	return nRate
end

return Alg