
--  跑马灯

package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path
package.path = "../lua/base/socket/?.lua;./lua/base/socket/?.lua;" .. package.path
package.path = "../lua/Logon_s/?.lua;./lua/Logon_s/?.lua;" .. package.path
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path



local tBase       = require("base")         -- 基础功能接口
local tApi        = require("publicApi")    -- 共用功能接口
local tName       = require("typename")     -- 类弄定义接口
local tErr        = require("ErrorSink")       -- 捕捉错误
local tLocation  = require("LocationInfo")

MarqueePublic = {}



--发送跑马灯： 参数：  跑马灯类型， 跑马灯内容 
function MarqueePublic.Push_Marquee(tData)
	tBase.Log(" 推送比赛的跑马灯   nUserID: %d     nType: %d  	sDetails: %s  ",tData.nUserID,tData.nType,tData.sDetails )
 --    local s = tBase.GetSP().new(tPubProto.MAIN.SYSLOBBY, tPubProto.SubLobby.SUB_REQ_PAY_MARQUEE)
 --    s:AddInt32(tData.nUserID)     -- 预留： 
 --    s:AddInt32(tData.nType)       -- 跑马灯类型： 1 停服维护（后台直接配置 ，直接播放）2 全娱币公告，3 比赛开始公告，4 比赛第一名公告，5比赛晋级公告
 --    s:AddString(tData.sDetails)   -- 跑马灯内容 
 --    if tData.nType == 3 or tData.nType == 4  then 
	--     local getwaykey = tBase.GetSrcAllKey(tName.gateway)
	--     for key, val in pairs(getwaykey) do
	--     	tBase.Log(" 推送比赛的跑马灯   key=  "..key )
	--         tBase.PostToServer(val, 0, s:GetData(), s:GetSize())
	--     end  
	--     return
	-- end     

	-- local t = tLocation.GetUserLocation(tData.nUserID)
	-- if t == nil then  	tBase.Log(" 推送比赛的跑马灯    nUserID: %d  GetUserLocation Error	 ",tData.nUserID) return    end 
	-- local sKey = t["sGateKey"]
 --    tBase.PostToServer(sKey, tData.nUserID, s:GetData(), s:GetSize())

    return 
end




return MarqueePublic













