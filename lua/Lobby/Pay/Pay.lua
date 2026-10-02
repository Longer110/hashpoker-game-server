-- pay.lua
package.path  = "../lua/base/luasec/?.lua;./lua/base/luasec/?.lua;" .. package.path

local http     = require("socket.http")
local ltn12    = require("ltn12")
local cjson    = require("cjson.safe")
local m        = require("base")
local myHttp   = require("MyHttps")

local Pay      = {}
Pay.__index    = Pay
Pay.cfg        = require("PayConfig")
Pay.TopupTopic = "tron_transfer_topup"
Pay._callbacks = {
    order_cb    = nil, -- 支付订回调
    withdraw_cb = nil,
}

local Path     = {
    TOPUP = "/pay/v1/topup/createOrder",
    WITHDRAW = "/pay/v1/withdraw",
    CHECKWITHDRAW = "/api/trade/notifyNewWithdraw" 
}
local function join_url(base, path)
    base = tostring(base or "")
    path = tostring(path or "")
    local b = base:match("/$") and base:sub(1, -2) or base
    local p = path:match("^/") and path or ("/" .. path)
    return b .. p
end


math.randomseed(tonumber(tostring(os.time()):reverse():sub(1, 7)))

local ALLOWED_CURRENCIES = { usdt = true }
-- local ALLOWED_CHANNELS = { bank = true, tron = true, web = true } -- 预留

local ORDER_STATUS = {
    CREATED  = "CREATED",
    PENDING  = "PENDING",
    PAID     = "PAID",
    CANCELED = "CANCELED",
    TIMEOUT  = "TIMEOUT",
    SUCCESS  = "SUCCESS",
}

local function now() return os.time() end

local function decode_json(body)
    if not body or body == "" then
        return nil, "empty body"
    end
    local data, err = cjson.decode(body)
    if not data then
        return nil, "json decode error: " .. tostring(err)
    end
    return data, nil
end

local function get_json(url, headers)
    local resp_body = {}
    local ok, code, resp_headers, statusline = http.request {
        url = url,
        method = "GET",
        headers = headers or { ["accept"] = "application/json" },
        sink = ltn12.sink.table(resp_body),
    }

    if not ok or code ~= 200 then
        return nil, "http error: " .. tostring(code or statusline)
    end

    local body = table.concat(resp_body)
    return cjson.decode(body)
end

-- =========================
-- 生成随机的以WD开头的字符串
-- =========================
local function gen_id(prefix)
    -- 获取当前时间戳
    local currentTime = os.time()
    -- 格式化为日期部分 (年月日)
    local datePart = os.date("%Y%m%d%H%M%S", currentTime)
    
    -- 生成随机数部分 (4位数字)
    local randomPart = string.format("%04d", math.random(0, 9999))
    
    -- 组合生成最终ID: 前缀 + 日期 + 随机数
    return prefix .. datePart .. randomPart
end

local function post_json(url, tbl, headers)
	local opt = {}
	opt.method = "post"
	opt.body = cjson.encode(tbl or {})
	opt.headers ={["Content-Type"] = "application/json",}
	local err, code, result  = myHttp.request(url, opt)
	if code ~= 200 then
		m.Log("---post_json: error ---")
		m.Log(code)
        return nil, "http error: " .. tostring(code)
    end
	
	return result
	
 --   local payload                            = cjson.encode(tbl or {})
 --  local resp_body                          = {}
 --  headers                                  = headers or {}
 -- headers["content-type"]                  = headers["content-type"] or "application/json"
--    headers["content-length"]                = tostring(#payload)

--m.Log(url)
  ---  local ok, code, resp_headers, statusline = http.request {
  --      url     = url,
  --      method  = "POST",
 --       headers = headers,
 --       source  = ltn12.source.string(payload),
 --       sink    = ltn12.sink.table(resp_body),
  --  }

--   if not ok or code ~= 200 then
--	    m.Log(code)
--       return nil, "http error: " .. tostring(code or statusline)
--    end

--   local body = table.concat(resp_body)
--    return cjson.decode(body)
end


local function assert_arg(cond, msg)
    if not cond then return nil, msg or "invalid argument" end
    return true
end

local function trim(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end



-- =========================
-- 创建充值订单（单位：分）
-- =========================
-- uid: 用户ID（字符串或数字）
-- amount: 金额（分，整数），例：1 USDT => 100
-- currency: 仅 usdt
-- subject: 订单标题
-- channel: 渠道（暂不校验）
function Pay:create_order(uid, amount, currency, subject, channel)
    -- uid
    local ok, err = assert_arg(uid ~= nil and tostring(uid) ~= "", "uid required")
    if not ok then
        return nil, err
    end
    uid = tostring(uid)

    -- amount（必须为整数分，>0）
    local n = tonumber(amount)
    if not n then
        return nil, "amount is not a valid number"
    end

    if n <= 0 then
        return nil, "amount must be > 0"
    end

    if n % 1 ~= 0 then
        return nil, "amount must be integer cents"
    end

    local amount_cents = math.floor(n)
    -- currency
    if not currency then
        currency = "usdt"
    end

    currency = string.lower(currency)
    ok, err = assert_arg(ALLOWED_CURRENCIES[currency], "unsupported currency")
    if not ok then
        return nil, err
    end

    -- subject
    subject = trim(subject)
    ok, err = assert_arg(type(subject) == "string" and subject ~= "", "subject required")
    if not ok then
        return nil, err
    end
    -- 	Uid       string `json:"uid"`
    -- Amount    string `json:"amount"`
    -- Channel   string `json:"channel"`
    -- Currency  string `json:"currency"`
    local req_data = {
        uid      = uid,
        amount   = tostring(amount),
        channel  = "",
        currency = "usdt"
    }

    local respon, err = post_json(join_url(Pay.cfg.host, Path.TOPUP), req_data)
    if err ~= nil or respon == nil or respon.data == nil then
        return nil, "创建订单失败"
    end
    -- 返回的数据格式
    -- {
    -- "id": 1,
    -- "order_id": "T202510170001",  //订单id
    -- "uid": "user_123", //用户id
    -- "amount": 100,  //金额 （分）
    -- "currency": "usdt", //充值货币
    -- "channel": "merchant", // 渠道（暂不校验）
    -- "topup_url": "https://pay.example.com/order/1", // 充值url
    -- "fee": 0,  //手续费目前为0
    -- "subject": "iPhone 17", //标题
    -- "metadata": "{}", //额外信息
    -- "status": 0, //订单状态  0未支付 1已完成 2 出错
    -- "message": "",  //出错信息
    -- "created_at": "2025-10-17 12:00:00", // 创建时间
    -- "updated_at": "2025-10-17 12:00:00" // 更新时间
    -- }
    if respon.code == nil or respon.code ~= 0 then
        return nil, respon.msg or "创建订单失败"
    end
    return respon.data, nil
end


-- =========================
-- 创建提现订单（单位：分）
-- =========================
-- uid: 用户ID
-- amount: 分（整数）例：1 USDT => 100
-- currency: 仅 usdt（可为空，默认 usdt）
-- dest: 提现目标（必填，非空）
-- remark: 备注（可选）
function Pay:create_withdraw(uid, amount, currency, dest, remark)
    -- uid
    local ok, err = assert_arg(uid ~= nil and tostring(uid) ~= "", "uid required")
    if not ok then
        return nil, err
    end

    uid = tonumber(uid)
    local sendUid = math.floor(uid)

    -- currency
    if currency == nil then
        currency = "usdt"
    end
    currency = string.lower(currency)
    ok, err = assert_arg(ALLOWED_CURRENCIES[currency], "unsupported currency")
    if not ok then
        return nil, err
    end

    dest = trim(dest)
    ok, err = assert_arg(type(dest) == "string" and dest ~= "", "dest required")
    if not ok then
        return nil, err
    end

    if remark ~= nil then
        remark = tostring(remark)
    end

    local req_data = {
        order_id   = gen_id("WD"),
        to_address = dest,
        user_id    = tostring(sendUid),
        amount     = tostring(amount), 
        timestamp  = now(),
        sign       = ""
    }

    -- 返回创建订单信息
    return req_data, nil
end

-- =========================
-- 发送自动审核订单请求（
-- =========================
-- req_data: json请求数据

function Pay:requestCheckWitchdraw(req_data)
    if req_data == nil then
        return nil, "发送自动审核订单请求失败"
    end

    m.Log("HTTP Response Data: %s", cjson.encode(req_data))
    local respon, err = post_json(join_url(Pay.cfg.manageHost, Path.CHECKWITHDRAW), req_data)
    if err ~= nil or respon == nil or respon.data == nil then
        m.Log(err)
        m.Log("err ~= nil or respon == nil or respon.data == nil")
        return nil, "审核订单请求失败"
    end

    --{"code":0,
    --  "data":{"info":{
    --                  "order_id":"aaa",
    --                  "to_address":"bbb",
    --                  "user_id":123455,
    --                  "amount":"0.111",
    --                  "timestamp":123123,
    --                  "sign":""
    --                  },
    --          "result":0
    --          },
    --      "msg":"ok"
    --  }
    return respon, nil
end

-- =========================
-- 审核通过，向钱包请求提现订单
-- =========================
-- req_data: json请求数据
function Pay:requestRealWichdraw(req_data)
    if req_data == nil then
         return nil, "审核通过，向钱包请求提现订单"
    end

    -- WITHDRAW = "/pay/v1/withdraw"
    m.Log("HTTP Response Data: %s", cjson.encode(req_data))
    local respon, err = post_json(join_url(Pay.cfg.host, Path.WITHDRAW), req_data)
    if err ~= nil or respon == nil or respon.data == nil then
        m.Log(err)
        m.Log("err ~= nil or respon == nil or respon.data == nil")
        return nil, "未通过钱包提现请求"
    end

    
    -- 返回的数据格式
    -- {
    --    "code": 0
    --    "msg":
    --    "data":
    --     {
    --          "id": 数据库id,
    --          "user_id": "10001",
    --          "order_id": "WD202511010001",
    --          "to_addr": "TJr9xk2e1vF6e2UHRvRgYxDgJeK5HVYvVq",
    --          "intput_amount": "123.456",
    --          "amount": "123.456000",
    --          "tx_hash": "a8a239c890ae5a53e9ecad09c36f853f1b2e6d9b5a4c7d0a91d1c6f0a6b2b1c9",
    --          "status": 0,
    --          "desc": "提现处理中",
    --          "create_at": "2025-11-01T10:25:00Z",
    --          "update_at": "2025-11-01T10:25:00Z"
    --    }
    -- }
    if respon.code == nil or respon.code ~= 0 then
        m.Log("respon.code == nil or respon.code ~= 0")
        return nil, respon.msg or "创建订单失败"
    end

    return respon.data, nil
end


-- =========================
-- 注册 订单回调，回调的data就是
-- 订单的结构，判断订单状态
-- 如果是SUCCESS支付成功增加余额
-- =========================
function Pay:registerOrderCb(fn)
    if type(fn) ~= "function" then
        return nil, "callback must be a function"
    end

    self._callbacks.order_cb = fn
    return true, nil
end


-- =========================
-- 注册 订单提现回调，回调的data就是
-- 提现订单的结构，判断订单状态
-- 如果是SUCCESS提现成功通知用户或其他操作
-- =========================
function Pay:registerWithdrawCb(fn)
    if type(fn) ~= "function" then
        return nil, "callback must be a function"
    end

    self._callbacks.withdraw_cb = fn
    return true, nil
end



function Pay:_emit(event, data)
    local cb = self._callbacks[event]
    if cb then
        local ok, err = pcall(cb, data)
        if not ok then
            print("callback error:", err)
        end
    end
end

function Pay:Topic(topic, data) --  msg.topic, msg.partition, msg.offset, #msg.value, msg.value)
    m.Log("topic=%s,data=%s", topic, data)
    if topic ~= self.TopupTopic then
        return
    end

    local transfer, err = cjson.decode(data)
    if err ~= nil then
        m.Log("pay:topic err:" .. err)
        return
    end

    m.Log("transfer,txhash=%s,from=%s,to=%s,amount=%s,contract=%s", transfer.tx_hash, transfer.from, transfer.to,
        transfer.amount, transfer.contract)

    -- 只有充值才会有订单信息
    if transfer.tx_hash ~= nil then
        self:_emit("order_cb", transfer)
    end
   
end

return Pay
