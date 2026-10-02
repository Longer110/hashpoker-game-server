package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase 	= require("base")         -- 基础功能接口
local tUserMgr  = require("UserManager")
local tPubUserApi = require("PublicUserInfo")
local tTableMgr = require("TableManage")
local tConfig =require("GameConfig") -- 
local mlogger = require("logger") -- 日志对象 
local tJson = require("cjson")
UserLogin = {}

--真正退出游戏服（清除玩家在游戏服数据）
function UserLogin.OnUserLogout(sClientID)
	local tUser = tUserMgr.GetUserInfoByLink(sClientID)
	if tUser ~= nil then
		tBase.Log("找到即将删除的玩家")
		UserLogin.ClearUserData(tUser)
	end
end

--清除玩家数据
function UserLogin.ClearUserData(tUser)
	if tUser.isAndroid == false then
		local nGroupId = tConfig.GetGroupId(tonumber(tUser.nShopID))
		if nGroupId == -1 then
			mlogger:info(tJson.encode(tUser))
			tBase.Log("ClearUserData tUser_%s",tJson.encode(tUser))
		end
		CheckTableTimeOut.DelLoginNumber(nGroupId,tUser.GameType,tUser.GameLevel)
	end
	
	tUserMgr.DelUser(tUser)
    local tTable = tTableMgr.GetTable(tUser.nTableId)
	tBase.Log("ClearUserData nTableId_%d",tUser.nTableId)
    if (tTable == nil) then tBase.Log("已经退出了") return   end
    tPubUserApi.LeaveGame(tUser.nUserID,tTable.nGameType)
	tBase.Log("牌桌%s 玩家:%d正常离开......",tTable.sTableId,tUser.nUserID)
end

return UserLogin