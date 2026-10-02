package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path
package.path = "../lua/base/socket/?.lua;./lua/base/socket/?.lua;" .. package.path
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

local TgBotMessage = {}

local tBase       = require("base")         -- 基础功能接口
local http        = require("socket.http")  -- Http 服务器
local dbInfo      = require("DBInfo")    -- 数据库连接信息
local cJson       = require("cjson")   -- Json 编码
local baseSink    = require("BaseSink")    -- base 编码解码

function TgBotMessage.Init(nTimeID)
    TgBotMessage.cache = {}
    base.SetTimer(nTimeID, 1000, -1, function()
        for k, v in pairs(TgBotMessage.cache) do
            if v.expire < os.time() then
                TgBotMessage.cache[k] = nil
            end
        end
    end)
end

local function genTableMsg(cfg)
    local table_msg = ""
    if cfg.nGameId == 125 then
        table_msg = string.format("%s/%s", cfg.nSmallBlind, cfg.nBigBlind)
        if cfg.nZhuaTou and cfg.nZhuaTou > 0 then
            table_msg = string.format("%s/%s", table_msg, cfg.nZhuaTou)
        end
        if cfg.nPreAnte and cfg.nPreAnte > 0 then
            table_msg = string.format("%s(%s)", table_msg, cfg.nPreAnte)
        end
    elseif cfg.nGameId == 175 then
        if cfg.nSmallBlind and cfg.nBigBlind and cfg.nSmallBlind > 0 and cfg.nBigBlind > 0 then
            if cfg.nPreAnte and cfg.nPreAnte > 0 then
                table_msg = string.format("%s/%s(%s)", cfg.nSmallBlind, cfg.nBigBlind, cfg.nPreAnte)
            else
                table_msg = string.format("%s/%s", cfg.nSmallBlind, cfg.nBigBlind)
            end
        elseif cfg.nPreAnte and cfg.nPreAnte > 0 then
            local preAnteOdd = cfg.preAnteOdd or 2
            table_msg = string.format("%s/%s", cfg.nPreAnte,cfg.nPreAnte* preAnteOdd)
        end
    end
    return table_msg
end

local function genChatMsg(chatLog)
    local arr = {}
    for i = 1, #chatLog do
        local v = chatLog[i]
        local str = string.format("%s: %s", baseSink.decode(v.sName), baseSink.decode(v.sStr))
        table.insert(arr, str)
    end
    return arr
end

-- 推送
function TgBotMessage.PushChat(msg)
    local req = {
        game_id = msg.baseCfg.nGameId,
        room_name = baseSink.decode(msg.baseCfg.sTableName),
        room_id = msg.baseCfg.sTableId,
        blinds = genTableMsg(msg.baseCfg),
        chat_log = genChatMsg(msg.chatLog)
    }
    tBase.LogT({"推送聊天信息", msg})
    tBase.LogT({"推送聊天信息", req})
    local body = cJson.encode(req)
    local sHttps = dbInfo.backUrl .. "/bot/v1/notifyChatMsg"
    local nResult  = http.request(sHttps, body)     -- 请求后台 
    if type(nResult)  == "string" then
        tBase.Log(" 请求推送结果失败，   没有资源  Error_Info==172  ")
        return
    end
    if nResult == 1 then     -- 0  成功， 其他失败
        tBase.Log(" 请求推送结果成功 nResult:%s ",nResult)
    else
        tBase.Log(" 请求推送结果失败  Error_Info==173 nResult:%s ",nResult)
    end
end

-- 推送开桌信息
function TgBotMessage.PushTable(msg)
    -- 构造 seats 数组
    local seats = {
        -- { idx = 1, nick_name = "玩家A", chip = "1000", icon = "1" },
    }
    msg.seats = msg.seats or {}
    for _, v in pairs(msg.seats) do
        table.insert(seats, {
            idx = v.nPos,
            nick_name = baseSink.decode(v.nName),
            chip = string.format("%.1f", v.nProfit),
            icon = v.nFaceID
        })
    end
    local req = {
        game_id = msg.baseCfg.nGameId,
        room_name = msg.baseCfg.sTableName,
        room_id = msg.baseCfg.sTableId,
        table_msg = genTableMsg(msg.baseCfg),
        seats = seats
    }
    tBase.LogT({"推送开桌信息", msg})
    tBase.LogT({"推送开桌信息", req})
    local body = cJson.encode(req)
    local sHttps = dbInfo.backUrl .. "/bot/v1/notifyRoom"
    local nResult  = http.request(sHttps, body)     -- 请求后台 
    if type(nResult)  == "string" then
        tBase.Log(" 请求推送结果失败，   没有资源  Error_Info==172  ")
        return
    end
    if nResult == 1 then     -- 0  成功， 其他失败
        tBase.Log(" 请求推送结果成功 nResult:%s ",nResult)
    else
        tBase.Log(" 请求推送结果失败  Error_Info==173 nResult:%s ",nResult)
    end
end

local function getSeatResult(arr, type)
    if not arr or #arr == 0 then return {} end
    local result = arr[1]
    for i = 1, #arr do
        local v = arr[i]
        if type == 1 then
            if v.nProfit > result.nProfit then
                result = v
            end
        elseif type == 2 then
            if (v.nPlayCnt or 0) > (result.nPlayCnt or 0) then
                result = v
            end
        elseif type == 3 then
            if v.nProfit < result.nProfit then
                result = v
            end
        end
    end
    local chip = string.format("%.1f", result.nProfit)
    if type == 2 then
        chip = string.format("%s", result.nPlayCnt)
    end
    return {
        nick_name = baseSink.decode(result.nName),
        chip = chip,
        icon = result.nFaceID
    }
end

-- 推送游戏结束
function TgBotMessage.PushTableWin(msg)
    -- 构造 seats 数组
    msg.seats = msg.seats or {}
    local shark = getSeatResult(msg.seats, 1)  -- 吃鱼王
    local mostHands = getSeatResult(msg.seats, 2)  -- 手数最多
    local fish = getSeatResult(msg.seats, 3)  -- 输鱼王
    if not (next(shark) and next(mostHands)) then
        return
    end
    local req = {
        room_name = msg.baseCfg.sTableName,
        game_id = msg.baseCfg.nGameId,
        room_id = msg.baseCfg.sTableId,
        blinds = genTableMsg(msg.baseCfg),
        shark = shark,
        most_hands = mostHands,
        fish = fish,
    }
    tBase.LogT({"推送输赢结果", msg})
    tBase.LogT({"推送输赢结果", req})
    local body = cJson.encode(req)
    local sHttps = dbInfo.backUrl .. "/bot/v1/notifySettlementMsg"
    local nResult  = http.request(sHttps, body)     -- 请求后台 
    if type(nResult)  == "string" then
        tBase.Log(" 请求推送结果失败，   没有资源  Error_Info==172  ")
        return
    end
    if nResult == 1 then     -- 0  成功， 其他失败
        tBase.Log(" 请求推送结果成功 nResult:%s ",nResult)
    else
        tBase.Log(" 请求推送结果失败  Error_Info==173 nResult:%s ",nResult)
    end
end

return TgBotMessage




--[[
curl -X POST "http://127.0.0.1:8891/bot/v1/notifyRoom" \
-H "Content-Type: application/json" \
-d '{
    "table_msg": "10/20/40",
    "room_name": "6ZW/54mM5oqT5aS0LTE2NQ==",
    "room_id": "562#1764AF01E2",
    "seats": [
        {
            "icon": "https://res.hashpoker.vip/icon/rSyIyocmeKH40F3fc2OC5-EWVWntyXu2pX8KOmDcmybk3vbBs7zNR9Yr_gUMvXFg.svg",
            "nick_name": "111111111",
            "chip": "0",
            "idx": 1
        },
        {
            "icon": "https://t.me/i/userpic/320/RE8WAftD32L-QpMupNmc-h5MwKsaYdJZWwO7oaEQHbdIg2hc9xDMZadZQjgP84Mm.svg",
            "nick_name": "xiaoming20271",
            "chip": "0",
            "idx": 7
        }
    ],
    "game_id": 125
}'
]]