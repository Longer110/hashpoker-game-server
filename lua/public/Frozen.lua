--金币处理
package.path        = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path
local env           = require("env")         -- 环境配置
local tBase         = require("base")
local cjson         = require("cjson")       -- json
local http          = require("socket.http") -- Http 服务器
local ltn12         = require("ltn12")
local jwt           = require("JwtHs256Sign")
local url_escape    = require("socket.url").escape
local frozen        = {}
frozen.Host         = env.eventHost
frozen.redPacketPat = "/api/v1/wallet/frozen"

function frozen:getFrozen(uid)
    local token = jwt.sign(env.jwtSecret, { uid = tostring(uid) })
    local url = frozen.Host .. frozen.redPacketPat .. "?user_id=" .. url_escape(tostring(uid))
    local response_body = {}
    local ok, code, headers, status = http.request{
        url = url,
        method = "GET",
        headers = {
            ["Authorization"] = token,
        },
        sink = ltn12.sink.table(response_body),
    }
    local resp = table.concat(response_body or {})
    if not code then
        return 0, ("请求失败: %s"):format(tostring(ok))
    end
    code = tonumber(code)
    if code ~= 200 then
        return 0, ("请求状态吗错误:%s status:%s resp:%s"):format(
            tostring(code), tostring(status), tostring(resp)
        )
    end
    if resp == "" then
        return 0, "空的返回值"
    end
    local decodeOk, rsp = pcall(cjson.decode, resp)
    if not decodeOk then
        return 0, ("json格式化失败: %s resp:%s"):format(tostring(rsp), resp)
    end
    if type(rsp) ~= "table" then
        return 0, ("返回值错误: %s resp:%s"):format(type(rsp), tostring(resp))
    end
    if tonumber(rsp.code) ~= 0 then
        return 0, rsp.msg or ("获取锁定金币失败, code=" .. tostring(rsp.code))
    end
    if rsp.data == nil then
        return 0, "获取锁定金币失败, data=nil"
    end
    if rsp.data.frozen == nil then
        return 0,nil
    end
    local frozenAmount = math.floor(tonumber(rsp.data.frozen))
    return frozenAmount / 100 ,nil
end

return frozen
