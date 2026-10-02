--[[
	建立主从关系 架构 公共部分

    使用方式：
    主从服在监听协议 调用该接口 PublicLiveGame.Reg()   
    只需要从服 开服的时候 调用 PublicLiveGame.StartLiveGameRegist() 
     
-- ]]

local tBase  = require("base")         -- 基础功能接口 
local cjson     = require("cjson")        -- json   
local ProtoManager = require("ProtoManager")   -- 协议管理对象  
local tLiveCSRelation =require("LiveCSRelation")
local Quick = require("Quick")
local tSrvInfo = require("ServerInfo")
local Typename = require("typename")
local Api = require("publicApi") -- 共用功能接口

--主服务器管理
PublicLiveGame = {
    nCenterId = nil,   -- 游戏服 key 
    sCenterKey = nil,  -- 游戏服 key 
    arrSlave = {},  -- 直播主服 
}

-- 主从之间 通信 协议 
PublicLiveGame.Msg ={
    sMsgM = "MASTER_SLAVE",             -- 通知从服
    sTableHandle = "REQ_TABLEHANDEL",   -- 牌桌操作(开关桌)
    sScence      = "REQ_TABLESCENCE",   -- 牌桌场景
    sNotify      = "REQ_TABLENOTIFY",   -- 广播消息
    sInformGame  = "REQ_INFORMGAME",    -- 竞猜服 通知 游戏服
    sAddSlave    = "MSG_ADDSLAVE",      -- 添加从服成功
}
 
-- 共用定时器
PublicLiveGame.Timer = {
    nResitTimer = tBase.m_wTimer_ID_LiveGameResit,          
    nLogonToCenterTimer = tBase.m_wTimer_ID_LogonToCenter,
    nCenterServIdTimer =  tBase.m_wTimer_ID_CenterServId,
    nCenterServKeyTimer = tBase.m_wTimer_ID_CenterServKey,
}


local Protocol = ProtoManager.PubProto_1_pb.MasterSlave_Proto()  -- 协议
local ProStruct = ProtoManager.PubProto_1_pb                      -- 数据结构


-- 监听协议
function PublicLiveGame.Reg()     
    Quick.Reg()
    tBase.RegFunc(Protocol.Main,Protocol.SUB_REQ_ADDSLAVE, PublicLiveGame.AddLiveGame)       -- 请求 登录游戏服 
    tBase.RegFunc(Protocol.Main, Protocol.SUB_REP_ADDSLAVE, PublicLiveGame._LogonCenterRep)  -- 返回 登录游戏服   
end

---------------------------------------------------------------------------------------------
-- 主服 
---------------------------------------------------------------------------------------------
 
-- 主服 加入
function PublicLiveGame.AddLiveGame(sClientID, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local nMainID = ReadData:GetModuleID() 
    local nSubID = ReadData:GetMsgID()

    local tRead = ProStruct.Req_AddSlave()
    tRead:ParseFromString(ReadData:GetString()) 
    tBase.Log("_AddLiveGame 主服加入 nSlaveId:%d sKey:%s nGameId：%d", tRead.nSrvId, tRead.sKey,tRead.nGameId)    
    PublicLiveGame.AddSlaveToCenter(tRead.nSrvId, tRead.sKey,tRead.nGameId)

    -- 回复 
    local tSend = ProStruct.Rep_AddSlave()
    tSend.nSrvId = ServerInfo.nServerId
    tSend.sKey = tBase.m_tKey
    tSend.nResult = 1
    local s = tBase.GetSP().new(Protocol.Main,Protocol.SUB_REP_ADDSLAVE)
    s:AddString(tSend:SerializeToString())
    tBase.PostToClient(sClientID, s:GetData(), s:GetSize())
    tBase.Log("_AddLiveGame 主服,从服务器加入主服 返回 nSlaveId:%d sKey:%s", tRead.nSrvId, tRead.sKey)
    return 
end

--  加入中心服
function PublicLiveGame.AddSlaveToCenter(nSlaveId, sSlaveKey,nGameId)
    local t = {nSlaveId=nSlaveId, sSlaveKey=sSlaveKey,nGameId=nGameId or 0}
    local IsSlaveKey = true 
    tBase.LogT("PublicLiveGame.arrSlave_", PublicLiveGame.arrSlave)   
    for k,t in pairs(PublicLiveGame.arrSlave) do
        if t.nSlaveId == nSlaveId and t.sSlaveKey ==sSlaveKey then 
            IsSlaveKey = false
        end 
    end
    if IsSlaveKey then 
        table.insert(PublicLiveGame.arrSlave, t)
        tBase.Log("_AddSlaveToCenter 主服, 从服务器加入主服 成功 nGameId_%d nSlaveId:%d sKey:%s",nGameId,nSlaveId,sSlaveKey)
        
        --添加从服成功，发送消息告诉对应的中心服
        local sKey = tBase.m_tKey
        if sKey then
            Quick.SendMsgToTargetServer(sKey, {["sMsgM"]="inner", ["sMsgS"]=PublicLiveGame.Msg.sAddSlave, tData=t})
        end
    end     
end

-- 通知 直播主服 
function PublicLiveGame.SendLiveGame(SendData,nDateSize)
    for _, v in pairs(PublicLiveGame.arrSlave) do 
        -- tBase.Log("_SendLiveGame  广播直播主服 %s  ",v.sSlaveKey)
        if v.sSlaveKey then 
            tBase.PostToServer(v.sSlaveKey, 0, SendData, nDateSize)                
        end 
    end 
end

 
-- 主服 -----> 从服  

--广播消息到从服务器
function PublicLiveGame.BrocastToSlave(sMsgM, sMsgS, tMsg) 
    for _, v in pairs(PublicLiveGame.arrSlave) do        
        Quick.SendMsgToTargetServer(v.sSlaveKey, {["sMsgM"]=sMsgM, ["sMsgS"]=sMsgS, tData=tMsg}) 
    end 
end
 
-- 游戏 转发 旁观服
function PublicLiveGame.GameTransmitLooker(sClientID,strProto,tPacket)   
    local s = tBase.GetSP().new(Protocol.Main,Protocol.SUB_MasterTransmitSlave)   
    s:AddString(sClientID)  
    s:AddString(strProto) 
    s:AddBuff(tPacket:GetData(),tPacket:GetSize()) 
    PublicLiveGame.SendLiveGame(s:GetData(),s:GetSize())   
    return 
end

-- 游戏 广播旁观服
function PublicLiveGame.TransmitProtobuf(sTableId,strProto,tPacket)   
    local s = tBase.GetSP().new(Protocol.Main,Protocol.SUB_MasterBroadcastSlave)  
    s:AddString(sTableId) 
    s:AddString(strProto) 
    s:AddBuff(tPacket:GetData(),tPacket:GetSize())   
    PublicLiveGame.SendLiveGame(s:GetData(),s:GetSize())   
    return 
end

-- 多级广播: 游戏服--> 直播主服--> 直播从服 
function PublicLiveGame.MultistepBrocast(sMsgS,tData)  
    PublicLiveGame.BrocastToSlave(PublicLiveGame.Msg.sMsgM,sMsgS,tData)  
    return 
end
 

---------------------------------------------------------------------------------------------
-- 从服  
---------------------------------------------------------------------------------------------
 
--从服务器加入
function PublicLiveGame._LogonCenterRep(sClientID, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local nMainID = ReadData:GetModuleID() 
    local nSubID = ReadData:GetMsgID()
    local tRead = ProStruct.Rep_AddSlave()
    tRead:ParseFromString(ReadData:GetString())
    if tRead.nResult == 0 then 
        tBase.Log("_LogonCenterRep  直播主服注册 收到 游戏服返回   nResult:%d",tRead.nResult)
        return
    end 
    tBase.Log("_LogonCenterRep 从服,从服务器加入成功 sKey_%s  ",tRead.sKey)
    PublicLiveGame.sCenterKey = tRead.sKey 
    return 
end

--发送登陆协议到中心服(心跳)
local function LogonToCenter()
    local tSend = ProStruct.Req_AddSlave()
    tSend.nSrvId = ServerInfo.nServerId
    tSend.sKey = tBase.m_tKey

    local nGameId = PublicLiveGame.GetGameId(tSend.sKey)
    if nGameId then
        tBase.Log("LogonToCenter  获得 中心服key sKey:_%s 对应的nGameId_%d",tSend.sKey,nGameId)  
    else
        tBase.Log("LogonToCenter  中心服key sKey:_%s 对应的游戏GameId没有找到 ",tSend.sKey)
        return
    end
    tSend.nGameId = nGameId
    tBase.Log("LogonToCenter nSrvId_%d sKey_%s nGameId_%d",tSend.nSrvId,tSend.sKey,nGameId)

    local s = tBase.GetSP().new(Protocol.Main,Protocol.SUB_REQ_ADDSLAVE)
    s:AddString(tSend:SerializeToString())
    tBase.PostToServer(PublicLiveGame.sCenterKey, 0, s:GetData(), s:GetSize())   
    return 
end

--获得本服对应的中心服id
local function _GetTheCenterServId(nTimerId)
    local function tFunc()
       PublicLiveGame.nCenterId  = tLiveCSRelation.GetCenterServId(ServerInfo.nServerId)
       if PublicLiveGame.nCenterId then
            tBase.Log("_GetTheCenterServId    nCenterId: %d",PublicLiveGame.nCenterId)
            return
        end
        -- tBase.Log("_GetTheCenterServId   获取nServerId_%d 对应 nCenterId  ",ServerInfo.nServerId)
        tLiveCSRelation.ReqDbLiveCSRelation()
        tBase.SetTimer(nTimerId, 1000*2, 1, tFunc,true)   

        tBase._SlaveRelevanceSendTelegram()
        
    end
    tFunc()
end

--获得本服对应的中心服key
local function _GetTheCenterServKey(nTimerId)
    local function tFunc()
        if PublicLiveGame.nCenterId then 
            local sServKey =  tBase.GetServerIdIdKey(PublicLiveGame.nCenterId)
            if not sServKey then  
                tBase.Log("_GetTheCenterServKey  nCenterId:_%d  对应 中心服key  is nil ",PublicLiveGame.nCenterId) 
            else
                PublicLiveGame.sCenterKey=sServKey                
            end 
        end 
        if PublicLiveGame.sCenterKey then
            tBase.Log("_GetTheCenterServKey  获得对应 中心服key sCenterServKey:_%s",PublicLiveGame.sCenterKey)                     
            LogonToCenter()    --登陆中心服
            tBase.SetTimer(PublicLiveGame.Timer.nLogonToCenterTimer,1000*60, -1,LogonToCenter,true)       
            return
        end
        tBase.SetTimer(nTimerId, 1000*3, 1, tFunc,true)   
    end
    tFunc()
end

function PublicLiveGame.AddSlave()
    if PublicLiveGame.sCenterKey then
        return
    end
    -- tBase.Log("_AddSlave  从服务器 请求加入主服")
    _GetTheCenterServId(PublicLiveGame.Timer.nCenterServIdTimer)
    _GetTheCenterServKey(PublicLiveGame.Timer.nCenterServKeyTimer)   
    return 
end 

-- 获取 机器人 游戏服ID 
function PublicLiveGame.GetRandomServerId(nGameId)
    local arrServerId ={}
    for _,v in pairs(PublicLiveGame.arrSlave) do
        if v.nGameId and v.nGameId == nGameId then         
            table.insert(arrServerId,v.nSlaveId)
        end 
    end
    if #arrServerId==0 then
        return nil
    end
    local nRandomDex =math.random(1,#arrServerId)
    return arrServerId[nRandomDex]
end

-- 开始向 游戏服定时请求 注册 
function PublicLiveGame.StartLiveGameRegist()
    tBase.Log("_AddSlave  开始建立主从服关系 ")
    PublicLiveGame.AddSlave()
    tBase.SetTimer(PublicLiveGame.Timer.nResitTimer, 1000*10, -1, PublicLiveGame.AddSlave,true)  
    return  
end
 

-- 从服 -----> 主服  

-- 向主服发通知
function PublicLiveGame.SendToMaster(SendData,nDateSize)
    if PublicLiveGame.sCenterKey then  
        tBase.PostToServer(PublicLiveGame.sCenterKey,0, SendData, nDateSize)  
    else
        tBase.Log("_SendToMaster sCenterKey is nil")
        return
    end 
end

function PublicLiveGame.GetGameId(ServerKey)
    local sGameName,sServerId = Api.GetGameNameByServerKey(ServerKey)
    local nGameId = nil
    if sGameName == Typename.FellTreeSlave or sGameName == Typename.FellTreeCenter then --砍树
        nGameId = 158
    elseif  sGameName == Typename.LiveM or sGameName == Typename.LiveS then --直播主服
        nGameId = 231
    elseif sGameName == Typename.dezhouslave or sGameName == Typename.texas then --直播德州
        nGameId = 140
    elseif sGameName == Typename.BasketballSlave or sGameName == Typename.BasketballCenter then --直播篮球
        nGameId = 160
    else
        tBase.Log("GetGameId ServerKey_%s 找不到对应游戏ID",ServerKey)
    end
    return nGameId
end

return PublicLiveGame
