package.path = require("./lua/Club/Slave/Head").path

local  ClientSink = {}

--启动服务器
function ClientSink.OnStart()
    --设置日志目录：
    local sLogDir =  DBInfo.LogDir.."/Club/"..Define.sSlaveLogDir.."/" .. Base.GetPort() .. "-" .. Base.GetThreadIndex()
    Logger.SetFile( sLogDir , Define.sSlaveLogDir, Base )
    --设置全局等级
    Logger:setLevel( Logging.DEFAULT, "Game" )  
    -- 消息接收处理，不用默认函数
    Base.m_MyMonitorFun =nil -- ClientSink.onMsgRecv
    -- 注册服务器
    Base.RegServer(Define.sSlaveName)
    -- 注册协议
    ClientSink.Protocol()

    local cnt =PublicUserInfo.UnLockServAllUsersGold()
    Base.Log("Unlock User Cnt:%d",cnt)

    GameConfig.SetIsNeedGameList(false)    --不需要获取游戏列表(只获取店与组的关系表)

    RedisCahche.SetRedisNotifyCallBack(MsgOnTime.OnWebRedisNotifyCallBack)  --设置后台修改配置后的回调通知函数

    SlaveData.tTimerId.ReqDbLiveCSRelation = TimerAux.GetATimerId()
    Base.SetTimer(SlaveData.tTimerId.ReqDbLiveCSRelation, 1000*1, 1, LiveCSRelation.ReqDbLiveCSRelation) --获取主从服对应关系
    SlaveData.tTimerId.GetTheCenterServId = TimerAux.GetATimerId()
    Base.SetTimer(SlaveData.tTimerId.GetTheCenterServId, 1000*3, 1, ClientSink.GetTheCenterServId) --获取从服对应的中心服id
    SlaveData.tTimerId.loadConfig = TimerAux.GetATimerId()
    Base.SetTimer(SlaveData.tTimerId.loadConfig, 1000*5, 1, ClientSink.loadConfig) --加载配置
    SlaveData.tTimerId.Check = TimerAux.GetATimerId()
    Base.SetTimer(SlaveData.tTimerId.Check, 1000*1, -1, MsgOnTime.Check) --定时检查处理消息
    SlaveData.tTimerId.CheckMaintenance = TimerAux.GetATimerId()
    Base.SetTimer(SlaveData.tTimerId.CheckMaintenance, 1000*30, -1, MsgMaintenance.CheckMaintenance) --定时检查维护状态
    SlaveData.tTimerId.InitFinish = TimerAux.GetATimerId()
    Base.SetTimer(SlaveData.tTimerId.InitFinish, 1000*6, 1, ClientSink.InitFinish) --定时检查维护状态
    
    SlaveData.tTimerId.getConfig = TimerAux.GetATimerId()
    Base.SetTimer(SlaveData.tTimerId.getConfig, 1000*10, 1, GameConfig.ReqDbGloBalConfig) --请求全局配置

    UserOnTime.InitTimer()
 

    for k,v in pairs(SlaveData.tTimerId) do
        Base.Log("SlaveData.tTimerId.%s:%d",k,v)
    end
     
    Base.Log(" ClubSlave Server Start") 

    
    -- 异步http访问
    HttpNB.Init(1101, 1102)

    
end


--停止服务器
function ClientSink.OnStop()
   -- 取消本地服务器
   Base.UnRegServer()
   Logger:info("server stop") 
end

--获取从服对应的中心服id
function ClientSink.GetTheCenterServId()
    MsgApi.nCenterServId  = LiveCSRelation.GetCenterServId(ServerInfo.nServerId)
    if MsgApi.nCenterServId then
        Base.Log("获取到中心服 nCenterServId:%d",MsgApi.nCenterServId)
        ClientSink.GetTheCenterServKey() --获得本服对应的中心服key
        return
    end

    Base.Log("没有获取到中心服id,稍后再次获取")

    --获取主从服对应关系
    LiveCSRelation.ReqDbLiveCSRelation()
    --2s后再次获取从服对应的中心服id
    Base.SetTimer(SlaveData.tTimerId.GetTheCenterServId, 1000*2, 1, ClientSink.GetTheCenterServId)
end

--获得本服对应的中心服key
function ClientSink.GetTheCenterServKey()
    local arrAllCenterKey =Base.GetSrcAllKey(Define.sCenterName) or {}
    for _,sServKey in ipairs(arrAllCenterKey) do
        local nServerId =tonumber(string.match(sServKey,"_(%d+)"))
        if nServerId ==MsgApi.nCenterServId then
            MsgApi.sCenterServKey= sServKey
            break
        end
    end
    if MsgApi.sCenterServKey then
        Base.Log("  获得本服对应的中心服key sCenterServKey:_%s",MsgApi.sCenterServKey)
        --连接中心服
        ClientSink.ClubCConnectReq()
        return
    end
    Base.Log("  没有获得本服对应的中心服key,稍后再次获取")
    if not SlaveData.tTimerId.GetTheCenterServKey then
        SlaveData.tTimerId.GetTheCenterServKey = TimerAux.GetATimerId()
        Base.Log("SlaveData.tTimerId.GetTheCenterServKey:%d",SlaveData.tTimerId.GetTheCenterServKey)
    end
    Base.SetTimer(SlaveData.tTimerId.GetTheCenterServKey, 1000*2, 1, ClientSink.GetTheCenterServKey)
    Base._SlaveRelevanceSendTelegram()
end

--连接中心服
function ClientSink.ClubCConnectReq()
    MsgApi.SendToCenterServer("ClubCConnectReq",{nServerId=ServerInfo.nServerId})
    Base.Log("ClubCConnectReq .......")
    if not SlaveData.tTimerId.ClubCConnectReq then
        SlaveData.tTimerId.ClubCConnectReq = TimerAux.GetATimerId()
        Base.Log("SlaveData.tTimerId.ClubCConnectReq:%d",SlaveData.tTimerId.ClubCConnectReq)
    end
    Base.SetTimer(SlaveData.tTimerId.ClubCConnectReq, 1000*60, 1, ClientSink.ClubCConnectReq)
end

--加载配置
function ClientSink.loadConfig()
    GameConfig.Req_AllDbConfig()
    
    Store.LoadStoreConfig()
    
    -- Base.SetTimer(SlaveData.tTimerId.loadConfig, 1000*20, 1, ClientSink.loadConfig) --加载配置
    Base.SetTimer(SlaveData.tTimerId.loadConfig, 1000*60*5, 1, ClientSink.loadConfig) --加载配置
end

function ClientSink.InitFinish()
    Base.Log("开服加载结束，可进行操作")
    SlaveData.isInitFinish = true
end

function ClientSink.Protocol()

    ActivityPublic.Protocol()
    
    --中心服协议
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCSceneNotify_CMD ,MsgCenter.OnClubCSceneNotify)  --俱乐部场景通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCSwitchNotify_CMD ,MsgCenter.OnClubCSwitchNotify)  --切换俱乐部通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCSceneChangeNotify_CMD ,MsgCenter.OnClubCSceneChangeNotify)  --俱乐部场景信息改变通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCUserInfoChangeNotify_CMD ,MsgCenter.OnClubCUserInfoChangeNotify)  --俱乐部玩家信息改变通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCKickOutNotify_CMD ,MsgCenter.OnClubCKickOutNotify)  --踢出俱乐部通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCUserMsgNotify_CMD ,MsgCenter.OnClubCUserMsgNotify)  --玩家消息通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCTableOpenNotify_CMD ,MsgCenter.OnClubCTableOpenNotify)  --俱乐部桌开桌通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCTableCloseNotify_CMD ,MsgCenter.OnClubCTableCloseNotify)  --俱乐部桌关桌通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCTableInfoNotify_CMD ,MsgCenter.OnClubCTableInfoNotify)  --俱乐部桌信息改变通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCCloseNotify_CMD ,MsgCenter.OnClubCCloseNotify)  --俱乐部关闭通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCServerMaintenanceNotify_CMD ,MsgCenter.OnClubCServerMaintenanceNotify)  --维护信息通知
    Base.RegFunc(CMD_Center.Main_CMD ,CMD_Center.ClubCServerGroupNotify_CMD ,MsgCenter.OnClubCServerGroupNotify)  --中心服分组数据通知
     
 

    --前端请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSLogOnReq_CMD,MsgClient.OnClubSLogOnReq)--登陆请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSSwitchReq_CMD,MsgClient.OnClubSSwitchReq)--切换俱乐部请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetUserClubListReq_CMD,MsgClient.OnClubSGetUserClubListReq)--获取玩家的俱乐部列表请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSCreateReq_CMD,MsgClient.OnClubSCreateReq)--创建俱乐部请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSSearchReq_CMD,MsgClient.OnClubSSearchReq)--搜索俱乐部请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSApplyReq_CMD,MsgClient.OnClubSApplyReq)--申请加入俱乐部请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSChangeInfoReq_CMD,MsgClient.OnClubSChangeInfoReq)--修改俱乐部信息请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSMembersReq_CMD,MsgClient.OnClubSMembersReq)--俱乐部成员请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSSearchMemberReq_CMD,MsgClient.OnClubSSearchMemberReq)--搜索俱乐部成员请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSOperateReq_CMD,MsgClient.OnClubSOperateReq)--管理员操作请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSTransferClubGoldReq_CMD,MsgClient.OnClubSTransferClubGoldReq)--个人俱乐部币增加退还请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSTransferRecordReq_CMD,MsgClient.OnClubSTransferRecordReq)--个人俱乐部币流水记录请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSPaiJuRecordReq_CMD,MsgClient.OnClubSPaiJuRecordReq)--俱乐部个人历史牌局请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSContribRecordReq_CMD,MsgClient.OnClubSContribRecordReq)--俱乐部个人贡献请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSBlacklistReq_CMD,MsgClient.OnClubSBlacklistReq)--俱乐部黑名单请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSBlacklistMgrReq_CMD,MsgClient.OnClubSBlacklistMgrReq)--黑名单管理操作请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSBlacklistSearchReq_CMD,MsgClient.OnClubSBlacklistSearchReq)--黑名单玩家搜索请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSTableRecordReq_CMD,MsgClient.OnClubSTableRecordReq)--俱乐部牌桌记录请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSTableUserReq_CMD,MsgClient.OnClubSTableUserReq)--俱乐部牌桌参与玩家请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSMemberInfoReq_CMD,MsgClient.OnClubSMemberInfoReq)--俱乐部成员信息请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSAdminListReq_CMD,MsgClient.OnClubSAdminListReq)--俱乐部管理员列表请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSAdminMgrReq_CMD,MsgClient.OnClubSAdminMgrReq)--俱乐部增加删除管理员请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSChangeAdminPowerReq_CMD,MsgClient.OnClubSChangeAdminPowerReq)--修改管理员权限请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGoldChangeRecordReq_CMD,MsgClient.OnClubSGoldChangeRecordReq)--俱乐部账户的俱乐部币流水请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSApplyListReq_CMD,MsgClient.OnClubSApplyListReq)--俱乐部申请列表请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSApplyHandleReq_CMD,MsgClient.OnClubSApplyHandleReq)--俱乐部申请处理请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSInviteUserReq_CMD,MsgClient.OnClubSInviteUserReq)--邀请用户请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSSearchUserReq_CMD,MsgClient.OnClubSSearchUserReq)--搜索用户请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetGameParamsReq_CMD,MsgClient.OnClubSGetGameParamsReq)--获取后台配置请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSOpenTableReq_CMD,MsgClient.OnClubSOpenTableReq)--俱乐部开桌请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSCloseTableReq_CMD,MsgClient.OnClubSCloseTableReq)--俱乐部关桌请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTableListReq_CMD,MsgClient.OnClubSGetTableListReq)--俱乐部牌桌列表请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSPaiPuReq_CMD,MsgClient.OnClubSPaiPuReq)--牌谱请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSOpratePaiPuReq_CMD,MsgClient.OnClubSOpratePaiPuReq)--操作牌谱请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSUserNoticeReq_CMD,MsgClient.OnClubSUserNoticeReq)--个人通知请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSUserNoticeHandleReq_CMD,MsgClient.OnClubSUserNoticeHandleReq)--处理个人通知请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetApplyListReq_CMD,MsgClient.OnClubSGetApplyListReq)--玩家俱乐部币申请记录请求（玩家个人）
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSUserApplyOpReq_CMD,MsgClient.OnClubSUserApplyOpReq)--玩家申请处理请求（玩家个人）
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSUserInfoReq_CMD,MsgClient.OnClubSUserInfoReq)--玩家个人信息请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSChangeUserInfoReq_CMD,MsgClient.OnClubSChangeUserInfoReq)--修改玩家个人信息请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSChangeLoginPassWardReq_CMD,MsgClient.OnClubSChangeLoginPassWardReq)--修改登录密码请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSPlaybackDataReq_CMD,MsgClient.OnClubSPlaybackDataReq)--回放数据请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSUserRedDotReq_CMD,MsgClient.OnClubSUserRedDotReq)--玩家红点数据请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTablePaiJuIdReq_CMD,MsgClient.OnClubSGetTablePaiJuIdReq)--获取牌桌的牌局id请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSSetSafePassWardOpenReq_CMD,MsgClient.OnClubSSetSafePassWardOpenReq)--设置安全密码开启关闭请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetClubConfigReq_CMD,MsgClient.OnClubSGetClubConfigReq)--获取俱乐部相关配置请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSSendCodeReq_CMD,MsgClient.OnClubSSendCodeReq)--发送短信验证码请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSCodeCheckReq_CMD,MsgClient.OnClubSCodeCheckReq)--短信验证码校验请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSSafePassWardCheckReq_CMD,MsgClient.OnClubSSafePassWardCheckReq)--安全密码校验请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSNeedCheckSafePassWardReq_CMD,MsgClient.OnClubSNeedCheckSafePassWardReq)--是否需要安全码校验请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSInputRedeemCodeReq_CMD,MsgClient.ClubSInputRedeemCodeReq)--输入兑换码请求
	Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetPersonTableRecordReq_CMD,MsgClient.OnClubSGetPersonTableRecordReq)--获取玩家个人牌桌记录请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTableDetailReq_CMD,MsgClient.OnClubSGetTableDetailReq)--获取牌桌详细记录请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTablePaiPuReq_CMD,MsgClient.OnClubSGetTablePaiPuReq)--获取牌桌牌谱请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTableInsuranceReq_CMD,MsgClient.OnClubSGetTableInsuranceReq)--获取牌桌保险明细请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTableUserListReq_CMD,MsgClient.OnClubSGetTableUserListReq)--获取牌桌玩家列表请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetPersonTableRecord2Req_CMD,MsgClient.OnClubSGetPersonTableRecord2Req)--获取玩家个人牌桌记录2请求(大厅永久牌桌)
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTableDetail2Req_CMD,MsgClient.OnClubSGetTableDetail2Req)--获取牌桌详细记录2请求(大厅永久牌桌)
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTableUserList2Req_CMD,MsgClient.OnClubSGetTableUserList2Req)--获取牌桌玩家列表2请求(大厅永久牌桌)
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTablePaiPu2Req_CMD,MsgClient.OnClubSGetTablePaiPu2Req)--获取牌桌牌谱2请求(大厅永久牌桌)
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetTableInsurance2Req_CMD,MsgClient.OnClubSGetTableInsurance2Req)--获取牌桌保险明细2请求(大厅永久牌桌)
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetPaijuDetailReq_CMD,MsgClient.OnClubSGetPaijuDetailReq)--牌局明细查询请求(大厅:抢庄牛)

    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSAdvertiseMentGoldRep_CMD,MsgClient.OnClubSAdvertiseMentGoldRep)--俱乐部广告奖励金请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSUserMWStringReq_CMD,MsgClient.OnClubSUserMWStringReq)--明文密码请求
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubsFileConfigReq_CMD,MsgClient.OnClubsFileConfigReq)--前端用文件编码请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubTransferWayReq_CMD,MsgClient.OnClubTransferWayReq)--转账方式请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubRechargeWithdrawalReq_CMD,MsgClient.OnClubRechargeWithdrawalReq)--充值提现请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubRechargeWithdrawalV2Req_CMD,MsgClient.OnClubRechargeWithdrawalV2Req)--充值提现请求2
    -- Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubActivityInfoReq_CMD,MsgClient.OnClubActivityInfoReq) --活动信息请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubBindReq_CMD,MsgClient.OnClubBindReq)                   --绑定手机或邮箱请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSignInfoReq_CMD,MsgClient.OnClubSignInfoReq)           --签到界面信息 请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSignReq_CMD,MsgClient.OnClubSignReq)                   --签到 请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubGetBindAwardReq_CMD,MsgClient.OnClubGetBindAwardReq)   --领取绑定奖励 请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubGetValueByKeyReq_CMD,MsgClient.OnGetValueByKeyReq)--根据key获取value请求

    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubActivityListReq_CMD,MsgClient.OnClubActivityListReq)--获取活动列表请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSumUserCountReq_CMD,MsgClient.OnClubSumUserCountReq)--获取用户总数请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSGetPersonTableStaticReq_CMD,MsgClient.OnClubSGetPersonTableStaticReq)--获取大厅统计信息(大厅永久牌桌)
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSGetConfigReq_CMD,MsgClient.OnClubSGetConfigReq)--获取配置信息
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSGetGoldHistoryReq_CMD,MsgClient.OnClubSGetGoldHistoryReq)--获取玩家账变信息
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSGetGameGoldHistoryReq_CMD,MsgClient.OnClubSGetGameGoldHistoryReq)--局内消耗
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSGetGameGoldDetailReq_CMD,MsgClient.OnClubSGetGameGoldDetailReq)--局内消耗详情
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSHashListReq_CMD,MsgClient.OnClubSHashListReq)--可存证hash请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSHashCardReq_CMD,MsgClient.OnClubSHashCardReq)--Hash指定局牌序列请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSOnlineUserReq_CMD,MsgClient.OnClubSOnlineUserReq)--在线用户请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSInvitePlayGameReq_CMD,MsgClient.OnClubSInvitePlayGameReq)--邀请玩家进入牌局请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSInvitedPlayGameReq_CMD,MsgClient.OnClubSInvitedPlayGameReq)--收到邀请回复
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSGoldTransToUserReq_CMD,MsgClient.OnClubSGoldTransToUserReq)--内部转币
    -- Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSTableModuleSaveReq_CMD,MsgClient.OnClubSTableModuleSaveReq)--牌桌模板保存/修改
    -- Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSTableModuleListReq_CMD,MsgClient.OnClubSTableModuleListReq)--牌桌模板列表
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSMarkUserReq_CMD,MsgClient.OnClubSMarkUserReq)--标记玩家请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSLookCardReq_CMD,MsgClient.OnClubSLookCardReq)--看牌操作
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSTablePassReq_CMD,MsgClient.OnClubSTablePassReq)--验证密码
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubSGetBillRecordReq_CMD,MsgClient.OnClubSGetBillRecordReq)--获取充提账单

    --网关通知
    Base.RegFunc(ProtoManager.GatewayPro.GATEWAY,ProtoManager.Sub_GateWay.SUB_GATEWAY_CLIENT_CLOSE,MsgClient.OnClose)--断线通知
    Base.RegFunc(ProtoManager.GatewayPro.GATEWAY,ProtoManager.Sub_GateWay.SUB_REQ_GAMESRV_SWICTHCONN,MsgClient.OnSwicthConn)--切换连接通知

    --后台
    Base.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.ChangeUserInfoNotify_CMD, MsgWeb.OnWebChangeUserInfoNotify) --后台个人信息刷新通知
    Base.RegFunc(ProtoManager.Sub_LobbyGame.SYSLOBBY_GAME, ProtoManager.Sub_LobbyGame.SUB_GAME_KICK_USER, MsgWeb.OnWebKickOut)  --后台踢人通知
    Base.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.WithDrawGoldNotify_CMD, MsgClient.OnWithDrawGoldNotify) --后台用户提现通知
    -- Base.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.VerifyNotify_CMD, MsgClient.OnVerifyNotify) --后台审核通知
    Base.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.GloBalConfigNotice_CMD, MsgClient.OnVerifyNotify) --全局配置变更
    Base.RegFunc(ProtoManager.Sub_LobbyGame.SYSLOBBY_GAME, ProtoManager.Sub_LobbyGame.SUB_CLUB_RECHARGE, UserOnTime.OnUserRecharge)  --玩家充值

    --Web服返回
    Base.RegFunc(CMD_Web.Main_CMD, CMD_Web.WebUrlRsp_CMD, MsgClient.OnWebNotify) --web服通知
    
    --DB服返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubUserLogonRsp_CMD,MsgClient.OnDBClubUserLogonRsp)--玩家登录俱乐部 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.GetUserClubListRsp_CMD,MsgClient.OnDBGetUserClubListRsp)--玩家俱乐部列表 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.CreateClubRsp_CMD,MsgClient.OnDBCreateClubRsp)       --创建俱乐部 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.SearchClubRsp_CMD,MsgClient.OnDBSearchClubRsp)--搜索俱乐部 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ApplyJoinClubRsp_CMD,MsgClient.OnDBApplyJoinClubRsp)--申请加入俱乐部 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ChangeClubInfoRsp_CMD,MsgClient.OnDBChangeClubInfoRsp)--修改俱乐部信息 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubMembersRsp_CMD,MsgClient.OnDBClubMembersRsp)--俱乐部成员 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.SearchClubMemberRsp_CMD,MsgClient.OnDBSearchClubMemberRsp)--搜索俱乐部成员 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubAdminOperateRsp_CMD,MsgClient.OnDBClubAdminOperateRsp)--管理员操作 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.TransferClubGoldRsp_CMD,MsgClient.OnDBTransferClubGoldRsp)--个人俱乐部币增加退还
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.TransferRecordRsp_CMD,MsgClient.OnDBTransferRecordRsp)--个人俱乐部币流水记录 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubPaiJuRecordRsp_CMD,MsgClient.OnDBClubPaiJuRecordRsp)--俱乐部个人历史牌局 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubContribRecordRsp_CMD,MsgClient.OnDBClubContribRecordRsp)--俱乐部个人贡献(俱乐部收益) 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubBlacklistRsp_CMD,MsgClient.OnDBClubBlacklistRsp)--俱乐部黑名单 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubBlacklistMgrRsp_CMD,MsgClient.OnDBClubBlacklistMgrRsp)--黑名单管理操作 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubBlacklistSearchRsp_CMD,MsgClient.OnDBClubBlacklistSearchRsp)--黑名单玩家搜索 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubTableRecordRsp_CMD,MsgClient.OnDBClubTableRecordRsp)--俱乐部牌桌记录 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubTableUserRsp_CMD,MsgClient.OnDBClubTableUserRsp)--俱乐部牌桌参与玩家 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubMemberInfoRsp_CMD,MsgClient.OnDBClubMemberInfoRsp)--俱乐部成员信息 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubAdminListRsp_CMD,MsgClient.OnDBClubAdminListRsp)--俱乐部管理员列表 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubAdminMgrRsp_CMD,MsgClient.OnDBClubAdminMgrRsp)--俱乐部增加删除管理员 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubChangeAdminPowerRsp_CMD,MsgClient.OnDBClubChangeAdminPowerRsp)--修改管理员权限 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGoldChangeRecordRsp_CMD,MsgClient.OnDBClubGoldChangeRecordRsp)--俱乐部账户的俱乐部币流水 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubApplyListRsp_CMD,MsgClient.OnDBClubApplyListRsp)--俱乐部申请列表 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubApplyHandleRsp_CMD,MsgClient.OnDBClubApplyHandleRsp)--俱乐部申请处理 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubInviteUserRsp_CMD,MsgClient.OnDBClubInviteUserRsp)--邀请用户 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubSearchUserRsp_CMD,MsgClient.OnDBClubSearchUserRsp)--搜索用户 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubApplyInfoRsp_CMD,MsgClient.OnDBClubApplyInfoRsp)--俱乐部某条申请的信息 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubPaiPuResp_CMD,MsgClient.OnDBClubPaiPuResp)--牌谱返回 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubOpratePaiPuResp_CMD,MsgClient.OnDBClubOpratePaiPuResp)--操作牌谱返回 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubUserNoticeRsp_CMD,MsgClient.OnDBClubUserNoticeRsp)--玩家个人通知 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubUserNoticeHandleRsp_CMD,MsgClient.OnDBClubUserNoticeHandleRsp)--处理个人通知 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetUserNoticeInfoRsp_CMD,MsgClient.OnDBClubGetUserNoticeInfoRsp)--获取某条个人通知信息 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetApplyListRsp_CMD,MsgClient.OnDBClubGetApplyListRsp)--玩家俱乐部币申请记录（玩家个人） 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubUserApplyOpRsp_CMD,MsgClient.OnDBClubUserApplyOpRsp)--玩家申请处理 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubUserInfoRsp_CMD,MsgClient.OnDBClubUserInfoRsp)--玩家个人信息 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubChangeUserInfoRsp_CMD,MsgClient.OnDBClubChangeUserInfoRsp)--修改玩家个人信息 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubChangeLoginPassWardRsp_CMD,MsgClient.OnDBClubChangeLoginPassWardRsp)--修改登录密码 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubPlaybackDataRsp_CMD,MsgClient.OnDBClubPlaybackDataRsp)--回放数据 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubUserRedDotRsp_CMD,MsgClient.OnDBClubUserRedDotRsp)--玩家红点数据 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetTablePaiJuIdResp_CMD,MsgClient.OnDBClubGetTablePaiJuIdResp)--获取牌桌的牌局id 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetPersonTableRecordRsp_CMD,MsgClient.OnDBClubGetPersonTableRecordRsp)--获取玩家个人牌桌记录 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetTableDetailRsp_CMD,MsgClient.OnDBClubGetTableDetailRsp)--获取牌桌详细记录 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetTablePaiPuRsp_CMD,MsgClient.OnDBClubGetTablePaiPuRsp)--获取牌桌牌谱 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetTableInsuranceRsp_CMD,MsgClient.OnDBClubGetTableInsuranceRsp)--获取牌桌保险明细 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetTableUserListRsp_CMD,MsgClient.OnDBClubGetTableUserListRsp)--获取牌桌玩家列表 返回

    Base.RegFunc(CMD_DbClubServer.Main_CMD ,CMD_DbClubServer.ClubGetPersonTableRecord2Rsp_CMD,MsgClient.OnDBClubGetPersonTableRecord2Rsp)--获取玩家个人牌桌记录2请求(大厅永久牌桌)
    Base.RegFunc(CMD_DbClubServer.Main_CMD ,CMD_DbClubServer.ClubGetTableDetail2Rsp_CMD,MsgClient.OnDBClubGetTableDetail2Rsp)--获取牌桌详细记录2请求(大厅永久牌桌)
    Base.RegFunc(CMD_DbClubServer.Main_CMD ,CMD_DbClubServer.ClubGetTableUserList2Rsp_CMD,MsgClient.OnDBClubGetTableUserList2Rsp)--获取牌桌玩家列表2请求(大厅永久牌桌)
    Base.RegFunc(CMD_DbClubServer.Main_CMD ,CMD_DbClubServer.ClubGetTablePaiPu2Rsp_CMD,MsgClient.OnDBClubGetTablePaiPu2Rsp)--获取牌桌牌谱2请求(大厅永久牌桌)
    Base.RegFunc(CMD_DbClubServer.Main_CMD ,CMD_DbClubServer.ClubGetTableInsurance2Rsp_CMD,MsgClient.OnDBClubGetTableInsurance2Rsp)--获取牌桌保险明细2请求(大厅永久牌桌)
    Base.RegFunc(CMD_DbClubServer.Main_CMD ,CMD_DbClubServer.ClubGetPaijuDetailRsp_CMD,MsgClient.OnDBClubGetPaijuDetailRsp)--获取牌局明细查询返回(抢庄牛)


    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.LoadStoreConfigRep_CMD,Store.OnDBLoadStoreConfigRep)  --商城配置返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.PayOrder_CreateRep_CMD,Store.OnDBPayOrder_CreateRep)  --创建订单返回 
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.PayOrder_DealRep_CMD,Store.OnDBPayOrder_DealRep)  --处理订单返回 
    Base.RegFunc(CMD_DbClubServer.Main_CMD ,CMD_DbClubServer.ClubGetPayOrderRep_CMD,Store.OnDBClubGetPayOrderRep)-- 充值账单查询返回

    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSGetStoreCfgReq_CMD,Store.OnClubSGetStoreCfgReq)    --请求商城配置  
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSBuyGoodsReq_CMD,Store.OnClubSBuyGoodsReq)          --请求购买商品
    
    Base.RegFunc(CMD_Slave.Main_CMD ,CMD_Slave.ClubSPayInfoReq_CMD,Store.OnClubSPayInfoReq)             --请求充值信息

    Base.RegFunc(CMD_Backstage.Main_CMD ,CMD_Backstage.StorePayReq_CMD,Store.OnWebRepPayResult)        --后台通知支付结果
    Base.RegFunc(CMD_Backstage.Main_CMD ,CMD_Backstage.StoreConfigNotify_CMD,Store.OnWebLoadConfig)    --后台通知加载配置
    
	Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubSetSafePassWardOpenRsp_CMD,MsgClient.OnDBClubSetSafePassWardOpenRsp)--设置安全密码开启关闭 返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubInputRedeemCodeRsp_CMD,MsgClient.OnDBClubInputRedeemCodeRsp)--输入兑换码 返回

    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubAddiInfoChangeRsp_CMD,MsgClient.OnDBClubAddiInfoChangeRsp)--明文密码 返回

    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubSearchSecuPwdRsp_CMD,MsgClient.OnDBClubCSearchSecuPwdRsp)--安全密码校验 返回

    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubNotifyRecordRsp_CMD,MsgClient.OnDBClubNotifyRecordRsp)--后台审核通知 返回

    -- Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetActiInfoRsp_CMD,MsgClient.OnDBClubActivityInfoRsp)--活动信息返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetActivityListRsp_CMD,MsgClient.OnClubGetActivityListRsp)  --获取活动列表 返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetPersonTableStaticRsp_CMD,MsgClient.OnClubGetPersonTableStaticRsp) --获取大厅统计信息 返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetGoldHistoryRsp_CMD,MsgClient.OnClubSGetGoldHistoryRsp) --获取玩家账变信息 返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetGameGoldRsp_CMD,MsgClient.OnClubGetGameGoldRsp) --局内消耗 返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetGameGoldDetailRsp_CMD,MsgClient.OnClubGetGameGoldDetailRsp) --局内消耗详情 返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetHashListRsp_CMD,MsgClient.OnClubGetHashListRsp) --可存证hash请求 返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetHashCardRsp_CMD,MsgClient.OnClubGetHashCardRsp) --可存证hash请求 返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGoldTransUserRsp_CMD,MsgClient.OnClubGoldTransUserRsp) --内部转币 返回
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubTableModuleSaveRsp_CMD,MsgClient.OnClubTableModuleSaveRsp) --牌桌模板保存回复
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetTableModuleListRsp_CMD,MsgClient.OnClubGetTableModuleListRsp) --牌桌模板列表回复
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubMarkUserRsp_CMD,MsgClient.OnClubMarkUserRsp) --标记玩家请求回复
    Base.RegFunc(CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1.ClubGetBillRecordRsp_CMD,MsgClient.OnClubGetBillRecordRsp) --获取充提账单
    
    
    Base.RegFunc(CMD_DbServer1.Main_CMD,CMD_DbServer1.DbBindRsp_CMD,MsgClient.OnDbBindRsp)                  --手机邮箱绑定 返回
    Base.RegFunc(CMD_DbServer1.Main_CMD,CMD_DbServer1.DbSignInfoRsp_CMD,MsgClient.OnDbSignInfoRsp)          --签到界面信息 返回
    Base.RegFunc(CMD_DbServer1.Main_CMD,CMD_DbServer1.DbSignRsp_CMD,MsgClient.OnDbSignRsp)                  --签到 返回
    Base.RegFunc(CMD_DbServer1.Main_CMD,CMD_DbServer1.DbGetBindAwardRsp_CMD,MsgClient.OnDbGetBindAwardRsp)  --领取绑定奖励 返回
    
end


return ClientSink