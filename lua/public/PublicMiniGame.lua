
local tBase = require("base")           -- 基础功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local cjson     = require("json")          -- json (空对象编码成空数组) 
local RecordDbr = require("RecordDbr")

local PublicMiniGame ={

}

 
local function _GetMiniGameCfg(nGroupId)
    local tCfg = RedisCahche._GetMiniGameCfg(0)  
    for k, v in pairs(tCfg) do 
        if tonumber(k) == nGroupId then   
            local t = cjson.decode(v)
            t.nExChangeRatio = tonumber(t.nExChangeRatio)   -- 兑换比例 (打开兑换界面)
            t.nExChangeLimit = tonumber(t.nExChangeLimit)   -- 每日可兑换上限 (打开兑换界面) 
            return t 
        end  
    end    
end

-- 操作小游戏 兑换上限
local function _Handle_MiniGame_ExChangeLimit(nHandle,nUserId,nCnt)
	local redis = tBase.m_MyRedisData[2].redis 
	local sKey = string.format("MiniGame_ExChangeLimit")      
    if nHandle == 1 then 
        local nExChangeLimit = redis:hget(sKey,math.floor(nUserId)) or 0
        return tonumber(nExChangeLimit) 
    else
        local nExChangeLimit = redis:hget(sKey,math.floor(nUserId)) or 0
        nExChangeLimit = tonumber(nExChangeLimit) + nCnt        
        redis:hset(sKey,math.floor(nUserId),nExChangeLimit) 

        -- 重新计算 零点有效期   
        local nZeroTime = publicApi.GetLeroLeadTime()           
        redis:expire(sKey,nZeroTime)     
        return nExChangeLimit   
    end 
end

--  小游戏 兑换业务
function PublicMiniGame.ExchangeLogic(ClientID, Data, Len,nUserId)
    local r = tBase.GetRP().new(Data, Len)
    local MainID = r:GetModuleID()
    local SubID = r:GetMsgID()
    local Read = ProtoMgr.Gateway_pb.MiniGame_PublicRsq()
    Read:ParseFromString(r:GetString())
    local nHandle = Read.nHandle  
    local nMiniGameId = Read.nMiniGameId  
    local tUser = PublicUserInfo.GetUserInfo(nUserId)
    if not tUser then 
        tBase.Log("_ExchangeLogic  nUserId: %d   tUser is nil   ",nUserId)
        return 
    end  
    local nGroupId = PublicUserInfo.Get_User_GroupId(nUserId)
    local tCfg = _GetMiniGameCfg(nGroupId)
    if not tCfg or not tCfg.nExChangeRatio or not tCfg.nExChangeLimit then 
        tBase.Log("_ExchangeLogic  nUserId: %d  nGroupId: %d  tCfg is nil  %s  "
        ,nUserId,nGroupId,cjson.encode(tCfg))
        local tSend = ProtoMgr.Gateway_pb.MiniGame_PublicRsp()
        tSend.nHandle = nHandle
        tSend.nResult = -1        
        local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.MiniGame_PublicRsp)
        s:AddString(tSend:SerializeToString())        
        local s = tBase.GetSP().new2(s:GetData(), s:GetSize())
        s:SendData(tBase.GetNetworkEngine(), ClientID)
        return 
    end 
    local nNowExChange = _Handle_MiniGame_ExChangeLimit(1,nUserId)
    local nExChangeRlt = 1
    local tSend = ProtoMgr.Gateway_pb.MiniGame_PublicRsp()
    tSend.nHandle = nHandle
    if nHandle == 1 then -- 打开兑换界面 
        tSend.nExChangeRatio = tCfg.nExChangeRatio  -- 兑换比例 (打开兑换界面)
        tSend.nExChangeLimit = tCfg.nExChangeLimit   -- 每日可兑换上限 (打开兑换界面)
    elseif nHandle == 2 then
        local nExChange = tonumber(Read.nExChange) or 0  -- 兑换数量    
        local nMiniGold = PublicUserInfo.Get_User_Gold(nUserId,100) --  获取小游戏币 
        if nMiniGold < nExChange then 
            nExChangeRlt = 2
        end 
        tBase.Log("_ExchangeLogic  nUserId: %d  小游戏兑换: %d ",nUserId,nExChange)

        -- 是否超出上限 
        if tCfg.nExChangeLimit <= nNowExChange or tCfg.nExChangeLimit < nNowExChange+nExChange then 
            nExChangeRlt = 3
        end 
        -- 兑换成功
        if nExChangeRlt == 1 then 
            local nChange = nExChange * tCfg.nExChangeRatio 
            local nSourceType =10000 + 100* nMiniGameId + 9   -- 小游戏币 兑换金币类型
            local nItemId = 1
            PublicUserInfo.ChangeUserTreasure({nUserID=nUserId,nItemID=nItemId,nDel=nChange,nSourceType=nSourceType,isNotCheck=true})
            local nItemId = 100
            PublicUserInfo.ChangeUserTreasure({nUserID=nUserId,nItemID=nItemId,nDel=-nExChange,nSourceType=nSourceType,isNotCheck=true})            
            
            nNowExChange = _Handle_MiniGame_ExChangeLimit(2,nUserId,nExChange)
            tBase.Log("_ExchangeLogic   兑换成功 nUserId_%d   nExChange_%.1f nChange_%.1f  nMiniGameId_%d ",nUserId,nExChange,nChange,nMiniGameId)        
                    
            -- 写战绩: 目的 APP 拉账用
            local tData ={}
            tData.nUserId = nUserId
            tData.nGameType = nMiniGameId
            tData.nSession = 1
            tData.nWinlose = nChange 
            tData.nDrawWater = 0
            tData.sPaiJuId = ""
            tData.nShopId = tonumber(tUser.nShopID)
            tData.nXiaZhu=  0
            tData.nValid= 0 
            tData.nGroupId =nGroupId 
            tData.IsControl = false 
            tData.tElseInfo={}        
            RecordDbr.Write_WinLoseRecord(tData)      
            
            local sDomainName = PublicRedis._GetSurrenderUrl()
            if not sDomainName then 
                tBase.Log("_ExchangeLogic   sDomainName  is nil ")
                return
            end  
            local sUrl = string.format("table/SetProfitWash?memberId=%d&orderNo=%d&amount=%.1f",nUserId,os.time(),nChange)
			local sHttp = sDomainName..sUrl
			tBase.Log("_ExchangeLogic   上报APP  sHttp: %s  ",sHttp)
			tBase.PublicPushWebHttp(sHttp) 	
        
        end 
        tSend.nExChangeRlt = nExChangeRlt  --兑换结果 (请求兑换) 1成功、0失败、2金币不足、3超每日兑换上限 
    end  
    -- 获取最新金币
    local nGold = PublicUserInfo.Get_User_Gold(nUserId,1) --  获取小游戏币 
    local nMiniGold = PublicUserInfo.Get_User_Gold(nUserId,100) --  获取小游戏币   
    tSend.nGold = nGold     --  当前金币
    tSend.nMiniGold = nMiniGold  -- 当前游戏币  
    tSend.nNowExChange = nNowExChange  -- 当前游戏币       

    local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.MiniGame_PublicRsp)
    s:AddString(tSend:SerializeToString())        
    local s = tBase.GetSP().new2(s:GetData(), s:GetSize())
    s:SendData(tBase.GetNetworkEngine(), ClientID)
    tBase.Log("_ExchangeLogic  小游戏兑换_%d nUserId_%d  [%.1f、%.1f]  %d nRlt %d  tCfg: %s  "
    ,nHandle,nUserId,nGold,nMiniGold,nNowExChange,nExChangeRlt,cjson.encode(tCfg))

    return 
end


return PublicMiniGame
 