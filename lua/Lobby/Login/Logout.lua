package.path = require("./lua/Lobby/Head").path

local tBase      = require("base")           -- 基础功能接口
local tApi       = require("publicApi")      -- 共用功能接口
local tRdf       = require("redisdefine")    -- redis用到的kdy
-- local tUserMgr   = require("UserManager")	   -- 用户管理
local tPubUserApi   = require("PublicUserInfo")    --玩家数据同步
local tName      = require("typename")     -- 类弄定义接口


Logout = {}

--用户离线
function Logout.OnUserLogout(nUserId)
	-- 记录玩家下线时间
	--Logout.User_TapeOut_Time(nUserId)
end


--  更新玩家下线时间
function  Logout.User_TapeOut_Time(nUserID)
	
	tBase.Log(" 更新玩家： %d  下线时间 ",nUserID)

	local sSql = "Call Update_User_TapeOut_Time("..nUserID..")"
    -- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_UPDATE_TAPEOUT)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, nUserID, s:GetData(), s:GetSize())

end

return Logout
