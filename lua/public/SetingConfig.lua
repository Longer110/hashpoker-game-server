-- package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

local tSrvInfo = require("ServerInfo")
local cjson = require("cjson")

SetingConfig = {
    passSecret = "kj*80BW97.rveH)#jtWD=pddFzpi",
    sVersionFile = "2024-12-20-1_0_29.19.12",
    TelegramBotToken =
    {
        "8544338325:AAH6nbLP6L_qDK4oABFIel-Sfyag_QTRBsE",
        "7922332100:AAHAxnsjo96J5cYPUVuSvZ2ACo8cafQy8Cs",
        "8536508129:AAEWfnY3adbjPtWbeLIEeGK3Yxt-X17W2BU"
    },
    -- "8544338325:AAH6nbLP6L_qDK4oABFIel-Sfyag_QTRBsE",
    sHttpMonitor = "http://104.194.235.105:12244/bot1143931395:AAFOZ2yIphCjl825bHtpEGoBr65SHValzXA/sendMessage?",
    nChatId = -477599587,                                  -- 发布版ID
    isGm = false,                                          -- GM 命令开启
    RunTimeOut = 500,                                      -- 运行超时时间(毫秒)
    nAndroidGrpId = 0,                                     -- 机器人组id

    nDissolveTable = 1000 * 60 * 60 * 24 * 7,              -- 预开桌解散(毫秒)
    IsPreOpenTable = true,                                 -- 预开桌开关{发布改成true}
    nMathRandNumber = 5,                                   -- 匹配开桌桌数(6)
    sPublicRedisKey = "50F3DF333BB14C9AA7B51EAA8D0A18C7_", -- Redis公共key， 后台可进行配置
    nMinGoldTime = 5,                                      --百人场机器人进入的最低的金币倍数
    nMaxGoldTime = 150,                                    --百人场机器人进入的最低的金币倍数
    SetUserNumber = math.random(60, 120),                  -- 机器人和真人大厅显示人数定时器时长
    RunEnvironment = "HSkin",                              -- 直播(ZSkin) 合集(HSkin)
    nProbabilityOfDefault = 50,                            -- 分组玩家优先匹配到全机器人 默认概率  50%
    tAddAndroidInning = { 4, 8 },                          --  4-8 局 随机后  才加机器人
    tGameMatchingCfg = {
        { 60, 1.5, 2 },                                    --60% 匹配概率   匹配时间范围  1.5,2
        { 40, 3,   4 },                                    --40% 匹配概率   匹配时间范围  3,4
    },

    tZhiBoGameId = {
        nZhiboYuXiaXie = 121, --直播鱼虾蟹
        nZhiboBaijiale = 122, --直播百家乐
        nDeZhou = 123,        --直播德州
        nFootBall = 129,      --直播射龙门
        nPilot = 133,         --直播飞行棋
        nSeDieM = 153,        --直播色蝶
        nToubao = 155,        --直播骰宝
        nFellTree = 157,      --直播砍树
        nBasketball = 159,    --直播篮球
        nLongHu = 139,        --直播龙虎
        nZhiboNiuNiu = 143,   --直播牛牛
    },
    arrClubGameId = {
        nTexas = 125,          --俱乐部德州
        nTexasOmaha = 126,     --俱乐部奥马哈
        nTexasShortCard = 175, --俱乐部短牌
    },

    nInit_Memory = 0, -- 开服后 内存
    nMemory = 0,      -- 当前内存情况

}

-- 获取 牌桌多少局才加机器人
function SetingConfig._GetTableAndroid_RandomIning()
    return math.random(SetingConfig.tAddAndroidInning[1], SetingConfig.tAddAndroidInning[2])
end

-- 获取匹配时间
function SetingConfig._GetMathingTime()
    local tMatchingTime = SetingConfig.tGameMatchingCfg
    local nRandom = math.random(1, 100)
    local nTime = 1
    if tMatchingTime[nTime][nTime] >= nRandom then
        nTime = 2
    end
    local arrMatchingTime = tMatchingTime[nTime]
    local nSeconds = math.random(math.floor(arrMatchingTime[2]), math.floor(arrMatchingTime[3])) .. "." ..
    math.random(1, 9)
    nSeconds = tonumber(nSeconds)
    -- base.Log("_GetMathingTime   nSeconds="..nSeconds)
    return nSeconds
end

-- 是否直播游戏ID
function SetingConfig._IsZhiBoGameId(nGameId)
    for k, v in pairs(SetingConfig.tZhiBoGameId) do
        if v == nGameId then
            return true
        end
    end
    return false
end

-- 热更新文件脚本
local function UndateScript(sClientID, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainID = ReadData:GetModuleID()
    local nSubID = ReadData:GetMsgID()
    local tRead = ProtoManager.Backstage_pb.ReqUndateScript()
    tRead:ParseFromString(ReadData:GetString())
    if tRead.nServerId == ServerInfo.nServerId then
        base.Log("_UndateScript 热更新  nServerId_%d nType: %d(暂支持文件更新)  sUpdateData_%s ", ServerInfo.nServerId, tRead
        .nType, tRead.sUpdateData)
        local tData = cjson.decode(tRead.sUpdateData) -- sUpdateData 格式 {"nType":1,"sUpdataFile":"ModuleFile"}
        if tData and tRead.nType and tData.sUpdataFile and tRead.nType == 2 then
            tData.nType = tRead.nType
            HotFix.WebUpdateFile(tData)
        end
    else
        base.Log("_UndateScript 不同服,不执行 nServerId_%d  %d  sUpdateData_%s ", ServerInfo.nServerId, tRead.nServerId,
            tRead.sUpdateData)
    end
    return
end

-- 全服公共协议
function SetingConfig.PublicProtocol()
    local BackstageCmd = ProtoManager.Backstage_pb.Backstage_Proto()
    base.RegFunc(BackstageCmd.Main_CMD, BackstageCmd.ReqUndateScript_CMD, UndateScript) -- 后台通知 更新服务器文件
    return
end

-- 清除主播开桌 公共接口
local function CleanLiveOpenTable()
    -- 检查 该服 是否 中心服
    local function Func()
        local dwStartTime = base.GetTime()
        local sKey = "APIOpenTale_" .. tSrvInfo.nServerId .. "#" .. "*"
        local tRedis = base.m_MyRedisData[2].redis
        local arrTableInfo = tRedis:keys(sKey)
        local dwSpaceTime = base.GetTime() - dwStartTime
        if #arrTableInfo == 0 then return end
        local arrTableId = {}
        for k, sTableId in pairs(arrTableInfo) do
            local nTableType = tRedis:hget(sTableId, "nTableType")
            if nTableType and tonumber(nTableType) == 1 then
                tRedis:del(sTableId)
                base.Log("_CleanLiveOpenTable  清除主播开桌 sTableKey_%s", sTableId)
                table.insert(arrTableId, sTableId)
            end
        end
        base.Log("_CleanLiveOpenTable sKey_%s  arrTableId_%d %s ", sKey, #arrTableId, cjson.encode(arrTableId))
    end

    local isSuccee, sErr = pcall(Func)
    if not isSuccee then
        base.Log("_CleanLiveOpenTable 11 ")
        local sSend = string.format("_CleanLiveOpenTable  sErr: %s", sErr)
        base._OnMonitorInfo(sSend)
    end

    return
end

function SetingConfig._UpdateServerVersion()
    local nServerId = ServerInfo.nServerId
    SetingConfig.sVersionFile = SetingConfig.sVersionFile .. " Restart: " .. publicApi.OsTimetoDataTime(base.m_CountTime)
    if SetingConfig.isSendDB then
        local sql = string.format("call Update_ServerIdVersion(%d,'%s');", nServerId, SetingConfig.sVersionFile)
        local ParserAux = require("ParserAux")
        local tPacket = ParserAux.DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_PlatformDB", sSql = sql })
        base.PostDatasByType(typename.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
        -- base.Log("_UpdateServerVersion  sql_%s ",sql)

        local nTime = math.random(300, 600)
        base.SetTimer(base.m_wTimer_ID_StartServer, 1000 * nTime, 1, SetingConfig._UpdateServerVersion, true)
        SetingConfig.isSendDB = nil
    else
        local sSend = string.format("开服通知: %s Id=%d 当前版本:%s", tSrvInfo.sName, tSrvInfo.nServerId,
            SetingConfig.sVersionFile)
        base._OnMonitorInfo(sSend)
    end
end

-- 重启服务器 nHandleType: 1开服,2关服
function SetingConfig.RestartServer(nHandleType)
    CleanLiveOpenTable()
    if nHandleType == 1 then
        base.m_CountTime = os.time()

        SetingConfig.isSendDB = true
        base.SetTimer(base.m_wTimer_ID_StartServer, 1000 * 10, 1, SetingConfig._UpdateServerVersion, true)


        SetingConfig.PublicProtocol() -- 全服 监听协议

        base.SetTimer(base.m_wTimer_ID_Memory, 1000 * 60, -1, SetingConfig._Statistics_Memory, true)
    else
        CleanLiveOpenTable()
    end
    return
end

-- 统计内存情况
function SetingConfig._Statistics_Memory()
    if 1 then return end

    local nNowCnt = collectgarbage("count")
    if nNowCnt - SetingConfig.nMemory > 0 then
        local nAdd_KB = math.floor(nNowCnt - SetingConfig.nMemory)
        local nAdd_KB1 = math.floor(nNowCnt - SetingConfig.nInit_Memory)
        -- local nAdd_MB =  math.floor(nAdd_KB / 1024 )
        -- local nAdd_MB1 =  math.floor( (nNowCnt-SetingConfig.nInit_Memory) / 1024 )
        base.Log("_Statistics_Memory   New: %.1f KB  Old: %.1f KB  最近增加 %d KB  Init: %.1fKB  最初增加 %d KB   "
        , nNowCnt, SetingConfig.nMemory, nAdd_KB, SetingConfig.nInit_Memory, nAdd_KB1)
    else
        -- base.Log("_Statistics_Memory   New: %.1f KB  Old: %.1f KB   减少 %.1f KB ",nNowCnt,SetingConfig.nMemory,nNowCnt - SetingConfig.nMemory)
    end
    SetingConfig.nMemory = nNowCnt
    if SetingConfig.nInit_Memory == 0 then
        SetingConfig.nInit_Memory = nNowCnt
    end
end

return SetingConfig
