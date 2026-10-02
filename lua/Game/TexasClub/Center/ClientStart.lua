package.path = require("./lua/Game/TexasClub/Center/Head").path

local tBase = require("base") -- 基础功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local mlogger = require("logger") -- 日志对象 
local tGame =require("Game")
local tConfig =require("GameConfig") -- 
local tlogging = require("logging") -- 日志等级接口
local dbInfo = require("DBInfo") -- 数据库连接信息
local tPubUser = require("PublicUserInfo") -- 用户信息 
local tSetingConfig = require("SetingConfig") -- 
local Define =require("Define")
local tTimerAux =require("TimerAux")
local tProtoAux =require("ProtoCoder").Aux
local tPLiveGame =require("PublicLiveGame") 
local tSrvInfo = require("ServerInfo")
local tname = require("typename") -- 类弄定义接口

HttpNB = require("HttpNB")       -- HTTP 异步 
require("HttpNB2")
require("DeZhouCenter_pb")
require 'TexasAi_pb' 

--游戏服<->AI服协议
local CMD_Ai =TexasAi_pb.DZA_Proto()
local ToCMD_Ai =function(strProto)
  return CMD_Ai.Main_CMD,CMD_Ai[strProto..'_CMD']
end

--游戏服<->中心服协议
local pb_Center =DeZhouCenter_pb
local CMD_Center =DeZhouCenter_pb.DZC_Proto()
local ToCMD_Center =function(strProto)
  return CMD_Center.Main_CMD,CMD_Center[strProto..'_CMD']
end
--后台协议
local pb_Backstage =ProtoMgr.Backstage_pb
local CMD_Backstage =ProtoMgr.Backstage_pb.Backstage_Proto()
local ToCMD_Backstage =function(strProto)
  return CMD_Backstage.Main_CMD,CMD_Backstage[strProto..'_CMD']
end
--生成全局的编解码辅助对象
BackstageAux =tProtoAux:New(pb_Backstage,ToCMD_Backstage)
CenterAux =tProtoAux:New(pb_Center,ToCMD_Center)
AiAux =tProtoAux:New(TexasAi_pb,ToCMD_Ai)

local  ClientSink = {}

function UrlRequest(sUrl, funcRes, funcError,sSendType,sBody)
  local ss =string.match(sUrl,"^%s*(https?)")
  if ss=="https" then
      ClientSink.m_https:request(sUrl, funcRes, funcError, sSendType, sBody)
  else
    ClientSink.m_http:request(sUrl, funcRes, funcError, sSendType, sBody)
  end
end


--获得比赛服key
local sMatchServKey=nil
local sMatchServId =nil
local function _GetMatchServKey(nTimerId)
  local function tFunc()
    local arrKey =tBase.GetSrcAllKey(tname.TexasCup) or {}
    table.sort(arrKey)
    sMatchServKey =arrKey[1]
    if sMatchServKey then
      sMatchServId =tonumber(string.match(sMatchServKey,"_(%d+)"))
      tBase.Log("sMatchServKey:%s sMatchServId:%d",sMatchServKey,sMatchServId)
      return
    end
    tBase.SetTimer(nTimerId, 1000*15, 1, tFunc)   
  end
  tFunc()
end

--发送协议到比赛服
local function SendToMatchServer(strProto,tData)
  if not sMatchServKey then
    tBase.Log("SendToMatchServer Fail,%s",strProto)
    return
  end
  local tPacket =CenterAux:Encode(strProto,tData)
  tBase.PostToServer(sMatchServKey, 0, tPacket:GetData(), tPacket:GetSize())
end

--发送登陆协议到比赛服
local function LogonToMatch()
  local nRlt =SendToMatchServer("DZCLogOnReq",{nServerId=tSrvInfo.nServerId})
  tBase.Log("LogonToMatch %d",(nRlt or 0))
end

-- 启动服务器
function ClientSink.OnStart()
    --设置日志目录：
    local sLogDir =  dbInfo.LogDir.."Game/ClubDezhou/"..Define.LLogDir.."/" .. tBase.GetPort() .. "-" .. tBase.GetThreadIndex()
     mlogger.SetFile( sLogDir , Define.LLogDir, tBase )
    --设置全局等级
    mlogger:setLevel( tlogging.DEFAULT, "Game" ) 

    tBase.m_IsSupportMultiMsgQue=false  --禁止多消息队列，以保证状态同步

    -- 注册服务器
    tBase.RegServer(Define.sGameName)
    -- 注册协议
    ClientSink.Protocol()
    tBase.Log(" %s Server Start 2023-03-06 10:13",Define.sGameName)  

   --卡房检测与清理
    tPubUser.GameClear(Define.nGameId_Normal) 
    tPubUser.GameClear(Define.nGameId_Ahm) 

    --解锁玩家金币
    local cnt =tPubUser.UnLockServAllUsersGold()
    tBase.Log("Unlock User Cnt:%d",cnt) 
 
    -- 异步http访问
    HttpNB.Init(tTimerAux.GetATimerId(), tTimerAux.GetATimerId())

    ClientSink.m_https = HttpNB2:new(true)  -- 参数2：true为ssl方式，false为非ssl方式 参数3：wrapParms，https不填则用默认,http不需要
    ClientSink.m_https:Init(tTimerAux.GetATimerId(), tTimerAux.GetATimerId())
    ClientSink.m_https:setTimeout(2)

    ClientSink.m_http = HttpNB2:new(false)  -- 参数2：true为ssl方式，false为非ssl方式 参数3：wrapParms，https不填则用默认,http不需要
    ClientSink.m_http:Init(tTimerAux.GetATimerId(), tTimerAux.GetATimerId())
    ClientSink.m_http:setTimeout(2)

    --创建一个测试用桌子
    local CreateTestTable =function()
      for i=1,1 do
        tGame.CreateTestTable()
      end
    end
    --tBase.SetTimer(tTimerAux.GetATimerId(), 1000*20, 1, CreateTestTable)
    tGame.SendToMatchServer =SendToMatchServer

    --获得比赛服key
    _GetMatchServKey(tTimerAux.GetATimerId())
    
    --登陆比赛服
    tBase.SetTimer(tTimerAux.GetATimerId(), 1000*20, 1, LogonToMatch)   
    tBase.SetTimer(tTimerAux.GetATimerId(), 1000*60, -1, LogonToMatch) 

    --删除桌子
    tGame.DeleteTable() 

end

--停止服务器
function ClientSink.OnStop()
  --删除桌子
  tGame.DeleteTable() 
  
   -- 取消本地服务器
   tBase.UnRegServer()
   tBase.Log(" %s Server stop",Define.sGameName) 
end


function ClientSink.Protocol()
  --从服请求
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCLogOnReq_CMD ,tGame.OnDZCLogOnReq)       --从服登陆请求+
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCReq_CMD ,tGame.OnDZCReq)                 --
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCScenceReq_CMD ,tGame.OnDZCScenceReq)     --
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCTableCreateReq_CMD,tGame.OnDZCTableCreateReq)
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCTestTableCreateReq_CMD,tGame.OnDZCTestTableCreateReq) --试玩房创建
  
  --比赛服
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCLogOnResp_CMD ,tGame.OnDZCLogOnResp)   --登录返回
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCMtReq_CMD ,tGame.OnDZCMtReq)           --比赛服 请求

  --AI服返回
  tBase.RegFunc(CMD_Ai.Main_CMD ,CMD_Ai.DZARsp_CMD,tGame.OnDZARsp)    --Ai结果返回

  --后台命令
  tBase.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.ReqAPI_Table_CMD, tGame.OnReqAPI_Table)   --后台桌子管理请求 (创建与关闭)
  tBase.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.ReqAddAndroid_CMD, tGame.OnAndroidIncr) --后台增减桌子机器人
  
end


function ClientSink.OnAccept(ClientID, ip, port)
end
function ClientSink.OnClose(ClientID)
end

return ClientSink