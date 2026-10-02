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
	tUserObj.nGold =tonumber(tUserInfo.nGold) or 0
	tUserObj.nShopId =tonumber(tUserInfo.nShopID) or -1
	tUserObj.isAndroid =false
	tUserObj.nAccountType=tonumber(tUserInfo.nAccountType) or -1
	tUserObj.sShopAcc = tUserInfo.sShopAccount or ""
	tUserObj.nGroupId = GameConfig.GetGroupId(tUserObj.nShopId) or tonumber(tUserInfo.nGroupId) or -1
	tUserIdToUser[nUserId] =tUserObj
	-- Base.Log("_CreateUser nUserId_%d  nGroupId_%d  ",nUserId,tUserObj.nGroupId or -1)
	return tUserObj,true
end

--删除玩家
function UserManager.DelUser(nUserId)
	Base.Log("_DelUser nUserId_%d   ",nUserId)
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

--玩家离开俱乐部
function UserManager.UserLeaveClub(nUserId,nClubId)
	local tUser = tUserIdToUser[nUserId]
	if tUser then
		local nNowClubId = tUser:GetNowClub()
		if nNowClubId==nClubId then
			tUser:DelNowClub()
			Base.Log("UserManager _UserLeaveClub nClubId_%d",nClubId)
			return true
		end
	end
	return false
end

--玩家进入俱乐部
function UserManager.UserEnterClub(nUserId,nClubId)
	local tUser = tUserIdToUser[nUserId]
	if tUser then
		local nNowClubId = tUser:GetNowClub()
		assert(nNowClubId==0,string.format("_UserEnterClub nUserId_%d nNowClubId_%d~=0",nUserId,nNowClubId))
		tUser:SetNowClub(nClubId)
		return true
	end
	return false
end

--获取本服所有玩家的信息
function UserManager.GetAllUserInfo()
	return tUserIdToUser
end

--刷新玩家金币
function UserManager.RefleshUserGold(nUserId,nGold)
	if tUserIdToUser[nUserId] then
		tUserIdToUser[nUserId].nGold = nGold
	end
end

return UserManager

