 package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local m = require("base") -- 基础功能接口
local tname = require("typename") -- 类弄定义接口
local dbInfo = require("DBInfo") -- 数据库连接信息
local tProtoMgr = require("ProtoManager") -- 协议管理对象 
local mlogger = require("logger") -- 日志对象 
local tProto   = require("Protocol")
local tTableMgr = require("TableManage")
local  tSrvPub = require("SrvPublic")
local tChanel = require("Chanel")
local tEventHelp = require("EventHelp")
local tEventManager = require("EventMgr")
local tAndroidIo = require("AndroidIo")
local tConfig =require("GameConfig")
local  tGlogic = require("GLogic")
local tProtoAux =require("ProtoCoder").Aux 
local tSrvInfo = require("ServerInfo")
local tPubUser = require("PublicUserInfo") -- 用户信息 

--后台协议
local pb_Backstage =tProtoMgr.Backstage_pb
local CMD_Backstage =tProtoMgr.Backstage_pb.Backstage_Proto()
local ToCMD_Backstage =function(strProto)
  return CMD_Backstage.Main_CMD,CMD_Backstage[strProto..'_CMD']
end
--db服<->游戏服协议
local pb_DbServer =tProtoMgr.DbServer1_pb
local CMD_DbServer =pb_DbServer.Db_Proto1()
local ToCMD_DbServer =function(strProto)
  return CMD_DbServer.Main_CMD,CMD_DbServer[strProto..'_CMD']
end
--生成全局的编解码辅助对象
DbServAux =tProtoAux:New(pb_DbServer,ToCMD_DbServer)
BackstageAux =tProtoAux:New(pb_Backstage,ToCMD_Backstage)

-- -- 玩家功能回调
 ClientSink = { LevelLog = nil }

 -- 启动服务器
function ClientSink.OnStart()
	-- 设置日志目录：
    local sLogDir =  dbInfo.LogDir.."/Game/ClubQiangZhuangNiu/" .. m.GetPort() .. "-" .. m.GetThreadIndex()
    mlogger.SetFile( sLogDir , "ClubQiangZhuangNiu", m )

	--设置全局等级
	mlogger:setLevel( mlogger.LogObject.DEFAULT, "Game" )  
    -- 消息接收处理，不用默认函数
    m.m_MyMonitorFun = ClientSink.onMsgRecv
    m.Log(" 随机 Server Start ")  
    -- 注册服务器
    m.RegServer(tname.ClubQiangZhuangNiu)
    -- 注册协议
    ClientSink.Protocol()
    tEventHelp.tEventMgr = tEventManager
    tEventHelp.tEventMgr.Reg()
    m.Log("ClubQiangZhuangNiu Server Start ")  
    tTableMgr.Init()
    m.SetTimer(12341, 1000*3, 1, ClientSink.OnTimer)          --加载配置
    m.SetTimer(12345, 1000 *SetingConfig.SetUserNumber , -1, GLogic.TotalTable2)          --各个房间人数统计
    TableApi.OnStart(GLogic.TotalTable,12343)
    mlogger:info(m.m_tKey)
    CheckTableTimeOut.Init(tGlogic.OnCloseGroupCallBack,SrvPub.Timer.CheckOuTime,SrvPub.Timer.CheckOuTime + 1999)
    mlogger:info(ServerInfo.nServerId)
    --删除桌子
    ClientSink.DeleteTable() 

    local cnt =tPubUser.UnLockServAllUsersGold()
    m.Log("Unlock User Cnt:%d",cnt)  

 end

 --加载配置定时器
 function  ClientSink.OnTimer()
    tConfig.Req_AllDbConfig(0)
    m.SetTimer(12341, 1000 * 60 * 5, 1, ClientSink.OnTimer)          --加载配置
 end

 --停止服务器
 function ClientSink.OnStop()
    --删除桌子
    ClientSink.DeleteTable() 
    -- 取消本地服务器
    m.UnRegServer()
    mlogger:info(" ClubQiangZhuangNiu Server OnStop ") 
 end

 -- 重启服务器 将桌子删除
function ClientSink.DeleteTable()  
	local sKey = "APIOpenTale_"..tSrvInfo.nServerId.."#*"
	local tRedis =m.m_MyRedisData[2].redis
	local arrTableInfo = tRedis:keys(sKey)
   local nCnt = 0
	for _,val in pairs(arrTableInfo) do
		local tInfo = tRedis:hgetall(val)
		local nGameId =tonumber(tInfo.nGameId)
		if tInfo and tInfo.sTableId and (nGameId == GConfig.GameType.KanPaiNiuNiu) then 
		  tRedis:del(val)
        nCnt = nCnt + 1
		end 
	end
   mlogger:info(string.format(" ClubQiangZhuangNiu Server start DeleteTable %d",nCnt))
 end 

function ClientSink.Protocol()
   --前端请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_LOGIN, tProto.LogRequest) --登录 请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_ACTION, tProto.Req_Action) --操作 请求(站起/坐下)
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_QIANGZHUAGN, tProto.Req_QiangZhuang) --抢庄 请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_XIAZHU, tProto.Req_XiaZhu) --下注 请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_TANPAI_READY, tProto.TanPaiReady) --摊牌 请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_LOGOUT_GAME, tProto.Req_LogOut) --登出请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_Retain,tProto.Req_Retain) --'留座离桌'或'回到座位' 请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_Chat,tProto.Req_Chat) --表情聊天 请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_OverView,tProto.Req_OverView) --牌桌总览 请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_HeadInfo,tProto.Req_HeadInfo) --头像信息 请求
    m.RegFunc( tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REQ_PaijuDetail,tProto.Req_PaijuDetail) --牌局详情 请求
    
    --网关
    m.RegFunc( tProtoMgr.GatewayPro.GATEWAY, tProtoMgr.Sub_GateWay.SUB_GATEWAY_CLIENT_CLOSE, tProto.OnClose) --网关关闭 请求
  
    m.RegFunc( tProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, tProtoMgr.Sub_LobbyGame.SUB_GAME_KICK_USER, tProto.ReqKickUser)  --后台踢人

    m.RegFunc(tProtoMgr.GatewayPro.GATEWAY,tProtoMgr.Sub_GateWay.SUB_REQ_GAMESRV_SWICTHCONN,tProto.OnSwicthConn)  --链接切换

    --后台
    m.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.ReqAPI_Table_CMD, GLogic.OnReqAPI_Table)   --后台桌子管理 请求 (创建与关闭)

    m.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.ReqAddAndroid_CMD, tProto.OnAdjustRobCountReq)   --后台修改某张桌机器人数量 请求
    
    --db服返回
    m.RegFunc(CMD_DbServer.Main_CMD, CMD_DbServer.GetResultsBySqlRsp_CMD, tProto.OnDbRecordDetailRsp)              --牌局明细结果
    m.RegFunc(CMD_DbServer.Main_CMD, CMD_DbServer.DbRechargeRsp_CMD, tProto.OnDbRechargeRsp)                        --充值结果返回

    for _, v in pairs(tSrvPub.Event) do m.RegFunc(tSrvPub.EMain, v, tChanel.OnNewChanel) end

    tAndroidIo.Start()
end

 return ClientSink