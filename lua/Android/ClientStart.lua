package.path = require("./lua/Android/Head").path

local Define = require("Define")
local mlogger = require("logger")      -- 日志对象
local tALog = require("AndroidLog")
local NameLibMgr = require("NameLibMgr")
local AndroidMgr = require("AndroidMgr")
local ProtoManager = require("ProtoManager")
local AnProtocol = require("AnProtocol")
local tBase = require("base")
local tPublicApi = require("publicApi")
local tPublicRedis = require("PublicRedis")
local Quick = require("Quick")
local TypeName = require("typename")
local RentalInfo = require("RentalInfo")

local ClientSink = {}

 -- 启动服务器
function ClientSink.OnStart()  
    mlogger.SetFile("./log/Android/" .. tBase.GetPort() .. "-" .. tBase.GetThreadIndex(), "Android", tBase)
    mlogger:setLevel(mlogger.LogObject.FATAL, "Android" )  
    tBase.m_MyMonitorFun = ClientSink.onMsgRecv
    tBase.RegServer(TypeName.android)
    ClientSink.Protocol()

    tALog.Print("Android Key:"..tBase.m_tKey)
    tALog.Print("Android Server Start")
    
    ClientSink.OnStartTimer()

    tBase.SetTimer(Define.Timer.LoadCfg, 10*1000, 1, ClientSink.InitServer)
 
    
    tPublicRedis._TimerAndroidPeople()  -- 处理非百人数量
end
 
function ClientSink.OnStartTimer()
    tBase.SetTimer(Define.Timer.CheckAndroid, 1*1000, -1, AndroidMgr.CheckAndroid)
    tBase.SetTimer(Define.Timer.CheckNickLib, 3*60*1000, -1, NameLibMgr.CheckLanguageEnough)
    tBase.SetTimer(Define.Timer.CheckRental, 3*60*1000, -1, RentalInfo.ShowInfo)
    tBase.SetTimer(Define.Timer.CheckInvalid, 1*60*1000, -1, AndroidMgr.CheckInvalid)
end

function ClientSink.OnKillTimer()
    tBase.KillTimer(Define.Timer.CheckAndroid)
    tBase.KillTimer(Define.Timer.CheckNickLib)
    tBase.KillTimer(Define.Timer.CheckRental)
    tBase.KillTimer(Define.Timer.CheckInvalid)
end

--初始化服务器
function ClientSink.InitServer()
    Quick.Reg()
    AndroidMgr.Init()
end

 --停止服务器
function ClientSink.OnStop()
    -- 取消本地服务器
    ClientSink.OnKillTimer()
    tBase.UnRegServer()
    tALog.Print("Android Server OnStop") 
end

function ClientSink.Protocol()
    tBase.RegFunc(ProtoManager.Sys.DB, ProtoManager.Sub_DB.SUB_REP_GETANDROIDNAME, NameLibMgr.DealLoad)
    tBase.RegFunc(ProtoManager.Sys.ANDROID, ProtoManager.Sub_Android.SUB_REQ_GETANDROID, AnProtocol.Req_GetAndroid)
    tBase.RegFunc(ProtoManager.Sys.ANDROID, ProtoManager.Sub_Android.SUB_REQ_SETANDROID, AnProtocol.Req_SetAndroid)

    local CMD_Backstage = ProtoManager.Backstage_pb.Backstage_Proto()
    tBase.RegFunc(CMD_Backstage.Main_CMD, CMD_Backstage.DelAndroidsReq_CMD, AndroidMgr.DelAndroidsReq)  --后台请求删除机器人
end

return ClientSink