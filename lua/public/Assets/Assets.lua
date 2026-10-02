--金币处理
package.path        = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path
local env           = require("env")         -- 环境配置
local tBase         = require("base")
local cjson         = require("cjson")       -- json
local http          = require("socket.http") -- Http 服务器
local ltn12         = require("ltn12")
local pkey          = require("openssl.pkey")
local digest        = require("openssl.digest")
local AssetsManager = {}
AssetsManager.Host  = env.assetsHost
AssetsManager.Redis = nil
AssetsManager.Reason = {
    RoomBuyIn      = "room_buy_in",         -- 进入房间/带入
    RoomSettle     = "room_settle",         -- 离开房间结算（输赢结算/派奖）
    RedPacketSend  = "red_packet_send",     -- 发红包扣款
    Deposit        = "deposit",             -- 充值成功入账
    Withdraw       = "withdraw",            -- 提现
    Interaction    = "interaction",         -- 其他消耗(比如：道具购买、抽奖,打赏灯)
}
AssetsManager.priv = assert(pkey.new(env.assetsPri))
http.TIMEOUT = http.TIMEOUT or 5
local function b64encode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r, byte = '', x:byte()
        for i = 8, 1, -1 do
            r = r .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and '1' or '0')
        end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do
            c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0)
        end
        return b:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

function AssetsManager:RsaSha256Sign(data)
    local md = digest.new("sha256")
    md:update(data)
    local signature = assert(self.priv:sign(md))
    return b64encode(signature)
end

local incrbyex = function(key, inc, ttl)
    if not AssetsManager.Redis then
        AssetsManager.Redis = tBase.m_MyRedisData[2].redis
    end
    if not AssetsManager.Redis then
        return nil, "redis connection not available"
    end
    inc = tonumber(inc) or 1
    ttl = tonumber(ttl) or 60
    local script = [[
        local v = redis.call("INCRBY", KEYS[1], ARGV[1])
        if v == tonumber(ARGV[1]) then
            redis.call("EXPIRE", KEYS[1], ARGV[2])
        end
        return v
    ]]
    return AssetsManager.Redis:eval(script, 1, key, inc, ttl)
end

function AssetsManager:TraceId(uid)
    local timeStr = os.date("%Y%m%d%H%M%S", os.time())
    local key = "assets:trace:" .. timeStr
    local seq = incrbyex(key, 1, 5)
    if not seq then
        return nil, "traceId generate failed"
    end
    return timeStr .. string.format("%06d", seq)
end

function AssetsManager:_PostBizTransfer(body)
    if type(body) ~= "table" then
        return false, "body must be table"
    end
    local url = self.Host .. "/api/biz_transfer"
    local uid = body.uid and tostring(body.uid) or ""
    if uid == "" then
        return false, "uid missing in body"
    end
    local traceId, traceErr = self:TraceId(uid)
    if not traceId then
        return false, traceErr or "traceId生成失败"
    end
    local jsonData = cjson.encode(body)
    local response_body = {}
    local ok, code, headers = http.request{
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"]   = "application/json",
            ["TraceId"]        = traceId,
            ["Content-Length"] = tostring(#jsonData),
            ["Signature"]      = self:RsaSha256Sign(jsonData),
        },
        source = ltn12.source.string(jsonData),
        sink   = ltn12.sink.table(response_body),
    }
    local resp = table.concat(response_body)
    if not code then
        return false, ("http request failed: %s"):format(tostring(ok))
    end
    if tonumber(code) ~= 200 then
        return false, ("http error:%s resp:%s"):format(tostring(code), resp)
    end
    if resp == nil or resp == "" then
        return false, "empty response body"
    end
    local data
    local decodeOk, decodeErr = pcall(function()
        data = cjson.decode(resp)
    end)
    if not decodeOk then
        return false, ("json decode failed: %s resp:%s"):format(tostring(decodeErr), resp)
    end
    if type(data) ~= "table" then
        return false, ("invalid response type: %s resp:%s"):format(type(data), resp)
    end
    if data.code ~= 0 then
        return false, data.msg or ("biz_transfer failed, code=" .. tostring(data.code))
    end
    return true, data
end

-- 进入房间扣除金币 uid 用户id amount 金额 room_id 房间唯一id
function AssetsManager:EnterRoom(uid, amount, room_id)
    if uid == nil or amount == nil or room_id == nil then
        return false, "参数错误"
    end
    uid = tostring(uid)
    room_id = tostring(room_id)
    if uid == "" then
        return false, "uid不能为空"
    end
    if room_id == "" then
        return false, "room_id不能为空"
    end
    amount = tonumber(amount)
    if not amount then
        return false, "amount必须是数字"
    end
    amount = math.floor(amount)
    if amount <= 0 then
        return false, "amount必须大于0"
    end
    local body = {
        ch       = "dz",
        uid      = uid,
        amount   = amount,
        reason   = self.Reason.RoomBuyIn,
        currency = "1",
        extra    = { room_id = room_id }
    }

    return self:_PostBizTransfer(body)
end

-- 离开房间带出 uid 用户id amount 金额 room_id 房间唯一id
function AssetsManager:LeaveRoom(uid, amount, room_id)
    if uid == nil or amount == nil or room_id == nil then
        return false, "参数错误"
    end
    uid = tostring(uid)
    room_id = tostring(room_id)
    if uid == "" then
        return false, "uid不能为空"
    end
    if room_id == "" then
        return false, "room_id不能为空"
    end
    amount = tonumber(amount)
    if not amount then
        return false, "amount必须是数字"
    end
    amount = math.floor(amount)
    if amount <= 0 then
        return false, "amount必须大于0"
    end
    local body = {
        ch       = "dz",
        uid      = uid,
        amount   = amount,
        reason   = self.Reason.RoomSettle,
        currency = "1",
        extra    = { room_id = room_id }
    }
    return self:_PostBizTransfer(body)
end

-- 其他消耗（）
function AssetsManager:OtherConsumption(uid, amount, reason)
    if uid == nil or amount == nil or reason == nil then
        return false, "参数错误"
    end
    uid = tostring(uid)
    reason = tostring(reason)
    if uid == "" then
        return false, "uid不能为空"
    end
    if reason == "" then
        return false, "reason不能为空"
    end
    amount = tonumber(amount)
    if not amount then
        return false, "amount必须是数字"
    end
    amount = math.floor(amount)
    if amount <= 0 then
        return false, "amount必须大于0"
    end
    local body = {
        ch       = "dz",
        uid      = uid,
        amount   = amount,
        reason   = self.Reason.Interaction,
        currency = "1"
    }
    return self:_PostBizTransfer(body)
end

return AssetsManager