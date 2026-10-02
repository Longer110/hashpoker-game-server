local tBase 	  = require("base")         -- 基础功能接口
-- 局抽水工具
local Penalty = {}
-- 房间数据
Penalty._roomData = {}

-- 工具函数 获取用户数据
local function _getUser(roomid, uid)
    -- 不存在创建数据
    if not Penalty._roomData[roomid] then
        Penalty._roomData[roomid] = {}
    end
    if not Penalty._roomData[roomid][uid] then
        Penalty._roomData[roomid][uid] = {
            buy = 0,   ---购买筹码
            out = 0,   ---带出筹码
            taxed = 0, ---抽水筹码
            insurance = 0, --保险收入
            lastPaijuId =  "",
        }
    end
    return Penalty._roomData[roomid][uid]
end

function Penalty:getAllUser(roomid)
    return Penalty._roomData[roomid] or {}
end

-- 用户带入筹码/ uid:用户id,roomid:房间id,chip:带入筹码数
function Penalty:buyChip(uid, roomid, buyIn)
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
function Penalty:removeChip(uid, roomid, remove)
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
function Penalty:clearRoom(roomid)
    Penalty._roomData[roomid] = nil
    tBase.Log("Penalty, clearRoom roomid:%s",  roomid)
end

--用户坐下
function Penalty:joinRoom(uid, roomid, chip)
    uid = tostring(uid)
    roomid = tostring(roomid)
    chip = chip or 0
    local user = _getUser(roomid, uid)
    local lastTaxed = user.taxed or 0
    lastTaxed = lastTaxed or 0
    self:buyChip(uid, roomid, chip)
    user.taxed = 0
    tBase.Log("Penalty, joinRoom uid:%s, roomid:%s, 带入:%0.2f, 上次抽水:%0.2f", uid, roomid, chip, lastTaxed)
    return lastTaxed
end
-- 保险收入(保险不算盈利)
function Penalty:insuranceWin(uid, roomid,chip)
    uid = tostring(uid)
    roomid = tostring(roomid)
    chip = chip or 0
    local user = _getUser(roomid, uid)
    user.insurance = user.insurance + chip
    tBase.Log("Penalty, insurance uid:%s, roomid:%s, 保险收入:%0.2f, 带出后:%0.2f", uid, roomid, chip, user.out)
end

-- 站起时返回盈利信息 (clear 表示是否清除数据)
function Penalty:onStandUp(uid, roomid, chipDelta, clear, paijuId)
    clear = clear or false
    uid = tostring(uid)
    roomid = tostring(roomid)
    chipDelta = chipDelta or 0
    if chipDelta < 0 then
        chipDelta = 0
    end
    local user = _getUser(roomid, uid)
    if paijuId and paijuId ~= "" then
        user.lastPaijuId = paijuId
    end
    user.out = user.out + chipDelta
    local profit = user.out - user.buy - user.insurance
    tBase.Log("Penalty, onStandUp uid:%s, roomid:%s, 带走:%0.2f, 买入:%0.2f, 保险:%0.2f, 盈利:%0.2f", uid, roomid, chipDelta, user.buy, user.insurance, profit)
    if clear then
        -- 清除用户数据
        Penalty._roomData[roomid][uid] = nil
        tBase.Log("Penalty, onStandUp clear uid:%s, roomid:%s", uid, roomid)
    end
    return profit
end

return Penalty
