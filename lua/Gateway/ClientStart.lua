package.path = require("./lua/Gateway/Head").path

local m = require("base") -- 基础功能接口
local api = require("publicApi") -- 共用功能接口
local tCScriptCfg = require("CScriptCfg")
local tname = require("typename") -- 类弄定义接口
local dbInfo = require("DBInfo") -- 数据库连接信息 
local ProtoMgr = require("ProtoManager") -- 协议管理对象  
local mlogger = require("logger") -- 日志对象  
local tPubUser = require("PublicUserInfo") -- 用户信息  
local tVarsion = require("Version")
local tUserIP = require("UserIpInfo")
local tSrvInfo = require("ServerInfo")
local tParserAux = require("ParserAux")
local tReforwardRule  =require("ReforwardRule")
local tTimerId =require("TimerId")
local tGameConfig =require("GameConfig") 
local tMaintenance =require("Maintenance") 
local tAdNoticeNote = require("AdNoticeNote")
local cjson = require("cjson")
local tAdNoticeCfg = require("AdNoticeCfg")
local rdf = require("redisdefine")
local tLiveCSRelation =require("LiveCSRelation")
local tGameLogon =require("GameLogon")
local tPublicUserOnLineStatus =require("PublicUserOnLineStatus")
local tPublicRedis =require("PublicRedis")
local PublicMiniGame =require("PublicMiniGame")

 
local MaintainerCmd= ProtoMgr.Maintainer_pb.Maintainer_Proto()
local MaintainerAux =tParserAux.MaintainerAux
local LogAux =tParserAux.LogAux
local LogCmd =ProtoMgr.Log_pb.Log_Proto()
local DbCmd =ProtoMgr.DbServer_pb.Db_Proto()  
local BurProto = ProtoManager.Bur_pb.BurProto() 
local BackstageAux =tParserAux.BackstageAux
local Backstage_pb =ProtoMgr.Backstage_pb
local BackstageCmd=Backstage_pb.Backstage_Proto() 
local CMD_LiveSlave =ProtoMgr.LiveSlave_pb.LiveSlave_Proto() 
local ChatPro = ProtoManager.Chat_pb.Chat_Proto()  
local LobbyAux =tParserAux.LobbyAux
local LobbCmd = ProtoManager.LobbyPro 


--网关之间通信命令
local GateWayCmd ={
    nMainCmd=1897,
    nKickReq=123,
    nKickRsp=124,
}

local tClientLogFile={} --fileName be key
-- 玩家功能回调
local ClientSink = { LevelLog = nil } 
ClientSink.m_ClientList = {} -- 保存每个玩家的信息的链表

function ClientSink:new( table )
    local t =  table or {}
    self.__index = self
    setmetatable(t,self)
    return t
end

-- 启动服务器
function ClientSink.OnStart()
    -- 设置日志目录：
    local sLogDir =  dbInfo.LogDir.."Gateway/".. m.GetPort() .. "-" .. m.GetThreadIndex()
    mlogger.SetFile( sLogDir , "Gateway", m )
    
    -- 设置全局等级
    mlogger:setLevel( mlogger.LogObject.DEFAULT, "Gateway" )
    -- 消息接收处理，不用默认函数
    m.m_MyMonitorFun =function(...) return ClientSink.onMsgRecv(...) end --这样写可以热更
    -- 注册服务器
    m.RegServer(tname.gateway)
    -- 版本信息加载
   -- tVarsion.RequestVersion()
    m.SetTimer(tTimerId.GetATimerId(), 1000*60*1, -1, tVarsion.onTimerRequestVersion)
    -- m.SetTimer(tTimerId.GetATimerId(), 1000*60*10, -1, tUserIP.onTimerLoaderIpInfo)
    tAdNoticeNote.m_client_sink_list = ClientSink.m_ClientList
    tAdNoticeNote.arrAllCfg = tAdNoticeCfg
   local hotFunc =function()
    local patchModuleName ="GatewayPatch"
    package.loaded[patchModuleName] = nil
    require(patchModuleName)
   end
    -- m.SetTimer(tTimerId.GetATimerId(), 1000*60*2, -1, hotFunc)                                  --热更
    m.SetTimer(tTimerId.GetATimerId(), 1000*6, 1, tReforwardRule.onTimerRefowardRuleReq)        --转发规则
    m.SetTimer(tTimerId.GetATimerId(), 1000*60*1, -1, tReforwardRule.onTimerRefowardRuleReq)    --转发规则
    m.SetTimer(tTimerId.GetATimerId(), 1000*8, 1, tAdNoticeCfg.ReqDbAdNoticNoteList)
    m.SetTimer(tTimerId.GetATimerId(), 1000*60*10, -1, ClientSink.UpdataOnlineNum)
    tGameConfig.SetIsNeedGameList(false)    --不需要获取游戏列表(只获取店与组的关系表)
    local loadConfig=function()
        tGameConfig.Req_AllDbConfig(0)
        tLiveCSRelation.ReqDbLiveCSRelation()
    end
    m.SetTimer(tTimerId.GetATimerId(), 1000*6, 1, loadConfig)          --店与组关系表
    m.SetTimer(tTimerId.GetATimerId(), 1000*60*1, -1, loadConfig)      --店与组关系表
    m.SetTimer(tTimerId.GetATimerId(), 1000*10, -1, tMaintenance.OnTimerReadMaintenanceData)    --服务器维护信息读取
    m.SetTimer(tTimerId.GetATimerId(), 1000*10, -1,tReforwardRule.OnTimerGetServerIdOfBan)  --服务器id维护列表读取
    m.SetTimer(tTimerId.GetATimerId(), 1000*60*5, -1, tPublicUserOnLineStatus.OnTimerClearUserData)  --定时清理离线玩家数据 5分钟
    m.SetTimer(tTimerId.GetATimerId(), 1000*8, 1, tReforwardRule.ReqDbWhitList)   --获取白名单配置
    ClientSink.LoadGateData()
end

--起服
function ClientSink.LoadGateData()
    tPubUser.SetGateKeyPortOnline(rdf.GateWay_key.GateList, m.m_tKey, tSrvInfo.nIp, tSrvInfo.nPort, tSrvInfo.nSocketType, 0)
end

--服务器停止
function ClientSink.OnStop()
    mlogger:info(string.format("Gateway Server OnStop m_tKey:%s tSrvInfo:%s GateKey:%s",rdf.GateWay_key.GateList,cjson.encode(tSrvInfo), m.m_tKey ) )
    ClientSink.ClearGateData()
    m.UnRegServer()
end

function ClientSink.ClearGateData()
    if m.m_MyRedisData[1].redis:hdel(rdf.GateWay_key.GateList,m.m_tKey) then
        mlogger:debug("dGateWayAdd_succ")
    else
        mlogger:debug("dGateWayAdd_fail")
    end
end

local function _NewClientInfo(ClientID,sIp,port)
    local clientinfo = {}
    clientinfo.ClientID = ClientID
    clientinfo.ip = sIp
    clientinfo.port = port
    clientinfo.tmp = 0
    clientinfo.nID = 0 --直属玩家归属唯一ID
    clientinfo.sChannel = ""
    clientinfo.Server = {} -- 保存转发服务器的KEY
    clientinfo.IsLogon = false -- 是否登陆成功
    clientinfo.nUserId = 0 -- 登录验证过才有userId
    clientinfo.nShopId=-1  --对应登陆成功后的玩家分店id   
    clientinfo.IsOnline = true -- 玩家在线状态
    clientinfo.isToClose = false --连接是否即将关闭 (目前只有挤号时，服务器才会主动关闭该玩家先前的连接)
    clientinfo.isDataComeFromThisSrv = true --玩家数据来源(本服或者其他服)
    clientinfo.LogObj =nil         --本连接日志文件对象 (用于给前端写入日志)

    -- 记录玩家游戏
    clientinfo.nGameId = -1
    clientinfo.nRoomId = -1
    clientinfo.nAcceptTime = m.GetTime()   -- 连接时间

    clientinfo.SpecialReforwardRule=   --直播游戏需要到的选服需求
    {
        stypename=nil,                  --需要特殊选服的typename
        nCenterServId=nil,
    }
    clientinfo.sRealIp = nil --真实ip

    return clientinfo
end

--有新用户连接
function ClientSink.OnAccept(ClientID, ip, port)
    local sIp = api.Dword2String(ip)  -- 将IP转换为点分十进制形式表示 
    m.Log("OnAccept: ClientID_%d ip_%s port_%d sIp_%s ", ClientID, ip, port,sIp)
    -- 创建用户信息
    ClientSink.m_ClientList[ClientID] = _NewClientInfo(ClientID, ip, port) --将信息加入链表
    tPubUser.IncrConnection()

    local tAccptInfo = {}
    tAccptInfo.ip = sIp
    tAccptInfo.port = port
    tAccptInfo.ClientID = ClientID  
    ClientSink.SetUserAcceptInfo(tAccptInfo)
end-- ws 握手信息
function ClientSink.OnHandShake(ClientID, info)
    m.Log("OnHandShake:"..info)
    local patternIp = 'real%-ip%s*%:%s*(%d+%.%d+%.%d+%.%d+)'
    --local patternHost = 'Host%s*%:%s*(%d+%.%d+%.%d+%.%d+)'
    local sIp =string.match(info, patternIp)
    --local sHost =string.match(info, patternHost)
    if not sIp then
        return
    end
    m.Log("OnHandShake ClientID:%d 真实ip:%s",ClientID,sIp)
    local sClientID = m.m_tKey .. ":" .. math.ceil(ClientID)
    local sKey = "UserAcceptInfo_"..sClientID
    local sSubKey = "real_ip"
    m.m_MyRedisData[1].redis:hset(sKey,sSubKey,sIp)

    ClientSink.m_ClientList[ClientID].sRealIp = sIp
end

-- 设置玩家连接信息
function ClientSink.SetUserAcceptInfo(tAccptInfo)
    local sClientID = m.m_tKey .. ":" .. math.ceil(tAccptInfo.ClientID)
    local sKey = "UserAcceptInfo_"..sClientID
    m.m_MyRedisData[1].redis:hmset(sKey, tAccptInfo)
    m.m_MyRedisData[1].redis:expire(sKey,10)
end

local function BroadCastUserClose(client)
    local nUserId =client.nUserId
    if nUserId==nil or nUserId==0 then return end
    local tSend = ProtoMgr.Gateway_pb.RUQ_User_Line()
    tSend.nUserID  = nUserId
    local s = m.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_GATEWAY_CLIENT_CLOSE)
    for k, v in pairs(client.Server) do
        if k ~= tname.gateway then               
            s:AddString(tSend:SerializeToString())
            ClientSink.PostToServer(k, client, s:GetData(), s:GetSize())
            m.Log("_BroadCastUserClose   UserId:%d   servername_%s  ",client.nUserId,k)
        end
    end
end
local function KickOutUserFromLocalGate(client)
    BroadCastUserClose(client)    --通知其它服务器，该玩家连接关闭
    if ClientSink.FindClientByUserId(client.nUserId) then
        m.Log("have new client info UserId:%d",client.nUserId)
        return
    end
    tPublicUserOnLineStatus.OffLine(client.nUserId)
    tPubUser.DelGateKey(client.nUserId,m.m_tKey)
    local isDelSuccee,sFailReason =tPubUser.TryDelUserInfo(client.nUserId)
    m.Log("KickOutUserFromLocalGate UserId:%d isDelSuccee:%s sFailReason:%s", client.nUserId, tostring(isDelSuccee), sFailReason or "")
    if sFailReason and sFailReason=='Playing' then      --如果是因为在游戏中而删除失败
        tPubUser.ExpireUserInfo(client.nUserId, 60*60*1)   --断线后，假设一局游戏 2小时内会结束。(防卡房)
    end
end

--连接关闭
function ClientSink.OnClose(ClientID)
    m.Log("OnClose:ClientID_%d",ClientID)
    tPubUser.DecrConnection()
    local client = ClientSink.m_ClientList[ClientID]
    if client == nil then
        m.Log("Err happen,why client is nil")
        return
    end
    m.Log("玩家连接关闭 UserId:%d", client.nUserId)
    ClientSink.m_ClientList[ClientID] = nil
    
    if client.nUserId==nil or client.nUserId==0  then --or client.IsLogon==false
        m.Log("ClientID_%d can not find userid",ClientID)
        return
    end
    KickOutUserFromLocalGate(client)
end

function ClientSink.LoadData(nUserId, nCurClientId)
    local clientinfo = ClientSink.m_ClientList[nCurClientId]
    local t = ClientSink.GetGateWaySwapData(nUserId)
    for k, v in pairs(t) do
        m.Log("GateWay Data: %s, %s", k, v)
        clientinfo.Server[k] = v
    end
    clientinfo.isDataComeFromThisSrv = false
    ClientSink.ClearGateWaySwapData(nUserId)
end


function ClientSink.SetGateWaySwapData(clientinfo, t)
    m.m_MyRedisData[1].redis:hmset("GateWayData" .. clientinfo.nUserId, t)
end

function ClientSink.GetGateWaySwapData(nUserId)
    return m.m_MyRedisData[1].redis:hgetall("GateWayData" .. nUserId)
end

function ClientSink.ClearGateWaySwapData(nUserId)
    m.m_MyRedisData[1].redis:del("GateWayData" .. nUserId)
end


function ClientSink.SaveData(clientinfo)
    local t = {}
    for k, v in pairs(clientinfo.Server) do
        t[k] = v
    end
    ClientSink.SetGateWaySwapData(clientinfo, t)
end

local function MainIdToName(MainID)
    if MainID >= 0 and MainID < 100 then -- 登陆服务
        return tname.logon
    end
    if MainID == 101 then -- 大厅服务
        return tname.lobby
    end
    if MainID == 110 then -- 聊天
        return tname.chat
    end 
    if MainID >= 600 and  MainID < 700 then  -- web服
        return tname.web
    end
    if MainID == 201 then 
        return tname.niuniu
    elseif MainID == 201 then 
        return tname.niuniu
    elseif MainID == 202 then 
        return tname.niuniu
    elseif MainID == 203 then 
        return tname.niuniu
    elseif MainID == 204 then 
        return tname.brniuniu
    elseif MainID == 205 then 
        return tname.zhajinhua
    elseif MainID == 206 then 
        return tname.dian21
    elseif MainID == 207 then 
        return tname.baijiale
    elseif MainID == 208 then 
        return tname.mahjong
    elseif MainID == 212 then 
        return tname.tuidaohu
    elseif MainID == 213 then 
        return tname.sangong
    elseif MainID == 214 then 
        return tname.baijiale
    elseif MainID == 215 then 
        return tname.qzbaijiale     --抢庄百家乐
    elseif MainID ==216 then
        return tname.paijiu     --牌九
    elseif MainID ==217 then
        return tname.tbbaijiale     --通比百家乐
    elseif MainID==218 then
        return tname.BaiRenZhaJinHua   --百人炸金花
    elseif MainID == 220 then
        return tname.erbagang     -- 二八杠
    elseif  MainID ==221 then
        return tname.DdzHuanLe
    elseif  MainID ==222 then
        return tname.yuxiaxieslave
    elseif MainID==300 or MainID==301 then --301是处理自动下注的协议
        return tname.BaiJiaLeSlave    --直播百家乐 
    elseif MainID==219 then
        return tname.BoDeng   --搏灯
    elseif MainID==224 then
        return tname.yuxiaxieJH --集合鱼虾蟹
    elseif MainID==253 then
        return tname.gaobo      --高博
    elseif MainID==227 then     --飞行棋小游戏
        return tname.pilotmslave  --tname.PilotSmallGame 以前的下注服命令发飞行棋服
    elseif MainID==259 then
        return tname.pilotmslave
    elseif MainID==228 then
        return tname.PilotGuessGame
    elseif MainID==260 then
        return tname.SeDieHJSlave
    elseif MainID==230 then
        return tname.SeDie      --色碟
    elseif MainID==229 then     --德州扑克(从服)
        return tname.dezhouslave        
	elseif MainID==252 then     --骰宝
        return tname.toubaoslave    
    elseif MainID==255 then     --直播色碟游戏服
        return tname.SeDieMSlave
    elseif MainID==263 then  --俱乐部从服
        return tname.ClubSlave 
    elseif MainID==302 then     --直播旁观服
        return tname.LiveS        
    elseif MainID==311 then     --足球
        return tname.FootBallSlave
    elseif MainID==312 then     --砍树
        return tname.FellTreeSlave
    elseif MainID==313 then     --篮球
        return tname.BasketballSlave
    elseif MainID==231 then     --俱乐部德州
        return tname.clubdezhouslave
    elseif MainID==232 then     --俱乐部短牌
        return tname.TexasShortCardSlave
    elseif MainID==234 then     --俱乐部抢庄牛
        return tname.ClubQiangZhuangNiu
    elseif MainID==307 then     --直播龙虎
        return tname.LongHuSlave
    elseif MainID==309 then     --直播牛牛
        return tname.NiuNiuSlave
    elseif MainID==331 then     --老司机
        return tname.OldHand
    elseif MainID==332 then     --弹球
        return tname.TanQiu
    elseif MainID==333 then     --地鼠
        return tname.DiShu
    elseif MainID==334 then     --弹线
        return tname.TanXian
    elseif MainID==317 then     --红黑彩
        return tname.BRLottellySlave
    elseif MainID==337 then     --德州比赛
        return tname.TexasCup
    elseif MainID==320 then
        return tname.JackLot
    elseif MainID and MainID > 0 then   -- 新增游戏 
        return  RedisCahche._GetMainIdToTypeName(MainID)             
    end
end

function ClientSink.SendMaintenanceNotify(ClientID,sTimeStart,sTimeEnd,nStartTimestamp,nEndTimestamp)
    local MaintenanceNotify={}
    MaintenanceNotify.sTimeStart =sTimeStart or 'unknown'
    MaintenanceNotify.sTimeEnd =sTimeEnd or 'unknown'
    MaintenanceNotify.nStartTimestamp=nStartTimestamp
    MaintenanceNotify.nEndTimestamp =nEndTimestamp
    local tPacket =MaintainerAux:Encode('MaintenanceNotify',MaintenanceNotify)
    local s = m.GetSP().new2(tPacket:GetData(), tPacket:GetSize())
    s:SendData(m.GetNetworkEngine(), ClientID)
end

function ClientSink._IsOnLineAndPlaying(clientinfo)
    if (not clientinfo.IsLogon) or  (not clientinfo.nUserId) then
        return false
    end
    local nGameId =tPubUser.GetUserPlayingGame(clientinfo.nUserId)
    if not nGameId then
        return false
    end
    return true
end

function ClientSink._ServId_MaintenanceCheck(clientinfo,nCenterServId)
   local tem= tPublicRedis.BlockchainStopServerMaintian(nCenterServId)
   if tem ==nil or tem.nType ~=0 then
     return true
   end
   if tem.nPassTime<=30 then
     return true
   end
   if tPublicRedis.IsWhiteListUser(clientinfo.nUserId) then
    return true
   end

   ClientSink.SendMaintenanceNotify(clientinfo.ClientID,tem.sStartTime,tem.sEndTime,tem.ActualStart,tem.ActualEnd)
   ClientSink.ToCloseCliendId(clientinfo.ClientID,false)
   m.Log("维护回复_ ClientID_%d",clientinfo.ClientID)
   return false
end

function ClientSink._MaintenanceCheck(clientinfo,MainID,SubID)
    if not clientinfo.IsLogon then
        return true
    end
    if tMaintenance.IsNotMaintenance() then
        return true
    end
    local nGroupId = tGameConfig.GetGroupId(clientinfo.nShopId)
    local isMaintenance,sStartTime,sEndTime,nActualStart,nActualEnd =tMaintenance.IsMaintenance(nGroupId,clientinfo.nUserId,MainID,SubID)
    if not isMaintenance then
        return true
    end
    if tMaintenance.IsLetPlayingUserPass() then
        if ClientSink._IsOnLineAndPlaying(clientinfo) then
            return true
        end
    end
    ClientSink.SendMaintenanceNotify(clientinfo.ClientID,sStartTime,sEndTime,nActualStart,nActualEnd)
    ClientSink.ToCloseCliendId(clientinfo.ClientID,false)
    m.Log("_MaintenanceCheck 维护回复 ClientID_%s  MainID_%d SubID_%d ",clientinfo.ClientID,MainID or -1,SubID or -1)
    return false
end


-- 收到外网发过来的协议
function ClientSink.OnRecv(ClientID, Data, Len)
    local r = m.GetRP().new(Data, Len)
    -- 根据协议进行内网转发
    local MainID = r:GetModuleID()
    local SubID = r:GetMsgID()
    local clientinfo = ClientSink.m_ClientList[ClientID]
    if clientinfo==nil then                                          --clientinfo在accept时创建，ClientID关闭时才同步销毁
       assert(false,"Err happen,clientinfo is nil:ClientID_"..(ClientID or "nil"))
       return
    end
    m.Log("_OnRecv 外网消息:MainID_%d SubID_%d Len_%d ClientID_%d nUserId_%d",MainID,SubID,Len,ClientID,(clientinfo.nUserId or 0))
    if clientinfo.isToClose then                                     --连接即将关闭，这时前端不应该再发消息来
        m.Log("_OnRecv Err may be happen,this connect is to close")
        return
    end
    if MainID==MaintainerCmd.Main_CMD then                          --版本请求请求处理
        ClientSink.OnMaintainerProto(ClientID, Data, Len,SubID)
        return
    end
    if MainID ==LogCmd.Main_CMD then                                --日志请求处理
        ClientSink.OnLogProto(ClientID, Data, Len,SubID)
        return
    end
    if MainID==ProtoMgr.GatewayPro.GATEWAY and SubID==ProtoMgr.Sub_GateWay.SUB_REQ_CHECKOFFICIAL then  --检查是否是官方房
        ClientSink.CheckOffical(ClientID, Data, Len)
        return
    end
    if not ClientSink._MaintenanceCheck(clientinfo,MainID,SubID) then            --服务器维护判断与处理
        return
    end
    if clientinfo.nUserId and clientinfo.nUserId > 0 then      -- 网关维护判断 后台只需要维护网关即可
        if tReforwardRule.IsServBeWeiHu("", tSrvInfo.nServerId) then
            if not tReforwardRule.IsUserInWhiteList(clientinfo.nUserId) then
                return
            end
        end
    end
    if MainID==BurProto.Main_CMD then --统计数据请求
        ClientSink.OnBurProto(ClientID, Data, Len,SubID)
        return
    end
    if (not clientinfo.IsLogon==true) and MainID ~= ProtoMgr.LogonPro.LOGON_MAIN then --已登陆或登陆协议才能通过
        m.Log("_OnRecv  Err happen,ClientID_%d Not Logon",ClientID)
        return
    end
    if MainID == GateWayCmd.nMainCmd or MainID == ProtoMgr.GatewayPro.GATEWAY then                --发给网关本身处理的消息    
        if ClientSink.RecvGateDispose(ClientID, Data, Len) then 
            return 
        end         
    end

    local stypename = MainIdToName(MainID)
    if not stypename then
        m.Log("_OnRecv  Err happen,unknown MainId_%d,ClientID_%d,ip_%s,port_%d", MainID,ClientID,clientinfo.ip,clientinfo.port)  -- 未知协议
        return 
    end    
    if MainID == ChatPro.Main_CMD then --聊天服 登录 
        if ClientSink.ChatDispose(stypename,clientinfo, Data, Len) then 
            return 
        end 
    end 

    --捕抓直播类游戏的登录协议，获取其中心服id,以便选取其下的一个游戏服来转发协议
    local nCenterServId,sTableId =tGameLogon.IsLiveGameLogon(MainID,SubID,Data,Len)
    if nCenterServId~=nil then  
        if not ClientSink._ServId_MaintenanceCheck(clientinfo,nCenterServId) then
            return
        end
        if MainID == CMD_LiveSlave.Main_CMD  then  -- 旁观服
            nId =tLiveCSRelation.GetSlaveServId(nCenterServId)
            nCenterServId = nId
            m.Log("_OnRecv 11 获取其中心服id %s MainID_%d  SubID_%d nId_%d ", stypename,MainID,SubID,nId or 0)
        end  
        clientinfo.SpecialReforwardRule.stypename=stypename
        clientinfo.SpecialReforwardRule.nCenterServId=nCenterServId
        clientinfo.Server[stypename]=nil
        m.Log("_OnRecv  获取其中心服id %s MainID_%d  SubID_%d nCenterServId_%d  sTableId: %s ", stypename,MainID,SubID,nCenterServId or 0,sTableId or "")
    end
    --俱乐部登录
    if nCenterServId==nil then
        nCenterServId = tGameLogon.IsClubLogon(MainID,SubID,Data,Len)
        if nCenterServId~=nil then
            if not ClientSink._ServId_MaintenanceCheck(clientinfo,nCenterServId) then
                return
            end
            clientinfo.SpecialReforwardRule.stypename=stypename
            clientinfo.SpecialReforwardRule.nCenterServId=nCenterServId
            clientinfo.Server[stypename]=nil
            m.Log("_OnRecv 俱乐部登录 获取其中心服id %s MainID_%d SubID_%d nCenterServId_%s", stypename,MainID,SubID,tostring(nCenterServId))
        end
    end
    local nRes, sKey = ClientSink.PostToServer(stypename, clientinfo, Data, Len)
    if nRes<=0 then
        clientinfo.Server[stypename]=nil 
        local nRes = 3 
        local sLog = string.format("维护中,%s",stypename)

        local arrTypenameServList =m.GetSrcAllKey(stypename)
        if not arrTypenameServList or #arrTypenameServList == 0 then 
            nRes = 1
            sLog = string.format("%s 该类型 key不存在或者没开服",stypename) 
        end 
        if nRes == 3 and nCenterServId and sTableId then 
            local sCenterKey  = m.GetServerIdIdKey(nCenterServId)
            if not sCenterKey then 
                nRes = 1
                sLog = string.format("nCenterServId: %d 没开服,%s",nCenterServId,stypename)  
            end 
            local t =api.string_split(sTableId,"#")
            sLog = string.format(" %s sTableId: %d = %s ",sLog,t[1],t[2])
        end       
        local sSend = string.format("_PostToServer fail,%s  ClientID_%d sKey: %s",sLog,ClientID,(sKey or 'nil'))
        if stypename ~= "liveslave" then 
            m._OnMonitorInfo(sSend)
        end 
        m.Log("_OnRecv  nUserId: %d nRes: %d Err happen, %s ",(clientinfo.nUserId or 0),nRes,sSend)
        local tSend = ProtoMgr.Gateway_pb.RUP_STOP_Server()
        tSend.cStat  = nRes    -- 3维护中 ,1 未开服
        local s = m.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_GATEWAY_STOP_SERVER_MAINTAIN)
        s:AddString(tSend:SerializeToString())
        s:SendData(m.GetNetworkEngine(), ClientID) 

        local nGameId,nRoomId,sGameServerKey,sGameName=tPubUser.GetUserPlayingGame(clientinfo.nUserId,-1)
        if nGameId and nGameId > 0 and  stypename==sGameName then
            m.Log("_OnRecv 清除相关标识key  nUserId_%d nGameId_%d stypename:%s  sGameServerKey: %s  "
            ,clientinfo.nUserId,nGameId,stypename,sGameServerKey or "nil")                
            tPubUser.LeaveGame(clientinfo.nUserId,nGameId)
        end    

        return
    end
    m.Log("_OnRecv   转发到内网 %s succee,sKey:%s   ", stypename,sKey)
    return
end 

-- 接收内网发过来的协议
function ClientSink.onMsgRecv(ChannelName, Data, Len)
    if ChannelName ~= m.m_tKey .. "Gateway" then
        m.Log("_onMsgRecv happen,ChannelName Error,"..(ChannelName or "nil"))
        return
    end
    local SrcKey, ClientID, Size, Buff = m.GetTCP(Data, Len) --获取TCP协议信息
    local r2 = base.GetRP().new(Buff, Size)
    local nMainId =r2:GetModuleID()
    local nSubId =r2:GetMsgID()
    m.Log("内网消息:MainId_%d SubId_%d ClientID_%d ChannelName_%s  SrcKey_%s",nMainId,nSubId,ClientID,ChannelName,SrcKey)

    if nMainId ==DbCmd.Main_CMD then                        --db服返回处理
        ClientSink.OnDbProto(ClientID, Buff, Size,nSubId)
        return
    end
    if nMainId == GateWayCmd.nMainCmd or nMainId == ProtoMgr.GatewayPro.GATEWAY  then                --发给网关本身处理的消息
        ClientSink.GateDispose(ClientID, Buff, Size)
        return
    end
    if nMainId==BackstageCmd.Main_CMD then                  --后台消息处理
        ClientSink.OnBackstageReq(ClientID, Buff, Size,nSubId)
        return
    end

    if ClientSink.LogonDispose(ClientID, Buff, Size) == -1 then
        return
    end
    --转发消息到外网
    local clientinfo = ClientSink.m_ClientList[(ClientID or -1)]
    if clientinfo==nil then
        m.Log("转发到外网失败:MainId_%d SubId_%d ClientID_%d. 原因:连接已关闭",nMainId,nSubId,ClientID)
        return
    end

    m.Log("转发到外网:MainId_%d SubId_%d ClientID_%d nUserId_%d Size_%d",nMainId,nSubId,ClientID,(clientinfo.nUserId or 0),Size)
    local s = m.GetSP().new2(Buff, Size)
    s:SendData(m.GetNetworkEngine(), ClientID)
end

function ClientSink.IsGameServer(stypename)
    if stypename==tname.logon then
        return false
    end
    if stypename==tname.lobby then
        return false
    end
    if stypename==tname.chat then
        return false
    end
    if stypename==tname.db then
        return false
    end
    if stypename==tname.web then
        return false
    end
    if stypename==tname.gateway then
        return false
    end
    if stypename==tname.android then
        return false
    end
    if stypename==tname.ClubSlave then
        return false
    end
    return true
end

-- 获取相应的转发服务器KEY
function ClientSink.GetDispatchKey(tClientInfo, stypename) 
    assert(tClientInfo~=nil,"tClientInfo is nil")
    local sCacheKey =tClientInfo.Server[stypename]
    if sCacheKey and (not tReforwardRule.IsServBeBan(sCacheKey)) then
        return sCacheKey
    end
    if tClientInfo.nUserId and ClientSink.IsGameServer(stypename) then
        local nGameId,nRoomId,sGameServerKey,sGameName=tPubUser.GetUserPlayingGame(tClientInfo.nUserId,-1)
        if stypename==sGameName then
            m.Log("_GetDispatchKey nUserId_%d stypename:%s  sGameServerKey: %s 指定key ",tClientInfo.nUserId,stypename,sGameServerKey or "nil")        
            tClientInfo.Server[stypename] =sGameServerKey
            return tClientInfo.Server[stypename]
        end
    end
    local sKey =nil
    if tClientInfo.IsLogon and tClientInfo.nUserId~=nil then
        local arrTypenameServList =m.GetSrcAllKey(stypename) 
        if not arrTypenameServList then 
            m.Log("_GetDispatchKey nUserId_%d stypename:%s  arrTypenameServList is nil  ",tClientInfo.nUserId,stypename) 
            return 
        end
        m.Log("_GetDispatchKey   nUserId:%d nShopId:%d #:%d",tClientInfo.nUserId,tClientInfo.nShopId, #arrTypenameServList)
        arrTypenameServList = tReforwardRule.ServerIdFilter(arrTypenameServList)  --根据被禁止的serverid过滤掉对应的serverKey
        local nCenterServId = tClientInfo.SpecialReforwardRule.nCenterServId
        if tClientInfo.SpecialReforwardRule.stypename~=stypename then
            nCenterServId=nil
        end
        sKey = tReforwardRule.PickAServKey(arrTypenameServList,tGameConfig.GetGroupId(tClientInfo.nShopId),nCenterServId,tClientInfo.nUserId,stypename)
        m.LogT("_GetDispatchKey  PickAServKey:",sKey)
    else    
        sKey = tReforwardRule._GetNornalServerKey(stypename)  -- 获取正式key 
        m.Log("_GetDispatchKey stypename:%s  random key: %s  ",stypename,sKey or "nil") 
    end
    tClientInfo.Server[stypename] = sKey
    return tClientInfo.Server[stypename]
end

--发送协议给内网
function ClientSink.PostToServer(stypename, tClientInfo, Data, Len)
    local sKey = ClientSink.GetDispatchKey(tClientInfo, stypename) -- 获取转发服务器      
    if sKey ==nil then
        m.Log("_PostToServer   nUserId:%d stypename: %s   sKey is nil ",tClientInfo.nUserId,stypename)
        return 0,sKey
    end 
    local nRes = m.PostToServer(sKey, tClientInfo.ClientID, Data, Len) --转发消息到内网
    if nRes ~=0 then 
        return nRes,sKey    --转发到内网成功
    end 
    -- 用户所选的转发服务器有错，清空选择
    tClientInfo.Server[stypename] = nil
    -- m.Log("_PostToServer   nUserId:%d  nRes_%d  转发服务器有错 sKey: %s ",tClientInfo.nUserId,nRes,sKey)

    return nRes,sKey
end

--用户是否在其他网关登陆了
local function IsLogonInOtherGate(nUserId)
    local sGateKey =tPubUser.GetGateKey(nUserId)
    if sGateKey==nil then
        return
    end
    if sGateKey == m.m_tKey then
        return
    end
    return sGateKey
end

--用户是否在本网关登陆了,是则返回对应的nClientId
local function IsLogonInLocal(nUserId,NewClientID)
   -- local arrClientInfo = {} 
    --local arrClientId = {} 
    for nClientId, v in pairs(ClientSink.m_ClientList) do
        if v.nUserId == nUserId and v.IsLogon==true and nClientId ~= NewClientID then
           -- table.insert(arrClientInfo,v)
           -- table.insert(arrClientId,nClientId)
             return nClientId
        end
    end

    --[[
    if #arrClientInfo > 0 then 
        local clientinfo = ClientSink.m_ClientList[NewClientID] 
        if not clientinfo then return end  
        local nOldId = NewClientID
        local nOldAcceptTime = clientinfo.nAcceptTime 
        for k,v in pairs(arrClientInfo) do
            if nOldAcceptTime > v.nAcceptTime then                 
                nOldId= v.ClientID               
                nOldAcceptTime = v.nAcceptTime
            end 
        end
        m.Log("_IsLogonInLocal NewId [%d=%d],nOldId [%d=%d]  arrClientId_%s "
        ,NewClientID,clientinfo.nAcceptTime,nOldId,nOldAcceptTime,cjson.encode(arrClientId))
        return nOldId
    end 
    ]] 
end
--通知网关,令特定用户登出
local function SendLetUserLogOut(sTargetGateKey,nLogOutUserId,ClientID,sToken)
     local s = m.GetSP().new(GateWayCmd.nMainCmd, GateWayCmd.nKickReq)
     s:AddInt32(nLogOutUserId)
     s:AddString(m.m_tKey)
     s:AddString(sToken or "")
     m.PostToServer(sTargetGateKey, ClientID, s:GetData(), s:GetSize())
     m.Log("_SendLetUserLogOut 通知别的网关将玩家移除 sKey:" .. sTargetGateKey)
     return 
end
--通知用户，账号因重复登陆被登出
local function SendLogOut(nTargetCliendId,nDelayCloseTime)
    local NotifyCmd =ProtoMgr.NotifyToCli_pb.NotifyCli_Proto()
    local tSend = ProtoMgr.NotifyToCli_pb.RepeatLogonNotify()
    tSend.nSecondsToClose  = nDelayCloseTime
     local s = m.GetSP().new(NotifyCmd.Main_CMD, NotifyCmd.RepeatLogonNotify_CMD)
     s:AddString(tSend:SerializeToString())
     s:SendData(m.GetNetworkEngine(), nTargetCliendId)
    m.Log("_SendLogOut 发送到外网:重复登陆 ClientID_%d 被登出",nTargetCliendId)
end

--通知其它服务器，玩家切换连接
local function SendSwicthConnect(nNewClientId)
    local clientInfo =ClientSink.m_ClientList[nNewClientId]
    assert(clientInfo~=nil,"clientInfo is nil")
    for k, v in pairs(clientInfo.Server) do
        if k ~= tname.gateway then
            local s = m.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_REQ_GAMESRV_SWICTHCONN)
            local tSend = ProtoMgr.Gateway_pb.RUQ_SwicthConn()
            tSend.nUserID  = clientInfo.nUserId
            s:AddString(tSend:SerializeToString())
            ClientSink.PostToServer(k, clientInfo, s:GetData(), s:GetSize())
            m.Log("通知服_%s 切换连接",k)
        end
    end 
end
local function CopyCliendDataToNew(nOldClientId,nNewClientID)
    local cp= m.DeepCopy(ClientSink.m_ClientList[nOldClientId])
    ClientSink.m_ClientList[nNewClientID] =cp
    ClientSink.m_ClientList[nNewClientID].ClientID = nNewClientID
end
local function SetLogonInLocal(ClientID,nUserId)
    local clientinfo = ClientSink.m_ClientList[ClientID]
    if clientinfo==nil then
        m.Log("SetLogonInLocal时,玩家连接已关闭 ClientID_%d nUserId_%d",ClientID,nUserId)
        return false
    end
    assert(clientinfo~=nil,"clientinfo is nil")
    if tReforwardRule.IsServBeWeiHu("", tSrvInfo.nServerId) then
        if not tReforwardRule.IsUserInWhiteList(clientinfo.nUserId) then
            m.Log("网关维护，玩家即将被登出 nUserID_%d nClientId_%d",nUserId,ClientID)
            return false
        end
    end
    clientinfo.nUserId = nUserId
    clientinfo.IsLogon = true
    clientinfo.nShopId =tPubUser.Get_User_SHopId(nUserId)
    clientinfo.sChannel = tPubUser.Get_User_Channel(nUserId) 
    clientinfo.nID = tGameConfig.GetShopIdByStoreChannel(clientinfo.nShopId,clientinfo.sChannel) 
    if not ClientSink._MaintenanceCheck(clientinfo) then            --服务器维护判断与处理
        m.Log("由于是维护中，玩家即将被登出 nUserID_%d nClientId_%d",nUserId,ClientID)
        return false
    end
    tPubUser.SetUserInfo({ nUserID = nUserId, nClientId = ClientID, sGateKey = m.m_tKey, sIp = clientinfo.ip, nSocketId = tSrvInfo.nSocketType, sRealIp=clientinfo.sRealIp })
    tPubUser.PersistUserInfo(nUserId)
    m.Log("玩家在本网关登陆成功 nUserID_%d nClientId_%d",nUserId,ClientID)
    tPublicUserOnLineStatus.OnLine(nUserId)
    return true
end

--目前只有挤号或维护期间才会导致服务器主动关闭连接
function ClientSink.ToCloseCliendId(CliendId,isRepeatLogon)
    local clientinfo = ClientSink.m_ClientList[CliendId]
    assert(clientinfo~=nil,"clientinfo is nil")
    clientinfo.IsLogon=false
    clientinfo.isToClose=true
    if isRepeatLogon then
        SendLogOut(CliendId,1)
    end
    m.DelayClose(CliendId, 1)
    m.Log("CliendId_%d 即将关闭",CliendId)
end

-- 网关服逻辑处理，原则上网关服尽量少作逻辑处理！！！
-- 处理登陆返回
function ClientSink.LogonDispose(ClientID, Data, Len)
    local r = m.GetRP().new(Data, Len)
    local MainID = r:GetModuleID()
    local SubID = r:GetMsgID()
    if MainID ~= ProtoMgr.LogonPro.LOGON_MAIN then
        return 0
    end
    if SubID == ProtoMgr.LogonPro.SUB_REP_REGISTER_RESULT then    
        local rRegist = ProtoMgr.Logon_pb.Rup_Regist()
        rRegist:ParseFromString(r:GetString())
        local nUserId = rRegist.nUserID 
        local nError =  rRegist.nError
        m.Log("_LogonDispose 注册返回:nUserID_%d  nError_%d", nUserId,nError)
        if nError ~=1 then
            return 0
        end
        if not SetLogonInLocal(ClientID,nUserId) then
            return -1
        end
        return 0
    end
    if SubID == ProtoMgr.LogonPro.SUB_REP_LOGON_RESULT then
        local rLogon = ProtoMgr.Logon_pb.Rup_Logon()
        rLogon:ParseFromString(r:GetString())
        local nUserId = rLogon.nUserID
        local nError =  rLogon.nError
        local sToken =nil
        if rLogon.sToken and #rLogon.sToken>0 then
            sToken =rLogon.sToken
        end
        m.Log("_LogonDispose 登陆返回:nUserID_%d Result_%d sConfineTime:%s",nUserId,nError,(rLogon.sConfineTime or 'nil'))
        if nError ~=1 then
            return 0
        end
        local clientinfo = ClientSink.m_ClientList[ClientID]
        if clientinfo==nil then
            m.Log("_LogonDispose 登陆返回时，玩家连接已关闭 ClientID_%d",ClientID)
            return 0
        end
        assert(clientinfo~=nil,"clientinfo is nil")

        if clientinfo.nUserId and clientinfo.nUserId==nUserId and clientinfo.IsLogon then
            m.Log("_LogonDispose 同一连接，同一玩家重复登陆 ClientID_%d nUserId_%d",ClientID,clientinfo.nUserId)
            return 0
        end 
        if clientinfo.nUserId and clientinfo.nUserId~=0 and clientinfo.nUserId~=nUserId then
            m.Log("_LogonDispose 同一连接，登陆不同的玩家 ClientID_%d nOldUserId_%d nNewUserId_%d",ClientID,clientinfo.nUserId,nUserId)
            ClientSink.m_ClientList[ClientID] =_NewClientInfo(clientinfo.ClientID,clientinfo.ip,clientinfo.port)
            KickOutUserFromLocalGate(clientinfo)
            clientinfo =ClientSink.m_ClientList[ClientID]
        end

        clientinfo.nUserId = nUserId
        clientinfo.IsLogon =false
        local sGateKey =IsLogonInOtherGate(nUserId)
        if sGateKey then                                        --玩家是否已经在其他网关登陆
           if not tPubUser.IsServerKeyExists(sGateKey) then     --如果该网关已经不存在了，则帮用户退出该网关(防卡住)
                tPubUser.DelGateKey(nUserId,m.m_tKey,true)
           else
                SendLetUserLogOut(sGateKey,nUserId,ClientID,sToken)
                return -1
           end
        end
        local nOldCliendId =IsLogonInLocal(nUserId,ClientID)
        if nOldCliendId then                                --玩家是否已经在本网关登陆
            m.Log("_LogonDispose nUserId_%d  nOldCliendId_%d",nUserId,nOldCliendId)
            CopyCliendDataToNew(nOldCliendId,ClientID)
            ClientSink.ToCloseCliendId(nOldCliendId,true)
            SendSwicthConnect(ClientID)
        end
        if not SetLogonInLocal(ClientID,nUserId) then
            return -1
        end
        return 0
    end
    return 0
end

-- 处理网关间通信
function ClientSink.GateDispose(ClientID, Data, Len)
    local r = m.GetRP().new(Data, Len)
    local MainID = r:GetModuleID()
    local SubID = r:GetMsgID()

    if MainID == ProtoMgr.GatewayPro.GATEWAY and SubID == ProtoMgr.Sub_GateWay.SUB_GATEWEY_BROAD then        
        ClientSink._BroadcastGame(r) 
        return 0
    end
    if MainID == ProtoMgr.GatewayPro.GATEWAY and SubID == ProtoMgr.Sub_GateWay.SUB_GATEWEY_USERGAME then        
        ClientSink._UserEnterLiveGame(ClientID, Data, Len) 
        return 0
    end
    if MainID == ProtoMgr.GatewayPro.GATEWAY and SubID == ProtoMgr.Sub_GateWay.SUB_SwitchGateWayServerkey then        
        ClientSink._SwicthGateWayServerKey(ClientID, Data, Len) 
        return 0
    end

    if SubID ==ProtoMgr.Sub_GateWay.SUB_CORR_CAPITAL or SubID ==ProtoMgr.Sub_GateWay.SUB_REP_TableSettleInfo or SubID ==ProtoMgr.Sub_GateWay.SUB_NOTICE_MSG then
        m.Log("_GateDispose  转发到外网:MainId_%d SubId_%d ClientID_%d   Size_%d",MainID,SubID,ClientID ,Len)
        local s = m.GetSP().new2(Data, Len)
        s:SendData(m.GetNetworkEngine(), ClientID)
        return
    end

    if MainID ~= GateWayCmd.nMainCmd then
         return 0
    end
    if SubID == GateWayCmd.nKickReq then
         local nUserId = r:GetInt32()
         local sKey = r:GetString()
         local sToken =r:GetString()
         local client = ClientSink.FindClientByUserId(nUserId)
         if client == nil then 
             m.Log("本网关找不到用户id:%d",nUserId)
             return 0 
         end
         local nClientId = client.ClientID
         m.Log("玩家在别的网关重复登陆,本网关即将断开该玩家连接 nUserId_%d nClientId_%d",client.nUserId,nClientId)
         m.Log("玩家登陆的网关key为:%s", sKey)
         local isDelSuccee =tPubUser.DelGateKey(nUserId,m.m_tKey)
         if isDelSuccee~=true then
             m.Log("DelGateKey fail")    --在本网关登陆的玩家，如果以接近并发的速度在另外两个网关重复登陆,会出现这里的情况
             return -1
         end
         ClientSink.SaveData(client)
         ClientSink.ToCloseCliendId(nClientId,true)
         local s = m.GetSP().new(GateWayCmd.nMainCmd, GateWayCmd.nKickRsp)
         s:AddInt32(nUserId)
         s:AddString(sToken or "")
         m.PostToServer(sKey, 0, s:GetData(), s:GetSize())
         return -1
    end
    if SubID == GateWayCmd.nKickRsp then
         local nUserId = r:GetInt32()
         local sToken =r:GetString()
         local client = ClientSink.FindClientByUserId(nUserId)
         if client==nil then
             m.Log("Err may be happen,why client is nil,nUserId_%d",nUserId)
             return -1
         end
         m.Log("其它网关已成功踢出玩家,本网关可以正常加载玩家数据了 userId:%d clientId:%d",nUserId, client.ClientID)
         ClientSink.LoadData(nUserId, client.ClientID)
         if not SetLogonInLocal(client.ClientID,nUserId) then
             return -1
         end
         SendSwicthConnect(client.ClientID)
         local s = m.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.SUB_REP_LOGON_RESULT)
         local rLogon = ProtoMgr.Logon_pb.Rup_Logon()
         rLogon.nUserID =nUserId
         rLogon.nError =1
         if sToken and #sToken>0 then
            rLogon.sToken=sToken
         end
         s:AddString(rLogon:SerializeToString())
         m.Log("发送到外网:ClientID_%d nUserId_%d 登陆成功",client.ClientID,nUserId)
         local s = m.GetSP().new2(s:GetData(), s:GetSize())
         s:SendData(m.GetNetworkEngine(), client.ClientID)
         return -1
     end 

    return 0
end

-- 处理聊天服 登录转发
function ClientSink.ChatDispose(stypename,clientinfo, Data, Len)
    local r = m.GetRP().new(Data, Len)
    local MainID = r:GetModuleID()
    local SubID = r:GetMsgID()
    local sChatkey 
    if SubID == ChatPro.ChatLogonReq_CMD then -- 登录聊天服
        local Read = ProtoMgr.Chat_pb.ChatLogonReq()
        Read:ParseFromString(r:GetString())
        local nChatType = Read.nChatType  
        if nChatType == 0 then 
            sChatkey = m.GetSrcKey(stypename,clientinfo.nUserId)
        else
            local sTableId = Read.sTableId  
            local tRedis =m.m_MyRedisData[1].redis
            local sKey = "TableChat_Key"
            sChatkey = tRedis:hget(sKey,sTableId)     
            if sChatkey then  
                clientinfo.Server[stypename] = sChatkey
            end  
        end 
    elseif SubID == ChatPro.LogonZhiBoReq_CMD then   -- 直播登陆请求    
        local Read = ProtoMgr.Chat_pb.LogonZhiBoReq()
        Read:ParseFromString(r:GetString())
        local sTableId = Read.sTableId  
        local tRedis =m.m_MyRedisData[1].redis
        local sKey = "TableChat_Key"
        sChatkey = tRedis:hget(sKey,sTableId)     
        if sChatkey then  
            clientinfo.Server[stypename] = sChatkey 
        end  
    elseif SubID == ChatPro.ChatBackToLobbyReq_CMD then   -- 返回大厅   
        sChatkey = clientinfo.Server[stypename] 
        clientinfo.Server[stypename]  = nil 
    else
        m.Log("_ChatDispose  nUserId_%d  SubID_%d ClientID_%d  SendToChat Error ",clientinfo.nUserId,SubID,clientinfo.ClientID)   
        return false  
    end 
    local nRes = 0 
    if sChatkey then  
        -- clientinfo.Server[stypename] = sChatkey
        nRes = m.PostToServer(sChatkey,clientinfo.ClientID,Data,Len) --转发消息到内网
        m.Log("_ChatDispose   转发聊天服 nUserId_%d ClientID_%d sKey:%s ",clientinfo.nUserId,clientinfo.ClientID,sChatkey)    
    else
        m.Log("_ChatDispose   转发聊天服 nUserId_%d  SubID_%d ClientID_%d  sChatkey is nil",clientinfo.nUserId,SubID,clientinfo.ClientID)   
    end     
    return true  
end 

-- 根据userid查找本服玩家
function ClientSink.FindClientByUserId(nUserId)
    for i, v in pairs(ClientSink.m_ClientList) do
        if v.nUserId == nUserId then
            return v
        end
    end
    return nil
end

local function _GetClientLogObjectForWrite(ClientID)
    local tClientLogInfo =ClientSink.m_ClientList[ClientID].tClientLogInfo
    if tClientLogInfo==nil then
        return
    end
    local sCurrentDate =os.date("%Y-%m-%d", os.time())
    if tClientLogInfo.tLogObj and tClientLogInfo.sData==sCurrentDate then
        return tClientLogInfo.tLogObj
    end
    local logObj =  m.GetLogObject().new()
    local logPath =string.format("%s/%s/%s",dbInfo.Client_LogDir or "/ClientLogL",sCurrentDate,tClientLogInfo.sEqID)
    logObj:SetLogPath(logPath, "ClientLog")
    tClientLogInfo.tLogObj =logObj
    tClientLogInfo.sData =sCurrentDate
    return tClientLogInfo.tLogObj
end

local function _CreateClientLog(ClientID,sEqID)
    local tClientLogInfo =ClientSink.m_ClientList[ClientID].tClientLogInfo
    if tClientLogInfo then
        if tClientLogInfo.sEqID ~=sEqID then
            tClientLogInfo.sEqID=sEqID
            tClientLogInfo.tLogObj=nil
        end
        return
    end
    local tClientLogInfo={}
    tClientLogInfo.sEqID =sEqID
    tClientLogInfo.sData =os.date("%Y-%m-%d", os.time())
    ClientSink.m_ClientList[ClientID].tClientLogInfo=tClientLogInfo
end

--日志协议处理
function ClientSink.OnLogProto(ClientID, Data, Len,SubID)
    if SubID ==LogCmd.LogFileCreateReq_CMD then
        local tData =LogAux:Parser(Data, Len,"LogFileCreateReq")
        if not tData then
            m.Log("Parser LogFileCreateReq fail")
            return
        end
        local sFileName =tData.sFileName or 'nil'
        if #sFileName >=128 then
            sFileName =string.sub(sFileName,1,128)  
        end
        _CreateClientLog(ClientID,sFileName)
        local tPacket =LogAux:Encode('LogFileCreateRsp',{nResult=0})
        local s = m.GetSP().new2(tPacket:GetData(), tPacket:GetSize())
        s:SendData(m.GetNetworkEngine(), ClientID)
    end
    --写日志请求
    if SubID ==LogCmd.LogWriteReq_CMD then
        -- local tData =LogAux:Parser(Data, Len,"LogWriteReq")
        -- if not tData then
        --     m.Log("Parser LogWriteReq fail")
        --     return
        -- end
        -- local logObj =_GetClientLogObjectForWrite(ClientID)
        -- if logObj then
        --     logObj:Log(tData.sText)
        -- else
        --     m.Log("LogWriteReqt:"..tData.sText)
        -- end
        return
    end   

    --线路监测
    if SubID ==LogCmd.LineCheckReq_CMD then
        local tData =LogAux:Parser(Data, Len,"LineCheckReq")
        if not tData then
            m.Log("_OnLogProto  Parser LogWriteReq fail")
            return
        end 
        local clientinfo = ClientSink.m_ClientList[ClientID]
        if not clientinfo then
            assert(false,"_OnLogProtoclientinfo is nil:ClientID_"..(ClientID or "nil")) 
            return            
        end
        local function SendClient(nType,nSendTime)
            local tPacket =LogAux:Encode('LineCheckRsp',{nType=nType,nSendTime=nSendTime})
            local s = m.GetSP().new2(tPacket:GetData(), tPacket:GetSize())
            s:SendData(m.GetNetworkEngine(), ClientID)            
        end

        local sIp = api.Dword2String(clientinfo.ip)  -- 将IP转换为点分十进制形式表示 
        if clientinfo.sRealIp then 
            sIp = clientinfo.sRealIp
        end  
        local nUserId = tData.nUserId or 0   -- 客户端发送时间戳  
        if tData.nType == 1 then                --  1发时间戳、2计算来回时间差 
            local nSendTime = tData.nSendTime   -- 客户端发送时间戳  
            SendClient(tData.nType,nSendTime)
            m.Log("_OnLogProto nUserId: %d/%d  sIp: %s  nSendTime: %.1f",nUserId,ClientID,sIp,nSendTime) 
 
        else            
            SendClient(tData.nType,-1)             

            local arrLineInfo = tData.arrLineInfo or {}
            m.Log("_OnLogProto nUserId: %d/%d  sIp: %s  arrLineInfo: %d",nUserId,ClientID,sIp,#arrLineInfo or 0) 
            for k, v in pairs(arrLineInfo) do
                if not v or not v.sLineName then break end                 
                local nTimeDiffer = tonumber(v.nTimeDiffer)   -- 线路来回时间差
                local sLineName = v.sLineName       -- 线路名称
                m.Log("_OnLogProto sLineName: %s  nTimeDiffer: %.1f",sLineName,nTimeDiffer) 
                local sSql = string.format("call ClientLineCheckRecord(%d,'%s','%s',%d)",nUserId,sLineName,sIp,nTimeDiffer)
                
                tCScriptCfg.DbPublicHandleEvent("DJH_RecordDB",sSql) 
            end
        end
        return
    end
end

--维护协议处理
function ClientSink.OnMaintainerProto(ClientID, Data, Len,SubID)
    --当前客户端版本信息请求
    if SubID ==MaintainerCmd.VersionInfoReq_CMD then
        local tData =MaintainerAux:Parser(Data, Len,"VersionInfoReq")
        local sPlatform =tData.sPlatform or 'nil'
        local sChannel =tData.sChannel or 'nil'
        m.Log("VersionInfoReq sPlatform_%s sChannel_%s",sPlatform,sChannel)
        local tVInfo =tVarsion.GetVersionInfo(sPlatform,sChannel)
        local VersionInfoRsp={}
        VersionInfoRsp.nResult =-1
        if tVInfo then
            local tVersionInfo ={}
            tVersionInfo.sVersion=tVInfo.sVersion or 'null_string'
            tVersionInfo.sDownloadurl=tVInfo.sDownloadurl or 'null_string'
            tVersionInfo.sAppurl =tVInfo.sAppurl or 'null_string'
            tVersionInfo.sConfigUrl =tVInfo.sConfigUrl or 'null_string'
            tVersionInfo.sConfigVersion =tVInfo.sConfigVersion or 'null_string'
            VersionInfoRsp.nResult =0
            VersionInfoRsp.tVersionInfo =tVersionInfo
        end
        local tPacket =MaintainerAux:Encode('VersionInfoRsp',VersionInfoRsp)
        local s = m.GetSP().new2(tPacket:GetData(), tPacket:GetSize())
        s:SendData(m.GetNetworkEngine(), ClientID)
        return
    end
end

--统计数据调用
function ClientSink.OnBurProto(ClientID, Data, Len,SubID)
    if SubID==BurProto.Bur_UserInfoReq_CMD then
        local s = m.GetRP().new(Data, Len)
        local Read = ProtoManager.Bur_pb.Bur_UserInfoREQ()
        Read:ParseFromString(s:GetString())
       -- m.LogT("前端数据= ",Read.tBuildUserData)
        tCScriptCfg.ExeScriptEvent(Read.tBuildUserData,ClientSink.tBurScript)
        local uSentData = ProtoManager.Bur_pb.Bur_UserInfoRSP()
        uSentData.nResult = 0
        local nClient = m.GetSP().new(BurProto.Main_CMD, BurProto.Bur_UserInfoRsp_CMD) 
        nClient:AddString(uSentData:SerializeToString()) 
        local s = m.GetSP().new2(nClient:GetData(), nClient:GetSize())
        s:SendData(m.GetNetworkEngine(), ClientID)
        return
    end
end

--db服结果返回处理
function ClientSink.OnDbProto(ClientID, Data, Len,SubID)
    --版本信息返回处理
    if SubID==DbCmd.VersionRsp_CMD then
        tVarsion.OnDbVersionRsp(ClientID, Data, Len)
        return
    end
    if SubID==DbCmd.MaintainerIpRsp_CMD then
        tUserIP.MaintainerIpRsp(ClientID, Data, Len)
        return
    end
    if SubID==DbCmd.RefowardRuleRsp_CMD then
        tReforwardRule.OnRefowardRuleRsp(ClientID, Data, Len)
        return
    end
    if SubID==DbCmd.DbShopListRsp_CMD then
        tGameConfig.OnDbShopListRsp(ClientID, Data, Len)
        return
    end
    if SubID==DbCmd.DbAdCfgListRsp_CMD then
        tAdNoticeCfg.OnDbAdCfgListRsp(ClientID, Data, Len)
        return
    end
    if SubID==DbCmd.DbLiveCSRelationRsp_CMD then
        tLiveCSRelation.OnDbLiveCSRelationRsp(ClientID, Data, Len)
        return
    end
    if SubID==DbCmd.ServerIdOfMaitainingRsp_CMD then
        tReforwardRule.OnServerIdOfMaitainingRsp(ClientID, Data, Len)
        return
    end
    if SubID==DbCmd.WhiteListRsp_CMD then
        tReforwardRule.OnWhiteListRsp(ClientID, Data, Len)
        return
    end

    m.Log("Warining Not Handle DbCmd SubID:%d",SubID)

end

function ClientSink.GetGameServerTypeName()
    local arrServerTypename={}
    for _,stypename in pairs(tname) do
        if ClientSink.IsGameServer(stypename) then
            table.insert(arrServerTypename,stypename)
        end
    end
    return arrServerTypename
end

function ClientSink.BroadCastToServers(arrServerNames,Data,Len)
    for _,stypename in ipairs(arrServerNames) do
        local arrServKeys =m.GetSrcAllKey(stypename) or {}
        for _,sKey in ipairs(arrServKeys) do
            m.PostToServer(sKey,0,Data, Len)
        end
    end
end
 
--后台请求处理
function ClientSink.OnBackstageReq(ClientID, Buff, Size,nSubId) 
	m.Log("OnBackstageReq nSubId_%d",(nSubId or -1))
    if nSubId==BackstageCmd.DbConfigReloadReq_CMD then
        local arrServName =ClientSink.GetGameServerTypeName()
        table.insert(arrServName,tname.lobby)
        --ClientSink.BroadCastToServers(arrServName,Buff,Size)
        --local tData =BackstageAux:Parser(Buff,Size,"DbConfigReloadReq")
        --m.Log("nWhatChange_%d",(tData.nWhatChange or -1))
        local n =tPubUser.Incr("DbConfigReloadReqCount")
        local tPacket =BackstageAux:Encode("DbConfigReloadReq",{nWhatChange=n})
        ClientSink.BroadCastToServers(arrServName,tPacket:GetData(), tPacket:GetSize())
        return
    end
    if nSubId==BackstageCmd.ReqNoticeNoteCfg_CMD then
        tAdNoticeCfg.WebReqAdNoticNoteList()
		return
    end
    if nSubId==BackstageCmd.MaintainingStartReq_CMD then
        local tData =BackstageAux:Parser(Buff,Size,"MaintainingStartReq")
        m.Log("_OnBackstageReq  后台维护通知 nServerId_%d nStatus_%d nSType_%d ",tData.nServerId,tData.nStatus,tData.nSType)      
        tReforwardRule.onTimerRefowardRuleReq()
        local weiHu = tReforwardRule.OnTimerGetServerIdOfBan()
        if weiHu then
            ClientSink.KickGameUsers()
        end
        if tData.nStatus == 2 then
            -- 屏蔽了
            -- local nSeconds = 1000 * 5
            -- m.TokenCallTimeID(tTimerId.GetATimerId(),nSeconds, 1 ,ClientSink.Maintaining, tData.nServerId,tData.nSType)
        end
        return
    end
    if nSubId==BackstageCmd.CloseServerNotice_CMD then
        m.Log("_OnBackstageReq  后台维护通知")
        tReforwardRule.onTimerRefowardRuleReq()
        local weiHu = tReforwardRule.OnTimerGetServerIdOfBan()
        if weiHu then
            ClientSink.KickGameUsers()
        end
    end
    if nSubId==BackstageCmd.WebRedisNotify_CMD then
        RedisCahche._OnWebRedisNotify()
    end
    if nSubId==BackstageCmd.WhiteListNotice_CMD then
        tReforwardRule.ReqDbWhitList()
        return
    end
end

function ClientSink.UpdataOnlineNum()
    local m_Num = tPubUser.PreciseGetOpenGateNum()
    if m_Num and m_Num>0 then
        local getwaykey = m.GetSrcAllKey(tname.gateway)
        if getwaykey then 
            for key, val in pairs(getwaykey) do
                local Skey = tostring(rdf.GateWay_key.GateList) 
                local sRK = m.m_MyRedisData[1].redis:hget(Skey,val)
                if sRK~=nil then                    
                    local m_incr = tPubUser.getcrConnection() or 0
                    local tV = api.string_split(sRK, '_')
                    local sV = { gatekey=val, nIp=tV[1], nPort=tV[2], nSocketType=tV[3] }
                    local nNum = tV[4] or 0
                    if nNum~=m_incr then mlogger:info(string.format("gate:%s nPreOnline:%d nBefoOnline:%d", val,nNum,m_incr) ) end
                    tPubUser.SetGateKeyPortOnline(Skey, sV.gatekey, sV.nIp, sV.nPort, sV.nSocketType, m_incr)
                end
            end
        end
    else
       mlogger:debug("No—Open-GateWay") 
    end
end

-- 玩家 登录或者离开游戏
function ClientSink._UserEnterLiveGame(ClientID, Data, Len) 
    if ClientSink.m_ClientList[ClientID] == nil then
        -- m.Log("_UserEnterLiveGame    ClientID_%d  tClientInfo is nil  ",ClientID)
        return
    end 
    local r = m.GetRP().new(Data, Len)
    local MainID = r:GetModuleID()
    local SubID = r:GetMsgID()
    local Read = ProtoMgr.Gateway_pb.SendGateWeyUserGame()
    Read:ParseFromString(r:GetString())

    local nUserId = Read.nUserId
    local nType   = Read.nType
    local nGameId = Read.nGameId
    local nRoomId = Read.nRoomId
    local nID = Read.nID
    local nTableId = Read.nTableId
    if nType == 1 then 
        ClientSink.m_ClientList[ClientID].nGameId = nGameId
        ClientSink.m_ClientList[ClientID].nRoomId = nRoomId
        ClientSink.m_ClientList[ClientID].nID = nID
        ClientSink.m_ClientList[ClientID].nTableId = nTableId
    else
        ClientSink.m_ClientList[ClientID].nGameId = -1
        ClientSink.m_ClientList[ClientID].nRoomId = -1
        ClientSink.m_ClientList[ClientID].nID = -1
        ClientSink.m_ClientList[ClientID].nTableId = -1
    end 
    m.Log("_UserEnterLiveGame   nUserId_%d  nType_%d【1进入 0离开】游戏  nGameId_%d  nLiveUserID_%d  nTableId_%d  ",nUserId,nType,nGameId,nID,nTableId)
end 

-- 游戏通知广播
function ClientSink._BroadcastGame_old(ReadData)
    local Buff, nlen = ReadData:GetBuff()
    local nCount = ReadData:GetInt32()
    m.Log("_BroadcastGame  nCount_%d nlen:%d  ",nCount, nlen)
    for i=1,nCount do
        local nClientId = ReadData:GetInt32()
        if ClientSink.m_ClientList[nClientId] then
            local s = m.GetSP().new2(Buff, nlen)
            s:SendData(m.GetNetworkEngine(), nClientId)
            m.Log("_BroadcastGame  SendData nCount_%d  nClientId_%d  nlen_%d  ",nCount,nClientId,nlen)
        else
            m.Log("_BroadcastGame  nClientId_%d   m_ClientList is nil  ",nClientId)
        end
    end
end

function ClientSink._BroadcastGame(ReadData)
    local nCount = ReadData:GetInt32()  -- 正确读取数量
    local list = {}
    for i = 1, nCount do
        table.insert(list, ReadData:GetInt32())
    end
    local Buff, nlen = ReadData:GetBuff() -- 最后读取 Buff
    m.Log("_BroadcastGame  nCount_%d nlen:%d  ",nCount, nlen)
    for i=1,nCount do
        local nClientId = list[i]
        if ClientSink.m_ClientList[nClientId] then
            local s = m.GetSP().new2(Buff, nlen)
            s:SendData(m.GetNetworkEngine(), nClientId)
            m.Log("_BroadcastGame  SendData nCount_%d  nClientId_%d  nlen_%d  ",nCount,nClientId,nlen)
        else
            m.Log("_BroadcastGame  nClientId_%d   m_ClientList is nil  ",nClientId)
        end
    end
end

--检查是否是官方房
function ClientSink.CheckOffical(ClientID, Data, Len)
    local ReadData = m.GetRP().new(Data, Len)
    local Read = ProtoMgr.Gateway_pb.RUQ_CheckOffical()
    Read:ParseFromString(ReadData:GetString())

    local sTableId = Read.sTableId or ""

    local isOffical,nTableType = tPublicRedis.CheckIsOffical(sTableId)

    m.Log("CheckOffical sTableId:%s isOffical:%s nTableType:%d",sTableId,tostring(isOffical),nTableType)

    local tSend = ProtoMgr.Gateway_pb.RUP_CheckOffical()
    tSend.sTableId  = sTableId
    tSend.IsOffical = isOffical
    tSend.nTableType = nTableType
    local tPacket = m.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_REP_CHECKOFFICIAL)
    tPacket:AddString(tSend:SerializeToString())
    local s = m.GetSP().new2(tPacket:GetData(), tPacket:GetSize())
    s:SendData(m.GetNetworkEngine(), ClientID)
end


function ClientSink.Maintaining(nServerId,nSType)     
    m.Log("_Maintaining  后台维护通知 nServerId_%d nSType: %d   ",nServerId,nSType)        
    if nSType > 10 then return end 

    local arrServer = {0,1}     -- 目前就只处理 登录服、大厅  
    local isMainNing = false 
    for _, v in pairs(arrServer) do
        if v == tonumber(nSType) then 
            isMainNing = true 
        end 
    end
    if not isMainNing then return end 
    local arrServKeys = m.GetServerId_ArrKey(nServerId)
    if #arrServKeys == 0 then  return end 

    local arrClientServerKey = {}
    local arrCLientId = {}                    
    for ClientID,tClientInfo in pairs(ClientSink.m_ClientList) do
        for stypename, sKey in pairs(tClientInfo.Server) do
            for _, v in ipairs(arrServKeys) do  
                if v == sKey then 
                    if not arrClientServerKey[ClientID]  then 
                        arrClientServerKey[ClientID] = {}
                    end 
                    arrClientServerKey[ClientID][stypename] = sKey 
                    table.insert(arrCLientId,ClientID)
                end                                 
            end                            
        end                        
    end          
    m.Log("_Maintaining  后台维护通知 nServerId_%d arrCLientId: %d   ",nServerId,#arrCLientId)     
    if # arrCLientId <= 0 then return end 

    -- 通知大厅切换
    local function SendLobby(ClientID,stypename)
        if stypename ~= tname.lobby then return end 
        local tClientInfo = ClientSink.m_ClientList[ClientID] 
        if not tClientInfo then return end 
        local s = m.GetSP().new(ProtoMgr.Lobby_Proto.Main_CMD, ProtoMgr.Lobby_Proto.LogonReq_CMD)
        local tSend = ProtoMgr.Lobby_pb.LogonReq()
        tSend.nUserID  = tClientInfo.nUserId
        s:AddString(tSend:SerializeToString()) 
        ClientSink.PostToServer(stypename, tClientInfo, s:GetData(), s:GetSize())       
        m.Log("_Maintaining  重新登录大厅 nUserId %d  ClientID: %d stypename: %s  ",tClientInfo.nUserId,ClientID,stypename)               
    end
    local nCnt = 0 
    for ClientID, v in pairs(arrClientServerKey) do
        local tClientInfo = ClientSink.m_ClientList[ClientID] 
        for stypename, sKey in pairs(v) do 
            if tClientInfo.Server[stypename] then 
                tClientInfo.Server[stypename] = nil                                
                SendLobby(ClientID,stypename)
                nCnt = nCnt + 1                                                            
            end                             
        end 
    end 
    m.Log("_Maintaining  后台维护通知 nServerId_%d arrCLientId: %d   nCnt_%d   ",nServerId,#arrCLientId,nCnt)                        

end

-- 切换中心服
function ClientSink._SwicthGateWayServerKey(ClientID, Data, Len) 
    local ReadData = m.GetRP().new(Data, Len)
    local MainID = ReadData:GetModuleID()
    local SubID = ReadData:GetMsgID()
    local nUserId = ReadData:GetInt32()
    local nClientID = ReadData:GetInt32()
    local nCenterServId = ReadData:GetInt32()
    local stypename = ReadData:GetString()
    local sServerKey = ReadData:GetString()     
    local Buff, nlen = ReadData:GetBuff() 
    local clientinfo = ClientSink.m_ClientList[nClientID]
    if not clientinfo then                       
        m.Log("_SwicthGateWayServerKey   nUserId_%d  nClientID_%d  tClientInfo is nil  ",nUserId,nClientID)
       return
    end    
    if not clientinfo.Server[stypename] then                       
        m.Log("_SwicthGateWayServerKey   nUserId_%d  clientinfo.Server[%s] is nil ",nUserId,stypename)
       return
    end    
    clientinfo.SpecialReforwardRule.stypename=stypename
    clientinfo.SpecialReforwardRule.nCenterServId=nCenterServId
    clientinfo.Server[stypename]=sServerKey 
    local nRes, sKey = ClientSink.PostToServer(stypename, clientinfo, Buff, nlen)
    if nRes<=0 then
        m.Log("_SwicthGateWayServerKey 转发失败  nUserId_%d nClientID_%d stypename_%s  sServerKey_%s  ",nUserId,nClientID,stypename,sServerKey)
        return
    end 
	m.Log("_SwicthGateWayServerKey   nUserId_%d nCenterServId_%d nClientID_%d stypename_%s  sServerKey_%s  "
    ,nUserId,nCenterServId,nClientID,stypename,sServerKey)
    return 
end 

-- 处理外网与网关间协议
function ClientSink.RecvGateDispose(ClientID, Data, Len)
    local r = m.GetRP().new(Data, Len)
    local MainID = r:GetModuleID()
    local SubID = r:GetMsgID()

    local clientinfo = ClientSink.m_ClientList[ClientID]
    if clientinfo==nil then                                      
       assert(false,"Err happen,clientinfo is nil:ClientID_"..(ClientID or "nil"))
       return
    end
    if clientinfo.nUserId <= 0 then 
        assert(false,"Err happen,clientinfo is nil:nUserId_"..(clientinfo.nUserId or "nil"))
        return
    end 
    -- 小游戏兑换 (全部小游戏共用)
    if MainID == ProtoMgr.GatewayPro.GATEWAY and SubID == ProtoMgr.Sub_GateWay.MiniGame_PublicRsq then        

        PublicMiniGame.ExchangeLogic(ClientID, Data, Len,clientinfo.nUserId)

        return true 
    end

    return 
end 

-- 踢出非白名单用户
function ClientSink.KickGameUsers()
    for ClientID,tClientInfo in pairs(ClientSink.m_ClientList) do
        repeat
            local arrKey = {}
            local sKey = ClientSink.GetDispatchKey(tClientInfo, tname.clubdezhouslave) -- 获取转发服务器
            if sKey ~= nil then
                table.insert(arrKey, sKey)
            end
            sKey = ClientSink.GetDispatchKey(tClientInfo, tname.TexasShortCardSlave) -- 获取转发服务器
            if sKey ==nil then
                table.insert(arrKey, sKey)
            end
            if tClientInfo.nUserId and tClientInfo.nUserId > 0 then      -- 网关维护判断 后台只需要维护网关即可 白名单跳过
                if tReforwardRule.IsUserInWhiteList(tClientInfo.nUserId) then
                    break
                end
            end
            local tSend = ProtoMgr.PubProto_1_pb.REQ_Kick_User()
            tSend.nUserId = tClientInfo.nUserId
            tSend.nType = 6  --暂时写6
            local s = tBase.GetSP().new(ProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, ProtoMgr.Sub_LobbyGame.SUB_GAME_KICK_USER)
            s:AddString(tSend:SerializeToString())
            for _, sServerKey in pairs(arrKey) do
                tBase.PostToServer(sServerKey, tClientInfo.ClientID, s:GetData(), s:GetSize())
            end
        until true
    end
end

return ClientSink