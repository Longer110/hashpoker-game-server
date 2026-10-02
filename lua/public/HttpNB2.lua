local dispatch = require("dispatchnb")
local dispatch_ssl = require("dispatchnb_ssl")
local http = require("socket.http")
local ltn12 = require("ltn12")
require("base") -- 基础功能接口
local cjson = require("cjson")
local logger = require("logger")      -- 日志对象
local socket = require("socket")
local smtp = require("socket.smtp")
local https = require("luasec.https")
local url    = require("socket.url")
HttpNB2 = {}

smtp.mBase = base
socket.mBase = base

function HttpNB2:new(ssl, wrapParms,o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    if ssl == true then
        o.m_handler = dispatch_ssl.newhandler("coroutine",wrapParms)
    else
        o.m_handler = dispatch.newhandler("coroutine")
    end

    -- 请求超过最大数时，先缓存
    o.m_cache = {}
    o.m_max = 500

    return o
end

function HttpNB2:Init(nTimeID1, nTimeID2)
    -- if timeout then
    --     self.m_handler:setTIMEOUT(timeout)
    -- end
    local _Check = function(nTimeID)
        self.m_handler:step()    
    end
    base.SetTimer(nTimeID1, 100, -1, _Check) 

    local _CheckCache = function(nTimeID)
        if #self.m_handler.receiving.set < self.m_max and #self.m_handler.sending.set < self.m_max and #self.m_cache > 0 then

            local nAddCount = self.m_max - math.max(#self.m_handler.receiving.set, #self.m_handler.sending.set)
            for i = 1, nAddCount do
                local tItem = table.remove(self.m_cache, 1)
                self:request_core(table.unpack(tItem))
                if #self.m_cache <= 0 then
                    break
                end
            end

        end

        if #self.m_cache > self.m_max * 10 then
            logger:error("HttpNB2.m_cache huge:"..#self.m_cache)
        end
        -- base.LogT("HttpNB2.m_cache count:", #HttpNB2.m_cache)
    end
    base.SetTimer(nTimeID2, 1000, -1, _CheckCache)
end

function HttpNB2:setTimeout(timeout)
    if timeout then
        self.m_handler:setTIMEOUT(timeout)
    end
end

--判断是http还是https
local function checkProtocol(url)
    if string.sub(url, 1, 7) == "http://" then
      return 1 -- HTTP
    elseif string.sub(url, 1, 8) == "https://" then
      return 0 -- HTTPS
    else
      return nil -- 无效的URL协议
    end
end

local function default_https_port(u)
    return url.build(url.parse(u, {port = 443}))
 end

function HttpNB2:request_core(Url, pCallBack, pError,sSendType,sBody,sContentType)
    if checkProtocol(Url) == 0 then
        Url = default_https_port(Url)
    end
    assert(type(Url) =="string")
    self.m_handler:start(function()
        local t = {}
        local reqt = {
            create = self.m_handler.tcp,                
            sink = ltn12.sink.table(t),
            url = Url,
        }
       
        if sSendType==nil or sSendType == "POST" then
            local sContentType =sContentType or "application/json"
            reqt.source = ltn12.source.string(sBody)
            reqt.headers = {
                ["content-length"] = string.len(sBody),
                ["content-type"] = sContentType
            }
            reqt.method = "POST"
        end
        base.LogT("_HttpNB2My")

        http.mBase = base
        local _, code, headers, status = http.request2(reqt)
        if not code then
            base.LogT("_HttpNB2.request,not code")
        else
            -- base.LogT("_HttpNB2.request,code_",code)
        end
        if not headers then
            base.LogT("_HttpNB2.request,not headers")
        else
            --base.LogT("_HttpNB2.request,headers_",headers)
        end
        if not status then
            base.LogT("_HttpNB2.request,not status")
        else
            -- base.LogT("_HttpNB2.request,status_",status)
        end
        local isSuccee, err = pcall(pCallBack, table.concat(t),code)
        if isSuccee == false then
            base.Log("[ERROR] HttpNB2.request:"..err)
            if type(err) == "string" then 
                logger:error(err)
            end
        end
        -- base.LogT("HttpNB2.request 结束: Url_",Url)
    end,
    function(ncode)
        base.LogT("HttpNB2.request 错误: Url_",Url)
        if ncode then
            base.LogT("HttpNB2.request 错误: ncode_",ncode)
        end
        local isSuccee, err = pcall(pError,ncode)
        if isSuccee == false then
            base.Log("[ERROR] er HttpNB2.request:"..err)
            if type(err) == "string" then 
                logger:error(err)
            end
        end
    end
    )
end

function HttpNB2:request(Url, pCallBack, pError,sSendType,sBody,sContentType)

    -- base.Log("HttpNB2.request len:"..#HttpNB2.m_handler.receiving.set..","..#HttpNB2.m_handler.sending.set)

    if #self.m_handler.receiving.set >= self.m_max or #self.m_handler.sending.set >= self.m_max then
        table.insert(self.m_cache, table.pack(Url, pCallBack, pError,sSendType,sBody,sContentType))
    else
        self:request_core(Url, pCallBack, pError,sSendType,sBody,sContentType)
    end
end

return HttpNB2
