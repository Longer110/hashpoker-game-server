package.path = require("./lua/Web/Head").path

local m = require("base") -- 基础功能接口
local api = require("publicApi") -- 共用功能接口
local tname = require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tlogging = require("logging") -- 日志等级接口 
local mlogger = require("logger") -- 日志对象 
local dbInfo = require("DBInfo") -- 数据库连接信息
local tMsgHandle = require("MsgHandle")
local tSetingConfig = require("SetingConfig") -- 
local cjson    = require("cjson")
 

require("HttpNB")
require("HttpNB2")
require("SmtpNB")
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

--
function UrlRequest(sUrl, funcRes, funcError,sSendType,sBody)
    if type(sUrl)=="table" then
        sBody =sUrl.body
        sUrl =sUrl.sUrl
    end
    local ss =string.match(sUrl,"^%s*(https?)")
    if ss=="https" then
        m.Log("do https req")
        ClientSink.m_https:request(sUrl, funcRes, funcError, sSendType, sBody)
    else
        HttpNB.request(sUrl, funcRes, funcError,sSendType,sBody)
    end
end


-- 启动服务器
function ClientSink.OnStart()
 
    -- 设置日志目录：
    local sLogDir =  dbInfo.LogDir.."/Web/" .. m.GetPort() .. "-" .. m.GetThreadIndex()
    mlogger.SetFile( sLogDir , "Web", m )

    
    -- 消息接收处理，不用默认函数
    m.m_MyMonitorFun = ClientSink.onMsgRecv
    -- 注册服务器
    m.RegServer(tname.web)
    -- 注册协议
    ClientSink.Protocol()

    base.SetTimer(60010, 1000*10, -1, tMsgHandle.OffLineUserCheck) 
    
  --  base.SetTimer(60012, 1000*5, 1, _Test) 

  --  base.SetTimer(60013, 1000*15, 1, _TestHttps) 
    
    m.Log(" web Server Start ")  
    
    -- ClientSink.OnStop()
 
    -- 等级案例
    mlogger:info("Web Server Start")
    mlogger:debug("debugging...")
    -- -----------------------------------
    -- local socket = require("socket")
    -- local ssl = require("ssl")
    -- m.Log("开始处理") 
    -- -- TLS/SSL client parameters (omitted)
    -- local params = {
    --   mode = "client",
    --   protocol = "tlsv1",
    --   verify = "none",
    --   options = "all",
    -- }
    -- local conn = socket.tcp()
    -- conn:connect("www.baidu.com", 443)
    -- -- TLS/SSL initialization
    -- conn = ssl.wrap(conn, params)
    -- conn:dohandshake()
    -- conn:send("GET / HTTP/1.1\n\n")
    -- local line, err = conn:receive()
    -- m.Log(err or line)
    -- conn:close()
    -- -----------------------------------
    -- 异步http访问
    HttpNB.Init(1101, 1102)

    ClientSink.m_https = HttpNB2:new(true)  -- 参数2：true为ssl方式，false为非ssl方式 参数3：wrapParms，https不填则用默认,http不需要
    ClientSink.m_https:Init(1105, 1106)

    -- local funcRes = function(sRes)
    --     m.Log("返回内容:"..sRes)
    --     -- 这里要判断错误码处理
    -- end
    -- local funcError = function()
    --     m.Log("异常的处理") 
    --     assert(false)
    -- end

    -- m.Log("开始处理") 

    -- local http = require("socket.http")
    -- http.ml = m

    -- local tmpTimer = function(nTimerID)
    --     local Url = {}
    --     Url.sUrl = "http://192.168.0.215:82/Text/GetData"
    --     Url.body = '{"userIds": ["1000", "1000"],"vendorNo": "RY","action": 1,"key": "28EOTrufKXHeErXb"}'
    --     HttpNB.request(Url, funcRes, funcError)
    -- end

    -- -- local sRes = http.request(Url.sUrl, Url.body)
    -- -- m.Log("返回："..sRes) 
    -- base.SetTimer(12551, 200, -1, tmpTimer) 

 
    -- -----------------------------------------------------------------------------------------------------------
    -- 发送邮件测试
    -- local _CheckCache = function(nTimeID)
    --     m.Log("***********") 
    -- end
    -- base.SetTimer(1112, 500, -1, _CheckCache) 

    -- ClientSink.mail()

    -- https请求测试
    -- local _CheckCache = function(nTimeID)
    --     m.Log("***********")
    -- end
    -- base.SetTimer(1112, 500, -1, _CheckCache) 

    -- ClientSink.httpsTest1()
    -- ClientSink.httpsTest2()

    -- 需使用定时器多次请求时需在上面先new
    -- base.SetTimer(12551, 1000*3, 2000, ClientSink.httpsTest1)
    -- base.SetTimer(12551, 1000*3, 2000, ClientSink.httpsTest1) 



end

-- 停止服务器
function ClientSink.OnStop()

    -- 取消本地服务器
    m.UnRegServer()
    m.Log(" web Server OnStop ") 

end

-- 有新用户连接
function ClientSink.OnAccept(ClientID, ip, port)
    m.Log(" web有新用户连接 Client:%d,  ip:%s, port:%d", ClientID, ip, port)
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

-- 注册协议  
function ClientSink.Protocol()
    local WebProto = ProtoMgr.Web_pb.Web_Sys()
    m.RegFunc(WebProto.Main_CMD, WebProto.WebUrlReq_CMD, tMsgHandle.OnWebUrlReq)
    m.RegFunc(WebProto.Main_CMD, WebProto.WebUrlReqAndReturn_CMD, tMsgHandle.OnWebUrlReqAndReturn)
    m.RegFunc(ProtoMgr.Sys1.WebMain, ProtoMgr.Sub_Web.WebMessReq_CMD, tMsgHandle.OnWebHttpReq)
    
    m.RegFunc(WebProto.Main_CMD, WebProto.WebUserOnlineStatus_CMD, tMsgHandle.OnWebUserOnlineStatus)
    m.RegFunc(WebProto.Main_CMD, WebProto.WebOtherPlatformWinloseReq_CMD, tMsgHandle.OnWebOtherPlatformWinloseReq)
    
end
 




return ClientSink