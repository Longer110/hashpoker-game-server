package.path = require("./lua/Club/Center/Head").path

local  ClientSink = {}
 

--启动服务器
function ClientSink.OnStart()
    --设置日志目录：
    local sLogDir =  DBInfo.LogDir.."/Club/"..Define.sCenterLogDir.."/" .. Base.GetPort() .. "-" .. Base.GetThreadIndex()
    Logger.SetFile( sLogDir , Define.sCenterLogDir, Base )
    --设置全局等级
    Logger:setLevel( Logging.DEFAULT, "Game" )  
    -- 消息接收处理，不用默认函数
    Base.m_MyMonitorFun =nil -- ClientSink.onMsgRecv
    -- 注册服务器
    Base.RegServer(Define.sCenterName)
    -- 注册协议
    ClientSink.Protocol() 

    PacketEncoder.Init(Pb_Center,CMD_Center)       --初始化编解码器     

    RedisCahche.SetRedisNotifyCallBack(MsgHandle.OnWebRedisNotifyCallBack)  --设置后台修改配置后的回调通知函数

    CenterData.tTimerId.DBServerGroupReq = TimerAux.GetATimerId() --60000
    Base.SetTimer(CenterData.tTimerId.DBServerGroupReq, 1000*10, 1, MsgHandle.DBServerGroupReq) --服务器分组请求
    CenterData.tTimerId.UpdateClubConfig = TimerAux.GetATimerId() --59999
    Base.SetTimer(CenterData.tTimerId.UpdateClubConfig, 1000*10*60, -1, MsgHandle.UpdateClubConfig) --更新俱乐部后台配置
    CenterData.tTimerId.HandleDataOnZero = TimerAux.GetATimerId() --59998
    Base.SetTimer(CenterData.tTimerId.HandleDataOnZero, (PubClubApi.GetNowToNextZeroTime()+math.random(2,5))*1000, 1, ClientSink.HandleDataOnZero) --零点处理数据
    CenterData.tTimerId.CheckClubTable = TimerAux.GetATimerId() --59997
    Base.SetTimer(CenterData.tTimerId.CheckClubTable, 1000*60*1, 1, MsgHandle.CheckClubTable) --定时检查俱乐部牌桌
    CenterData.tTimerId.CheckMaintenanceOfServer = TimerAux.GetATimerId() --59996
    Base.SetTimer(CenterData.tTimerId.CheckMaintenanceOfServer, 1000*15, 1, MsgHandle.CheckMaintenanceOfServer) --定时检查俱乐部服维护状态
    CenterData.tTimerId.OnTimeDealOverTimeApply = TimerAux.GetATimerId() --59995
    Base.SetTimer(CenterData.tTimerId.OnTimeDealOverTimeApply, 24*60*60*1000, -1, MsgHandle.OnTimeDealOverTimeApply) --处理过期申请
    CenterData.tTimerId.CheckServerOfTable = TimerAux.GetATimerId() --59994
    Base.SetTimer(CenterData.tTimerId.CheckServerOfTable, 1000*60*3, -1, MsgHandle.CheckServerOfTable) --检查牌桌所在服务器是否还在
    CenterData.tTimerId.CheckCenterId = TimerAux.GetATimerId() --59993
    Base.SetTimer(CenterData.tTimerId.CheckCenterId, 1000*60*3, -1, MsgHandle.CheckCenterId) --检查俱乐部所在中心服id是否能删掉

    CenterData.tTimerId.RestartTable = TimerAux.GetATimerId() --59992
    Base.SetTimer(CenterData.tTimerId.RestartTable, 1000*30, 1, MsgHandle._RestartTable) --恢复牌桌
    

    local cnt =PublicUserInfo.UnLockServAllUsersGold()
    Base.Log("Unlock User Cnt:%d",cnt)
    
    for k,v in pairs(CenterData.tTimerId) do
        Base.Log("CenterData.tTimerId.%s:%d",k,v)
    end

    CenterData.tTimerObj = TimerAux:New()   --初始化定时器
    PublicUserInfo.ClearClubData()
    
    Base.Log(" ClubCenter Server Start")  

end

--零点处理数据
function ClientSink.HandleDataOnZero()
    PublicRedis.DelClubTodayIncome() --删除所有俱乐部今日收益
    Base.Log("零点处理数据 删除所有俱乐部今日收益")

    local tDate = os.date("*t")
    if tDate.wday==2 then
        -- 星期一, 星期天为1
        PublicRedis.DelClubUserWeekCount() --删除俱乐部玩家本周局数
        Base.Log("周一零点处理数据 删除俱乐部玩家本周局数")
    end
 
    local nDay = os.date("%d")
    if tonumber(nDay) == 1 then 
        PublicRedis._HandleClubOpenTableNameCount(3) -- 1号 零点重置牌桌 名序号 
    end 

    Base.SetTimer(CenterData.tTimerId.HandleDataOnZero, (PubClubApi.GetNowToNextZeroTime()+math.random(2,5))*1000, 1, ClientSink.HandleDataOnZero) --零点处理数据
end

--停止服务器
function ClientSink.OnStop()
    -- 取消本地服务器
    Base.UnRegServer()
    Logger:info("server stop") 
end

function ClientSink.Protocol()
    --从服
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCConnectReq_CMD ,MsgHandle.OnClubCConnectReq)  --从服连接请求
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCCreateSucessReq_CMD ,MsgHandle.OnClubCCreateSucessReq)  --创建俱乐部成功请求
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCSceneChangeReq_CMD ,MsgHandle.OnClubCSceneChangeReq)  --俱乐部场景信息改变请求

    --DB服
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubDataRsp_CMD,MsgHandle.OnDBClubDataRsp)                --俱乐部数据 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubAssetChangeNotify_CMD,MsgHandle.OnDBClubAssetChangeNotify)   -- 修改俱乐部资产同步 
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ServerIdGroupRsp_CMD,MsgHandle.OnDBServerGroupRsp)   --服务器分组数据 返回 
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubApplyInvalidRsp_CMD,MsgHandle.OnDBClubApplyInvalidRsp)   --申请失效处理返回 返回

    --游戏服
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCGameOpenTableNotify_CMD ,MsgHandle.OnClubCGameOpenTableNotify)  --游戏服开桌通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCGameCloseTableNotify_CMD ,MsgHandle.OnClubCGameCloseTableNotify)  --游戏服关桌通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCGameTableInfoNotify_CMD ,MsgHandle.OnClubCGameTableInfoNotify)  --游戏服牌桌信息改变通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCGameUserSettleNotify_CMD ,MsgHandle.OnClubCGameUserSettleNotify)  --游戏服玩家结算通知

    --后台
    Base.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.WebOpenClubTableReq_CMD, MsgHandle.OnWebOpenClubTableReq) --后台开桌请求
    Base.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.WebCloseClubTableReq_CMD, MsgHandle.OnWebCloseClubTableReq) --后台关桌请求
end

return ClientSink