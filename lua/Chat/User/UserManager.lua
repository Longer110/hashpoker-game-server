
local User = require("User")   

--[[
	负责用户管理，管理登入该服务器的所有用户
]]

local UserManager ={}
local tUserIdToUser ={}		 	--用户id对应的用户信息(包括机器人)

--获取玩家信息
function UserManager.GetUserInfo(nUserId,isSynGoldWithRedis)
	local tUserObj =tUserIdToUser[nUserId]
	if isSynGoldWithRedis and tUserObj~=nil then
		local nGold = PublicUserInfo.Get_User_Gold(nUserId)
		if nGold then
			tUserObj.nGold = tonumber(nGold) or 0
		end
	end
	return tUserObj
end

--创建玩家
function UserManager.CreateUser(nUserId)
	local tUserObj =UserManager.GetUserInfo(nUserId,true)
	if tUserObj then
		return tUserObj,false
	end
	local tUserInfo =PublicUserInfo.GetAllUserInfo(nUserId)
	assert(tUserInfo~=nil,"Err happen,GetAllUserInfo return nil,nUserID_"..nUserId)
	tUserObj =User:New()
	tUserObj.nUserId = nUserId
	tUserObj.sName = tUserInfo.sNickName or "Tm9OYW1l"
	tUserObj.nSex = tonumber(tUserInfo.nSex) or 0 --0:男 1:女
	tUserObj.sFaceId = tUserInfo.sFaceID or "1" 
	tUserObj.sClientID = tUserInfo.sClientID or ""
	tUserIdToUser[nUserId] =tUserObj 
	return tUserObj,true
end

--删除玩家
function UserManager.DelUser(nUserId) 
	tUserIdToUser[nUserId] =nil
end

--根据sClientID获取玩家
function UserManager.GetUserInfoByClientId(sClientID)
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId or nUserId < 0 then
        Base.Log("_GetUserInfoByClientId Not Logon,sClientID_"..(sClientID or 'nil'))
        return
    end
	return tUserIdToUser[nUserId]
end

--获取所有玩家的sClientID
function UserManager.GetAllUserClientID()
	local arrClientID = {}
	for nUserId,v in pairs(tUserIdToUser) do
		local sClientID = ClientIdMgr.GetClientIdByUserId(nUserId)
		if sClientID then 
			table.insert(arrClientID,sClientID)
		end
	end
	return arrClientID
end

--获取玩家的sClientID
function UserManager.GetUserClientID(nUserId)
	return ClientIdMgr.GetClientIdByUserId(nUserId)
end

--玩家离开 牌桌聊天
function UserManager.UserLeaveTable(nUserId,sTableId)
	local tUser = tUserIdToUser[nUserId]
	if tUser then
		local nNowTableId = tUser:GetNowTable()
		if nNowTableId==sTableId then
			tUser:DelNowTable()
			Base.Log("_UserLeaveTable sTableId_%d",sTableId)
			return true
		end
	end
	return false
end

--玩家进入牌桌聊天
function UserManager.UserEnterTable(nUserId,sTableId)
	local tUser = tUserIdToUser[nUserId]
	if tUser then 
		tUser:SetNowTable(sTableId)
		return true
	end
	return false
end

return UserManager

