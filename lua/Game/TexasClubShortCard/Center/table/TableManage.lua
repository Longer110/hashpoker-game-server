--[[
	负责牌桌管理，创建牌桌，删除牌桌
]]
local tBase  = require("base")         -- 基础功能接口
local tTable = require("Table")
local Define =require("Define")

local TableManager = {}


local tTableIdToTable={}
local tTableTypeToList ={}

local function _AssertListExist(nGroupId,nTableType,nRoomId)
	local sKey =string.format("%d_%d_%d",nGroupId,nTableType,nRoomId)
	if not tTableTypeToList[sKey] then
		tTableTypeToList[sKey] ={}
	end
	return tTableTypeToList[sKey]
end


function TableManager.CreateTable(tTableLogicInterface,sTableId,tConfig)
	local tSlaveTable =tTableIdToTable[sTableId]
	if tSlaveTable then
		return false,tSlaveTable
	end
	tSlaveTable =tTable:New(sTableId,tTableLogicInterface,tConfig)
	tTableIdToTable[sTableId]=tSlaveTable

	if tConfig.nRoomId and tConfig.nTableType and tConfig.nGroupId then
		local tList =_AssertListExist(tConfig.nGroupId,tConfig.nTableType,tConfig.nRoomId)
		tList[sTableId] =tSlaveTable
	end
	return true,tSlaveTable
end

function TableManager.CloseTable(sTableId)
	local tSlaveTable =tTableIdToTable[sTableId]
	if tSlaveTable==nil then
		return
	end
	local nTableType =tSlaveTable:TableType()
	local nRoomId 	 =tSlaveTable:RoomId()
	local nGroupId =tSlaveTable:GroupId()

	if nTableType and nRoomId and nGroupId then
		local tList =_AssertListExist(nGroupId,nTableType,nRoomId)
		tList[sTableId] =nil
	end
	tTableIdToTable[sTableId]=nil
	local nCnt = TableManager.GetCntOfMatchTable(nGroupId,nRoomId)
	return nCnt
end

function TableManager.GetBaiRenTable(sTableId)
	return tTableIdToTable[sTableId]
end


function TableManager.GetTableOfMatch(nGroupId,nRoomId)
	local tList =_AssertListExist(nGroupId,Define.TableType.nMatch,nRoomId)
	for sTableId,tTable in pairs(tList) do
		if not tTable:IsFullCapacity() then --找一张没满座的桌子返回
			return tTable
		end
	end
end

function TableManager.GetCntOfMatchTable(nGroupId,nRoomId)
	local tList =_AssertListExist(nGroupId,Define.TableType.nMatch,nRoomId)
	local nCnt =0
	for sTableId,tTable in pairs(tList) do
		nCnt =nCnt +1
	end
	return nCnt
end


function TableManager.GetNextTableOfMatch(nGroupId,nRoomId,sNowTableId)
	local tList =_AssertListExist(nGroupId,Define.TableType.nMatch,nRoomId)
	local arr ={}
	for sTableId,tTable in pairs(tList) do
		table.insert(arr,sTableId)
	end
	table.sort(arr)
	local nNowDex =nil
	for dex,v in ipairs(arr) do
		if v==sNowTableId then
			nNowDex =dex
			break
		end
	end
	nNowDex =nNowDex or 0
	if nNowDex<#arr then
		nNowDex =nNowDex +1
	else
		nNowDex =1
	end
	local sNextTableId =arr[nNowDex]
	if sNextTableId then
		return tList[sNextTableId]
	end
end

return TableManager

