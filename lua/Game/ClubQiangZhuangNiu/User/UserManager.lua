--[[
	负责用户管理，管理登入该服务器的所有用户
]]
package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase = require("base")           -- 基础功能接口
local tUser = require("User")
local tApi = require("publicApi")
UserManager = 
{
	arrUser = {},

	enumUserType = 
	{
		nMiss 	= -1, --未知
		nUser 	= 0,  --玩家
		nLooker = 1,  --旁观
	}
}

function UserManager.AddUser(tUserInfo)
	if not tUserInfo then
		return false
	end

	if UserManager.arrUser[tUserInfo.nUserID] then
		return false
	end

	local tUsr = tUser:New()
	tUsr:Init(tUserInfo)
	UserManager.arrUser[tUserInfo.nUserID] = tUsr
	tBase.Log("增加玩家ID:"..tUserInfo.nUserID)
	return true
end

function UserManager.DelUser(tDelUser)
	tBase.Log("玩家ID:%d DelUser",tDelUser.nUserID)
	local tCurUser = UserManager.arrUser[tDelUser.nUserID]
	if tCurUser ~= nil then
		tCurUser:Del()
		UserManager.arrUser[tDelUser.nUserID] = nil
	end

end

--获取玩家信息
function UserManager.GetUserInfo(nUserID)
	if nUserID == nil then
		return nil
	end
	return UserManager.arrUser[tApi.Double2Int(nUserID)]
end

--获取clientId玩家
function UserManager.GetUserInfoByLink(sClientId)
	for _, v in pairs(UserManager.arrUser) do
		if v.sClientID == sClientId then
			return v
		end
	end
	return nil
end

--获取clientId玩家
function UserManager.LogAllUserData()
	for _, v in pairs(UserManager.arrUser) do
		tBase.Log("UserID".._)
	end
end

return UserManager

