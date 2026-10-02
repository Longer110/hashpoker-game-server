
local tBase  = require("base")         -- 基础功能接口
local tMatch = require("Match")


local MatchManager ={}
local tEventIdToMatch={}
local tTypeToList={}


local function _AssertListExist(nGroupId)
	local sKey =string.format("%d",nGroupId)
	if not tTypeToList[sKey] then
		tTypeToList[sKey] ={}
	end
	return tTypeToList[sKey]
end


function MatchManager.CreateMatch(tInterface,nEventId,tConfig)
	local t =tEventIdToMatch[nEventId]
	if t then
		return false,t
	end
	t =tMatch:New(nEventId,tInterface,tConfig)
	tEventIdToMatch[nEventId]=t
	if tConfig.nGroupId then
		local tList =_AssertListExist(tConfig.nGroupId)
		tList[nEventId] =t
	end
	return true,t
end

function MatchManager.CloseMatch(nEventId)
	local t =tEventIdToMatch[nEventId]
	if t==nil then
		return
	end
	local nGroupId =t:GroupId()
	if nGroupId then
		local tList =_AssertListExist(nGroupId)
		tList[nEventId] =nil
	end
	tEventIdToMatch[nEventId]=nil
end

function MatchManager.GetMatch(nEventId)
	return tEventIdToMatch[nEventId]
end

function MatchManager.GetMatchsByGrpId(nGroupId)
	local arr={}
	local isTest=false
	if nGroupId ==nil or isTest then	-- nil时返回全部
		for _,t in pairs(tEventIdToMatch) do
			table.insert(arr,t)
		end
		return arr
	end
	local tList =_AssertListExist(nGroupId)
	for _,t in pairs(tList) do
		table.insert(arr,t)
	end
	return arr
end


return MatchManager

