package.path            = require("./lua/Lobby/Head").path
-- local pay               = require("Pay")
local m                 = require("base")         -- 基础功能接口
local api               = require("publicApi")    -- 共用功能接口
local tname             = require("typename")     -- 类弄定义接口
local dbInfo            = require("DBInfo")       -- 数据库连接信息
local ProtoMgr          = require("ProtoManager") -- 协议管理对象
local tlogging          = require("logging")      -- 日志等级接口
local mlogger           = require("logger")       -- 日志对象
local tLogin            = require("LoginServer")  -- 登录大厅服
local tLogout           = require("Logout")       -- 玩家断开
local tGame             = require("GameLogic")    -- 道具配置
local cjson             = require("cjson")        -- json
local tConfig           = require("GameConfig")   --
local tWhiteList        = require("WhiteList")
local tGameVersion      = require("GameVersion")
local tPubUserApi       = require("PublicUserInfo") --玩家数据
local tReforwardRule    = require("ReforwardRule")
local tLiveCSRelation   = require("LiveCSRelation")
local PublicGameScence  = require("PublicGameScence")
local PublicLiveAutoBet = require("PublicLiveAutoBet")
local tPay              = require("Pay")
-- local luaKafka          = require("kafka")  --使用lua-kafka
-- local effil             = require("effil")
local tMsgHandle         = require("MsgHandle")
local DbServer_pb       = ProtoMgr.DbServer_pb
local DbServer1_pb      = ProtoMgr.DbServer1_pb

-- 玩家功能回调
local ClientSink        = { LevelLog = nil }

ClientSink.m_ClientList = {} -- 保存每个玩家的信息的链表

ClientSink.m_Servers    = {} -- 内网服务器表列，保存服务器与对应用户的关系，方便其它处理


function ClientSink:new(table)
    local t = table or {}
    self.__index = self
    setmetatable(t, self)
    return t
end


function onKafkaMsg(msg)
    m.Log("[Lua] onKafkaMsg topic="..msg.topic)
    tPay:Topic(msg.topic, msg.value)
end


-- 消息处理函数
-- function ProcessKafkaMessage(message)
--     m.Log("[Lua] processKafkaMessage")
--     local transfer, err = cjson.decode(message.value)
--     if not transfer then
--         m.Log("[Lua] ProcessKafkaMessage transfer is nil")
--         return
--     end

--     -- 充值告知消息
--     --print(string.format("topic=%s partition=%d offset=%d value=%s",message.topic, message.partition, message.offset, message.value))
--     tGame.CallAccountPayInfoReq(transfer)
-- end


-- function StartLuaKafka()
--     m.Log("[Lua] StartLuaKafka enter")

--     -- 创建一个 channel 用来线程间通信
--     local channel = effil.channel(100)

--     -- 子线程函数：Kafka 消费者
--     local consumer_thread = effil.thread(function(channel)
--         local settings = {
--                         ["bootstrap.servers"] = "18.139.123.249:9092", 
--                         ["group.id"] = "my_lua_group_lobby_1",
--                         ["auto.offset.reset"] = "latest",
--                         ["enable.partition.eof"] = "true"
--                     }
                        
--         local consumer = luaKafka.consumer(settings)
--         consumer:subscribe(tPay.TopupTopic)

--         while true do
--             local msg = consumer:poll(1000)  -- 1秒超时
--             if msg then
--                 if not msg.error then
--                     -- 把消息推送到 channel
--                     --channel:push(msg)
--                     ProcessKafkaMessage(msg)
--                     m.Log("[Lua] enter ProcessKafkaMessage")
--                 else
--                     --channel:push("Kafka错误: " .. msg.error)
--                     m.Log("msg.error = %s", msg.error)
--                 end
--             end
--         end
--     end)

--     -- 启动子线程
--     consumer_thread(channel)
--     m.Log("[Lua] StartLuaKafka out")
-- end


function StartKafka()
    m.Log("[Lua] StartKafka enter")
    local group = "my_lua_group_lobby_1" 
    local ok, err = Kafka.init {
        brokers = tPay.cfg.kafkaIP,   -- Kafka 集群地址(逗号分隔也可)
        group   = group,              -- 消费组
        topics  = { tPay.TopupTopic }, -- 订阅topic(可多个)这个充值topic
        config  = { ["auto.offset.reset"] = "latest" }  --earliest
    }
    if not ok then
        m.Log("[Lua] Kafka.init FAILED: " .. tostring(err))
        return
    end
    m.Log("[Lua] Kafka.init OK, group=" .. group)
    -- local h = function(msg)
    --     -- m.Log(("[Kafka cb] topic=%s partition=%d offset=%d len=%d value=%s"):format(
    --     --     msg.topic, msg.partition, msg.offset, #msg.value, msg.value
    --     -- ))
        
    -- end

    -- 注册请求付款消息
    tPay:registerOrderCb(tGame.CallAccountPayInfoReq)  
    -- 注册生成者
    -- Kafka.registerConsumerCb(h)
    -- 启动后台轮询线程
    local ok2, err2 = pcall(Kafka.start)
    if not ok2 then
        m.Log("[Lua] Kafka.start FAILED: " .. tostring(err2))
        return
    end
    m.Log("[Lua] Kafka.start OK (waiting for new messages...)")
end

-- 启动服务器
function ClientSink.OnStart()
    -- 设置日志目录：
    local sLogDir = dbInfo.LogDir .. "Lobby/" .. m.GetPort() .. "-" .. m.GetThreadIndex()
    mlogger.SetFile(sLogDir, "Lobby", m)

    -- 设置全局等级
    mlogger:setLevel(tlogging.DEFAULT, "Lobby")
    -- 消息接收处理，不用默认函数
    m.m_MyMonitorFun = nil -- ClientSink.onMsgRecv
    -- 注册服务器
    m.RegServer(tname.lobby)
    -- 注册协议
    ClientSink.Protocol()
    m.Log(" Lobby Server Start ")
    -- start kafka
    StartKafka()
    -- StartLuaKafka()

    -- 单独线程处理提现消息
    --tGame.initWithdraw()
    
    local temFunc = function()
        tConfig.Req_AllDbConfig(0)
        tGameVersion.RequestGameVersion()
        tLiveCSRelation.ReqDbLiveCSRelation()
    end

    m.SetTimer(60000, 1000 * 3, 1, temFunc)       --加载配置
    m.SetTimer(60001, 1000 * 60 * 1, -1, temFunc) --每2分钟,重新加载一次配置(改了数据库可以不用重启)
    m.SetTimer(60003, 1000 * 10, -1, tWhiteList.OnTimerGetWhiteList)

    m.SetTimer(60004, 1000 * 6, 1, tReforwardRule.onTimerRefowardRuleReq)       --转发规则
    m.SetTimer(60005, 1000 * 60 * 1, -1, tReforwardRule.onTimerRefowardRuleReq) --转发规则
    m.SetTimer(60006, 1000 * 10, -1, tReforwardRule.OnTimerGetServerIdOfBan)    --服务器id维护列表读取
    m.SetTimer(60007, 1000 * 10, 1, PublicLiveAutoBet._ReBoostLoadUserInfo)
    --m.SetTimer(60008, 1000 * 1, -1, tGame.UpdateWithdrawalProcessor)
end



-- 停止服务器
function ClientSink.OnStop()
    -- 取消本地服务器
    m.UnRegServer()
    m.Log(" Lobby Server OnStop ")
end

-- 有新用户连接
function ClientSink.OnAccept(ClientID, ip, port)
    m.Log(" Lobby有新用户连接 Client:%d,  ip:%s, port:%d", ClientID, ip, port)
    -- 创建用户信息
    local clientinfo = {}
    clientinfo.ClientID = ClientID

    local sIp = api.Dword2String(ip)
    m.Log(" ----------- OnAccept (将IP dword 转换 string) sIp = " .. sIp)

    clientinfo.ip = sIp
    clientinfo.port = port

    -- 将信息加入链表
    ClientSink.m_ClientList[ClientID] = clientinfo
end

-- 关闭连接
function ClientSink.OnClose(ClientID)
    -- 删除用户信息
    ClientSink.m_ClientList[ClientID] = nil
end

function GetHandleFunction(moduleName, sFuncName)
    local func = function(...)
        moduleName[sFuncName](...)
    end
    return func
end

-- 注册协议
function ClientSink.Protocol()
    local tPubProto = ProtoMgr.LobbyPro               -- 协议

    local tPubProto = ProtoMgr.Lobby_pb.Lobby_Proto()       -- 大厅协议
    local CMD_Slave = ProtoMgr.ClubSlave_pb.ClubS_Proto()   -- 俱乐部

    --玩家断开连接SUB_REQ_ENTER_GAME
    m.RegFunc(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_GATEWAY_CLIENT_CLOSE,
        GetHandleFunction(ClientSink, "OnGateClose"))
    m.RegFunc(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_REQ_GAMESRV_SWICTHCONN,
        GetHandleFunction(tGame, "OnSwicthConn")) --连接切换通知

    --前端请求处理
    m.RegFunc(tPubProto.Main_CMD, tPubProto.LogonReq_CMD, GetHandleFunction(tGame, "OnLogonReq"))                       --登陆请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.RoomListReq_CMD, GetHandleFunction(tGame, "OnRoomListReq"))                 --房间列表请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.TreasureReq_CMD, GetHandleFunction(tGame, "OnTreasureReq"))                 --财富请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.EnterBankReq_CMD, GetHandleFunction(tGame, "OnEnterBankReq"))               --进入银行请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.BankUnlockReq_CMD, GetHandleFunction(tGame, "OnBankUnlockReq"))             --解锁银行请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.BankAccessReq_CMD, GetHandleFunction(tGame, "OnBankAccessReq"))             --银行金币存取请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.BankPasswordChangeReq_CMD,
        GetHandleFunction(tGame, "OnBankPasswordChangeReq"))                                                            --银行密码更改请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.BankAccessDetailReq_CMD, GetHandleFunction(tGame, "OnBankAccessDetailReq")) --银行存取明细请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.PaijuRecordReq_CMD, GetHandleFunction(tGame, "OnPaijuRecordReq"))           --战绩查询请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.BeforeLoadScenceReq_CMD, GetHandleFunction(tGame, "OnBeforeLoadScenceReq")) --进入游戏时 预查询
    m.RegFunc(tPubProto.Main_CMD, tPubProto.PaijuDetailReq_CMD, GetHandleFunction(tGame, "OnPaijuDetailReq"))           --牌局明细查询请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.HelpInfoReq_CMD, GetHandleFunction(tGame, "OnHelpInfoReq"))                 --帮助列表请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.OnlinePeopleReq_CMD, GetHandleFunction(tGame, "OnlinePeopleReq"))           --在线人数列表请求

    m.RegFunc(tPubProto.Main_CMD, tPubProto.SUB_REQ_GET_USER_INFO, tGame.Get_User_GroupId)                              --请求玩家信息
    m.RegFunc(tPubProto.Main_CMD, tPubProto.SUB_REQ_GET_ZBTABLEID, tGame.Get_ZBTableID)

    m.RegFunc(tPubProto.Main_CMD, tPubProto.LobbyDeZhouRecordReq_CMD, GetHandleFunction(tGame, 'LobbyDeZhouRecordReq'))   --德州最近牌局记录查询 请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.LobbyDeZhouRecordDetailReq_CMD,
        GetHandleFunction(tGame, 'LobbyDeZhouRecordDetailReq'))                                                           --德州牌局记录详情查询 请求

    m.RegFunc(tPubProto.Main_CMD, tPubProto.BrLiveGameRecordReq_CMD, GetHandleFunction(tGame, 'BrLiveGameRecordReq'))     --百人直播游戏战绩 请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.BrLiveGameDetailReq_CMD, GetHandleFunction(tGame, 'BrLiveGameDetailReq'))     --百人直播游戏记录详情 请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.BlockChianListInfoReq_CMD, GetHandleFunction(tGame, 'BlockChianListInfoReq')) --区块链列表信息请求 请求

    m.RegFunc(tPubProto.Main_CMD, tPubProto.AccountCloseReq_CMD, GetHandleFunction(tGame, 'AccountCloseReq'))             --账号注销
    
    
    --转账相关
    m.RegFunc(tPubProto.Main_CMD, tPubProto.AccountPayURLReq_CMD, GetHandleFunction(tGame, 'AccountPayURLReq'))                 --请求URL
    m.RegFunc(tPubProto.Main_CMD, tPubProto.AccountPayInfoReq_CMD, GetHandleFunction(tGame, 'AccountPayInfoReq'))               --请求付款
    m.RegFunc(tPubProto.Main_CMD, tPubProto.AccountWithdrawalReq_CMD, GetHandleFunction(tGame, 'AccountWithdrawalReq'))         --请求提现
    m.RegFunc(tPubProto.Main_CMD, tPubProto.AccountWithdrawalViewReq_CMD, GetHandleFunction(tGame, 'AccountWithdrawalViewReq')) --请求界面信息

    -- 大厅各种消息处理的函数
    m.RegFunc(tPubProto.Main_CMD, tPubProto.ClubSUserNoticeReq_CMD, GetHandleFunction(tMsgHandle, "OnClubSUserNoticeReq"))          --玩家个人通知 请求
    m.RegFunc(tPubProto.Main_CMD, tPubProto.ClubSUserNoticeHandleReq_CMD,GetHandleFunction(tMsgHandle,"OnClubSUserNoticeHandleReq"))--处理个人通知请求

    --Db服返回处理
    local dbCmd = DbServer_pb.Db_Proto()
    local dbCmd1 = DbServer1_pb.Db_Proto1()
    m.RegFunc(dbCmd.Main_CMD, dbCmd.DbUserTreasureRsp_CMD, GetHandleFunction(tGame, "OnDbUserTreasureRsp"))             --用户财富返回
    m.RegFunc(dbCmd.Main_CMD, dbCmd.DbCheckSafePasswordRsp_CMD, GetHandleFunction(tGame, "OnDbCheckSafePasswordRsp"))   --银行密码验证结果返回
    m.RegFunc(dbCmd.Main_CMD, dbCmd.DbBankAccessDetailRsp_CMD, GetHandleFunction(tGame, "OnDbBankAccessDetailRsp"))     --银行存取明细返回
    m.RegFunc(dbCmd.Main_CMD, dbCmd.DbBankPasswordChangeRsp_CMD, GetHandleFunction(tGame, "OnDbBankPasswordChangeRsp")) --银行密码修改结果返回
    m.RegFunc(dbCmd.Main_CMD, dbCmd.RecentRecordRsp_CMD, GetHandleFunction(tGame, "OnDbRecentRecordRsp"))               --近期战绩查询返回
    m.RegFunc(dbCmd1.Main_CMD, dbCmd1.RecentDetailRsp_CMD, GetHandleFunction(tGame, "OnDbRecentDetailRsp"))             --近期牌局记录查询返回

    m.RegFunc(dbCmd1.Main_CMD, dbCmd1.DbAccountCloseRsp_CMD, GetHandleFunction(tGame, "OnDbAccountCloseRsp"))           --近期牌局记录查询返回



    m.RegFunc(tPubProto.Main_CMD, tPubProto.SUB_REQ_UPDATE_USERINFO, GetHandleFunction(tLogin, "Update_UserInfo"))
    m.RegFunc(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_UPDATE_USERINFO,
        GetHandleFunction(tLogin, "Send_Update_UserInfo_Result"))

    m.RegFunc(dbCmd1.Main_CMD, dbCmd1.DbLiveRecordRsp_CMD, GetHandleFunction(tGame, 'OnDbLiveRecordRsp'))       --德州db服输赢记录查询 返回
    m.RegFunc(dbCmd1.Main_CMD, dbCmd1.GetResultsBySqlRsp_CMD, GetHandleFunction(tGame, 'OnGetResultsBySqlRsp')) --sql执行结果(牌局明细)

    m.RegFunc(dbCmd.Main_CMD, dbCmd.RefowardRuleRsp_CMD, tReforwardRule.OnRefowardRuleRsp)                      -- db服返回网关转发规则
    m.RegFunc(dbCmd.Main_CMD, dbCmd.ServerIdOfMaitainingRsp_CMD, tReforwardRule.OnServerIdOfMaitainingRsp)      --db服返回 不停机维护，被设为维护的serverid
    m.RegFunc(dbCmd.Main_CMD, dbCmd.DbLiveCSRelationRsp_CMD, tLiveCSRelation.OnDbLiveCSRelationRsp)             --db服返回 不停机维护，被设为维护的serverid

    -- web 踢人删缓存
    m.RegFunc(ProtoMgr.WebPro.WEB, ProtoMgr.Sub_WEB.SUB_REQ_KICK_USER, GetHandleFunction(tLogin, "KickUser"))

    --后台通知
    local CMD_Backstage = ProtoMgr.Backstage_pb.Backstage_Proto()
    m.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.WebUserVipNotify_CMD, GetHandleFunction(tGame, "OnWebUserVipNotify")) --后台通知 玩家VIP身份

    -- 后台服务返回支付消息
    m.RegFunc(dbCmd.Main_CMD, dbCmd.PayInsertClientAddressRsp_CMD, GetHandleFunction(tGame, "OnDBInserClientAddRsp"))  --db返回插入地址消息
    m.RegFunc(dbCmd.Main_CMD, dbCmd.PayUpdateAddressRsp_CMD, GetHandleFunction(tGame, "OnDBUpdateAddrRsp"))            --db返回更新地址信息
    m.RegFunc(dbCmd.Main_CMD, dbCmd.PayInsertPayInfoRsp_CMD, GetHandleFunction(tGame, "OnDBInsertPayInfoRsp"))         --db返回插入支付订单信息
    m.RegFunc(dbCmd.Main_CMD, dbCmd.PayUpdatePayInfoRsp_CMD, GetHandleFunction(tGame, "OnDBUpdatePayInfoRsp"))         --db返回更新支付订单信息
    m.RegFunc(dbCmd.Main_CMD, dbCmd.PayInsertWithdrawInfoRsp_CMD, GetHandleFunction(tGame, "OnDBInsertWithdrawRsp"))   --db返回插入提现信息
    m.RegFunc(dbCmd.Main_CMD, dbCmd.PayGetPayAddressRsp_CMD, GetHandleFunction(tGame, "OnDBGetAddressRsp"))            --db返回获取支付地址信息

    -- 大厅处理DB返回用户的个人消息
    --玩家个人通知 返回
    m.RegFunc(dbCmd.Main_CMD, dbCmd.ClubUserNoticeRsp_CMD, GetHandleFunction(tMsgHandle, "OnDBClubUserNoticeRsp")) 
                                    
    --玩家插入DB消息后，返回到大厅
    m.RegFunc(dbCmd.Main_CMD, dbCmd.LobbyNotifyRecordRsp_CMD, GetHandleFunction(tMsgHandle, "OnLobbyNotifyRecordRsp")) 

    -- 直播游戏场景
    PublicGameScence.ListenGameProto()
end

-- 关闭连接   网关发过来
function ClientSink.OnGateClose(sClientID, Data, len)
    local ReadData = m.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID()

    local Read = ProtoMgr.Gateway_pb.RUQ_User_Line()
    Read:ParseFromString(ReadData:GetString())
    local nUserID = Read.nUserID

    tGame.OnConnectionClose(nUserID, sClientID)

    m.Log("   玩家: %d 断开连接  清除 数据   :%s", nUserID, sClientID)
    if ClientSink.m_ClientList[sClientID] == nil then
        -- m.Log(" 大厅服  玩家断开连接  清除玩家数据   ")
    end
    -- 删除用户信息
    ClientSink.m_ClientList[sClientID] = nil

    tLogout.OnUserLogout(nUserID) -- 清除redis中玩家数据
    tPubUserApi.IncrbyGamingUser(-1, -2, -1, false, -1, nUserID)
end

return ClientSink
