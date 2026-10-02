local dispatch = require("dispatchnb")
local http = require("socket.http")
local ltn12 = require("ltn12")
require("base") -- 基础功能接口
local cjson = require("cjson")
local logger = require("logger")      -- 日志对象
local socket = require("socket")
local smtp = require("socket.smtp")
HttpNB = {}

smtp.mBase = base
socket.mBase = base

function HttpNB.Init(nTimeID1, nTimeID2)

    -- 初始化
    HttpNB.m_handler = dispatch.newhandler("coroutine")

    local _Check = function(nTimeID)
        HttpNB.m_handler:step()    
    end
    base.SetTimer(nTimeID1, 100, -1, _Check) 

    -- 请求超过最大数时，先缓存
    HttpNB.m_cache = {}
    HttpNB.m_max = 500

    local _CheckCache = function(nTimeID)
        if #HttpNB.m_handler.receiving.set < HttpNB.m_max and #HttpNB.m_handler.sending.set < HttpNB.m_max and #HttpNB.m_cache > 0 then

            local nAddCount = HttpNB.m_max - math.max(#HttpNB.m_handler.receiving.set, #HttpNB.m_handler.sending.set)
            for i = 1, nAddCount do
                local tItem = table.remove(HttpNB.m_cache, 1)
                HttpNB.request_core(table.unpack(tItem))
                if #HttpNB.m_cache <= 0 then
                    break
                end
            end

        end

        if #HttpNB.m_cache > HttpNB.m_max * 10 then
            logger:error("HttpNB.m_cache huge:"..#HttpNB.m_cache)
        end
        -- base.LogT("HttpNB.m_cache count:", #HttpNB.m_cache)
    end
    base.SetTimer(nTimeID2, 1000, -1, _CheckCache)
end



function HttpNB.request_core(Url, pCallBack, pError,sSendType,sBody)

    assert(type(Url) =="string")
    HttpNB.m_handler:start(function()

        local t = {}
        local reqt = {
            create = HttpNB.m_handler.tcp,                
            sink = ltn12.sink.table(t),
            url = Url
        }

        if sSendType==nil or sSendType == "POST" then
            reqt.source = ltn12.source.string(sBody)
            reqt.headers = {
                ["content-length"] = string.len(sBody),
                ["content-type"] = "application/json"
            }
            reqt.method = "POST"
            -- base.Log("HttpNB.request: 使用POST请求")
        end

        http.mBase = base
        local _, code, headers, status = http.request2(reqt)
        if not code then
            base.LogT("_HttpNB.request,not code")
        else
            -- base.LogT("_HttpNB.request,code_",code)
        end
        if not headers then
            base.LogT("_HttpNB.request,not headers")
        else
            --base.LogT("_HttpNB.request,headers_",headers)
        end
        if not status then
            base.LogT("_HttpNB.request,not status")
        else
            -- base.LogT("_HttpNB.request,status_",status)
        end
        local isSuccee, err = pcall(pCallBack, table.concat(t),code)
        if isSuccee == false then
            base.Log("[ERROR] HttpNB.request:"..err)
            if type(err) == "string" then 
                logger:error(err)
            end
        end
        -- base.LogT("HttpNB.request 结束: Url_",Url)
    end,
    function(ncode)
        base.LogT("HttpNB.request 错误: Url_",Url)
        if ncode then
            base.LogT("HttpNB.request 错误: ncode_",ncode)
        end
        local isSuccee, err = pcall(pError,ncode)
        if isSuccee == false then
            base.Log("[ERROR] er HttpNB.request:"..err)
            if type(err) == "string" then 
                logger:error(err)
            end
        end
    end
    )
end

function HttpNB.request(Url, pCallBack, pError,sSendType,sBody)

    -- base.Log("HttpNB.request len:"..#HttpNB.m_handler.receiving.set..","..#HttpNB.m_handler.sending.set)

    if #HttpNB.m_handler.receiving.set >= HttpNB.m_max or #HttpNB.m_handler.sending.set >= HttpNB.m_max then
        table.insert(HttpNB.m_cache, table.pack(Url, pCallBack, pError,sSendType,sBody))
    else
        HttpNB.request_core(Url, pCallBack, pError,sSendType,sBody)
    end
end

return HttpNB
