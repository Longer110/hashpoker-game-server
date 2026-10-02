package.path = require("./lua/Game/TexasClubShortCard/Center/Head").path

local tBase = require("base") -- 基础功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local mlogger = require("logger") -- 日志对象 
local tGame =require("Game") 
local tlogging = require("logging") -- 日志等级接口
local dbInfo = require("DBInfo") -- 数据库连接信息
local tPubUser = require("PublicUserInfo") -- 用户信息  
local Define =require("Define") 
local tProtoAux =require("ProtoCoder").Aux 
require("DeZhouCenter_pb")

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


local  ClientSink = {}

-- 启动服务器
function ClientSink.OnStart()
    --设置日志目录：
    local sLogDir =  dbInfo.LogDir.."Game/TexasShortCard/"..Define.LLogDir.."/" .. tBase.GetPort() .. "-" .. tBase.GetThreadIndex()
     mlogger.SetFile( sLogDir , Define.LLogDir, tBase )
    --设置全局等级
    mlogger:setLevel( tlogging.DEFAULT, "Game" ) 

    tBase.m_IsSupportMultiMsgQue=false  --禁止多消息队列，以保证状态同步

    -- 注册服务器
    tBase.RegServer(Define.sGameName)
    -- 注册协议
    ClientSink.Protocol()
    tBase.Log("TexasShortCard Center Start ")  

   --卡房检测与清理
    tPubUser.GameClear(Define.nGameId) 

    --解锁玩家金币
    local cnt =tPubUser.UnLockServAllUsersGold()
    tBase.Log("Unlock User Cnt:%d",cnt) 
 
     
    --删除桌子
    tGame.DeleteTable() 
    tBase.SetTimer(60001, 1000*20, 1,tGame.RestartServiceTable)          --压测桌子开桌  

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
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCLogOnReq_CMD ,tGame.OnDZCLogOnReq)       --从服登陆请求+
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCReq_CMD ,tGame.OnDZCReq)                 --
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCScenceReq_CMD ,tGame.OnDZCScenceReq)     --
  tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.DZCTableCreateReq_CMD,tGame.OnDZCTableCreateReq)
  
  tBase.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.ReqAPI_Table_CMD, tGame.OnReqAPI_Table)   --后台桌子管理请求 (创建与关闭)
  tBase.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.ReqAddAndroid_CMD, tGame.OnAndroidIncr) --后台增减桌子机器人
end


function ClientSink.OnAccept(ClientID, ip, port)
end
function ClientSink.OnClose(ClientID)
end

return ClientSink