--[[
	负责用户管理，管理登入该服务器的所有用户
]]
package.path = require("./lua/Lobby/Head").path

local tBase = require("base")           -- 基础功能接口
local tUser = require("User")

UserManager = 
{
	arrUser = {}
}

function UserManager.AddUser(tUserInfo)
	if not tUserInfo then 
		return false
	end

	if UserManager.arrUser[tUserInfo.nUserId] then
		tBase.Log( "   玩家已存在 ，添加失败！ = %d ",tUserInfo.nUserId)   	
		return false
	end

	local tUsr = tUser:New()
	tUsr:Init(tUserInfo)

	UserManager.arrUser[tUserInfo.nUserId] = tUsr
	
	return true
end

function UserManager.DelUser(tDelUser)
	local tCurUser = UserManager.arrUser[tDelUser.nUserId]
	tCurUser:Del()
	UserManager.arrUser[tDelUser.nUserId] = nil
end

--获取玩家信息
function UserManager.GetUserInfo(nUserId)
	return UserManager.arrUser[nUserId]
end

--通过连接找User
function UserManager.GetUserInfoByLink(sClientID)
	for _, v in pairs (UserManager.arrUser) do
		if v.sClientID == sClientID then
			return v
		end
	end
	return nil
end

return UserManager

