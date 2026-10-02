
local tBase  = require("base")         -- 基础功能接口

local SlaveManager = {}


local tServIdToKey={}
function SlaveManager.AddSlaveServ(nServerId,sServerKey)
	tServIdToKey[nServerId] =sServerKey
end

--广播
function SlaveManager.Broadcast(sProto,tSendData)
	for nServerId,sServKey in pairs(tServIdToKey) do
		local tPacket =CenterAux:Encode(sProto,tSendData)
		assert(tPacket~=nil)
		local nRlt =tBase.PostToClient(sServKey, tPacket:GetData(), tPacket:GetSize())
		if nRlt~=1 then
			tServIdToKey[nServerId]=nil
		end
	end
end

function SlaveManager.Send(sServerKey,sProto,tSendData)
	local tPacket =CenterAux:Encode(sProto,tSendData)
	assert(tPacket~=nil)
	tBase.PostToClient(sServerKey, tPacket:GetData(), tPacket:GetSize())
end

function SlaveManager.IsHaveServerId(nServerId)
	if nServerId==nil then
		return false
	end
	if tServIdToKey[nServerId] then
		return true
	end
	return false
end

function SlaveManager.GetRandomServerId()
	local arrServerId ={}
	for nServerId,_ in pairs(tServIdToKey) do
		table.insert(arrServerId,nServerId)
	end
	if #arrServerId==0 then
		return nil
	end
	local nRandomDex =math.random(1,#arrServerId)
	return arrServerId[nRandomDex]
end

function SlaveManager.GetAllServerId()
	local arrServerId ={}
	for nServerId,_ in pairs(tServIdToKey) do
		table.insert(arrServerId,nServerId)
	end
	return arrServerId
end

return SlaveManager
