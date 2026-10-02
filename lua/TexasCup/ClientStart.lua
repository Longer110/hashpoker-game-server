package.path = require("./lua/TexasCup/Head").path

local tBase = require("base") -- 基础功能接口
local api = require("publicApi") -- 共用功能接口
local dbInfo = require("DBInfo") -- 数据库连接信息
local tname = require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tlogging = require("logging") -- 日志等级接口
local mlogger = require("logger") -- 日志对象  
local tGameConfig =require("GameConfig")  
local tPubUserApi  = require("PublicUserInfo")    --玩家数据
local tMsgHandle =require("MsgHandle")
local tProtoAux =require("ProtoCoder").Aux
local tTimerAux =require("TimerAux")

require("TexasEvents_pb")
require("DeZhouCenter_pb")
local ClientSink={}
--游戏服<->前端协议
local CMD_Client =TexasEvents_pb.TEvt_Proto()
local ToCMD_Client =function(strProto)
  return CMD_Client.Main_CMD,CMD_Client[strProto..'_CMD']
end
ClientAux =tProtoAux:New(TexasEvents_pb,ToCMD_Client)

--比赛服<->中心服协议
local pb_Center =DeZhouCenter_pb
local CMD_Center =DeZhouCenter_pb.DZC_Proto()
local ToCMD_Center =function(strProto)
  return CMD_Center.Main_CMD,CMD_Center[strProto..'_CMD']
end
CenterAux =tProtoAux:New(DeZhouCenter_pb,ToCMD_Center)


--db服<->游戏服协议
local pb_DbServer =ProtoMgr.DbServer1_pb
local CMD_DbServer =pb_DbServer.Db_Proto1()
local ToCMD_DbServer =function(strProto)
  return CMD_DbServer.Main_CMD,CMD_DbServer[strProto..'_CMD']
end
DbServAux =tProtoAux:New(pb_DbServer,ToCMD_DbServer)

--local tPacket =DbServAux:Encode("DbPublicAPIReq",{sDatabaseName="RecordDb",sSql=""})
--tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 




local function TestE()
    tBase.Log("Test")
   -- tMsgHandle.CreateMatchTest()
   --tMsgHandle.CreateTestCfg()
end


-- 启动服务器
function ClientSink.OnStart() 
    -- 设置日志目录:
    local sLogDir =  dbInfo.LogDir.."Game/TexasClup/" .. tBase.GetPort() .. "-" .. tBase.GetThreadIndex()
    mlogger.SetFile( sLogDir , "TexasCup", tBase )
    
    -- 设置全局等级
    mlogger:setLevel( tlogging.DEFAULT, "TexasCup" )
    -- 消息接收处理，不用默认函数
    tBase.m_MyMonitorFun = nil
    -- 注册服务器
    tBase.RegServer(tname.TexasCup)
    -- 注册协议
    ClientSink.Protocol()  


    tBase.Log(" Server Start")  

   --for Test
   tBase.SetTimer(tTimerAux.GetATimerId(), 1000*20, 1, TestE)

   --检查因服务器重启而中断的比赛,退还报名费用
   tBase.SetTimer(tTimerAux.GetATimerId(), 1000*25, 1, tMsgHandle.CheckBackFee)

   --定时检查redis配置，以决定创建或删除比赛
   tBase.SetTimer(tTimerAux.GetATimerId(), 1000*30, 1, tMsgHandle.Check)   
   tBase.SetTimer(tTimerAux.GetATimerId(), 1000*60, -1, tMsgHandle.Check) 
 
end   


-- 注册协议
function ClientSink.Protocol()  
    --前端协议
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtLogonReq_CMD,tMsgHandle.OnTEvtLogonReq)	            --x比赛服登陆 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtEventsOpenReq_CMD,tMsgHandle.OnTEvtEventsOpenReq)      --x赛事列表 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtEventsCloseReq_CMD,tMsgHandle.OnTEvtEventsCloseReq)    --x赛事列表关闭 请求 (关闭后不再接收通知:TEvtUserCntNotify,TEvtRuleDNotify)
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtUsersReq_CMD,tMsgHandle.OnTEvtUsersReq)                --x比赛信息=>玩家列表 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtAwardsReq_CMD,tMsgHandle.OnTEvtAwardsReq)              --x比赛信息=>奖励列表 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtSignUpReq_CMD,tMsgHandle.OnTEvtSignUpReq)              --x报名 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtSignUpCancelReq_CMD,tMsgHandle.OnTEvtSignUpCancelReq)  --x取消报名 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtSignUpDReq_CMD,tMsgHandle.OnTEvtSignUpDReq)            --x延迟报名 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtWatchReq_CMD,tMsgHandle.OnTEvtWatchReq)                --x观战 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtEnterReq_CMD,tMsgHandle.OnTEvtEnterReq)                --x进入比赛 请求 (调用后分两情况:1进入倒计时等待,倒计时完后,前端重新调用该请求 2直接进入比赛桌子)
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtCheckReq_CMD,tMsgHandle.OnTEvtCheckReq)                --x入口提示查询 请求
	tBase.RegFunc(CMD_Client.Main_CMD,CMD_Client.TEvtQuitReq_CMD,tMsgHandle.OnTEvtQuitReq)                  --退出比赛(弹窗里的;不再进行离线托管) 请求

  --中心服协议
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCLogOnReq_CMD ,tMsgHandle.OnDZCLogOnReq)                --中心服登陆请求+
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCMtRsp_CMD ,tMsgHandle.OnDZCMtRsp)                      --中心服通知或回复

  --网关与大厅通知
  tBase.RegFunc(ProtoMgr.GatewayPro.GATEWAY,ProtoMgr.Sub_GateWay.SUB_GATEWAY_CLIENT_CLOSE,tMsgHandle.OnClose)             --x断线通知
  tBase.RegFunc(ProtoMgr.GatewayPro.GATEWAY,ProtoMgr.Sub_GateWay.SUB_REQ_GAMESRV_SWICTHCONN,tMsgHandle.OnSwicthConn)      --x切换连接通知
end

--停止服务器
function ClientSink.OnStop()
    -- 取消本地服务器
    tBase.UnRegServer()
    mlogger:info("server stop") 
 end

--不应该有连接进入
function ClientSink.OnAccept(ClientID, ip, port)
end

function ClientSink.OnClose(ClientID)
end


return ClientSink

