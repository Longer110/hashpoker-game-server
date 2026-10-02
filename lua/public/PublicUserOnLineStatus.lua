--[[
	 直播区块链 相应接口
-- ]]

local tBase  = require("base")         -- 基础功能接口
local cjson     = require("cjson")        -- json
local tPublicRedis =require("PublicRedis") -- Redis 公共接口 
local ProtoMgr = require("ProtoManager") -- 协议管理对象
local tname = require("typename") -- 类弄定义接口
local tPubUserApi  = require("PublicUserInfo")    --玩家数据
local tPublicUserGold  = require("PublicUserGold")    --玩家数据
local WebCMD = ProtoMgr.Web_pb.Web_Sys()

function SafeExecute(func, funcName, ...)
    local success, result = pcall(func, ...)
    if not success then
        tBase.Log(string.format("函数 %s 执行失败: %s", funcName or "未知", result))
        return false, result
    end
    return true, result
end

local PublicUserOnLineStatus ={}
local tWaitClear = {}
-- 清理间隔（秒）
local nClearDelay = 60*10  -- 10分钟后清理

-- 获取Web服务节点Key
local function _GetWebServKey(nUserId)
    tBase.LogT("GetNotMaintainAllKey _GetWebServKey")
    local arrAllKey =  tPublicRedis.GetNotMaintainAllKey(tname.web)

    local sKey = nil
    local servertable = {}
    if nUserId ~= 0 and #arrAllKey>0 then
        local nId = nUserId % (#arrAllKey) + 1
        table.insert(servertable, arrAllKey[nId])
    else
        servertable = arrAllKey
    end
    if servertable ~= nil and next(servertable) ~= nil then
        local lIndex = math.random(1, #servertable)
        sKey = servertable[lIndex]
    end
    return sKey
end

-- 定时清理离线玩家数据
function PublicUserOnLineStatus.OnTimerClearUserData()
    tBase.Log("OnTimerClearUserData.OnLine")
    local now = os.time()
    local cleared = 0
    local clearUsers = {}

    for userId, logoutTime in pairs(tWaitClear) do
        if now - logoutTime >= nClearDelay then
            -- 二次确认：如果玩家已重新上线，不清理
            if not PublicUserOnLineStatus.IsUserOnline(userId) then
                SafeExecute(PublicUserOnLineStatus._ClearUserData, "_ClearUserData", userId)
                -- PublicUserOnLineStatus._ClearUserData(userId)
                tWaitClear[userId] = nil
                cleared = cleared + 1
                table.insert(clearUsers, userId)
            else
                -- 玩家已重新上线，移出清理表
                tWaitClear[userId] = nil
            end
        end
    end
    if cleared > 0 then
        tBase.Log("PublicUserOnLineStatus.OnTimerClearUserData: cleared %d user(%s)", cleared, cjson.encode(clearUsers))
    end
end

-- 清除redis中用户相关数据
function PublicUserOnLineStatus._ClearUserData(nUserId)
    tBase.Log("Clearing user data for userId=%d", nUserId)
    tPubUserApi.DeleteUserInfo(nUserId)
    tPublicUserGold.UnLockUserGold(nUserId, 1)
    tPublicRedis.TexaStatistic_Clear(nUserId)
    tPubUserApi.DelUserMarkInfo(nUserId)
end

function PublicUserOnLineStatus.IsUserOnline(nUserId)
    return tPubUserApi.IsUsernOnline(nUserId) == 1
end



function PublicUserOnLineStatus.OnLine(nUserId)
    if tWaitClear[nUserId] then
        tBase.Log("User %d online again, remove from clear list", nUserId)
        tWaitClear[nUserId] = nil
    end
    if true then
        return true
    end
    local sWebServKey =_GetWebServKey(nUserId)
    if sWebServKey==nil then
        tBase.Log("PublicUserOnLineStatus.OnLine _GetWebServKey nil,nUserId:%d",nUserId)
        return
    end
    local Send = ProtoMgr.Web_pb.WebUserOnlineStatus()
    Send.nUserId = nUserId
    Send.nStatus =1
    Send.sElse =tPubUserApi.Get_User_ShopAccount(nUserId) or ""
    if tonumber(Send.sElse)==nil then
        tBase.Log("PublicUserOnLineStatus.OnLine fail,nUserId:%d shopAccout:%s",nUserId,Send.sElse)
        return
    end
    local tPacket = tBase.GetSP().new(WebCMD.Main_CMD, WebCMD.WebUserOnlineStatus_CMD)
    tPacket:AddString(Send:SerializeToString())
    tBase.PostToServer(sWebServKey, 0, tPacket:GetData(), tPacket:GetSize())
    return true
end

function PublicUserOnLineStatus.OffLine(nUserId)
    tWaitClear[nUserId] = os.time()
    if true then
        return true
    end
    local sWebServKey =_GetWebServKey(nUserId)
    if sWebServKey==nil then
        return
    end
    local Send = ProtoMgr.Web_pb.WebUserOnlineStatus()
    Send.nUserId = nUserId
    Send.nStatus =2
    Send.sElse =tPubUserApi.Get_User_ShopAccount(nUserId) or ""
    if tonumber(Send.sElse)==nil then
        return
    end
    local tPacket = tBase.GetSP().new(WebCMD.Main_CMD, WebCMD.WebUserOnlineStatus_CMD)
    tPacket:AddString(Send:SerializeToString())
    tBase.PostToServer(sWebServKey, 0, tPacket:GetData(), tPacket:GetSize())
    return true
end

return PublicUserOnLineStatus
 