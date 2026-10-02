local dispatch = require("dispatchnb")
local dispatch_ssl = require("dispatchnb_ssl")
local smtp = require("socket.smtp")
local ltn12 = require("ltn12")
require("base") -- 基础功能接口
local cjson = require("cjson")
local logger = require("logger")      -- 日志对象
local socket = require("socket")
local ssl = require("ssl")

SmtpNB = {}

smtp.mBase = base
socket.mBase = base

function SmtpNB:new(ssl,o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    if ssl == true then
        o.m_handler = dispatch_ssl.newhandler("coroutine")
    else
        o.m_handler = dispatch.newhandler("coroutine")
    end

    -- 请求超过最大数时，先缓存
    o.m_cache = {}
    o.m_max = 500

    return o
end

function SmtpNB:Init(nTimeID1, nTimeID2)

    local _Check = function(nTimeID)
        self.m_handler:step()
    end
    base.SetTimer(nTimeID1, 100, -1, _Check) 

    local _CheckCache = function(nTimeID)
        if #self.m_handler.receiving.set < self.m_max and #self.m_handler.sending.set < self.m_max and #self.m_cache > 0 then

            local nAddCount = self.m_max - math.max(#self.m_handler.receiving.set, #self.m_handler.sending.set)
            for i = 1, nAddCount do
                local tItem = table.remove(self.m_cache, 1)
                self.send_core(table.unpack(tItem))
                if #self.m_cache <= 0 then
                    break
                end
            end

        end

        if #self.m_cache > self.m_max * 10 then
            logger:error("SmtpNB.m_cache huge:"..#self.m_cache)
        end
    end
    base.SetTimer(nTimeID2, 1000, -1, _CheckCache)
end


function SmtpNB:send_core(data, pCallBack, pError)

    self.m_handler:start(function()
        local mesgt = {
                 headers = {
                        from = data.from,
                        to =  data.to ,            --收件人
                        cc =  data.cc,             --抄送 
                        subject =  data.subject    --主题
                 },
                 body =  data.body
        }
        local r, e = smtp.send{
                 from = data.from,
                 rcpt = data.rcpt,
                 source  = smtp.message(mesgt),
                 server =  data.server,
                 user = data.user,
                 password =  data.password,
                 port = data.port,
                 create = self.m_handler.tcp,
        }

        local code = "ok"
        if  not r  then
            code = e
        end

        local isSuccee, err = pcall(pCallBack, code)
        if isSuccee == false then
            base.Log("[ERROR] SmtpNB.request:"..err)
            if type(err) == "string" then 
                logger:error(err)
            end
        end
    end,
    function(ncode)
        local isSuccee, err = pcall(pError, ncode)
        if isSuccee == false then
            base.Log("[ERROR] er SmtpNB.request:"..err)
            if type(err) == "string" then 
                logger:error(err)
            end
        end
    end
    )
end

function SmtpNB:send(data, pCallBack, pError, bSSL)

    -- base.Log("SmtpNB.request len:"..#SmtpNB.m_handler.receiving.set..","..#SmtpNB.m_handler.sending.set)

    if #self.m_handler.receiving.set >= self.m_max or #self.m_handler.sending.set >= self.m_max then
        table.insert(self.m_cache, table.pack(data, pCallBack, pError))
    else
        self:send_core(data, pCallBack, pError)
    end
end

return SmtpNB


-- function ClientSink.mail()
--     local SendData = {
--         from =  "tong.li@mail.lekan.com",  --发件人
--         --发送列表
--         rcpt = {
--                 "tong.li@mail.lekan.com",
--                 "529873244@qq.com",
--         },
--         to = "litongoracle@163.com" , --收件人
--         cc = "tong.li@mail.lekan.com" , --抄送 
--         subject = "This is Mail Title",  --主题
--         body = "This is Mail Content.", -- 内容
--     }

--     local funcRes = function(nCode)  
--         print(nCode)
--     end	
--     local funcErr = function(nCode)
--         print(nCode)
--     end 
--     SmtpNB.send(SendData, funcRes, funcErr) 
-- end