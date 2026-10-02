-- 定时处理玩家信息

local tPubUserApi   = require("PublicUserInfo")    --玩家数据同步
local redisdefine   = require("redisdefine")
local cjson         = require("cjson")          -- json (空对象编码成空对象)
local tBase 	    = require("base")
local publicApi     = require("publicApi")
local GlobalConfigKey = redisdefine.GlobalConfigKey

local UserOnTime = {}

local userCache = {}  -- 用户缓存
local needSaveUsers = {} -- 需要保存的用户ID集合
local needDel = {}

-- {
--     "free_register" : 1,      -- 注册赠送是否使用
--     "free_recharge" : 0,      -- 首充赠送是否使用
--     "cond_modify" : 0,        -- 是否处于条件修改状态
--     "cond_type" : 0,          -- 类型：loss / avgprofit
--     "cond_expire" : 0         -- 条件修改触发时间（或过期时间）
--     "last_time" : 0           -- 上次修改时间
--     "play_count" : 0,          -- 游戏次数
--     "hand_profit" : 0          -- 手均盈利
--     "loss_amount" : 0          -- 亏损金额
--     "need_save" : false        -- 是否需要保存
-- }

local function GetGlobalConfig(name)
    return SlaveData.globalConfig[name]
end

local function GetGlobalConfigPrice(name)
    local config = SlaveData.globalConfig[name]
    if config and tonumber(config.open) == 1 then
        return tonumber(config.price) or 0
    end
    return 0
end

--[[
    1、玩家的“注册免费”或“首充修改”的次数没有使用的情况下，不会触发“条件修改”
    2、玩家的上一次触发的“条件修改”没有使用的情况下，不会再次触发“条件修改”
    3、玩家同一时间最多保留1次修改次数，不会叠加修改次数
    4、近X日的计算时间从玩家没有修改昵称次数的时间开始算起
    如果玩家在处于“条件修改”的情况下，完成了首充，则首充修改可以覆盖“条件修改
]]

local function getUserData(nUserId)
    if not userCache[nUserId] then
        userCache[nUserId] = tPubUserApi.GetUserNameInfo(nUserId)
    end
    return userCache[nUserId]
end

function UserOnTime.deleteUserData(nUserId)
    if needSaveUsers[nUserId] then
        needDel[nUserId] = true
    else
        userCache[nUserId] = nil
        needSaveUsers[nUserId] = nil
    end
end

-- 标记用户需要保存
local function markUserNeedSave(nUserId)
    needSaveUsers[nUserId] = true
end

local defaultData = {
    free_register = 0,
    free_recharge = 0,
    cond_modify = 0,
    cond_type = 0,
    cond_expire = 0,
    last_time = 0,
    play_count = 0,
    hand_profit = 0,
    loss_amount = 0,
}

-- 获取用户改名信息
function UserOnTime.GetUserNameData(nUserId)
    local tUserData = getUserData(nUserId) or defaultData
    if tUserData.free_register == 1 then
        return 1, 0
    end
    if tUserData.free_recharge == 1 then
        return 1, GetGlobalConfigPrice(GlobalConfigKey.ChangeNameRecharge)
    end
    if tUserData.cond_modify == 1 then
        local price = 0
        if tUserData.cond_type == 1 then
            price = GetGlobalConfigPrice(GlobalConfigKey.ChangeNameLoss)
        elseif tUserData.cond_type == 2 then
            price = GetGlobalConfigPrice(GlobalConfigKey.ChangeNameHandProfit)
        elseif tUserData.cond_type == 3 then
            price = GetGlobalConfigPrice(GlobalConfigKey.ChangeNameTime)
        end
        return 1, price
    end
    return 0, 0
end

-- 改名成功后调用
function UserOnTime.ChangeNameSuccess(nUserId)
    local info = getUserData(nUserId)
    if info.free_register == 1 then
        info.free_register = 0
    elseif info.free_recharge == 1 then
        info.free_recharge = 0
    end
    info.free_register = 0
    info.cond_modify = 0
    info.cond_type = 0
    info.cond_expire = 0
    info.last_time = os.time()
    info.play_count = 0
    info.hand_profit = 0
    info.loss_amount = 0
    info.need_save = true
    markUserNeedSave(nUserId)
    tPubUserApi.SetUserNameInfo(nUserId, cjson.encode(info))
    UserOnTime.noticeNameCount(nUserId, 0, false, 0)
end

local function CheckModifyChance(nUserID)
    local info = getUserData(nUserID)
    -- 1. 有注册或者首充免费次数未使用 → 不触发条件修改
    if info.free_register == 1 or info.free_recharge == 1 then
        return
    end
    -- 2. 有正在生效的条件修改 → 不重复触发
    if info.cond_modify == 1 then
        return
    end
    -- 首充赠送是否使用
    -- local config1 = GetGlobalConfig(GlobalConfigKey.ChangeNameRecharge)
    -- if config1 and tonumber(config1.open) == 1 then
    -- end
    -- 获取玩家上次修改结束时间
    local last_time = info.last_time or 0
    if last_time == 0 then
        last_time = os.time()
    end
    -- 计算近 X 日亏损
    local config = GetGlobalConfig(GlobalConfigKey.ChangeNameLoss)
    if config and tonumber(config.open) == 1 then
        if info.loss_amount and info.loss_amount > tonumber(config.loss) then
            info.cond_modify = 1
            info.cond_type = 1
            info.cond_expire = os.time()
            info.need_save = true
            markUserNeedSave(nUserID)
            tPubUserApi.SetUserNameInfo(nUserID, cjson.encode(info))
            UserOnTime.noticeNameCount(nUserID, tonumber(config.price) or 0, false)
            return
        end
    end
    -- 近X日手均盈利低于X改名
    local config2 = GetGlobalConfig(GlobalConfigKey.ChangeNameHandProfit)
    if config2 and tonumber(config2.open) == 1 then
        if info.hand_profit and info.play_count > 0 and publicApi.Floor_n(info.hand_profit/info.play_count,2) > tonumber(config.loss) then
            info.cond_modify = 1
            info.cond_type = 2
            info.cond_expire = os.time()
            info.need_save = true
            markUserNeedSave(nUserID)
            tPubUserApi.SetUserNameInfo(nUserID, cjson.encode(info))
            UserOnTime.noticeNameCount(nUserID, tonumber(config2.price) or 0, false)
            return
        end
    end
    -- 改名冷却时间
    local config3 = GetGlobalConfig(GlobalConfigKey.ChangeNameTime)
    if config3 and tonumber(config3.open) == 1 then
        local nNow = os.time()
        if nNow - last_time >= tonumber(config3.interval) then
            info.cond_modify = 1
            info.cond_type = 3
            info.cond_expire = os.time()
            info.need_save = true
            markUserNeedSave(nUserID)
            tPubUserApi.SetUserNameInfo(nUserID, cjson.encode(info))
            UserOnTime.noticeNameCount(nUserID, tonumber(config3.price) or 0, false)
            return
        end
    end
end

-- 统计玩家信息
function UserOnTime.StaticUser(nUserId, tChangeInfo)
    local nWinlose = tChangeInfo.nWinlose or 0
    local nHandProfit = tChangeInfo.nHandProfit or 0
    local nPlayCount = 1
    local isRecharge = tChangeInfo.isRecharge
    local amount = tChangeInfo.amount or 0
    local tUserData = getUserData(nUserId)
    tBase.LogT("tChangeInfo", tChangeInfo)
    tBase.LogT("StaticUser", tUserData)
    if tUserData.free_register == 1 or tUserData.free_recharge == 1 then
        return
    end
    if tUserData.cond_modify == 1 then
        return
    end
    if isRecharge then
        local ok
        if tUserData.first_recharge and tUserData.first_recharge > 0 then
        else
            ok = true
            tUserData.first_recharge = amount
        end
        -- 首充赠送是否使用
        local config1 = GetGlobalConfig(GlobalConfigKey.ChangeNameRecharge)
        if config1 and ok and tonumber(config1.open) == 1 then
            tUserData.free_recharge = 1
            tUserData.need_save = true
            markUserNeedSave(nUserId)
            UserOnTime.noticeNameCount(nUserId, tonumber(config1.price) or 0, true)
        end
    else
        tUserData.play_count = (tUserData.play_count or 0) + nPlayCount
        tUserData.hand_profit = (tUserData.hand_profit or 0) + nHandProfit
        if nWinlose < 0 then
            tUserData.loss_amount = (tUserData.loss_amount or 0) + math.abs(nWinlose)
        else
            tUserData.loss_amount = (tUserData.loss_amount or 0) - nWinlose
        end
        tUserData.need_save = true
        markUserNeedSave(nUserId)
    end
    tPubUserApi.SetUserNameInfo(nUserId, cjson.encode(tUserData))
    CheckModifyChance(nUserId)
end


-- 通知玩家改名次数
function UserOnTime.noticeNameCount(nUserId, price, isRecharge, nCount)
    nCount = nCount or 1
    MsgApi.SendToUser2(nUserId,"ClubSNameCountNotify",{nCount=nCount,nCost=price,isRecharge=isRecharge})
end

-- 充值到账通知
function UserOnTime.OnUserRecharge(sReturnKey, Data, nLen)
   local ReadData = tBase.GetRP().new(Data, nLen)
   local Sys = ReadData:GetModuleID()
   local Sub = ReadData:GetMsgID()
   local Read = ProtoManager.PubProto_1_pb.REQ_Club_Recharge()
   Read:ParseFromString(ReadData:GetString())
   local nUserId = Read.nUserId or -1
   local nAmount = Read.nAmount or 0
   tBase.Log("UserOnTime.OnUserRecharge nUserId:%d nAmount:%.2f", nUserId, nAmount)
   if nUserId <= 0 or nAmount <= 0 then
       return
   end
   UserOnTime.StaticUser(nUserId, {isRecharge = true, amount = nAmount})
end

-- 充值到账通知
function UserOnTime.OnUserRechargeTest(Data)
   local nUserId = Data.nUserId or -1
   local nAmount = Data.nAmount or 0
   tBase.Log("UserOnTime.OnUserRechargeTest nUserId:%d nAmount:%.2f", nUserId, nAmount)
   if nUserId <= 0 or nAmount <= 0 then
       return
   end
   UserOnTime.StaticUser(nUserId, {isRecharge = true, amount = nAmount})
end

-- 定时保存需要保存的用户数据
function UserOnTime.TimerSaveUserData()
    local saveCount = 0
    local errorCount = 0
    for nUserId, _ in pairs(needSaveUsers) do
        local userData = userCache[nUserId]
        if userData and userData.need_save then
            local success, result = pcall(function()
                local ClubMarkUserReq = {}
                ClubMarkUserReq.nUserId = nUserId
                ClubMarkUserReq.nTarUid = 1
                ClubMarkUserReq.nText = ""
                ClubMarkUserReq.nColorId = 0
                ClubMarkUserReq.nIsMark = false
                MsgApi.SendToDBServer1("ClubMarkUserReq",ClubMarkUserReq,nUserId)
            end)
            if success then
                -- 保存成功后清除标记
                userData.need_save = false
                saveCount = saveCount + 1
                tBase.Log("定时保存用户数据成功, UserID: %d", nUserId)
            else
                errorCount = errorCount + 1
                tBase.Log("定时保存用户数据失败, UserID: %d, Error: %s", nUserId, tostring(result))
            end
        end
        -- 从待保存列表中移除（无论成功失败，避免重复处理）
        needSaveUsers[nUserId] = nil
        if needDel[nUserId] then
            userCache[nUserId] = nil
            needDel[nUserId] = nil
        end
        -- 每次定时器执行最多保存100个用户，避免阻塞
        if saveCount >= 100 then
            break
        end
    end
    if saveCount > 0 or errorCount > 0 then
        tBase.Log("定时保存完成: 成功%d个, 失败%d个", saveCount, errorCount)
    end
end

-- 初始化定时器
function UserOnTime.InitTimer()
    SlaveData.tTimerId.saveName = TimerAux.GetATimerId()
    tBase.SetTimer(SlaveData.tTimerId.saveName, 1000*60*4, -1, UserOnTime.TimerSaveUserData)
    tBase.Log("用户数据定时保存器初始化完成")
end

function UserOnTime._check_cd(nUserID, interval, price)
    local info = getUserData(nUserID)
    -- 1. 有注册或者首充免费次数未使用 → 不触发条件修改
    if info.free_register == 1 or info.free_recharge == 1 then
        return
    end
    -- 2. 有正在生效的条件修改 → 不重复触发
    if info.cond_modify == 1 then
        return
    end
    -- 获取玩家上次修改结束时间
    local last_time = info.last_time or 0
    if last_time == 0 then
        last_time = os.time()
    end
    local nNow = os.time()
    if nNow - last_time >= interval then
        info.cond_modify = 1
        info.cond_type = 3
        info.cond_expire = os.time()
        info.need_save = true
        markUserNeedSave(nUserID)
        tPubUserApi.SetUserNameInfo(nUserID, cjson.encode(info))
        UserOnTime.noticeNameCount(nUserID, price or 0, false)
        return
    end
end

-- 改名时间重置
function UserOnTime._OnTimerCb()
    local config3 = GetGlobalConfig(GlobalConfigKey.ChangeNameTime)
    if not config3 or tonumber(config3.open) == 0 then
        return
    end
    local interval = tonumber(config3.interval) or 0
    if interval <= 0 then
        return
    end
    local price = tonumber(config3.price) or 0
    for userId, _ in pairs(userCache) do
        UserOnTime._check_cd(userId, interval, price)
    end
    Base.SetTimer(SlaveData.tTimerId.timeReName, 1000*interval, 1, UserOnTime._OnTimerCb)
end

-- 定时多久免费改名
function UserOnTime.TryRestartReNameTimer()
    local config3 = GetGlobalConfig(GlobalConfigKey.ChangeNameTime)
    if not config3 or tonumber(config3.open) == 0 then
        return
    end
    local interval = tonumber(config3.interval) or 0
    if interval <= 0 then
        return
    end
    if not SlaveData.tTimerId.timeReName then
        SlaveData.tTimerId.timeReName = TimerAux.GetATimerId()
        Base.Log("TryRestartReNameTimer timeReName:%d",SlaveData.tTimerId.timeReName)
    end
    Base.SetTimer(SlaveData.tTimerId.timeReName, 1000*interval, 1, UserOnTime._OnTimerCb)
end

return UserOnTime