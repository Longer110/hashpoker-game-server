local tBase 	  = require("base")         -- 基础功能接口
-- 局抽水工具
local TaxHelp = {}
-- 房间数据
TaxHelp._roomData = {}

-- 工具函数 获取用户数据
local function _getUser(roomid, uid)
    -- 不存在创建数据
    if not TaxHelp._roomData[roomid] then
        TaxHelp._roomData[roomid] = {}
    end
    if not TaxHelp._roomData[roomid][uid] then
        TaxHelp._roomData[roomid][uid] = {
            buy = 0,   ---购买筹码
            out = 0,   ---带出筹码
            taxed = 0, ---抽水筹码
            insurance = 0, --保险收入
            lastPaijuId =  "",
        }
    end
    return TaxHelp._roomData[roomid][uid]
end

function TaxHelp:getAllUser(roomid)
    return TaxHelp._roomData[roomid] or {}
end

-- 用户带入筹码/ uid:用户id,roomid:房间id,chip:带入筹码数
function TaxHelp:buyChip(uid, roomid, buyIn)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local u = _getUser(roomid, uid)
    buyIn = buyIn or 0
    if buyIn < 0 then
        buyIn = 0
    end
    u.buy = u.buy + buyIn
    tBase.Log("TaxHelp, buyChip uid:%s, roomid:%s, 买入:%0.2f, 买入后:%0.2f", uid, roomid, buyIn, u.buy)
    return u.buy

end

-- 撤码
function TaxHelp:removeChip(uid, roomid, remove)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local u = _getUser(roomid, uid)
    remove = remove or 0
    if remove < 0 then
        remove = 0
    end
    u.out = u.out + remove
    tBase.Log("TaxHelp, removeChip uid:%s, roomid:%s, 移除:%0.2f, 移除后后:%0.2f", uid, roomid, remove, u.out)
    return u.out
end

-- 清除房间数据
function TaxHelp:clearRoom(roomid)
    TaxHelp._roomData[roomid] = nil
    tBase.Log("TaxHelp, clearRoom roomid:%s",  roomid)
end

function TaxHelp:updatePaiJuid(uid, roomid,paijuid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    user.lastPaijuId = paijuid
end

--用户坐下
function TaxHelp:joinRoom(uid, roomid, chip)
    uid = tostring(uid)
    roomid = tostring(roomid)
    chip = chip or 0
    local user = _getUser(roomid, uid)
    local lastTaxed = user.taxed or 0
    lastTaxed = lastTaxed or 0
    self:buyChip(uid, roomid, chip)
    user.taxed = 0
    tBase.Log("TaxHelp, joinRoom uid:%s, roomid:%s, 带入:%0.2f, 上次抽水:%0.2f", uid, roomid, chip, lastTaxed)
    return lastTaxed
end
-- 保险收入(保险不算盈利)
function TaxHelp:insuranceWin(uid, roomid,chip)
    uid = tostring(uid)
    roomid = tostring(roomid)
    chip = chip or 0
    local user = _getUser(roomid, uid)
    user.insurance = user.insurance + chip
    tBase.Log("TaxHelp, insurance uid:%s, roomid:%s, 保险收入:%0.2f, 带出后:%0.2f", uid, roomid, chip, user.out)
end

-- 用户站起  用户id ,房间号, 带走筹码chipDelta   返回需要算税收筹码数 ,rate 当前税率
function TaxHelp:onLeaveRoom(uid, roomid, chipDelta, rate)
    uid = tostring(uid)
    roomid = tostring(roomid)
    chipDelta = chipDelta or 0
    if chipDelta < 0 then
        chipDelta = 0
    end
    rate = rate or 0
    if rate > 1 or rate < 0 then
        rate = 0
    end
    local user = _getUser(roomid, uid)
    user.out = user.out + chipDelta
    local profit = user.out - user.buy - user.insurance
    if profit > 0 then
        local tax = profit * rate
        tax = tax - 1e-8
        local v100 = math.floor(tax * 100) -- 分(0.01)单位整数
        local v10  = math.floor(v100 / 10) -- 角(0.1)单位整数
        if (v100 % 10) > 0 then  -- 第二位(分位)有值就进 0.1
            v10 = v10 + 1
        end
        user.taxed = v10 / 10
        if user.taxed > chipDelta then
            user.taxed = chipDelta
        end
        tBase.Log("TaxHelp, onLeaveRoom uid:%s, roomid:%s, 带走:%0.2f, 买入:%0.2f, 带走筹码大于买入筹码, 需交税:%0.2f", uid, roomid, chipDelta, user.buy, user.taxed)
        return user.taxed
    end
    tBase.Log("TaxHelp, onLeaveRoom uid:%s, roomid:%s, 带走:%0.2f, 买入:%0.2f, 带走筹码不大于买入筹码, 不需交税", uid, roomid, chipDelta, user.buy)
    return 0
end

return TaxHelp
