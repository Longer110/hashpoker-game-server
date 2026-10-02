--[[
	负责牌桌管理，创建牌桌，删除牌桌
]]
local tPubUserApi = require("PublicUserInfo")

TableManager = 
{
	tTablePriKey = {nPriKey=0, nMax=0xFFFFFFFF}, --桌子唯一标识
}

-- 创建一个对象
function TableManager:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.arrTable = {}
	t.TMgrEnum =
	{
		CANT_FIND_FREE_PLACE = -1      -- 未能找到可以分配的桌子
	}
	t.nInitCnt = 2000
	for i = 1, t.nInitCnt do
		t.arrTable[i] = 0
	end
	return t
end

--桌子唯一标识
function TableManager.GetTablePriKey()
	if TableManager.tTablePriKey.nPriKey < TableManager.tTablePriKey.nMax then
		TableManager.tTablePriKey.nPriKey = TableManager.tTablePriKey.nPriKey + 1
	else
		TableManager.tTablePriKey.nPriKey = 0
	end 
	return TableManager.tTablePriKey.nPriKey
end

--加入table
function TableManager:AddTable(tTable)
	local nFreePlace = self:FindFreePlace()
	if nFreePlace ~= self.TMgrEnum.CANT_FIND_FREE_PLACE then
		self.arrTable[nFreePlace] = tTable
		tTable.nPriKey = TableManager.GetTablePriKey()
		tTable:SetTableId(nFreePlace)
	end
	return nFreePlace
end

--移除table
function TableManager:RemoveTable(nIdx)
	
	--从新设置标志位为0,让桌子空闲
	local  tTable = self.arrTable[nIdx]
	if tTable ~= nil and type(tTable) == "table" then
		tTable:Del()
	end
	self.arrTable[nIdx] = 0
	return true
end

--获取某个table
function TableManager:GetTable(nIdx)
	if self.arrTable[nIdx] ~= 0 then
		return self.arrTable[nIdx]
	end
	return nil
end

--找空闲的位置
function TableManager:FindFreePlace()
	local arrPlace = self.arrTable
	for i = 1, #arrPlace do
		if type(arrPlace[i]) == "number" and arrPlace[i] == 0 then
			return i
		end
	end
	return self.TMgrEnum.CANT_FIND_FREE_PLACE
end

function TableManager:GetOnlinePeople(nGameId)
	local nNum, nCount = 0, 0
	for k=1, #self.arrTable do
		local tTable = self.arrTable[k] 
		if tTable and type(tTable)~="number" then
			if nGameId==tTable.nGameId then
				nNum=nNum+#tTable.tUserIDArr
				nCount=nCount+1
			end
		end
	end
	tPubUserApi.SetOnlinePeopleNum(nGameId,nNum)
	return nNum
end

return TableManager

