local tBase              = require("base") -- 基础功能接口
local publicApi          = require("publicApi")
local cjson              = require("cjson")

-- 罚款数据管理
local PenaltyManager     = {}
-- 房间用户数据
PenaltyManager._roomData = {}

-- 工具函数 获取用户数据
local function _getUser(roomid, uid)
    -- 不存在创建数据
    if not PenaltyManager._roomData[roomid] then
        PenaltyManager._roomData[roomid] = {}
    end
    if not PenaltyManager._roomData[roomid][uid] then
        PenaltyManager._roomData[roomid][uid] = {
            sName = "",           --- 用户名,发送通知时需要使用
            buy = 0,              ---购买筹码
            out = 0,              ---带出筹码
            tax = 0,              ---抽水筹码
            insurance = 0,        --保险收入
            penalty2User = 0,     -- 罚款,用户收益部分
            penalty2System = 0,   -- 罚款,系统收益部分
            revenue = 0,          --罚款收益
            nPlayCnt = 0,         -- 玩家总手数
            nJoinInPlayCnt = -1,  -- 玩家参与游戏时, 牌局已玩总手数, 游戏开始时记录,起始值为1
            arrRevenueUsers = {}, -- 收益玩家列表
            nRetainCount = 0,     -- 用户留座次数, 离桌类型只能留座一次
            paijuid = "",
        }
    end
    return PenaltyManager._roomData[roomid][uid]
end

function PenaltyManager:getAllUser(roomid)
    return PenaltyManager._roomData[roomid] or {}
end

-- 添加用户离桌留座次数
function PenaltyManager:addRetainCount(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    user.nRetainCount = user.nRetainCount + 1
    return user.nRetainCount
end

-- 用户手数记录
function PenaltyManager:getRetainCount(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    return user.nRetainCount or 0
end

-- 用户手数记录
function PenaltyManager:addPlayCnt(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    user.nPlayCnt = user.nPlayCnt + 1
    return user.nPlayCnt
end

-- 用户初始手数记录
function PenaltyManager:initJoinTablePlayCnt(uid, roomid, nCnt, paijuid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    if user.nJoinInPlayCnt < 0 then
        user.nJoinInPlayCnt = nCnt or 0
    end
    user.paijuid = paijuid
    return user.nJoinInPlayCnt
end

-- 用户带入筹码/ uid:用户id,roomid:房间id,chip:带入筹码数
function PenaltyManager:buyChip(uid, roomid, buyIn)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local u = _getUser(roomid, uid)
    buyIn = buyIn or 0
    if buyIn < 0 then
        buyIn = 0
    end
    u.buy = u.buy + buyIn
    tBase.Log("PenaltyManager, buyChip uid:%s, roomid:%s, 买入:%0.2f, 买入后:%0.2f", uid, roomid, buyIn, u.buy)
    return u.buy
end

-- 撤码
function PenaltyManager:removeChip(uid, roomid, remove)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local u = _getUser(roomid, uid)
    remove = remove or 0
    if remove < 0 then
        remove = 0
    end
    u.out = u.out + remove
    tBase.Log("PenaltyManager, removeChip uid:%s, roomid:%s, 移除:%0.2f, 移除后后:%0.2f", uid, roomid, remove, u.out)
    return u.out
end

-- 清除房间数据
function PenaltyManager:clearRoom(roomid)
    PenaltyManager._roomData[roomid] = nil
    tBase.Log("PenaltyManager, clearRoom roomid:%s", roomid)
end

--用户坐下
function PenaltyManager:joinRoom(uid, roomid, chip)
    uid = tostring(uid)
    roomid = tostring(roomid)
    chip = chip or 0
    local user = _getUser(roomid, uid)
    local lastPenalty2User = user.penalty2User or 0
    local lastPenalty2System = user.penalty2System or 0
    lastPenalty2User = lastPenalty2User or 0
    lastPenalty2System = lastPenalty2System or 0
    self:buyChip(uid, roomid, chip)
    user.penalty2User = 0
    user.penalty2System = 0
    tBase.Log("PenaltyManager, joinRoom uid:%s, roomid:%s, 带入:%0.2f, 上次罚款给用户:%0.2f, 上次罚款给系统:%0.2f", uid, roomid, chip,
        lastPenalty2User, lastPenalty2System)
    return lastPenalty2User, lastPenalty2System
end

-- 保险收入(保险不算盈利)
function PenaltyManager:insuranceWin(uid, roomid, chip)
    uid = tostring(uid)
    roomid = tostring(roomid)
    chip = chip or 0
    local user = _getUser(roomid, uid)
    user.insurance = user.insurance + chip
    tBase.Log("PenaltyManager, insurance uid:%s, roomid:%s, 保险收入:%0.2f, 总保险收入:%0.2f", uid, roomid, chip, user.insurance)
end

-- 抽水扣除
function PenaltyManager:tax(uid, roomid, tax)
    uid = tostring(uid)
    roomid = tostring(roomid)
    tax = tax or 0
    local user = _getUser(roomid, uid)
    user.tax = user.tax + tax
    tBase.Log("PenaltyManager, insurance uid:%s, roomid:%s, 抽水扣除:%0.2f, 总扣除后:%0.2f", uid, roomid, tax, user.tax)
end

-- 用户站起  用户id ,房间号, 带走筹码chipDelta   返回需要算税收筹码数 ,rate 当前税率
function PenaltyManager:onStandUp(uid, roomid, chipDelta, tLeaveTableConfig, arrRevenueUsers, sName)
    uid = tostring(uid)
    roomid = tostring(roomid)
    arrRevenueUsers = arrRevenueUsers or {}

    local user = _getUser(roomid, uid)
    user.sName = sName or ""
    user.out = user.out + chipDelta
    local profit = user.out - user.buy - user.insurance - user.tax - user.revenue -- 用户抽水, 罚款收益部分不计入罚款
    -- 站起是如果牌桌上没有人了, 也就不需要罚款了
    if self:_needPenalty(profit, user.nPlayCnt, #arrRevenueUsers, tLeaveTableConfig) then
        local penalty = publicApi.Floor_n(profit * tLeaveTableConfig.nPenaltyRatio, 1)
        local penalty2User = publicApi.Floor_n(penalty * tLeaveTableConfig.nUserRatio, 1)
        local penalty2System = penalty - penalty2User
        user.penalty2User = user.penalty2User + penalty2User
        user.penalty2System = user.penalty2System + penalty2System
        user.arrRevenueUsers = arrRevenueUsers or {}

        tBase.Log(
            "PenaltyManager, onStandUp uid:%s, roomid:%s, 带走:%0.2f, 总带走:%0.2f, 买入:%0.2f, 带走筹码大于买入筹码, 需罚款:%0.2f %.2f",
            uid, roomid, chipDelta, user.out, user.buy, user.penalty2User, user.penalty2System)
        return user.penalty2User, user.penalty2System, user.paijuid
    end

    tBase.Log("PenaltyManager, onStandUp uid:%s, roomid:%s, 带走:%0.2f, 买入:%0.2f, 带走筹码不需要罚款", uid, roomid, chipDelta,
        user.buy)
    return 0, 0, user.paijuid
end

function PenaltyManager:_needPenalty(profit, nPlayCnt, nRevenueUsersCount, tLeaveTableConfig)
    if nRevenueUsersCount <= 0 then -- 如果牌桌上没有坐下的人了, 则不需要罚款
        tBase.Log("PenaltyManager, _needPenalty 桌子上没人了")
        return false
    end

    if not tLeaveTableConfig.isOpen then -- 如果没有开启离桌罚款功能则不需要罚款
        tBase.Log("PenaltyManager, _needPenalty 桌子未开启离桌罚款功能")
        return false
    end

    if profit < tLeaveTableConfig.nWinThreshold then -- 盈利未达到阈值则不需要罚款
        tBase.Log("PenaltyManager, _needPenalty 盈利[%.2f] 未达到罚款阈值[%.2f]", profit, tLeaveTableConfig.nWinThreshold)
        return false
    end

    if nPlayCnt >= tLeaveTableConfig.nLots then -- 牌局数达到阈值则不需要罚款
        tBase.Log("PenaltyManager, _needPenalty 手数[%d] 已达到罚款阈值[%d]", nPlayCnt, tLeaveTableConfig.nLots)
        return false
    end

    return true
end

-- 返还罚款
function PenaltyManager:ReturnPenalty(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    local nPenalty2User = user.penalty2User
    local nPenalty2System = user.penalty2System
    user.penalty2User = 0
    user.penalty2System = 0
    user.arrRevenueUsers = {}
    user.tax = 0
    return nPenalty2User, nPenalty2System,user.paijuid
end

-- 用户罚款
function PenaltyManager:Penalty(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    local nPenalty2User = user.penalty2User
    local nPenalty2System = user.penalty2System
    local arrRevenueUsers = user.arrRevenueUsers
    user.penalty2User = 0
    user.penalty2System = 0
    user.arrRevenueUsers = {}
    tBase.Log("PenaltyManager, Penalty uid:%s, roomid:%s, 罚款给用户:%0.2f, 罚款给系统: %.2f", uid, roomid, nPenalty2User,
        nPenalty2System)
    return nPenalty2User, nPenalty2System, arrRevenueUsers,user.paijuid
end

-- 用户罚款
function PenaltyManager:GetPenaltyInfo(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    local nPenalty2User = user.penalty2User
    local nPenalty2System = user.penalty2System
    local arrRevenueUsers = user.arrRevenueUsers

    tBase.Log("PenaltyManager, Penalty uid:%s, roomid:%s, 罚款给用户:%0.2f, 罚款给系统: %.2f", uid, roomid, nPenalty2User,
        nPenalty2System)
    return nPenalty2User, nPenalty2System, arrRevenueUsers
end

-- 获取当前的盈利, 只有在站起带出时, 才会将本桌的筹码传入带出筹码中, 故计算本桌盈利时,需要区分处理:
-- 如果是在站起状态时,nLockGoldInTable不需要传, 否则需要传入本桌的nLockGoldInTable
function PenaltyManager:GetProfit(uid, roomid, nLockGoldInTable)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)
    local profit = user.out + (nLockGoldInTable or 0) - user.buy - user.insurance - user.tax -
    user.revenue                                                                                            -- 用户抽水, 罚款收益部分不计入罚款
    tBase.Log(
        "PenaltyManager, GetProfit uid:%s, roomid:%s, 带走:%0.2f, 买入:%0.2f, 保险收入:%0.2f, 抽水扣除:%0.2f, 剩余筹码: %.2f, 盈利:%0.2f",
        uid, roomid, user.out, user.buy, user.insurance, user.tax, nLockGoldInTable or 0, profit)
    return profit
end

function PenaltyManager:getJoinInPlayCnt(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)

    return user.nJoinInPlayCnt or 0
end

function PenaltyManager:getUserInfo(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)

    return user or {}
end

function PenaltyManager:getPlayCnt(uid, roomid)
    uid = tostring(uid)
    roomid = tostring(roomid)
    local user = _getUser(roomid, uid)

    return user.nPlayCnt or 0
end

return PenaltyManager
