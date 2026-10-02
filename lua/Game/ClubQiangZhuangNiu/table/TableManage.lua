--[[
	负责牌桌管理，创建牌桌，删除牌桌
]]
package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase  = require("base")         -- 基础功能接口
local tPubUserApi = require("PublicUserInfo")
local tTable = require("Table")
local tJson = require("cjson")

TableManager = 
{
	TMgrEnum =
	{
		CANT_FIND_FREE_PLACE = -1      -- 未能找到可以分配的桌子
	},

	arrTable = {}	
}

--初始化桌子管理
function TableManager.Init()
	--启动GLogic日志

	--todo 根据配置加载桌子
	local nInitCnt = 2000
	for i = 1, nInitCnt do
		TableManager.arrTable[i] = 0
	end
end

--加入table
function TableManager.AddTable()
	local nFreePlace = TableManager.FindFreePlace()
	if nFreePlace ~= TableManager.TMgrEnum.CANT_FIND_FREE_PLACE then
		local tNewTable = tTable:New()
		tNewTable:Init(nil)
		tNewTable.nTableId = nFreePlace
		TableManager.arrTable[nFreePlace] = tNewTable
	end

	return nFreePlace
end

--移除table
function TableManager.RemoveTable(nIdx)
	local tCurTable = TableManager.arrTable[nIdx]
	if tCurTable == 0 then return false end

	tCurTable.bEnable = true
	-- --清除解散定時器
    -- tBase.KillTimer(SrvPub.Timer.OverLife + nIdx)
    -- --清除牌桌超時定時器
    -- tBase.KillTimer(SrvPub.Timer.VoteDissolution + nIdx)
    -- --删除托管定时器
    -- tBase.KillTimer(SrvPub.Timer.AutoHu + nIdx)
	

	tCurTable:Del()
	--从新设置标志位为0,让桌子空闲
	TableManager.arrTable[nIdx] = 0

	tBase.Log("移除桌子成功 TableId:%d", nIdx)
	return true
end

--获取某个table
function TableManager.GetTable(nIdx)
	if TableManager.arrTable[nIdx] ~= 0 then
		return TableManager.arrTable[nIdx]
	end
	return nil
end

--获取某个table
function TableManager.GetTableBySTableId(sTableId)
	tBase.Log("GetTableBySTableId:%s",sTableId)
	for k, v in pairs(TableManager.arrTable) do
		if type(v) == "table" and v.sTableId == sTableId then
			return v
		end
	end
	return nil
end

--找空闲的位置
function TableManager.FindFreePlace()
	local arrPlace = TableManager.arrTable
	for i = 1, #arrPlace do
		if type(arrPlace[i]) == "number" and arrPlace[i] == 0 then
			return i
		end
	end
	return TableManager.TMgrEnum.CANT_FIND_FREE_PLACE
end

function TableManager.GetNNOnlinePeople(nGameId)
	local nNum, nCount = 0, 0
	for k=1, #TableManager.arrTable do
		local tTable = TableManager.arrTable[k] 
		if tTable and type(tTable) ~= "number" then
			if tTable.nGameType==nGameId then
				nNum=nNum+#tTable.tUserIDArr
				nCount=nCount+1
			end
		end
	end
	tPubUserApi.SetOnlinePeopleNum(nGameId,nNum)
	return nNum
end

return TableManager

