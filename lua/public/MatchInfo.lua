--玩家所在比赛信息
package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path

local tBase 	= require("base")
local tApi     	= require("publicApi")

MatchInfo = {
	sSngInfoKey = "SngInfo",
	sSngListKey = "SngSrvList",
	nSngIdx = -1,
	nTotal = 0,
}


--我先不做服务器崩溃兼容列表删除 todo later
function MatchInfo.PushSngMatch(nMatchId, nSrvId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==129   ")  
		return
	end

	local sKey = MatchInfo.sSngListKey..nMatchId
	return tBase.m_MyRedisData[1].redis:lpush(sKey, nSrvId)
end

--sng服务器游标，用于分散游戏服压力
function MatchInfo.GetSngSelSrvId(nMatchId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==130   ")  
		return
	end

	local sKey = MatchInfo.sSngListKey..nMatchId
	local nLen = tBase.m_MyRedisData[1].redis:llen(sKey)
	if nLen <= 0 then return -1 end

	local nRandId = math.random(0, nLen-1)

	local tRet = tBase.m_MyRedisData[1].redis:lrange(sKey, nRandId, nRandId)

	return tonumber(tRet[1])
end

--sng比赛实际的matchId是合成的唯一id
function MatchInfo.GetSngMatchRealId(nMatchId, nTurn)
	return (nTurn << 16) + nMatchId
end

function MatchInfo.GetSngMatchId(nMatchRealId)
	return nMatchRealId & 0xFFFF
end

function MatchInfo.GetSngMatchTurn(nMatchRealId)
	return nMatchRealId >> 16 
end

function MatchInfo.IsSngMatch(nMatchRealId)
	if nMatchRealId > 65535 then
		return true
	end
	return false
end

return MatchInfo

