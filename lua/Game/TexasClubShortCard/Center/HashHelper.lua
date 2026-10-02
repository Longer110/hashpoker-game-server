local LuaCrypto = require("LuaCrypto") -- 加密库
local tBase = require("base") -- 基础功能接口
local PublicDefine =require("PublicDefine")
local RecordDbr =require("RecordDbr")

local Helper = {}

-- 生成平台随机种子，例如 AK202510182045309128
local function GenerateSeed()
    local prefix = prefix or "KK"
    local t = os.date("*t")
    local time_str = string.format("%02d%02d%02d%02d%02d%02d",
        t.year % 100, t.month, t.day, t.hour, t.min, t.sec)
    local rand_str = tostring(math.random(100000, 999999))
    return prefix .. time_str .. rand_str
end

local cacheNum = 5

function Helper:New(sTableId, nGameId, nGroupId, nRoomId)
	local t = {}
	setmetatable(t, self)
	self.__index = self

    t.nGroupId = nGroupId
    t.nGameId = nGameId
    t.sTableId = sTableId
    t.nRoomId = nRoomId
    t.tableArr = {}
    t.current = nil  --当前数据
    t.preData = nil  -- 预生成
    t.sendData = {} -- 同步从服信息
    math.randomseed(os.time())
	return t
end

-- 生成 SHA256 哈希（返回 hex 字符串）
local function sha256_hex(data)
    local d256 = LuaCrypto.sha256(data)
    return LuaCrypto.bin2hex(d256)
end

local function genDeckHash(deck)
    local str = table.concat(deck, ",")
    local seed = GenerateSeed()
    local card_str = str .. seed
    local card_hash = sha256_hex(card_str)
    local hash = sha256_hex(card_hash)
    return hash, card_hash, str, seed
end

local function normalizeKeys(t)
    local result = {}
    for k, v in pairs(t) do
        if type(k) == "number" then
            k = tostring(k)
        end
        result[k] = v
    end
    return result
end

-- 生成hash
-- hash 洗牌前哈希序列 card_hash牌序列哈希 cards 牌序列 hand 第几手 seed 随机种子
function Helper:GenTableHash(tPile, preTPile, sPaiJuId, nPlayCnt, handsDict, arrUser, isFirst)
    if isFirst then
        local hash1, card_hash1, desk1, seed1 = genDeckHash(tPile:GetAllCards())
        local hash, card_hash, desk, seed = genDeckHash(preTPile:GetAllCards())
        local data1 = {sPaiJuId = sPaiJuId, fTime = os.date("%Y-%m-%d %H:%M:%S"), show = 0, hash = hash1, card_hash = card_hash1, cards = desk1, time = os.date("%Y-%m-%d %H:%M:%S"), hand = nPlayCnt, handsDict = handsDict, seed = seed1, exData = { arrUser = normalizeKeys(arrUser), fTime = os.date("%Y-%m-%d %H:%M:%S") }}
        self.current = data1
        -- table.insert(self.tableArr, data1)
        self.preData =  {sPaiJuId = "", show = 0, hash = hash, card_hash = card_hash, cards = desk, time = os.date("%Y-%m-%d %H:%M:%S"), hand = nPlayCnt + 1, seed = seed}
        self.sendData = {}
        table.insert(self.sendData, data1)
        table.insert(self.sendData, self.preData)
    else
        local hash, card_hash, desk, seed = genDeckHash(preTPile:GetAllCards())
        self.current = {sPaiJuId = sPaiJuId, fTime = os.date("%Y-%m-%d %H:%M:%S"), show = 0, hash = self.preData.hash, card_hash = self.preData.card_hash, cards = self.preData.cards, time = self.preData.time, hand = self.preData.hand, handsDict = handsDict, seed = self.preData.seed, exData = { arrUser = normalizeKeys(arrUser), fTime = os.date("%Y-%m-%d %H:%M:%S") }}
        -- table.insert(self.tableArr, self.current)
        self.preData =  {sPaiJuId = "", show = 0, hash = hash, card_hash = card_hash, cards = desk, time = os.date("%Y-%m-%d %H:%M:%S"), hand = nPlayCnt + 1, seed = seed}
        self.sendData = {}
        table.insert(self.sendData, self.preData)
    end
    -- if #self.tableArr > PublicDefine.HashMaxNum then
    --     table.remove(self.tableArr, 1)
    -- end
    self:ChangeCurrent(handsDict, true)
    tBase.Log("GenTableHash sPaiJuId:%s hash:%s, cards:%s", sPaiJuId, self.preData.hash, self.preData.cards)
    tBase.LogT(self.current)
end

-- 当前牌局信息 1:公共牌 2:切牌位置 3: 座位数 4:转牌 5:河牌 6:庄家位置 [20000012]=39 玩家对应牌
-- details={[1]={28,21,2,3,4}}
function Helper:ChangeCurrent(data, ifDetails, show)
    if not self.current then
        return
    end
    if show then
        self.current.show = show
        return
    end
    self.current.exData = self.current.exData or {}
    local target = ifDetails and (self.current.exData.details or {}) or self.current.exData
    if ifDetails then
        self.current.exData.details = target
    end

    local dataS = normalizeKeys(data)
    for k, v in pairs(dataS) do
        if target[k] == nil then
            target[k] = v
        end
    end
end

local function getSaveData(item)
    local ret = {}
    table.insert(ret, {sPaiJuId = item.sPaiJuId, fTime = item.fTime, show = item.show, hash = item.hash, card_hash = item.card_hash, cards = item.cards, time = item.time, hand = item.hand , seed = item.seed, exData = item.exData})
    return ret
end

-- 存DB
function Helper:DoPersist()
    if not self.current then
        return
    end
    table.insert(self.tableArr, self.current)
    if #self.tableArr > PublicDefine.HashMaxNum then
        table.remove(self.tableArr, 1)
    end
    RecordDbr.WriteRecordHash(self.sTableId, self.nGameId, self.nRoomId, getSaveData(self.current))
end

function Helper:GetSlaveData()
    return self.sendData
end

-- 获取玩家手牌
local function getHand(item, nUserId)
    local hand = item.handsDict[nUserId]
    if hand then
        return table.concat(hand, ",")
    else
        return ""
    end
    for k, v in pairs(item.handsDict) do
        if k > 20 then
            hand = v
            break
        end
    end
    return table.concat(hand, ",")
end

-- 过滤用户自己的
function Helper.GetUserList(nUserId, nQueryCnt, nMinId, tableArr)
    local result = {list = {}, nMinId = nMinId}
    for i = #tableArr, 1, -1 do
        local item = tableArr[i]
        if nMinId == 0 or (item.hand < nMinId and item.handsDict[nUserId]) then
            table.insert(result.list, {sPaiJuId = item.sPaiJuId, show = item.show, sTime = item.time, hash = item.hash, cards = item.card_hash, hand = getHand(item, nUserId), nPlayCnt = item.hand, seed = item.seed})
            result.nMinId = item.hand
            if #result.list >= nQueryCnt then
                break
            end
        end
    end
    return result
end

local function GetCurrent(item, userId)
    return {sPaiJuId = item.sPaiJuId, fTime = item.fTime or "", show = item.show, sTime = item.time, hash = item.hash, cards = "", hand = getHand(item, userId), nPlayCnt = item.hand, seed = item.seed}
end

local function GetPreData(item, userId)
    return {sPaiJuId = item.sPaiJuId, fTime = item.fTime or "", show = item.show, sTime = item.time, hash = item.hash, cards = "", hand = "", nPlayCnt = item.hand, seed = item.seed}
end

function Helper:GetHashList(tJsonData)
    local nQueryCnt = tJsonData.nQueryCnt or 15
    if nQueryCnt == 0 then
        nQueryCnt = 15
    end
    local nUserId = tJsonData.nUserId
    nQueryCnt = math.min(nQueryCnt, 20)
    local nMinId = tJsonData.nMinId or 0
    local result = {list = {}, nMinId = nMinId}
    local curId = 0

    -- 首次查询：获取最新的数据
    if nMinId == 0 then
        -- 如果有当前对局，先加入当前对局
        if self.current then
            local item = GetPreData(self.preData)
            table.insert(result.list, item)
            item = GetCurrent(self.current, nUserId)
            table.insert(result.list, item)
            result.nMinId = item.nPlayCnt
            curId = item.nPlayCnt
        end
        -- 如果还需要更多数据，从最新的历史对局开始拿
        if #result.list < nQueryCnt then
            for i = #self.tableArr, 1, -1 do
                local item = self.tableArr[i]
                if item.hand ~= curId and item.handsDict[nUserId] then  -- 避免重复加入当前对局
                    local lookData = item.lookData or {}
                    local show = item.show
                    if lookData[nUserId] then
                        show = 1
                    end
                    table.insert(result.list, {
                        sPaiJuId = item.sPaiJuId,
                        sTime = item.time,
                        hash = item.hash,
                        cards = item.card_hash,
                        hand = getHand(item, tJsonData.nUserId),
                        nPlayCnt = item.hand,
                        seed = item.seed,
                        show = show,
                        fTime = item.fTime,
                    })
                    result.nMinId = item.hand  -- 更新为最小的hand
                end
                if #result.list >= nQueryCnt then
                    break
                end
            end
        end
    else
        -- 非首次查询：从nMinId开始往前拿更旧的数据
        for i = #self.tableArr, 1, -1 do
            local item = self.tableArr[i]
            if item.hand < nMinId and item.handsDict[nUserId] then  -- 拿比nMinId更小的数据（更旧的）
                local lookData = item.lookData or {}
                local show = item.show
                if lookData[nUserId] then
                    show = 1
                end
                table.insert(result.list, {
                    sPaiJuId = item.sPaiJuId,
                    sTime = item.time,
                    hash = item.hash,
                    cards = item.card_hash,
                    hand = getHand(item, tJsonData.nUserId),
                    nPlayCnt = item.hand,
                    seed = item.seed,
                    show = show,
                    fTime = item.fTime,
                })
                result.nMinId = item.hand  -- 更新为当前最小的hand
                if #result.list >= nQueryCnt then
                    break
                end
            end
        end
    end
    return result
end

-- 某一paiju item
function Helper:GetTableHash(tJsonData)
    local sPaiJuId = tJsonData.sPaiJuId
    for _, v in ipairs(self.tableArr) do
        if v.sPaiJuId == sPaiJuId then
            return v
        end
    end
    return
end

-- 某一paiju item 玩家看过标记
function Helper:SetTableHashLook(sPaiJuId, nUserId)
    for _, v in ipairs(self.tableArr) do
        if v.sPaiJuId == sPaiJuId then
            local lookData = v.lookData or {}
            lookData[nUserId] = true
            v.lookData = lookData
            return
        end
    end
    return
end

return Helper