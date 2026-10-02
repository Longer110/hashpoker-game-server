package.path = require("./lua/Logon_s/Head").path

local tBase = require("base") -- 基础功能接口
local api = require("publicApi") -- 共用功能接口
local dbInfo = require("DBInfo") -- 数据库连接信息
local tname = require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tlogging = require("logging") -- 日志等级接口
local mlogger = require("logger") -- 日志对象  
local LogonLink = require("LogonLink")  -- 登录和逻辑
local tGameConfig =require("GameConfig")  
local tMainVersion =require("MainVersion")
local tPubUserApi  = require("PublicUserInfo")    --玩家数据

local tPlatformChannelShopTb = require("PlatformChannelShopTb")  -- 登录和逻辑
local DbCmd =ProtoMgr.DbServer_pb.Db_Proto()
local Db_Proto1 =ProtoMgr.DbServer1_pb.Db_Proto1()

-- 玩家功能回调
ClientSink = { LevelLog = nil }

ClientSink.m_ClientList = {} -- 保存每个玩家的信息的链表

ClientSink.m_Servers = {}   -- 内网服务器表列，保存服务器与对应用户的关系，方便其它处理

function ClientSink:new( table )
    local t =  table or {}
    self.__index = self
    setmetatable(t,self)
    return t
end

-- 启动服务器
function ClientSink.OnStart() 
    
    -- 设置日志目录:
    local sLogDir =  dbInfo.LogDir.."Logon/" .. tBase.GetPort() .. "-" .. tBase.GetThreadIndex()
    mlogger.SetFile( sLogDir , "Logon", tBase )
    
    -- 设置全局等级
    mlogger:setLevel( tlogging.DEFAULT, "Logon" )
    -- 消息接收处理，不用默认函数
    tBase.m_MyMonitorFun = ClientSink.onMsgRecv
    -- 注册服务器
    tBase.RegServer(tname.logon)
    -- 注册协议
    ClientSink.Protocol()  

    --[[
    tBase.SetTimer(20000, 1000*2, 1, tPlatformChannelShopTb.onTimerReqPlatformChannelShopTb)
    tBase.SetTimer(20001, 1000*60*2, -1, tPlatformChannelShopTb.onTimerReqPlatformChannelShopTb)
    ]]
    tBase.Log(" logon Server Start ")  
      
    -- 等级案例
    mlogger:info("Logon Server Start")
    mlogger:debug("debugging...")
    -- mlogger:error("error!")
    local loadConfig=function()
        tGameConfig.Req_AllDbConfig(0) 
        tMainVersion.RequestMainVersion()
    end
    tBase.SetTimer(64501, 1000*6, 1, loadConfig)          --店与组关系表
    tBase.SetTimer(64502, 1000*60*1, -1, loadConfig)      --店与组关系表
 

    
end   

-- 停止服务器
function ClientSink.OnStop()

    -- 取消本地服务器
    tBase.UnRegServer()
    tBase.Log(" logon Server OnStop ") 

end

-- 有新用户连接
function ClientSink.OnAccept(ClientID, ip, port)

    tBase.Log(" logon有新用户连接 Client : %d,  ip = %s , port = %d ", ClientID, ip, port)
    -- 创建用户信息
    local clientinfo = {}
    clientinfo.ClientID = ClientID

    local sIp = api.Dword2String(ip) 
    tBase.Log(" ----------- OnAccept (将IP dword 转换 string) sIp = " .. sIp)

    clientinfo.ip = sIp
    clientinfo.port = port

    -- 将信息加入链表
    ClientSink.m_ClientList[ClientID] = clientinfo

end

-- 关闭连接
function ClientSink.OnClose(ClientID)
   tBase.Log(" 登录服 有用户离开 Client : %d ", ClientID)
    -- 删除用户信息
    if ClientSink.m_ClientList[ClientID] then
        ClientSink.m_ClientList[ClientID] = nil
    end
    
end

-- 注册协议
function ClientSink.Protocol()  


    local tPubProto =  ProtoMgr.LogonPro   -- 协议
    

    tBase.RegFunc(tPubProto.LOGON_MAIN,tPubProto.SUB_REQ_LOGON , LogonLink.RequestData)      -- 账号登录
    tBase.RegFunc(tPubProto.LOGON_MAIN,tPubProto.SUB_REQ_REGISTER , LogonLink.RequestData)       -- 账号注册 
    tBase.RegFunc(ProtoMgr.Sys.DB,ProtoMgr.Sub_DB.SUB_REQ_ACCOUNT_LOGON, LogonLink.DB_Return_Logon)    -- 账号登录
    tBase.RegFunc(ProtoMgr.Sys.DB,ProtoMgr.Sub_DB.SUB_REQ_ACCOUNT_REGISTER, LogonLink.DB_Return_Regist)   -- 账号注册  

    tBase.RegFunc(tPubProto.LOGON_MAIN,tPubProto.CurrentGameQuerryReq_CMD , LogonLink.OnCurrentGameQuerryReq)       --查询玩家当前游戏

    tBase.RegFunc(DbCmd.Main_CMD,DbCmd.PlatformChannelShopRsp_CMD, tPlatformChannelShopTb.OnPlatformChannelShopRsp) --db服结果返回

    tBase.RegFunc(ProtoMgr.GatewayPro.GATEWAY,ProtoMgr.Sub_GateWay.SUB_GATEWAY_CLIENT_CLOSE,ClientSink.OnGateClose) 
    
    tBase.RegFunc(tPubProto.LOGON_MAIN,tPubProto.VeriCodeReq_CMD , LogonLink.OnVeriCodeReq)                         --获取注册验证码请求
    tBase.RegFunc(Db_Proto1.Main_CMD,Db_Proto1.DbVeriCodeRsp_CMD , LogonLink.OnDbVeriCodeRsp)                          --获取验证码 db服返回

    tBase.RegFunc(tPubProto.LOGON_MAIN,tPubProto.BindQuerryReq_CMD,LogonLink.OnBindQuerryReq)                   --账号绑定查询请求
    tBase.RegFunc(tPubProto.LOGON_MAIN,tPubProto.PasswordResetReq_CMD,LogonLink.OnPasswordResetReq)               --密码重置请求

    tBase.RegFunc(Db_Proto1.Main_CMD,Db_Proto1.DbBindQuerryRsp_CMD , LogonLink.OnDbBindQuerryRsp)          --db服绑定查询返回
    tBase.RegFunc(Db_Proto1.Main_CMD,Db_Proto1.DbPasswordResetRsp_CMD , LogonLink.OnDbPasswordResetRsp)      --db服密码重置返回 
end


-- 关闭连接   网关发过来
function ClientSink.OnGateClose(sClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 

    local Read = ProtoMgr.Gateway_pb.RUQ_User_Line()
    Read:ParseFromString(ReadData:GetString())
    local nUserID =  Read.nUserID

    tPubUserApi.IncrbyGamingUser(-1,-2,-1,false,-1,nUserID)

    tBase.Log("   玩家: %d 断开连接  清除 数据   :%s",nUserID, sClientID)
    if ClientSink.m_ClientList[sClientID] ~= nil  then 
        tBase.Log(" 登录服  玩家断开连接  清除玩家数据   ")
        -- 删除用户信息
        ClientSink.m_ClientList[sClientID] = nil
    end
    
end

return ClientSink

