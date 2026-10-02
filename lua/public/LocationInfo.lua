
--玩家所在场景信息

package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path

-- local tPubUser   = require("PublicUserInfo")   -- 会 循环包含文件 了
local tBase 	= require("base")
local tSrvInfo  = require("ServerInfo")

LocationInfo = {}

function LocationInfo.ApplyEnter(tData)
	--{nUserId=HouseID, sTypeName=tname.mahjong, nSrvId=nServerId, sKey=sGameKey}
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==131   ")  
		return
	end

	local sKey = "ApplyEnter_"..tData.nUserId
	tBase.m_MyRedisData[1].redis:hmset(sKey, tData)

	tBase.m_MyRedisData[1].redis:persist(sKey)
	tBase.m_MyRedisData[1].redis:expire(sKey, 10)
end

function LocationInfo.GetApplyInfo(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==132   ")  
		return {}
	end

	local sKey = "ApplyEnter_"..nUserId
	return tBase.m_MyRedisData[1].redis:hgetall(sKey)
end

function LocationInfo.DelApply(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==133   ")  
		return
	end

	local sKey = "ApplyEnter_"..nUserId
	tBase.m_MyRedisData[1].redis:del(sKey)
end

function LocationInfo.SetUserLocation(tData)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==134   ")  
		return
	end

	local nUserId =math.floor(tData.nUserId)
	local sKey = "ULocation_"..nUserId

	local t = {}
	t["nUserId"] = nUserId
	t["nServerId"] = tData.nServerId
	t["sKey"] = tData.sKey
	t["sGateKey"] = tData.sGateKey
	t["sIp"] = tData.sIp
	t["sLobbyKey"] = tData.sLobbyKey
	--更新房锁
	-- tPubUser.WriteScoreLocker(t)

	return tBase.m_MyRedisData[1].redis:hmset(sKey, t)
end

function LocationInfo.GetUserLocation(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==135   ")  
		return {}
	end	
	local nUserId =math.floor(nUserId)
	local sKey = "ULocation_"..nUserId

--	tBase.Log("GetUserLocation: %s", sKey)
	return tBase.m_MyRedisData[1].redis:hgetall(sKey)
end

function LocationInfo.GetCheckIpCfg()
	if tBase.m_MyRedisData[2].redis == nil then
		tBase.Log(" Error_Info==139 ")  
		return {}
	end	 
	local sKey = "IpverifyKey_" 
	return tBase.m_MyRedisData[2].redis:hgetall(sKey)
end

function LocationInfo.ClearUserLocation(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==136   ")  
		return
	end

	local nUserId =math.floor(nUserId)

	local sKey = "ULocation_"..nUserId

	tBase.m_MyRedisData[1].redis:del(sKey)
	tBase.Log("删除玩家位置信息: sKey: %s UserId: %d", sKey, nUserId)
end

function LocationInfo.SetUserApplyMatchInfo(nUserId, nMatchId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==137   ")  
		return {}
	end	

	local sKey = "ULocation_"..nUserId

	local t = {}
	t["nMatchId"] = nMatchId
	tBase.m_MyRedisData[1].redis:hmset(sKey, t)
end

function LocationInfo.GetUserApplyMatchInfo(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==138   ")  
		return
	end

	local sKey = "ULocation_"..nUserId

	local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	return tonumber(t["nMatchId"] or 0)
end

function LocationInfo.SetClientId(nUserId, nClientId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==139   ")  
		return
	end	
	local sKey = "ULocation_"..nUserId
	local t = {}
	t["nCLientId"] = nClientId
	tBase.m_MyRedisData[1].redis:hmset(sKey, t)
end

function LocationInfo.GetClientId(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==140   ")  
		return
	end

	local sKey = "ULocation_"..nUserId

	local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	return tonumber(t["nClientId"] or 0)
end

return LocationInfo

