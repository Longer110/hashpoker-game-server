package.path = require("./lua/Logon_s/Head").path

local tBase = require("base") -- 基础功能接口
local api = require("publicApi") -- 共用功能接口
local dbInfo = require("DBInfo") -- 数据库连接信息
local tname = require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tlogging = require("logging") -- 日志等级接口
local mlogger = require("logger") -- 日志对象  
local tParserAux = require("ParserAux")
local redis = require("redis")
local tSrvInfo = require("ServerInfo") 

local DbCmd =ProtoMgr.DbServer_pb.Db_Proto()
local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse

-- 玩家功能回调
ClientSink = { LevelLog = nil }

ClientSink.m_ClientList = {} -- 保存每个玩家的信息的链表
ClientSink.m_wTimer_ID_MonitorServer = 20004 -- 检测服务器定时器
ClientSink.m_Servers = {}   -- 内网服务器表列，保存服务器与对应用户的关系，方便其它处理

function ClientSink:new( table )
    local t =  table or {}
    self.__index = self
    setmetatable(t,self)
    return t
end

local nReqId =0
local tReqToResp={}  --tReqToReply[1] ={type='redis',reqtime=15234234,replytime=1523434}

local function GetReqId()
    nReqId =nReqId+1
    return nReqId
end
local function ErrReport(sErrMsg,id)
    tBase.Log("sErrMsg:%s id:%d",(sErrMsg or "nil"),id or -1)
end

local function RedisCheck()
    if tBase.m_MyRedisData[1].redis==nil then
        ErrReport("MyRedis_1 is nil")
        return
    end
    if tBase.m_MyRedisData[2].redis==nil then
        ErrReport("MyRedis_2 is nil")
        return
    end
    local isNormal=true
    local ping1Rt =tBase.m_MyRedisData[1].redis:ping()
    if not ping1Rt then
        isNormal=false
        ErrReport("MyRedis_1 ping fail")
    end
    local ping2Rt =tBase.m_MyRedisData[2].redis:ping()
    if not ping2Rt then
        isNormal=false
        ErrReport("MyRedis_2 ping fail")
    end
    if not tBase.m_centerRedis.Mo:ping() then
        isNormal=false
        ErrReport("MoRedis ping fail")
    end
    if isNormal then
        tBase.Log("==>RedisCheck Normal")
    else
        tBase.Log("--------------------")
    end
end

local function ServExistCheck()
    local isNormal =true
    for _,sTypeName in pairs(tname) do
        if sTypeName~="web" then
            local arrServKeys =tBase.GetSrcAllKey(sTypeName) or {}
            if #arrServKeys==0 then
                local sErrStr =string.format("%s not Exist",sTypeName)
                isNormal=false
                ErrReport(sErrStr)
            end
        end
    end
    if isNormal then
        tBase.Log("==>ServExistCheck Normal")
    else
        tBase.Log("--------------------")
    end
end



local function _ReqDbServ(currentTime)
   local reqId = GetReqId()
   local tPacket,nMainCmd,nSubCmd =DbProtoEncode("DbCheckReq",{nId=reqId})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail","DbCheckReq")
        return
    end
    tReqToResp[reqId] ={type='Db',reqtime=currentTime}
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
end

local function DoReqSend()
    local currentTime =os.time()
    _ReqDbServ(currentTime)
end

local function DoReplyCheck()
    local currentTime =os.time()
    for nReqId,reply in pairs(tReqToResp) do
        if not reply.replytime and (currentTime-reply.reqtime)>10 then
            local sErrStr =string.format("%s timeout reply",reply.type)
            ErrReport(sErrStr,nReqId)
            tReqToResp[nReqId]=nil
        elseif reply.replytime and (reply.replytime-reply.reqtime)>10 then
            local sErrStr =string.format("%s delay time is great than 10 seconds",reply.type)
            ErrReport(sErrStr,nReqId)
            tReqToResp[nReqId]=nil
        elseif reply.replytime then
            tReqToResp[nReqId]=nil
        end
    end
end


-- 启动服务器
function ClientSink.OnStart() 
    
    -- 设置日志目录:
    local sLogDir =  dbInfo.LogDir.."Monitor/" .. tBase.GetPort() .. "-" .. tBase.GetThreadIndex()
    mlogger.SetFile( sLogDir , "Monitor", tBase )
    -- 设置全局等级
    mlogger:setLevel( tlogging.DEFAULT, "Monitor" )

    -- 消息接收处理，不用默认函数
    tBase.m_MyMonitorFun = nil
    -- 注册服务器
    tBase.RegServer(tname.monitor)
    -- 注册协议
    ClientSink.Protocol()  

    -- 获取服务器列表
    -- tBase.SetTimer(ClientSink.m_wTimer_ID_MonitorServer, 1000*30, 1, ClientSink.MonitorServer)
    tBase.Log(" Monitor Server Start ")  
end


-- 停止服务器
function ClientSink.OnStop()
    -- 取消本地服务器
    tBase.UnRegServer()
    tBase.Log(" Monitor Server OnStop ") 
end

-- 有新用户连接
function ClientSink.OnAccept(ClientID, ip, port)
end
-- 关闭连接
function ClientSink.OnClose(ClientID)
end


local function OnDbCheckRsp(sReturnKey, Data, nLen)
    local strReq ="DbCheckRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    local item =tReqToResp[tData.nId]
    if item then
        item.replytime=os.time()
    end
end


-- 注册协议
function ClientSink.Protocol()  
    if DbCmd.DbCheckRsp_CMD then
        tBase.RegFunc(DbCmd.Main_CMD,DbCmd.DbCheckRsp_CMD, OnDbCheckRsp) --db服结果返回
    end
end

--监控服务
function ClientSink.MonitorServer()
    local m_KOBJ = redis.connect(dbInfo.RedisParams.center)  
    if #dbInfo.RedisParams.center.pass>0 then m_KOBJ:auth(dbInfo.RedisParams.center.pass) end 
    m_KOBJ:select(1)
    for _, name in pairs(tname) do
        local sServerKey = tBase.m_Flist .. name .. '*'
        local arrServerKey = tBase.m_centerRedis.Mo:keys(sServerKey)
        if next(arrServerKey)~=nil and arrServerKey and arrServerKey~="{}"  then 
            local n=1
            for _, key in pairs(arrServerKey) do 
                local d = m_KOBJ:get(key)
                if not d then
                    local SendSMS = "【小承】通知服务器域名_"..name.." 总共"..#arrServerKey.." 子服务器有"..n.."个挂了，对应服务器ID_"..tSrvInfo.nServerId
                    tBase._OnMonitorInfo(SendSMS,tSrvInfo.nServerId)
                    n = n+1
                end 
            end
        else
            local SendSMS = "【小承】通知发下服务器域名_"..name.."服务器没开或者挂了，请管理员排查对应服务器ID_"..tSrvInfo.nServerId
            tBase._OnMonitorInfo(SendSMS,tSrvInfo.nServerId)
        end
    end
    tBase.SetTimer(ClientSink.m_wTimer_ID_MonitorServer, 1000*60*5, 1, ClientSink.MonitorServer)
end


return ClientSink