package.path = require("./lua/Game/Texas/Slave/Head").path

local m = require("base") -- 基础功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local mlogger = require("logger") -- 日志对象 
local tTimerAux =require("TimerAux")
local tlogging = require("logging") -- 日志等级接口
local Define =require("Define")
local dbInfo = require("DBInfo")
local tSrvInfo = require("ServerInfo")
local tMsgHandle = require("MsgHandle")
local tProtoAux =require("ProtoCoder").Aux
local tConfig =require("GameConfig")
local tLiveCSRelation =require("LiveCSRelation")
local tname = require("typename") -- 类弄定义接口
local tPubUser = require("PublicUserInfo") 
local tUserMgr   = require("UserManager")
require("DeZhouCenter_pb")
require("DeZhou_pb")

--游戏服<->中心服协议
local pb_Center =DeZhouCenter_pb
local CMD_Center =DeZhouCenter_pb.DZC_Proto()
local ToCMD_Center =function(strProto)
  return CMD_Center.Main_CMD,CMD_Center[strProto..'_CMD']
end

--游戏服<->前端协议
local pb_Slave =DeZhou_pb
local CMD_Slave =DeZhou_pb.DeZhou_Proto()
local ToCMD_Slave =function(strProto)
  return CMD_Slave.Main_CMD,CMD_Slave[strProto..'_CMD']
end
--web后台<->游戏服协议
local pb_Backstage =ProtoMgr.Backstage_pb
local CMD_Backstage =ProtoMgr.Backstage_pb.Backstage_Proto()
local ToCMD_Backstage =function(strProto)
  return CMD_Backstage.Main_CMD,CMD_Backstage[strProto..'_CMD']
end

--db服<->游戏服协议
local pb_DbServer =ProtoMgr.DbServer1_pb
local CMD_DbServer =pb_DbServer.Db_Proto1()
local ToCMD_DbServer =function(strProto)
  return CMD_DbServer.Main_CMD,CMD_DbServer[strProto..'_CMD']
end

--[全局] 生成两个全局的编解码辅助对象
CenterAux =tProtoAux:New(pb_Center,ToCMD_Center)
SlaveAux =tProtoAux:New(pb_Slave,ToCMD_Slave)
BackstageAux =tProtoAux:New(pb_Backstage,ToCMD_Backstage)
DbServAux =tProtoAux:New(pb_DbServer,ToCMD_DbServer)

--中心服key
local nCenterServId=nil
local sCenterServKey =nil
--发送协议到中心服
local function SendToCenterServer(nRoomId,strProto,tData)
  local tPacket =CenterAux:Encode(strProto,tData)
  if sCenterServKey then
    base.PostToServer(sCenterServKey, 0, tPacket:GetData(), tPacket:GetSize())
  end
end

--获得本服对应的中心服id
local function _GetTheCenterServId(nTimerId)
  local function tFunc()
    nCenterServId =tLiveCSRelation.GetCenterServId(tSrvInfo.nServerId)
    if nCenterServId then
      m.Log("nCenterServId:%d",nCenterServId)
      Define.nCenterServId=nCenterServId
      return
    end
    m.Log("ReqDbLiveCSRelation")
    tLiveCSRelation.ReqDbLiveCSRelation()
    m.SetTimer(nTimerId, 1000*5, 1, tFunc)   
  end
  tFunc()
end

--获得本服对应的中心服key
local function _GetTheCenterServKey(nTimerId)
  local function tFunc()
    local arrAllCenterKey =m.GetSrcAllKey(tname.dezhoucenter) or {}
    for _,sServKey in ipairs(arrAllCenterKey) do
      local nServerId =tonumber(string.match(sServKey,"_(%d+)"))
      if nServerId ==nCenterServId then
        sCenterServKey= sServKey
        break
      end
    end
    if sCenterServKey then
      m.Log("sCenterServKey:%s",sCenterServKey)
      return
    end
    m.SetTimer(nTimerId, 1000*5, 1, tFunc)   
  end
  tFunc()
end

--发送登陆协议到中心服
local function LogonToCenter()
    local nRlt =SendToCenterServer(1,"DZCLogOnReq",{nServerId=tSrvInfo.nServerId})
    m.Log("LogonToCenter %d",(nRlt or 0))
end

local  ClientSink = {}

--启动服务器
function ClientSink.OnStart()
    --设置日志目录：
    local sLogDir =  dbInfo.LogDir.."Game/Dezhou/slave/slave" .. m.GetPort() .. "-" .. m.GetThreadIndex()
    mlogger.SetFile( sLogDir , Define.LLogDir, m )
    --设置全局等级
    mlogger:setLevel( tlogging.DEFAULT, "Game" )  
    -- 消息接收处理，不用默认函数
    m.m_MyMonitorFun =nil -- ClientSink.onMsgRecv
    -- 注册服务器
    m.RegServer(Define.sGameName)
    -- 注册协议
    ClientSink.Protocol()
    --登陆中心服
    m.SetTimer(tTimerAux.GetATimerId(), 1000*15, 1, LogonToCenter)   
    m.SetTimer(tTimerAux.GetATimerId(), 1000*60, -1, LogonToCenter) 

    _GetTheCenterServId(tTimerAux.GetATimerId())
    _GetTheCenterServKey(tTimerAux.GetATimerId())

    tMsgHandle.InitSet(SendToCenterServer)
    m.Log("bjl slave Server Start")  
    
    local cnt =tPubUser.UnLockServAllUsersGold()
    m.Log("Unlock User Cnt:%d",cnt)  

   -- tConfig.SetIsNeedGameList(false)    --不需要获取游戏列表(只获取店与组的关系表)
    local loadConfig=function()
      tConfig.Req_AllDbConfig(0)
    end
    m.SetTimer(tTimerAux.GetATimerId(), 1000*6, 1, loadConfig)          --加载配置
    m.SetTimer(tTimerAux.GetATimerId(), 1000*60*5, -1, loadConfig)      --每5分钟,重新加载一次配置(改了数据库可以不用重启)

    --publicApi.PublicModuleUpdateFile(65001,"./lua/public/SetingConfig")   -- 热更新公共配置 

end

--停止服务器
function ClientSink.OnStop()
   -- 取消本地服务器
   m.UnRegServer()
   mlogger:info("server stop") 
end


function ClientSink.Protocol()
  --中心服务协议
  m.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCLogOnResp_CMD ,tMsgHandle.OnDZCLogOnResp)              --登陆回复	
  m.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCRsp_CMD ,tMsgHandle.OnDZCRsp)                          --中心服(回复或通知)
  m.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCScenceRsp_CMD ,tMsgHandle.OnDZCScenceRsp)              --桌子场景创建(回复或通知)
 
 --前端请求
	m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouLogOnReq_CMD,tMsgHandle.DeZhouLogOnReq)  			      --登陆请求 (进入游戏，需要先登陆)
	m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouOpReq_CMD,tMsgHandle.DeZhouOpReq) 					        --操作请求
	m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouBackToLobbyReq_CMD,tMsgHandle.DeZhouBackToLobbyReq) --返回大厅请求
	m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouPreOpReq_CMD,tMsgHandle.DeZhouPreOpReq) 			      --预操作请求
	m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouStanpUpReq_CMD,tMsgHandle.DeZhouStanpUpReq)		      --站起请求
	m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouSitDownReq_CMD,tMsgHandle.DeZhouSitDownReq)			    --坐下请求
	m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouTakeInRangeReq_CMD,tMsgHandle.DeZhouTakeInRangeReq)	--筹码买入范围查看请求
	m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhoTakeInReq_CMD,tMsgHandle.DeZhoTakeInReq)			        --筹码买入请求
  m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouCancelAutoReq_CMD,tMsgHandle.DeZhouCancelAutoReq)   --取消托管请求
  m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouCofingReq_CMD,tMsgHandle.DeZhouCofingReq)           --房间设置 请求
  m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouKickUserReq_CMD,tMsgHandle.DeZhouKickUserReq)       --主播踢人请求
  m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouChatReq_CMD,tMsgHandle.DeZhouChatReq)               --表情聊天请求
  m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouPauseReq_CMD,tMsgHandle.DeZhouPauseReq)             --暂停请求
  m.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.DeZhouGmReq_CMD,tMsgHandle.DeZhouGmReq)                   --Gm命令请求

  --网关与大厅通知
  m.RegFunc(ProtoMgr.GatewayPro.GATEWAY,ProtoMgr.Sub_GateWay.SUB_GATEWAY_CLIENT_CLOSE,tMsgHandle.OnClose)             --断线通知
  m.RegFunc(ProtoMgr.GatewayPro.GATEWAY,ProtoMgr.Sub_GateWay.SUB_REQ_GAMESRV_SWICTHCONN,tMsgHandle.OnSwicthConn)      --切换连接通知
  m.RegFunc( ProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, ProtoMgr.Sub_LobbyGame.SUB_GAME_KICK_USER, tMsgHandle.OnKickUser)  --后台踢人
 
  --db服返回
  m.RegFunc(CMD_DbServer.Main_CMD, CMD_DbServer.DbRechargeRsp_CMD, tMsgHandle.OnDbRechargeRsp)                        --充值结果返回
end


--不应该有连接进入
function ClientSink.OnAccept(ClientID, ip, port)
end

function ClientSink.OnClose(ClientID)
end

return ClientSink